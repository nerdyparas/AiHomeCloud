"""
Auto Backup routes — phone-to-NAS background backup.

Endpoints:
  POST   /api/v1/backup/check-duplicate
  POST   /api/v1/backup/record-hash
  GET    /api/v1/backup/status
  POST   /api/v1/backup/jobs
  DELETE /api/v1/backup/jobs/{job_id}
  POST   /api/v1/backup/jobs/{job_id}/report
  POST   /api/v1/backup/notify

Hash records live in kv.json under key "backup_file_hashes".
Job configs live in kv.json under key "backup_jobs".
"""

import logging
import uuid
from contextlib import suppress
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, field_validator

from ..auth import get_current_user
from .. import store

logger = logging.getLogger("aihomecloud.backup")

router = APIRouter(prefix="/api/v1/backup", tags=["backup"])

_MAX_HASHES = 50_000
_MAX_JOBS = 20
_VALID_DESTINATIONS = frozenset({"personal", "family"})


# ── Request models ─────────────────────────────────────────────────────────────

class DuplicateCheckRequest(BaseModel):
    sha256: str
    filename: str

    @field_validator("sha256")
    @classmethod
    def validate_sha256(cls, v: str) -> str:
        v = v.lower()
        if len(v) != 64 or not all(c in "0123456789abcdef" for c in v):
            raise ValueError("sha256 must be a 64-character hex string")
        return v


class RecordHashRequest(BaseModel):
    sha256: str
    filename: str
    destination: str

    @field_validator("sha256")
    @classmethod
    def validate_sha256(cls, v: str) -> str:
        v = v.lower()
        if len(v) != 64 or not all(c in "0123456789abcdef" for c in v):
            raise ValueError("sha256 must be a 64-character hex string")
        return v

    @field_validator("destination")
    @classmethod
    def validate_destination(cls, v: str) -> str:
        if v not in _VALID_DESTINATIONS:
            raise ValueError("destination must be personal or family")
        return v


class CreateJobRequest(BaseModel):
    phoneFolder: str
    destination: str

    @field_validator("destination")
    @classmethod
    def validate_destination(cls, v: str) -> str:
        if v not in _VALID_DESTINATIONS:
            raise ValueError("destination must be personal or family")
        return v

    @field_validator("phoneFolder")
    @classmethod
    def validate_phone_folder(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("phoneFolder must not be empty")
        return v


class SyncReportRequest(BaseModel):
    uploaded: int
    skipped: int
    lastSyncAt: str

    @field_validator("uploaded", "skipped")
    @classmethod
    def validate_non_negative(cls, v: int) -> int:
        if v < 0:
            raise ValueError("counts must be non-negative")
        return v


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/check-duplicate")
async def check_duplicate(
    req: DuplicateCheckRequest,
    user: dict = Depends(get_current_user),
) -> dict:
    """Check whether a SHA-256 hash already exists in the backup hash store."""
    hashes = await store.get_value("backup_file_hashes", default={})
    return {"exists": req.sha256 in hashes}


@router.post("/record-hash", status_code=status.HTTP_200_OK)
async def record_hash(
    req: RecordHashRequest,
    user: dict = Depends(get_current_user),
) -> dict:
    """Persist a SHA-256 → file mapping after a successful upload."""

    def _add(hashes: dict) -> dict:
        hashes[req.sha256] = {
            "filename": req.filename,
            "destination": req.destination,
            "saved_at": datetime.now(timezone.utc).isoformat(),
        }
        if len(hashes) > _MAX_HASHES:
            # Evict oldest entries to stay within the limit
            oldest = sorted(hashes, key=lambda k: hashes[k].get("saved_at", ""))
            for k in oldest[: len(hashes) - _MAX_HASHES]:
                del hashes[k]
        return hashes

    await store.atomic_update("backup_file_hashes", _add, default={})
    return {"ok": True}


@router.get("/status")
async def get_backup_status(
    user: dict = Depends(get_current_user),
) -> dict:
    """Return the current backup configuration and per-job stats."""
    jobs = await store.get_value("backup_jobs", default=[])
    return {
        "enabled": bool(jobs),
        "jobs": jobs,
    }


@router.post("/jobs", status_code=status.HTTP_201_CREATED)
async def create_backup_job(
    req: CreateJobRequest,
    user: dict = Depends(get_current_user),
) -> dict:
    """Create a new backup job configuration and persist it."""
    jobs = await store.get_value("backup_jobs", default=[])
    if len(jobs) >= _MAX_JOBS:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Maximum number of backup jobs reached",
        )

    job: dict = {
        "id": uuid.uuid4().hex[:12],
        "phoneFolder": req.phoneFolder,
        "destination": req.destination,
        "lastSyncAt": None,
        "totalUploaded": 0,
        "totalSkipped": 0,
    }
    jobs.append(job)
    await store.set_value("backup_jobs", jobs)
    return job


