"""
Tests for events.py (FileEventBus) and event_routes.py (EventBus, emit helpers, AppEvent).
"""

import asyncio
import time

import pytest

from app.events import FileEventBus, FileEvent, file_event_bus
from app.routes.event_routes import (
    EventBus,
    AppEvent,
    EventSeverity,
    emit_upload_complete,
    emit_storage_warning,
    emit_service_toggled,
    emit_device_mounted,
    emit_device_ejected,
    event_bus,
)


# — FileEvent ————————————————————————————————————————————————

class TestFileEvent:
    def test_creation(self):
        e = FileEvent(path="/srv/nas/file.txt", action="upload", user="alice")
        assert e.path == "/srv/nas/file.txt"
        assert e.action == "upload"
        assert e.user == "alice"
        assert e.timestamp is not None


# — FileEventBus —————————————————————————————————————————————

class TestFileEventBus:
    @pytest.mark.asyncio
    async def test_publish_and_recent(self):
        bus = FileEventBus(maxlen=10)
        event = FileEvent(path="/a", action="create", user="bob")
        await bus.publish(event)
        assert bus.buffer_len == 1
        recent = bus.recent()
        assert len(recent) == 1
        assert recent[0].path == "/a"

    @pytest.mark.asyncio
    async def test_recent_with_limit(self):
        bus = FileEventBus(maxlen=100)
        for i in range(20):
            await bus.publish(FileEvent(path=f"/{i}", action="create", user="x"))
        assert len(bus.recent(5)) == 5
        assert len(bus.recent(None)) == 20

    @pytest.mark.asyncio
    async def test_subscribe_receives_events(self):
        bus = FileEventBus(maxlen=10)
        async with bus.subscribe() as q:
            assert bus.subscriber_count == 1
            await bus.publish(FileEvent(path="/x", action="delete", user="y"))
            event = q.get_nowait()
            assert event.path == "/x"
        assert bus.subscriber_count == 0

    @pytest.mark.asyncio
    async def test_buffer_overflow_evicts_old(self):
        bus = FileEventBus(maxlen=3)
        for i in range(5):
            await bus.publish(FileEvent(path=f"/{i}", action="a", user="u"))
        assert bus.buffer_len == 3
        paths = [e.path for e in bus.recent()]
        assert paths == ["/2", "/3", "/4"]

    @pytest.mark.asyncio
    async def test_full_queue_drops_subscriber(self):
        bus = FileEventBus(maxlen=1000)
        async with bus.subscribe() as q:
            # Fill up the queue (maxsize=200)
            for i in range(201):
                await bus.publish(FileEvent(path=f"/{i}", action="a", user="u"))
        # Subscriber should be auto-removed after queue overflow
        assert bus.subscriber_count == 0


# — AppEvent ————————————————————————————————————————————————

class TestAppEvent:
    def test_to_json(self):
        e = AppEvent(
            type="test",
            title="Test",
            body="Test body",
            severity="info",
            timestamp=1234567890.0,
        )
        j = e.to_json()
        assert '"type": "test"' in j
        assert '"title": "Test"' in j

    def test_with_data(self):
        e = AppEvent(
            type="t",
            title="T",
            body="B",
            severity="info",
            timestamp=0.0,
            data={"key": "val"},
        )
        assert '"key": "val"' in e.to_json()


# — EventBus —————————————————————————————————————————————————

