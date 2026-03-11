"""
WiFi management — auto-disable WiFi when Ethernet is active.

Uses nmcli (NetworkManager) for WiFi radio control.
Reads /sys/class/net/<iface>/operstate for Ethernet link detection.
"""

import asyncio
import logging
from pathlib import Path

from .subprocess_runner import run_command

logger = logging.getLogger("cubie.wifi")

# Persistent flag: if user explicitly enables WiFi via API, don't auto-disable
_user_wifi_override = False


def _ethernet_is_up() -> bool:
    """Check if any wired Ethernet interface has carrier (operstate = 'up')."""
    net_dir = Path("/sys/class/net")
    if not net_dir.exists():
        return False
    for iface in net_dir.iterdir():
        name = iface.name
        # Skip loopback, wireless, virtual interfaces
        if name == "lo" or name.startswith("wl") or name.startswith("docker") or name.startswith("veth"):
            continue
        operstate = iface / "operstate"
        if operstate.exists():
            try:
                state = operstate.read_text().strip()
                if state == "up":
                    logger.debug("Ethernet interface %s is up", name)
                    return True
            except OSError:
                continue
    return False


async def disable_wifi() -> bool:
    """Disable WiFi radio via nmcli. Returns True on success."""
    rc, out, err = await run_command(["nmcli", "radio", "wifi", "off"], timeout=10)
    if rc == 0:
        logger.info("WiFi radio disabled")
        return True
    logger.warning("Failed to disable WiFi: %s", err)
    return False


async def enable_wifi() -> bool:
    """Enable WiFi radio via nmcli. Returns True on success."""
    rc, out, err = await run_command(["nmcli", "radio", "wifi", "on"], timeout=10)
    if rc == 0:
        logger.info("WiFi radio enabled")
        return True
    logger.warning("Failed to enable WiFi: %s", err)
    return False


async def get_wifi_status() -> dict:
    """Return current WiFi radio state and Ethernet status."""
    rc, out, err = await run_command(["nmcli", "radio", "wifi"], timeout=10)
    wifi_enabled = out.strip().lower() == "enabled" if rc == 0 else None
    return {
        "wifiEnabled": wifi_enabled,
        "ethernetUp": _ethernet_is_up(),
        "userOverride": _user_wifi_override,
    }


async def auto_disable_wifi_if_ethernet() -> None:
    """On startup: if Ethernet is up, disable WiFi (unless user overrode)."""
    global _user_wifi_override
    if _user_wifi_override:
        logger.info("WiFi auto-disable skipped — user override active")
        return
    if _ethernet_is_up():
        logger.info("Ethernet is active — disabling WiFi radio")
        await disable_wifi()
    else:
        logger.info("Ethernet is not active — keeping WiFi on")


async def set_user_wifi_override(enabled: bool) -> None:
    """User explicitly toggles WiFi — set override flag."""
    global _user_wifi_override
    _user_wifi_override = enabled
    if enabled:
        await enable_wifi()
    else:
        await disable_wifi()
