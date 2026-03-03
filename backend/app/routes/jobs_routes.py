"""
Job status routes.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ..auth import get_current_user
from ..job_store import get_job

router = APIRouter(prefix="/api/v1/jobs", tags=["jobs"])


@router.get("/{job_id}")
async def get_job_status(job_id: str, user: dict = Depends(get_current_user)):
    job = get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    return {
        "id": job.id,
        "status": job.status.value,
        "startedAt": job.started_at.isoformat(),
        "result": job.result,
        "error": job.error,
    }