class TestEventBus:
    @pytest.mark.asyncio
    async def test_publish_and_subscribe(self):
        bus = EventBus()
        q = bus.subscribe()
        assert bus.subscriber_count == 1
        event = AppEvent(type="t", title="T", body="B", severity="info", timestamp=time.time())
        await bus.publish(event)
        received = q.get_nowait()
        assert received.type == "t"
        bus.unsubscribe(q)
        assert bus.subscriber_count == 0

    @pytest.mark.asyncio
    async def test_recent_events_capped(self):
        bus = EventBus()
        bus._max_recent = 5
        for i in range(10):
            await bus.publish(AppEvent(type=f"t{i}", title="T", body="B", severity="info", timestamp=float(i)))
        assert len(bus._recent) == 5

    @pytest.mark.asyncio
    async def test_full_queue_cleans_dead(self):
        bus = EventBus()
        q = bus.subscribe()
        # Fill queue beyond capacity
        for i in range(101):
            await bus.publish(AppEvent(type="t", title="T", body="B", severity="info", timestamp=float(i)))
        # Dead subscriber removed
        assert bus.subscriber_count == 0


# — emit helpers ————————————————————————————————————————————

class TestEmitHelpers:
    @pytest.mark.asyncio
    async def test_emit_upload_complete(self):
        bus = EventBus()
        q = bus.subscribe()
        # Temporarily replace singleton
        import app.routes.event_routes as mod
        original = mod.event_bus
        mod.event_bus = bus
        try:
            await emit_upload_complete("photo.jpg", "alice")
            event = q.get_nowait()
            assert event.type == "upload_complete"
            assert "photo.jpg" in event.body
        finally:
            mod.event_bus = original

    @pytest.mark.asyncio
    async def test_emit_storage_warning_critical(self):
        bus = EventBus()
        q = bus.subscribe()
        import app.routes.event_routes as mod
        original = mod.event_bus
        mod.event_bus = bus
        try:
            await emit_storage_warning(96.0, 1.5)
            event = q.get_nowait()
            assert event.type == "storage_warning"
            assert event.severity == "error"
            assert "Critical" in event.title
        finally:
            mod.event_bus = original

    @pytest.mark.asyncio
    async def test_emit_storage_warning_low(self):
        bus = EventBus()
        q = bus.subscribe()
        import app.routes.event_routes as mod
        original = mod.event_bus
        mod.event_bus = bus
        try:
            await emit_storage_warning(87.0, 5.0)
            event = q.get_nowait()
            assert event.severity == "warning"
        finally:
            mod.event_bus = original

    @pytest.mark.asyncio
    async def test_emit_storage_warning_normal_skips(self):
        bus = EventBus()
        q = bus.subscribe()
        import app.routes.event_routes as mod
        original = mod.event_bus
        mod.event_bus = bus
        try:
            await emit_storage_warning(50.0, 100.0)
            assert q.empty()
        finally:
            mod.event_bus = original

    @pytest.mark.asyncio
    async def test_emit_service_toggled(self):
        bus = EventBus()
        q = bus.subscribe()
        import app.routes.event_routes as mod
        original = mod.event_bus
        mod.event_bus = bus
        try:
            await emit_service_toggled("smbd", True)
            event = q.get_nowait()
            assert event.type == "service_toggled"
            assert "Started" in event.title
        finally:
            mod.event_bus = original

    @pytest.mark.asyncio
    async def test_emit_device_mounted(self):
        bus = EventBus()
        q = bus.subscribe()
        import app.routes.event_routes as mod
        original = mod.event_bus
        mod.event_bus = bus
        try:
            await emit_device_mounted("/dev/sda1", "/srv/nas")
            event = q.get_nowait()
            assert event.type == "device_mounted"
        finally:
            mod.event_bus = original

    @pytest.mark.asyncio
    async def test_emit_device_ejected(self):
        bus = EventBus()
        q = bus.subscribe()
        import app.routes.event_routes as mod
        original = mod.event_bus
        mod.event_bus = bus
        try:
            await emit_device_ejected("/dev/sda1")
            event = q.get_nowait()
            assert event.type == "device_ejected"
        finally:
            mod.event_bus = original


# — EventSeverity ————————————————————————————————————————————

class TestEventSeverity:
    def test_values(self):
        assert EventSeverity.info.value == "info"
        assert EventSeverity.success.value == "success"
        assert EventSeverity.warning.value == "warning"
        assert EventSeverity.error.value == "error"
