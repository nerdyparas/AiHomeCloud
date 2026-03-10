"""
In-app event bus for AiHomeCloud.
Broadcasts events to all connected WebSocket clients (Flutter apps).
"""

import asyncio
import json
import logging
import time
from enum import Enum
from dataclasses import dataclass, asdict
from typing import Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query

logger = logging.getLogger("cubie.events")

router = APIRouter(tags=["events"])


# ─── Event types ─────────────────────────────────────────────────────────────

class EventSeverity(str, Enum):
    info = "info"
    success = "success"
    warning = "warning"
    error = "error"


@dataclass
class AppEvent:
    type: str            # e.g. "upload_complete", "storage_warning"
    title: str
    body: str
    severity: str        # EventSeverity value
    timestamp: float     # epoch seconds
    data: Optional[dict] = None

    def to_json(self) -> str:
        return json.dumps(asdict(self))


# ─── Global event bus ────────────────────────────────────────────────────────

class EventBus:
    """Simple pub-sub for broadcasting events to WebSocket clients."""

    def __init__(self):
        self._subscribers: list[asyncio.Queue] = []
        self._recent: list[AppEvent] = []
        self._max_recent = 50

    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=100)
        self._subscribers.append(q)
        return q

    def unsubscribe(self, q: asyncio.Queue):
        self._subscribers = [s for s in self._subscribers if s is not q]

    async def publish(self, event: AppEvent):
        """Broadcast event to all subscribers."""
        self._recent.append(event)
        if len(self._recent) > self._max_recent:
            self._recent = self._recent[-self._max_recent:]

        dead = []
        for q in self._subscribers:
            try:
                q.put_nowait(event)
            except asyncio.QueueFull:
                dead.append(q)
        for q in dead:
            self._subscribers = [s for s in self._subscribers if s is not q]

        logger.debug("Event published: %s (%d subscribers)", event.type, len(self._subscribers))

    @property
    def subscriber_count(self) -> int:
        return len(self._subscribers)


# Singleton
event_bus = EventBus()


# ─── Convenience emitters ───────────────────────────────────────────────────

async def emit_upload_complete(file_name: str, user_name: str):
    await event_bus.publish(AppEvent(
        type="upload_complete",
        title="Upload Complete",
        body=f"{file_name} uploaded by {user_name}",
        severity=EventSeverity.success.value,
        timestamp=time.time(),
        data={"fileName": file_name, "userName": user_name},
    ))


async def emit_storage_warning(used_percent: float, free_gb: float):
    if used_percent >= 95:
        severity = EventSeverity.error.value
        title = "Storage Critical"
        body = f"Only {free_gb:.1f} GB free ({used_percent:.0f}% full)"
    elif used_percent >= 85:
        severity = EventSeverity.warning.value
        title = "Storage Low"
        body = f"{free_gb:.1f} GB remaining ({used_percent:.0f}% full)"
    else:
        return  # No warning needed

    await event_bus.publish(AppEvent(
        type="storage_warning",
        title=title,
        body=body,
        severity=severity,
        timestamp=time.time(),
        data={"usedPercent": used_percent, "freeGB": free_gb},
    ))


async def emit_service_toggled(service_name: str, enabled: bool):
    await event_bus.publish(AppEvent(
        type="service_toggled",
        title=f"{service_name} {'Started' if enabled else 'Stopped'}",
        body=f"{service_name} has been {'enabled' if enabled else 'disabled'}",
        severity=EventSeverity.info.value,
        timestamp=time.time(),
        data={"serviceName": service_name, "enabled": enabled},
    ))


async def emit_device_mounted(device: str, mount_point: str):
    await event_bus.publish(AppEvent(
        type="device_mounted",
        title="Storage Mounted",
        body=f"{device} mounted at {mount_point}",
        severity=EventSeverity.success.value,
        timestamp=time.time(),
        data={"device": device, "mountPoint": mount_point},
    ))


async def emit_device_ejected(device: str):
    await event_bus.publish(AppEvent(
        type="device_ejected",
        title="Device Ejected",
        body=f"{device} safely removed",
        severity=EventSeverity.info.value,
        timestamp=time.time(),
        data={"device": device},
    ))


# ─── WebSocket endpoint ─────────────────────────────────────────────────────

@router.websocket("/ws/events")
async def events_ws(ws: WebSocket, token: str = Query(default=None)):
    """
    Push in-app notifications to connected Flutter clients.
    Each event is a JSON object: {type, title, body, severity, timestamp, data}.
    Requires JWT token as query parameter: /ws/events?token=<jwt>
    """
    # Authenticate before accepting
    if not token:
        await ws.close(code=4001, reason="Missing token")
        return
    try:
        from ..auth import decode_token
        decode_token(token)
    except Exception:
        await ws.close(code=4003, reason="Invalid token")
        return

    await ws.accept()
    queue = event_bus.subscribe()

    try:
        while True:
            event = await queue.get()
            await ws.send_text(event.to_json())
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        event_bus.unsubscribe(queue)