@router.delete("/jobs/{job_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_backup_job(
    job_id: str,
    user: dict = Depends(get_current_user),
) -> None:
    """Remove a backup job configuration by ID."""
    jobs = await store.get_value("backup_jobs", default=[])
    updated = [j for j in jobs if j.get("id") != job_id]
    if len(updated) == len(jobs):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Backup job not found")
    await store.set_value("backup_jobs", updated)


@router.post("/jobs/{job_id}/report")
async def report_sync_run(
    job_id: str,
    req: SyncReportRequest,
    user: dict = Depends(get_current_user),
) -> dict:
    """Update a job's stats after a completed sync run."""
    jobs = await store.get_value("backup_jobs", default=[])
    for job in jobs:
        if job.get("id") == job_id:
            job["totalUploaded"] = job.get("totalUploaded", 0) + req.uploaded
            job["totalSkipped"] = job.get("totalSkipped", 0) + req.skipped
            job["lastSyncAt"] = req.lastSyncAt
            await store.set_value("backup_jobs", jobs)
            return job
    raise HTTPException(status.HTTP_404_NOT_FOUND, "Backup job not found")


# ── Telegram backup notification ─────────────────────────────────────────────

class BackupNotifyRequest(BaseModel):
    success: bool
    uploaded: int = 0
    skipped: int = 0
    folders: int = 0
    error_message: str = ""


@router.post("/notify")
async def send_backup_notification(
    req: BackupNotifyRequest,
    user: dict = Depends(get_current_user),
) -> dict:
    """Send a backup summary or failure notification via the Telegram bot."""
    try:
        from .. import telegram_bot as tb
    except ImportError:
        return {"sent": False, "reason": "telegram_not_available"}

    if tb._application is None:
        return {"sent": False, "reason": "telegram_not_configured"}

    linked_ids = await tb._get_linked_ids()
    if not linked_ids:
        return {"sent": False, "reason": "no_linked_users"}

    if req.success:
        lines = ["✅ <b>Backup complete</b>\n"]
        lines.append(
            f"📁 {req.folders} folder{'s' if req.folders != 1 else ''} checked"
        )
        if req.uploaded > 0:
            lines.append(
                f"⬆️ {req.uploaded} file{'s' if req.uploaded != 1 else ''} uploaded"
            )
        if req.skipped > 0:
            lines.append(f"⏭ {req.skipped} already synced")
        if req.uploaded == 0 and req.skipped == 0:
            lines.append("✨ Everything is up to date")
        msg = "\n".join(lines)
    else:
        msg = f"❌ <b>Backup failed</b>\n\n{req.error_message or 'Unknown error'}"

    sent = 0
    for chat_id in linked_ids:
        with suppress(Exception):
            await tb._application.bot.send_message(
                chat_id=chat_id, text=msg, parse_mode="HTML"
            )
            sent += 1

    return {"sent": True, "recipients": sent}
