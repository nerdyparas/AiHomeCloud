"""
Auto-AP: automatically start the Wi-Fi hotspot when no network is available.

On startup, checks if Ethernet or Wi-Fi station is connected.
If neither is available after a 10-second grace period, starts the
AiHomeCloud hotspot so the user can connect and configure the device.

A background task periodically checks connectivity:
- If a real network (LAN or Wi-Fi station) comes up, the auto-started
  hotspot is torn down automatically.
- If the network drops again, the hotspot is re-enabled.

The ``wifi_setup_connect`` coroutine is called by the ``/network/wifi/setup``
endpoint during initial onboarding: it tears down the hotspot, tries the
user-provided Wi-Fi credentials with retries (every 10 s, up to 120 s),
and powers off the device if all attempts fail.

This module only acts when ``settings.auto_ap_enabled`` is True.
"""

import asyncio
import logging

from .config import settings
from .subprocess_runner import run_command

logger = logging.getLogger("cubie.auto_ap")

# Sentinel to track whether the hotspot was started by auto-AP
# (so we don't tear down a user-started hotspot).
_auto_ap_active = False

# Background task handle
_monitor_task: asyncio.Task | None = None

# How often the background monitor checks connectivity (seconds)
_CHECK_INTERVAL = 30

# Grace period before starting hotspot on boot (seconds)
_STARTUP_DELAY = 10

# Wi-Fi setup retry parameters
_WIFI_RETRY_INTERVAL = 10  # seconds between attempts
_WIFI_RETRY_TOTAL = 120    # max seconds to keep trying


async def _run(cmd: list[str], timeout: int = 5) -> tuple[int, str, str]:
    return await run_command(cmd, timeout=timeout)


async def _has_lan() -> bool:
    """Return True if any wired Ethernet interface is UP with an IP."""
    for iface in ("eth0", "end0", "enp1s0"):
        rc, out, _ = await _run(["ip", "link", "show", iface])
        if rc == 0 and "state UP" in out:
            # Verify it has an IP
            rc2, out2, _ = await _run(["ip", "-4", "-o", "addr", "show", iface])
            if rc2 == 0 and out2.strip():
                return True
    return False


async def _has_wifi_station() -> bool:
    """Return True if connected to a Wi-Fi network in station mode (not AP)."""
    rc, out, _ = await _run([
        "nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION",
        "device", "status",
    ])
    if rc != 0:
        return False

    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) >= 4 and parts[1] == "wifi" and parts[2] == "connected":
            conn_name = parts[3]
            # Check it's station mode, not AP
            rc2, out2, _ = await _run([
                "nmcli", "-t", "-f", "802-11-wireless.mode",
                "connection", "show", conn_name,
            ])
            if rc2 == 0 and "ap" not in out2.lower():
                return True
    return False


async def _is_hotspot_active() -> bool:
    """Return True if a hotspot (AP-mode) Wi-Fi connection is active."""
    rc, out, _ = await _run([
        "nmcli", "-t", "-f", "NAME,TYPE,DEVICE",
        "connection", "show", "--active",
    ])
    if rc != 0:
        return False

    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[1] == "802-11-wireless":
            name = parts[0]
            rc2, out2, _ = await _run([
                "nmcli", "-t", "-f", "802-11-wireless.mode",
                "connection", "show", name,
            ])
            if "ap" in out2.lower():
                return True
    return False


async def _start_hotspot() -> bool:
    """Start the AiHomeCloud hotspot. Returns True on success."""
    global _auto_ap_active

    # Check if a hotspot profile already exists
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
        rc, _, err = await _run([
            "nmcli", "device", "wifi", "hotspot",
            "ifname", "wlan0",
            "ssid", settings.hotspot_ssid,
            "password", settings.hotspot_password,
        ])

    if rc != 0:
        logger.error("auto_ap_start_failed", extra={"error": err})
        return False

    _auto_ap_active = True
    logger.info(
        "auto_ap_started",
        extra={"ssid": settings.hotspot_ssid, "reason": "no network detected"},
    )
    return True


async def _stop_hotspot() -> bool:
    """Stop the auto-started hotspot. Returns True on success."""
    global _auto_ap_active

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
                rc3, _, err = await _run(["nmcli", "connection", "down", name])
                if rc3 != 0:
                    logger.error("auto_ap_stop_failed", extra={"error": err})
                    return False
                _auto_ap_active = False
                logger.info(
                    "auto_ap_stopped",
                    extra={"reason": "network connection restored"},
                )
                return True
    return False


