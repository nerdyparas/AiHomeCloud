"""
In-memory job tracking for long-running operations.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
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


def create_job() -> Job:
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
