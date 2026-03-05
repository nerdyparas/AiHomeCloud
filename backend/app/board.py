"""
Board abstraction layer for multi-SBC support (Cubie A7Z, Raspberry Pi 4, etc).

Handles:
- Board model detection from /proc/device-tree/model
- Thermal zone path resolution
- LAN interface discovery
- CPU governor path mapping
"""

import os
import logging
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class BoardConfig:
    """Immutable hardware board configuration."""
    model_name: str
    thermal_zone_path: str
    lan_interface: str
    cpu_governor_path: str


# Known board configurations
KNOWN_BOARDS: dict[str, BoardConfig] = {
    "Radxa CUBIE A7Z": BoardConfig(
        model_name="Radxa CUBIE A7Z",
        thermal_zone_path="/sys/class/thermal/thermal_zone0/temp",
        lan_interface="eth0",
        cpu_governor_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",
    ),
    "Raspberry Pi 4 Model B": BoardConfig(
        model_name="Raspberry Pi 4 Model B",
        thermal_zone_path="/sys/class/thermal/thermal_zone0/temp",
        lan_interface="eth0",
        cpu_governor_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",
    ),
}

# Fallback default board
DEFAULT_BOARD = BoardConfig(
    model_name="unknown",
    thermal_zone_path="/sys/class/thermal/thermal_zone0/temp",
    lan_interface="eth0",
    cpu_governor_path="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor",
)


def detect_board() -> BoardConfig:
    """
    Detect the current board by reading /proc/device-tree/model.
    
    Falls back to DEFAULT_BOARD if detection fails or board not recognized.
    Logs the detected board at startup.
    
    Returns:
        BoardConfig matching the detected board, or DEFAULT_BOARD as fallback.
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
        board = DEFAULT_BOARD
        logger.info("board_detected", model_name=board.model_name, reason="fallback")
        return board
    
    # Look up in known boards
    if model_name in KNOWN_BOARDS:
        board = KNOWN_BOARDS[model_name]
        logger.info(
            "board_detected",
            model_name=board.model_name,
            thermal_zone=board.thermal_zone_path,
            lan_interface=board.lan_interface,
        )
        return board
    
    # Unknown board, use defaults
    logger.warning(
        "board_unknown",
        model_name=model_name,
        falling_back_to=DEFAULT_BOARD.model_name,
    )
    logger.info(
        "board_detected",
        model_name=DEFAULT_BOARD.model_name,
        reason="unknown_model_fallback",
    )
    return DEFAULT_BOARD
