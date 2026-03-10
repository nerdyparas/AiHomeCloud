"""
Network management routes — WiFi, hotspot, Bluetooth, LAN status.
Uses nmcli, ip, ethtool, and bluetoothctl to query / toggle interfaces.
"""

import asyncio
import logging
import re

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import get_current_user, require_admin
from ..config import settings
from ..models import (
    NetworkStatus, ToggleRequest, WifiNetwork, WifiConnectRequest,
    WifiConnectionResult, WifiSetupRequest, WifiSetupResponse,
)
from ..subprocess_runner import run_command

logger = logging.getLogger("cubie.network")

router = APIRouter(prefix="/api/v1/network", tags=["network"])


# ─── Helpers ─────────────────────────────────────────────────────────────────

async def _run(cmd: list[str], timeout: float = 5.0) -> tuple[int, str, str]:
    """Delegate to centralized subprocess runner."""
    return await run_command(cmd, timeout=int(timeout))


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


async def _gateway_dns_info() -> dict:
    """Return default gateway IP and DNS nameservers."""
    gateway = None
    dns_servers: list[str] = []

    # Gateway from ip route
    rc, out, _ = await _run(["ip", "route", "show", "default"])
    if rc == 0:
        for line in out.splitlines():
            if "default via" in line:
                parts = line.split()
                try:
                    gateway = parts[parts.index("via") + 1]
                    break
                except (ValueError, IndexError):
                    pass

    # DNS from resolv.conf
    try:
        with open("/etc/resolv.conf") as f:
            for line in f:
                line = line.strip()
                if line.startswith("nameserver"):
                    parts = line.split()
                    if len(parts) >= 2:
                        dns_servers.append(parts[1])
    except OSError:
        pass

    return {"gateway": gateway, "dns": dns_servers or None}


# ─── Routes ──────────────────────────────────────────────────────────────────

