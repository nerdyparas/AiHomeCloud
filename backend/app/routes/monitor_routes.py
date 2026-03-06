"""
WebSocket endpoint — streams live system stats every 2 seconds.
Uses psutil for real CPU / RAM / temp / network / disk readings.
Respects board-specific thermal zone paths for accurate temperature readings.
"""

import asyncio
import json
import time

import psutil
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from shutil import disk_usage

from ..config import settings
from .event_routes import emit_storage_warning

router = APIRouter(tags=["monitor"])

# Track boot time once
_boot_time = psutil.boot_time()

# Track network counters for delta calculation
_prev_net = psutil.net_io_counters()
_prev_time = time.time()


def _read_system_stats(thermal_zone_path: str = None) -> dict:
    """
    Gather real system metrics.
    
    Args:
        thermal_zone_path: Optional board-specific path to thermal zone temp file.
                          If provided, will read from this path instead of psutil sensors.
    """
    global _prev_net, _prev_time

    # CPU & RAM
    cpu = psutil.cpu_percent(interval=None)
    ram = psutil.virtual_memory().percent

    # Temperature — try board-specific path first, then fall back to psutil sensors
    temp = 0.0
    
    # Try board-specific thermal zone path if available
    if thermal_zone_path:
        try:
            with open(thermal_zone_path, "r") as f:
                temp_millidegrees = int(f.read().strip())
                temp = temp_millidegrees / 1000.0  # Convert millidegrees C to degrees C
        except Exception:
            # Fall through to psutil approach
            pass
    
    # Fall back to psutil sensors if board path didn't work or wasn't provided
    if temp == 0.0:
        temps = psutil.sensors_temperatures()
        if temps:
            # Common keys: 'cpu_thermal', 'coretemp', 'soc_thermal'
            for key in ("cpu_thermal", "soc_thermal", "coretemp"):
                if key in temps and temps[key]:
                    temp = temps[key][0].current
                    break
            if temp == 0.0:
                # Fallback: first available sensor
                first = next(iter(temps.values()), [])
                if first:
                    temp = first[0].current

    # Uptime
    uptime_sec = int(time.time() - _boot_time)

    # Network throughput (delta)
    now_time = time.time()
    now_net = psutil.net_io_counters()
    dt = now_time - _prev_time if now_time != _prev_time else 1.0
    up_mbps = ((now_net.bytes_sent - _prev_net.bytes_sent) * 8) / (dt * 1_000_000)
    down_mbps = ((now_net.bytes_recv - _prev_net.bytes_recv) * 8) / (dt * 1_000_000)
    _prev_net = now_net
    _prev_time = now_time

    # Disk
    try:
        usage = disk_usage(str(settings.nas_root))
        total_gb = usage.total / (1024 ** 3)
        used_gb = usage.used / (1024 ** 3)
    except Exception:
        total_gb = settings.total_storage_gb
        used_gb = 0.0

    return {
        "cpuPercent": round(cpu, 1),
        "ramPercent": round(ram, 1),
        "tempCelsius": round(temp, 1),
        "uptimeSeconds": uptime_sec,
        "networkUpMbps": round(up_mbps, 2),
        "networkDownMbps": round(down_mbps, 2),
        "storage": {
            "totalGB": round(total_gb, 1),
            "usedGB": round(used_gb, 1),
        },
    }


@router.websocket("/ws/monitor")
async def monitor_ws(ws: WebSocket):
    """
    Stream system stats to the Flutter app every 2 seconds.
    Uses board-specific thermal zone path for accurate temperature readings.
    No auth on the WS itself — the app should already be paired.
    """
    await ws.accept()

    # Get board-specific thermal zone path from app state
    board = getattr(ws.app.state, 'board', None)
    thermal_zone_path = board.thermal_zone_path if board else None

    # Prime the CPU meter (first call always returns 0)
    psutil.cpu_percent(interval=None)

    # Throttle storage warnings (at most once per 5 minutes)
    _last_storage_warn = 0

    try:
        while True:
            stats = _read_system_stats(thermal_zone_path)
            await ws.send_text(json.dumps(stats))

            # Check storage thresholds periodically
            storage = stats["storage"]
            total = storage["totalGB"]
            used = storage["usedGB"]
            if total > 0:
                pct = (used / total) * 100
                free = total - used
                now = time.time()
                if pct >= 85 and (now - _last_storage_warn) > 300:
                    _last_storage_warn = now
                    await emit_storage_warning(pct, free)

            await asyncio.sleep(2)
    except WebSocketDisconnect:
        pass
    except Exception:
        await ws.close()
