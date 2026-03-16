"""Lightweight audit logger — writes structured records to the app log."""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger("aihomecloud.audit")


def audit_log(event: str, **kwargs: Any) -> None:
    """Log an audit event with structured context."""
    logger.info("AUDIT %s %s", event, kwargs)