async def _monitor_loop() -> None:
    """Background loop: check connectivity and toggle hotspot accordingly."""
    global _auto_ap_active

    while True:
        try:
            await asyncio.sleep(_CHECK_INTERVAL)

            has_network = await _has_lan() or await _has_wifi_station()

            if has_network and _auto_ap_active:
                # Network is back — tear down the auto-started hotspot
                await _stop_hotspot()

            elif not has_network and not _auto_ap_active:
                # No network — make sure hotspot is running
                if not await _is_hotspot_active():
                    await _start_hotspot()

        except asyncio.CancelledError:
            logger.info("auto_ap_monitor_cancelled")
            return
        except Exception:
            logger.exception("auto_ap_monitor_error")


async def maybe_start_auto_ap() -> None:
    """Called once at startup from lifespan. Checks connectivity and starts
    hotspot if needed, then spawns the background monitor task."""
    global _monitor_task

    if not settings.auto_ap_enabled:
        logger.info("auto_ap_disabled")
        return

    has_network = await _has_lan() or await _has_wifi_station()

    if not has_network:
        logger.info(
            "auto_ap_no_network_detected",
            extra={"delay_seconds": _STARTUP_DELAY},
        )
        # Wait before starting hotspot — gives Ethernet/Wi-Fi time to come up.
        await asyncio.sleep(_STARTUP_DELAY)

        # Re-check after the grace period
        has_network = await _has_lan() or await _has_wifi_station()
        if not has_network:
            await _start_hotspot()
        else:
            logger.info("auto_ap_network_appeared_during_wait")
    else:
        logger.info(
            "auto_ap_network_available",
            extra={"reason": "skipping hotspot startup"},
        )

    # Start background monitor regardless — it handles network drop/restore
    _monitor_task = asyncio.create_task(_monitor_loop())
    logger.info("auto_ap_monitor_started")


async def shutdown_auto_ap() -> None:
    """Cancel the background monitor task. Called during app shutdown."""
    global _monitor_task, _auto_ap_active

    if _monitor_task and not _monitor_task.done():
        _monitor_task.cancel()
        try:
            await _monitor_task
        except asyncio.CancelledError:
            pass
        _monitor_task = None

    _auto_ap_active = False
    logger.info("auto_ap_shutdown")


def is_auto_ap_active() -> bool:
    """Return True when the hotspot was started by auto-AP."""
    return _auto_ap_active


async def wifi_setup_connect(ssid: str, password: str) -> bool:
    """Tear down the auto-AP hotspot and connect to *ssid* with retries.

    Called from the ``/network/wifi/setup`` endpoint during initial
    onboarding.  Retries every ``_WIFI_RETRY_INTERVAL`` seconds up to
    ``_WIFI_RETRY_TOTAL`` seconds.  If all attempts fail the device is
    powered off.  Returns ``True`` on success.
    """
    global _auto_ap_active

    logger.info("wifi_setup_connect_start", extra={"ssid": ssid})

    # 1. Tear down hotspot so wlan0 is free for station mode
    await _stop_hotspot()
    _auto_ap_active = False

    # Brief pause for NM to release the interface
    await asyncio.sleep(2)

    # 2. Ensure Wi-Fi radio is on
    await _run(["nmcli", "radio", "wifi", "on"])
    await asyncio.sleep(1)

    # 3. Retry loop
    elapsed = 0
    attempt = 0
    while elapsed < _WIFI_RETRY_TOTAL:
        attempt += 1
        logger.info(
            "wifi_setup_attempt",
            extra={"attempt": attempt, "ssid": ssid, "elapsed": elapsed},
        )

        rc, out, err = await _run(
            ["nmcli", "device", "wifi", "connect", ssid, "password", password],
            timeout=20,
        )
        if rc == 0:
            # Wait for DHCP
            await asyncio.sleep(3)
            if await _has_wifi_station():
                logger.info("wifi_setup_connected", extra={"ssid": ssid})

                # Save as autoconnect profile
                await _run([
                    "nmcli", "connection", "modify", ssid,
                    "connection.autoconnect", "yes",
                    "connection.autoconnect-priority", "10",
                ])
                return True

        logger.warning(
            "wifi_setup_attempt_failed",
            extra={"attempt": attempt, "ssid": ssid, "error": err.strip()},
        )
        await asyncio.sleep(_WIFI_RETRY_INTERVAL)
        elapsed += _WIFI_RETRY_INTERVAL

    # 4. All retries exhausted — power off
    logger.error(
        "wifi_setup_all_retries_failed",
        extra={"ssid": ssid, "total_seconds": _WIFI_RETRY_TOTAL},
    )
    await _run(["sudo", "systemctl", "poweroff"], timeout=10)
    return False