@router.get("/status", response_model=NetworkStatus)
async def get_network_status(user: dict = Depends(get_current_user)):
    """Aggregated network status — WiFi, hotspot, Bluetooth, LAN."""
    wifi, hotspot, bt, lan, gw = await asyncio.gather(
        _wifi_info(),
        _hotspot_info(),
        _bluetooth_info(),
        _lan_info(),
        _gateway_dns_info(),
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
        gateway=gw["gateway"],
        dns=gw["dns"],
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
                "ssid", settings.hotspot_ssid,
                "password", settings.hotspot_password,
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


# ─── Auto-AP settings ───────────────────────────────────────────────────────

@router.get("/auto-ap")
async def get_auto_ap_setting(user: dict = Depends(get_current_user)):
    """Get the current auto-AP configuration."""
    from ..auto_ap import _auto_ap_active
    return {
        "enabled": settings.auto_ap_enabled,
        "hotspotSsid": settings.hotspot_ssid,
        "autoApActive": _auto_ap_active,
    }


@router.put("/auto-ap", status_code=status.HTTP_204_NO_CONTENT)
async def set_auto_ap_setting(
    body: ToggleRequest,
    user: dict = Depends(require_admin),
):
    """Enable or disable the auto-AP feature.

    When disabled, the auto-started hotspot (if running) is torn down
    and the background monitor stops checking.
    """
    from ..auto_ap import (
        _auto_ap_active, _stop_hotspot,
        maybe_start_auto_ap, shutdown_auto_ap,
    )

    settings.auto_ap_enabled = body.enabled

    if not body.enabled and _auto_ap_active:
        # Disable: stop the auto-started hotspot and cancel monitor
        await shutdown_auto_ap()
        await _stop_hotspot()
        logger.info("auto_ap_disabled_by_user")
    elif body.enabled:
        # Re-enable: start the monitor (and hotspot if needed)
        await maybe_start_auto_ap()
        logger.info("auto_ap_enabled_by_user")


@router.get("/lan")
async def get_lan_status(user: dict = Depends(get_current_user)):
    """Detailed LAN interface status."""
    lan = await _lan_info()
    return {
        "lanConnected": lan["connected"],
        "lanIp": lan["ip"],
        "lanSpeed": lan["speed"],
    }


# ─── Wi-Fi scan / connect / disconnect / forget ─────────────────────────────

@router.get("/wifi/scan", response_model=list[WifiNetwork])
async def scan_wifi_networks(user: dict = Depends(get_current_user)):
    """Scan for available Wi-Fi networks.

    Returns a de-duplicated list sorted by signal strength.
    """
    # Ensure radio is on
    rc, out, _ = await _run(["nmcli", "radio", "wifi"])
    if out.strip().lower() != "enabled":
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "Wi-Fi radio is turned off. Enable it first.",
        )

    # Trigger a fresh scan (best-effort; may fail if already scanning)
    await _run(["nmcli", "device", "wifi", "rescan"], timeout=10)
    # Short pause to let results populate
    await asyncio.sleep(0.5)

    # Fetch scan results in terse format
    rc, out, _ = await _run([
        "nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY",
        "device", "wifi", "list", "--rescan", "no",
    ])
    if rc != 0:
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "Failed to list Wi-Fi networks.",
        )

    # Get saved connection names
    rc2, saved_out, _ = await _run([
        "nmcli", "-t", "-f", "NAME,TYPE",
        "connection", "show",
    ])
    saved_names: set[str] = set()
    for line in saved_out.splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[1] == "802-11-wireless":
            saved_names.add(parts[0])

    # Parse and de-duplicate (keep highest signal per SSID)
    best: dict[str, WifiNetwork] = {}
    for line in out.splitlines():
        # IN-USE:SSID:SIGNAL:SECURITY  (IN-USE is "*" or "")
        parts = line.split(":")
        if len(parts) < 4:
            continue
        in_use = parts[0].strip() == "*"
        ssid = parts[1].strip()
        if not ssid:
            continue  # hidden networks
        try:
            signal = int(parts[2].strip())
        except ValueError:
            signal = 0
        security = parts[3].strip() or "Open"

        network = WifiNetwork(
            ssid=ssid,
            signal=signal,
            security=security,
            in_use=in_use,
            saved=ssid in saved_names,
        )
        existing = best.get(ssid)
        if existing is None or signal > existing.signal or (in_use and not existing.in_use):
            best[ssid] = network

    # Sort: connected first, then by signal descending
    result = sorted(best.values(), key=lambda n: (not n.in_use, -n.signal))
    return result


