"""
Network routes — WiFi status, user toggle, and LAN network status.
"""

import logging
from pathlib import Path

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..auth import get_current_user
from ..models import NetworkStatus
from ..subprocess_runner import run_command
from ..wifi_manager import get_wifi_status, set_user_wifi_override

logger = logging.getLogger("cubie.network")

router = APIRouter(prefix="/api/v1", tags=["network"])


@router.get("/network/status", response_model=NetworkStatus)
async def network_status(_user: dict = Depends(get_current_user)):
    """Return LAN-only network state for ethernet-connected device."""
    lan_connected = False
    lan_ip = None
    lan_speed = None

    net_dir = Path("/sys/class/net")
    if net_dir.exists():
        for iface in sorted(net_dir.iterdir()):
            name = iface.name
            if name == "lo" or name.startswith("wl") or name.startswith("docker") or name.startswith("veth"):
                continue
            operstate = iface / "operstate"
            if operstate.exists():
                try:
                    state = operstate.read_text().strip()
                except OSError:
                    continue
                if state != "up":
                    continue
                lan_connected = True
                # Get IP address
                rc, out, _ = await run_command(["ip", "-4", "addr", "show", name])
                if rc == 0:
                    for line in out.splitlines():
                        line = line.strip()
                        if line.startswith("inet "):
                            lan_ip = line.split()[1].split("/")[0]
                            break
                # Get link speed
                speed_file = iface / "speed"
                if speed_file.exists():
                    try:
                        speed_val = speed_file.read_text().strip()
                        if speed_val.lstrip("-").isdigit() and int(speed_val) > 0:
                            lan_speed = f"{speed_val} Mb/s"
                    except OSError:
                        pass
                break

    return NetworkStatus(
        wifiEnabled=False,
        wifiConnected=False,
        wifiSsid=None,
        wifiIp=None,
        hotspotEnabled=False,
        hotspotSsid=None,
        bluetoothEnabled=False,
        lanConnected=lan_connected,
        lanIp=lan_ip,
        lanSpeed=lan_speed,
        gateway=None,
        dns=None,
    )


@router.get("/network/wifi")
async def wifi_status(_user: dict = Depends(get_current_user)):
    """Return WiFi radio state, Ethernet link status, and user override flag."""
    return await get_wifi_status()


class WifiToggleRequest(BaseModel):
    enabled: bool


@router.put("/network/wifi")
async def toggle_wifi(body: WifiToggleRequest, _user: dict = Depends(get_current_user)):
    """Toggle WiFi radio."""
    await set_user_wifi_override(body.enabled)
    return await get_wifi_status()
