"""
Structured JSON logging configuration for the backend.
"""

from __future__ import annotations

import logging
from contextvars import ContextVar
from typing import Any

from pythonjsonlogger import jsonlogger


_request_id_ctx: ContextVar[str] = ContextVar("request_id", default="-")


class _RequestIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = _request_id_ctx.get()
        return True


def set_request_id(request_id: str) -> Any:
    return _request_id_ctx.set(request_id)


def reset_request_id(token: Any) -> None:
    _request_id_ctx.reset(token)


def configure_logging(log_level: str) -> None:
    """Configure root logger to emit structured JSON lines."""
    level = getattr(logging, (log_level or "INFO").upper(), logging.INFO)

    handler = logging.StreamHandler()
    handler.setLevel(level)
    handler.addFilter(_RequestIdFilter())
    handler.setFormatter(
        jsonlogger.JsonFormatter(
            "%(asctime)s %(levelname)s %(name)s %(message)s %(module)s %(request_id)s",
            rename_fields={
                "asctime": "ts",
                "levelname": "level",
                "message": "msg",
            },
        )
    )

    root = logging.getLogger()
    root.handlers.clear()
    root.setLevel(level)
    root.addHandler(handler)