@router.post("/wifi/connect", response_model=WifiConnectionResult)
async def connect_wifi(
    body: WifiConnectRequest,
    user: dict = Depends(require_admin),
):
    """Add / update a Wi-Fi network profile.

    If Ethernet is active the profile is **saved only** (fallback).
    If Ethernet is down the profile is saved and activated immediately.
    """
    ssid = body.ssid.strip()
    if not ssid:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "SSID is required.")

    # Detect whether Ethernet is currently active
    eth_active = False
    for iface in ("eth0", "end0", "enp1s0"):
        rc, out, _ = await _run(["ip", "link", "show", iface])
        if rc == 0 and "state UP" in out:
            eth_active = True
            break

    # Check if a saved connection already exists for this SSID
    rc, out, _ = await _run([
        "nmcli", "-t", "-f", "NAME,TYPE",
        "connection", "show",
    ])
    existing_name = None
    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[0] == ssid and parts[1] == "802-11-wireless":
            existing_name = parts[0]
            break

    if existing_name and body.password:
        # Update the password on the existing profile
        await _run([
            "nmcli", "connection", "modify", existing_name,
            "wifi-sec.key-mgmt", "wpa-psk",
            "wifi-sec.psk", body.password,
        ])
        if not eth_active:
            rc, _, err = await _run(
                ["nmcli", "connection", "up", existing_name],
                timeout=30,
            )
        else:
            rc, err = 0, ""
    elif existing_name:
        if not eth_active:
            # Re-activate saved profile without changing password
            rc, _, err = await _run(
                ["nmcli", "connection", "up", existing_name],
                timeout=30,
            )
        else:
            rc, err = 0, ""
    else:
        if not eth_active:
            # Create and connect immediately
            cmd = [
                "nmcli", "device", "wifi", "connect", ssid,
            ]
            if body.password:
                cmd += ["password", body.password]
            rc, _, err = await _run(cmd, timeout=30)
        else:
            # Save profile only — don't activate while Ethernet is up
            cmd = [
                "nmcli", "connection", "add",
                "type", "wifi",
                "con-name", ssid,
                "ssid", ssid,
                "autoconnect", "no",
            ]
            if body.password:
                cmd += [
                    "wifi-sec.key-mgmt", "wpa-psk",
                    "wifi-sec.psk", body.password,
                ]
            rc, _, err = await _run(cmd, timeout=15)

    if rc != 0:
        # Differentiate wrong password from other errors
        lower_err = err.lower()
        if "secrets were required" in lower_err or "no suitable" in lower_err:
            msg = "Incorrect password."
        elif "no network with ssid" in lower_err:
            msg = "Network not found."
        else:
            msg = err.strip() or "Failed to save network."
        logger.warning("wifi_connect_failed ssid=%s err=%s", ssid, err)
        return WifiConnectionResult(success=False, message=msg)

    # Ensure autoconnect as fallback with lower priority than wired
    await _run([
        "nmcli", "connection", "modify", ssid,
        "connection.autoconnect", "yes",
        "connection.autoconnect-priority", "10",
    ])

    if eth_active:
        # Bring down WiFi if NM auto-activated it during profile creation
        rc_chk, act_out, _ = await _run([
            "nmcli", "-t", "-f", "NAME,TYPE,DEVICE",
            "connection", "show", "--active",
        ])
        for act_line in act_out.splitlines():
            act_parts = act_line.split(":")
            if (len(act_parts) >= 3
                    and act_parts[0] == ssid
                    and act_parts[1] == "802-11-wireless"):
                await _run(["nmcli", "connection", "down", ssid])
                break

        logger.info("wifi_saved_fallback ssid=%s", ssid)
        return WifiConnectionResult(
            success=True,
            message=f"Saved {ssid} as fallback",
        )

    # Fetch the allocated IP (only when we actually connected)
    ip_addr = None
    await asyncio.sleep(2)  # let DHCP complete
    rc, out, _ = await _run([
        "nmcli", "-t", "-f", "IP4.ADDRESS",
        "device", "show", "wlan0",
    ])
    for line in out.splitlines():
        match = re.search(r"(\d+\.\d+\.\d+\.\d+)", line)
        if match:
            ip_addr = match.group(1)
            break

    logger.info("wifi_connected ssid=%s ip=%s", ssid, ip_addr)
    return WifiConnectionResult(
        success=True,
        message=f"Connected to {ssid}",
        ip=ip_addr,
    )


@router.post("/wifi/setup", response_model=WifiSetupResponse)
async def wifi_setup(body: WifiSetupRequest):
    """Accept home Wi-Fi credentials during initial onboarding.

    **No authentication required** — the endpoint is only available when:
    - The auto-AP hotspot is currently active, OR
    - No users have been created yet (first-time setup).

    On success, the backend tears down the hotspot and connects to the
    specified Wi-Fi network in a background task (retries every 10 s,
    up to 120 s total).  If all attempts fail the device powers off.
    """
    from ..auto_ap import is_auto_ap_active, wifi_setup_connect
    from ..store import get_users

    # Gate: only during initial setup
    users = await get_users()
    if not is_auto_ap_active() and len(users) > 0:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Wi-Fi setup is only available during initial device setup.",
        )

    ssid = body.ssid.strip()
    if not ssid:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "SSID is required.")

    # Kick off the connect-with-retry in a background task so the response
    # reaches the client before the hotspot is torn down.
    asyncio.create_task(wifi_setup_connect(ssid, body.password))

    logger.info("wifi_setup_accepted ssid=%s", ssid)
    return WifiSetupResponse(
        accepted=True,
        message="Wi-Fi credentials accepted. AiHomeCloud is connecting to your network.",
    )


