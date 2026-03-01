"""
WebSocket endpoint — streams live system stats every 2 seconds.
Uses psutil for real CPU / RAM / temp / network / disk readings.
"""

import asyncio
import json
import time

import psutil
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from shutil import disk_usage

from ..config import settings

router = APIRouter(tags=["monitor"])

# Track boot time once
_boot_time = psutil.boot_time()

# Track network counters for delta calculation
_prev_net = psutil.net_io_counters()
_prev_time = time.time()


def _read_system_stats() -> dict:
    """Gather real system metrics."""
    global _prev_net, _prev_time

    # CPU & RAM
    cpu = psutil.cpu_percent(interval=None)
    ram = psutil.virtual_memory().percent

    # Temperature — try thermal zones (Linux ARM)
    temp = 0.0
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
    No auth on the WS itself — the app should already be paired.
    """
    await ws.accept()

    # Prime the CPU meter (first call always returns 0)
    psutil.cpu_percent(interval=None)

    try:
        while True:
            stats = _read_system_stats()
            await ws.send_text(json.dumps(stats))
            await asyncio.sleep(2)
    except WebSocketDisconnect:
        pass
    except Exception:
        await ws.close()
