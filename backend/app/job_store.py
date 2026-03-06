"""
In-memory job tracking for long-running operations.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from enum import Enum
from typing import Any
from uuid import uuid4


class JobStatus(str, Enum):
    pending = "pending"
    running = "running"
    completed = "completed"
    failed = "failed"


@dataclass
class Job:
    id: str
    status: JobStatus
    started_at: datetime
    result: Any = None
    error: str | None = None


_jobs: dict[str, Job] = {}
_MAX_JOBS = 100
_JOB_TTL = timedelta(hours=1)


def _purge_old_jobs() -> None:
    """Remove completed/failed jobs older than _JOB_TTL, keep at most _MAX_JOBS."""
    now = datetime.now(timezone.utc)
    expired = [
        jid for jid, job in _jobs.items()
        if job.status in (JobStatus.completed, JobStatus.failed)
        and (now - job.started_at) > _JOB_TTL
    ]
    for jid in expired:
        del _jobs[jid]
    # If still over limit, remove oldest completed/failed first
    if len(_jobs) > _MAX_JOBS:
        finished = sorted(
            [(jid, j) for jid, j in _jobs.items()
             if j.status in (JobStatus.completed, JobStatus.failed)],
            key=lambda x: x[1].started_at,
        )
        for jid, _ in finished[:len(_jobs) - _MAX_JOBS]:
            del _jobs[jid]


def create_job() -> Job:
    _purge_old_jobs()
    job = Job(
        id=uuid4().hex,
        status=JobStatus.pending,
        started_at=datetime.now(timezone.utc),
    )
    _jobs[job.id] = job
    return job


def update_job(
    job_id: str,
    *,
    status: JobStatus | None = None,
    result: Any = None,
    error: str | None = None,
) -> Job | None:
    job = _jobs.get(job_id)
    if not job:
        return None

    if status is not None:
        job.status = status
    if result is not None:
        job.result = result
    if error is not None:
        job.error = error

    return job


def get_job(job_id: str) -> Job | None:
    return _jobs.get(job_id)
