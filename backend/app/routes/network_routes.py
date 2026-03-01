"""
Network management routes — WiFi, hotspot, Bluetooth, LAN status.
Uses nmcli, ip, ethtool, and bluetoothctl to query / toggle interfaces.
"""

import asyncio
import logging
import re

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import get_current_user, require_admin
from ..models import NetworkStatus, ToggleRequest

logger = logging.getLogger("cubie.network")

router = APIRouter(prefix="/api/network", tags=["network"])


# ─── Helpers ─────────────────────────────────────────────────────────────────

async def _run(cmd: list[str], timeout: float = 5.0) -> tuple[int, str, str]:
    """Run a subprocess and return (returncode, stdout, stderr)."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=timeout
        )
        return proc.returncode or 0, stdout.decode().strip(), stderr.decode().strip()
    except FileNotFoundError:
        return 1, "", f"Command not found: {cmd[0]}"
    except asyncio.TimeoutError:
        return 1, "", "Command timed out"
    except Exception as e:
        return 1, "", str(e)


async def _wifi_info() -> dict:
    """Get WiFi radio state and active connection info via nmcli."""
    # Check if radio is on
    rc, out, _ = await _run(["nmcli", "radio", "wifi"])
    enabled = out.strip().lower() == "enabled"

    connected = False
    ssid = None
    ip_addr = None

    if enabled:
        # Check active wifi connection
        rc, out, _ = await _run([
            "nmcli", "-t", "-f", "ACTIVE,SSID,DEVICE",
            "dev", "wifi", "list", "--rescan", "no",
        ])
        for line in out.splitlines():
            parts = line.split(":")
            if len(parts) >= 2 and parts[0].lower() == "yes":
                connected = True
                ssid = parts[1] if parts[1] else None
                break

        if not connected:
            # Fallback: check device status
            rc, out, _ = await _run([
                "nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION",
                "device", "status",
            ])
            for line in out.splitlines():
                parts = line.split(":")
                if len(parts) >= 4 and parts[1] == "wifi" and parts[2] == "connected":
                    connected = True
                    ssid = parts[3] if parts[3] else None
                    break

        if connected:
            # Get IP of wifi interface
            rc, out, _ = await _run([
                "nmcli", "-t", "-f", "IP4.ADDRESS",
                "device", "show", "wlan0",
            ])
            for line in out.splitlines():
                if "IP4.ADDRESS" in line:
                    # Format: IP4.ADDRESS[1]:192.168.0.100/24
                    match = re.search(r"(\d+\.\d+\.\d+\.\d+)", line)
                    if match:
                        ip_addr = match.group(1)
                    break

    return {
        "enabled": enabled,
        "connected": connected,
        "ssid": ssid,
        "ip": ip_addr,
    }


async def _hotspot_info() -> dict:
    """Check if a WiFi hotspot connection is active."""
    rc, out, _ = await _run([
        "nmcli", "-t", "-f", "NAME,TYPE,DEVICE",
        "connection", "show", "--active",
    ])
    enabled = False
    ssid = None
    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[1] == "802-11-wireless":
            # Check if this is a hotspot (AP mode)
            name = parts[0]
            rc2, out2, _ = await _run([
                "nmcli", "-t", "-f", "802-11-wireless.mode",
                "connection", "show", name,
            ])
            if "ap" in out2.lower():
                enabled = True
                ssid = name
                break

    return {"enabled": enabled, "ssid": ssid}


async def _bluetooth_info() -> dict:
    """Check Bluetooth power state via bluetoothctl."""
    rc, out, _ = await _run(["bluetoothctl", "show"])
    enabled = False
    for line in out.splitlines():
        if "Powered:" in line:
            enabled = "yes" in line.lower()
            break
    return {"enabled": enabled}


async def _lan_info() -> dict:
    """Get LAN (eth0/end0) link status, IP, and speed."""
    connected = False
    ip_addr = None
    speed = None

    # Try common ethernet interface names
    iface = None
    for name in ("eth0", "end0", "enp1s0"):
        rc, out, _ = await _run(["ip", "link", "show", name])
        if rc == 0 and "state UP" in out:
            iface = name
            connected = True
            break
        elif rc == 0:
            # Interface exists but not UP
            iface = name
            break

    if iface and connected:
        # Get IP
        rc, out, _ = await _run(["ip", "-4", "-o", "addr", "show", iface])
        match = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", out)
        if match:
            ip_addr = match.group(1)

        # Get link speed
        rc, out, _ = await _run(["ethtool", iface])
        for line in out.splitlines():
            if "Speed:" in line:
                speed = line.split("Speed:")[1].strip()  # e.g. "1000Mb/s"
                break

    return {
        "connected": connected,
        "ip": ip_addr,
        "speed": speed,
    }


# ─── Routes ──────────────────────────────────────────────────────────────────

@router.get("/status", response_model=NetworkStatus)
async def get_network_status(user: dict = Depends(get_current_user)):
    """Aggregated network status — WiFi, hotspot, Bluetooth, LAN."""
    wifi, hotspot, bt, lan = await asyncio.gather(
        _wifi_info(),
        _hotspot_info(),
        _bluetooth_info(),
        _lan_info(),
    )

    return NetworkStatus(
        wifi_enabled=wifi["enabled"],
        wifi_connected=wifi["connected"],
        wifi_ssid=wifi["ssid"],
        wifi_ip=wifi["ip"],
        hotspot_enabled=hotspot["enabled"],
        hotspot_ssid=hotspot["ssid"],
        bluetooth_enabled=bt["enabled"],
        lan_connected=lan["connected"],
        lan_ip=lan["ip"],
        lan_speed=lan["speed"],
    )


@router.post("/wifi", status_code=status.HTTP_204_NO_CONTENT)
async def toggle_wifi(
    body: ToggleRequest,
    user: dict = Depends(require_admin),
):
    """Enable or disable the WiFi radio."""
    action = "on" if body.enabled else "off"
    rc, _, err = await _run(["nmcli", "radio", "wifi", action])
    if rc != 0:
        logger.error("WiFi toggle failed: %s", err)
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR,
                            f"Failed to toggle WiFi: {err}")


@router.post("/hotspot", status_code=status.HTTP_204_NO_CONTENT)
async def toggle_hotspot(
    body: ToggleRequest,
    user: dict = Depends(require_admin),
):
    """Enable or disable the WiFi hotspot."""
    if body.enabled:
        # Check if a hotspot connection profile exists
        rc, out, _ = await _run([
            "nmcli", "-t", "-f", "NAME,TYPE",
            "connection", "show",
        ])
        hotspot_name = None
        for line in out.splitlines():
            parts = line.split(":")
            if len(parts) >= 2 and "hotspot" in parts[0].lower():
                hotspot_name = parts[0]
                break

        if hotspot_name:
            rc, _, err = await _run(["nmcli", "connection", "up", hotspot_name])
        else:
            # Create a new hotspot
            rc, _, err = await _run([
                "nmcli", "device", "wifi", "hotspot",
                "ifname", "wlan0",
                "ssid", "CubieCloud",
                "password", "cubiecloud",
            ])
        if rc != 0:
            logger.error("Hotspot enable failed: %s", err)
            raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR,
                                f"Failed to enable hotspot: {err}")
    else:
        # Find and deactivate the hotspot connection
        rc, out, _ = await _run([
            "nmcli", "-t", "-f", "NAME,TYPE,DEVICE",
            "connection", "show", "--active",
        ])
        for line in out.splitlines():
            parts = line.split(":")
            if len(parts) >= 2 and parts[1] == "802-11-wireless":
                name = parts[0]
                rc2, out2, _ = await _run([
                    "nmcli", "-t", "-f", "802-11-wireless.mode",
                    "connection", "show", name,
                ])
                if "ap" in out2.lower():
                    rc, _, err = await _run(["nmcli", "connection", "down", name])
                    if rc != 0:
                        logger.error("Hotspot disable failed: %s", err)
                        raise HTTPException(
                            status.HTTP_500_INTERNAL_SERVER_ERROR,
                            f"Failed to disable hotspot: {err}",
                        )
                    break


@router.post("/bluetooth", status_code=status.HTTP_204_NO_CONTENT)
async def toggle_bluetooth(
    body: ToggleRequest,
    user: dict = Depends(require_admin),
):
    """Enable or disable Bluetooth."""
    action = "on" if body.enabled else "off"
    rc, _, err = await _run(["bluetoothctl", "power", action])
    if rc != 0:
        logger.error("Bluetooth toggle failed: %s", err)
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR,
                            f"Failed to toggle Bluetooth: {err}")


@router.get("/lan")
async def get_lan_status(user: dict = Depends(get_current_user)):
    """Detailed LAN interface status."""
    lan = await _lan_info()
    return {
        "lanConnected": lan["connected"],
        "lanIp": lan["ip"],
        "lanSpeed": lan["speed"],
    }