@router.post("/wifi/disconnect", status_code=status.HTTP_204_NO_CONTENT)
async def disconnect_wifi(user: dict = Depends(require_admin)):
    """Disconnect from the current Wi-Fi network (keeps saved profile)."""
    rc, out, _ = await _run([
        "nmcli", "-t", "-f", "NAME,TYPE,DEVICE",
        "connection", "show", "--active",
    ])
    disconnected = False
    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) >= 3 and parts[1] == "802-11-wireless" and parts[2] == "wlan0":
            name = parts[0]
            # Skip hotspot connections
            rc2, mode_out, _ = await _run([
                "nmcli", "-t", "-f", "802-11-wireless.mode",
                "connection", "show", name,
            ])
            if "ap" in mode_out.lower():
                continue
            rc, _, err = await _run(["nmcli", "connection", "down", name])
            if rc != 0:
                raise HTTPException(
                    status.HTTP_500_INTERNAL_SERVER_ERROR,
                    f"Failed to disconnect: {err}",
                )
            disconnected = True
            break

    if not disconnected:
        raise HTTPException(status.HTTP_409_CONFLICT, "No active Wi-Fi connection.")


@router.delete("/wifi/saved/{ssid}", status_code=status.HTTP_204_NO_CONTENT)
async def forget_wifi_network(
    ssid: str,
    user: dict = Depends(require_admin),
):
    """Remove a saved Wi-Fi network profile from NetworkManager."""
    # Find the connection by name matching the SSID
    rc, out, _ = await _run([
        "nmcli", "-t", "-f", "NAME,TYPE",
        "connection", "show",
    ])
    found = False
    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[0] == ssid and parts[1] == "802-11-wireless":
            rc, _, err = await _run(["nmcli", "connection", "delete", ssid])
            if rc != 0:
                raise HTTPException(
                    status.HTTP_500_INTERNAL_SERVER_ERROR,
                    f"Failed to forget network: {err}",
                )
            found = True
            break

    if not found:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Saved network not found.")


@router.get("/wifi/saved", response_model=list[WifiNetwork])
async def list_saved_wifi_networks(user: dict = Depends(get_current_user)):
    """List saved Wi-Fi network profiles from NetworkManager.

    Returns profiles even if the network is not currently in range.
    """
    rc, out, _ = await _run([
        "nmcli", "-t", "-f", "NAME,TYPE",
        "connection", "show",
    ])
    if rc != 0:
        return []

    # Get active connections to mark inUse
    rc2, active_out, _ = await _run([
        "nmcli", "-t", "-f", "NAME,TYPE,DEVICE",
        "connection", "show", "--active",
    ])
    active_names: set[str] = set()
    for line in active_out.splitlines():
        parts = line.split(":")
        if len(parts) >= 3 and parts[1] == "802-11-wireless":
            # Check it's station mode, not AP
            name = parts[0]
            rc3, mode_out, _ = await _run([
                "nmcli", "-t", "-f", "802-11-wireless.mode",
                "connection", "show", name,
            ])
            if rc3 == 0 and "ap" not in mode_out.lower():
                active_names.add(name)

    results: list[WifiNetwork] = []
    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[1] == "802-11-wireless":
            name = parts[0]
            # Skip hotspot profiles
            rc4, mode_out, _ = await _run([
                "nmcli", "-t", "-f", "802-11-wireless.mode",
                "connection", "show", name,
            ])
            if rc4 == 0 and "ap" in mode_out.lower():
                continue

            # Get security type
            rc5, sec_out, _ = await _run([
                "nmcli", "-t", "-f", "802-11-wireless-security.key-mgmt",
                "connection", "show", name,
            ])
            security = "Open"
            if rc5 == 0 and sec_out.strip():
                km = sec_out.split(":")[-1].strip()
                if "wpa" in km:
                    security = "WPA2" if "wpa-psk" in km else km.upper()

            results.append(WifiNetwork(
                ssid=name,
                signal=0,  # not in range — unknown
                security=security,
                in_use=name in active_names,
                saved=True,
            ))

    return results
