"""
Board abstraction layer for multi-SBC support (Cubie A7Z, Raspberry Pi 4, etc).

Handles:
- Board model detection from /proc/device-tree/model
- Thermal zone path resolution (auto-detect or fallback)
- LAN interface discovery (future)
- CPU governor path mapping
"""

import os
import logging
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class BoardConfig:
    """Immutable hardware board configuration."""
    model_name: str
    thermal_zone_path: str
    lan_interface: str
    cpu_governor_path: str


# Known board configurations (thermal_zone_path is auto-detected at runtime)
KNOWN_BOARDS: dict[str, BoardConfig] = {
    "Radxa CUBIE A7Z": BoardConfig(
        model_name="Radxa CUBIE A7Z",
        thermal_zone_path="",  # Will be overridden by auto-detection
        lan_interface="eth0",
        cpu_governor_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",
    ),
    "Raspberry Pi 4 Model B": BoardConfig(
        model_name="Raspberry Pi 4 Model B",
        thermal_zone_path="",  # Will be overridden by auto-detection
        lan_interface="eth0",
        cpu_governor_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",
    ),
}

# Fallback default board (thermal_zone_path is auto-detected at runtime)
DEFAULT_BOARD = BoardConfig(
    model_name="unknown",
    thermal_zone_path="",  # Will be overridden by auto-detection
    lan_interface="eth0",
    cpu_governor_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",
)


def find_thermal_zone() -> str:
    """
    Auto-detect the appropriate thermal zone path by scanning /sys/class/thermal/.
    
    Scans thermal_zone0, thermal_zone1, etc. for the first zone whose 'type' file
    contains 'cpu' or 'soc' (case-insensitive). Falls back to thermal_zone0 if
    no matching zone is found.
    
    Returns:
        Path string like "/sys/class/thermal/thermal_zone0/temp" (or thermal_zone1, etc).
    """
    thermal_base = Path("/sys/class/thermal")
    
    # Try to find a thermal zone with cpu or soc in its type
    try:
        if thermal_base.exists():
            # List all thermal_zone* directories
            zones = sorted(thermal_base.glob("thermal_zone*"))
            for zone_dir in zones:
                type_file = zone_dir / "type"
                try:
                    with open(type_file, "r") as f:
                        zone_type = f.read().strip().lower()
                        if "cpu" in zone_type or "soc" in zone_type:
                            thermal_zone_path = str(zone_dir / "temp")
                            logger.info(
                                "thermal_zone_detected",
                                path=thermal_zone_path,
                                zone_type=zone_type,
                            )
                            return thermal_zone_path
                except (FileNotFoundError, OSError):
                    # Zone directory exists but can't read type, continue to next
                    continue
    except Exception as e:
        logger.debug(
            "thermal_zone_scan_error",
            error=str(e),
        )
    
    # Fallback to thermal_zone0
    fallback_path = "/sys/class/thermal/thermal_zone0/temp"
    logger.info(
        "thermal_zone_fallback",
        path=fallback_path,
        reason="no_cpu_or_soc_zone_found",
    )
    return fallback_path


def detect_board() -> BoardConfig:
    """
    Detect the current board by reading /proc/device-tree/model.
    Auto-detects thermal zone path by scanning /sys/class/thermal/.
    
    Falls back to DEFAULT_BOARD if detection fails or board not recognized.
    Logs the detected board and thermal zone at startup.
    
    Returns:
        BoardConfig matching the detected board, with auto-detected thermal zone path.
    """
    model_name = None
    
    try:
        with open("/proc/device-tree/model", "r") as f:
            model_name = f.read().rstrip("\x00\n")  # Strip null bytes and newlines
    except (FileNotFoundError, OSError) as e:
        logger.warning(
            "board_detection_failed",
            path="/proc/device-tree/model",
            error=str(e),
        )
        thermal_zone_path = find_thermal_zone()
        board = BoardConfig(
            model_name=DEFAULT_BOARD.model_name,
            thermal_zone_path=thermal_zone_path,
            lan_interface=DEFAULT_BOARD.lan_interface,
            cpu_governor_path=DEFAULT_BOARD.cpu_governor_path,
        )
        logger.info("board_detected", model_name=board.model_name, reason="fallback")
        return board
    
    # Look up in known boards
    if model_name in KNOWN_BOARDS:
        base_board = KNOWN_BOARDS[model_name]
        thermal_zone_path = find_thermal_zone()
        board = BoardConfig(
            model_name=base_board.model_name,
            thermal_zone_path=thermal_zone_path,
            lan_interface=base_board.lan_interface,
            cpu_governor_path=base_board.cpu_governor_path,
        )
        logger.info(
            "board_detected",
            model_name=board.model_name,
            thermal_zone=board.thermal_zone_path,
            lan_interface=board.lan_interface,
        )
        return board
    
    # Unknown board, use defaults with auto-detected thermal zone
    thermal_zone_path = find_thermal_zone()
    board = BoardConfig(
        model_name=DEFAULT_BOARD.model_name,
        thermal_zone_path=thermal_zone_path,
        lan_interface=DEFAULT_BOARD.lan_interface,
        cpu_governor_path=DEFAULT_BOARD.cpu_governor_path,
    )
    logger.warning(
        "board_unknown",
        model_name=model_name,
        falling_back_to=DEFAULT_BOARD.model_name,
    )
    logger.info(
        "board_detected",
        model_name=board.model_name,
        thermal_zone=board.thermal_zone_path,
        reason="unknown_model_fallback",
    )
    return board
