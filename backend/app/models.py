"""
Pydantic models — mirror the Flutter models exactly so JSON serialization
matches what the app expects.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


# ─── CubieDevice ─────────────────────────────────────────────────────────────

class CubieDevice(BaseModel):
    serial: str
    name: str
    ip: str
    firmware_version: str = Field(alias="firmwareVersion")

    model_config = {"populate_by_name": True}


# ─── StorageStats ────────────────────────────────────────────────────────────

class StorageStats(BaseModel):
    total_gb: float = Field(alias="totalGB")
    used_gb: float = Field(alias="usedGB")

    model_config = {"populate_by_name": True}

    @property
    def free_gb(self) -> float:
        return self.total_gb - self.used_gb

    @property
    def used_percent(self) -> float:
        return min(max(self.used_gb / self.total_gb, 0.0), 1.0)


# ─── SystemStats ─────────────────────────────────────────────────────────────

class SystemStats(BaseModel):
    cpu_percent: float = Field(alias="cpuPercent")
    ram_percent: float = Field(alias="ramPercent")
    temp_celsius: float = Field(alias="tempCelsius")
    uptime_seconds: int = Field(alias="uptimeSeconds")
    network_up_mbps: float = Field(alias="networkUpMbps")
    network_down_mbps: float = Field(alias="networkDownMbps")
    storage: StorageStats

    model_config = {"populate_by_name": True}


# ─── FileItem ────────────────────────────────────────────────────────────────

class FileItem(BaseModel):
    name: str
    path: str
    is_directory: bool = Field(alias="isDirectory")
    size_bytes: int = Field(alias="sizeBytes")
    modified: datetime
    mime_type: Optional[str] = Field(None, alias="mimeType")

    model_config = {"populate_by_name": True}


class FileListResponse(BaseModel):
    items: list[FileItem]
    total_count: int = Field(alias="totalCount")
    page: int
    page_size: int = Field(alias="pageSize")

    model_config = {"populate_by_name": True}


# ─── FamilyUser ──────────────────────────────────────────────────────────────

class FamilyUser(BaseModel):
    id: str
    name: str
    is_admin: bool = Field(alias="isAdmin")
    folder_size_gb: float = Field(alias="folderSizeGB")
    avatar_color: str = Field(alias="avatarColor")  # hex string e.g. "FFE8A84C"

    model_config = {"populate_by_name": True}


# ─── ServiceInfo ─────────────────────────────────────────────────────────────

class ServiceInfo(BaseModel):
    id: str
    name: str
    description: str
    is_enabled: bool = Field(alias="isEnabled")

    model_config = {"populate_by_name": True}


# ─── StorageDevice ───────────────────────────────────────────────────────────

class StorageDevice(BaseModel):
    """A block device (partition) detected on the system."""
    name: str                                          # "sda1", "nvme0n1p1"
    path: str                                          # "/dev/sda1"
    size_bytes: int = Field(alias="sizeBytes")          # raw byte count
    size_display: str = Field(alias="sizeDisplay")      # "64.0 GB"
    fstype: Optional[str] = None                        # "ext4", None if unformatted
    label: Optional[str] = None                         # partition label
    model: Optional[str] = None                         # "SanDisk Ultra"
    transport: str                                      # "usb", "nvme", "sd"
    mounted: bool = False
    mount_point: Optional[str] = Field(None, alias="mountPoint")
    is_nas_active: bool = Field(False, alias="isNasActive")
    is_os_disk: bool = Field(False, alias="isOsDisk")   # True for SD card OS

    model_config = {"populate_by_name": True}


# ─── Storage Requests ────────────────────────────────────────────────────────

class FormatRequest(BaseModel):
    """Format a block device. confirmDevice must match device for safety."""
    device: str                                         # "/dev/sda1"
    label: str = "CubieNAS"                             # ext4 label
    confirm_device: str = Field(alias="confirmDevice")  # must match device

    model_config = {"populate_by_name": True}


class MountRequest(BaseModel):
    """Mount a block device at the NAS root."""
    device: str                                         # "/dev/sda1"


class EjectRequest(BaseModel):
    """Eject a specific device (unmount + power off)."""
    device: str                                         # "/dev/sda1"


# ─── Request / Response helpers ──────────────────────────────────────────────

class PairRequest(BaseModel):
    serial: str
    key: str


class LoginRequest(BaseModel):
    name: str
    pin: str


class RefreshRequest(BaseModel):
    refresh_token: str = Field(alias="refreshToken")

    model_config = {"populate_by_name": True}


class TokenResponse(BaseModel):
    token: str


class CreateUserRequest(BaseModel):
    name: str
    pin: Optional[str] = None


class RefreshTokenRecord(BaseModel):
    jti: str
    user_id: str = Field(alias="userId")
    issued_at: int = Field(alias="issuedAt")
    expires_at: int = Field(alias="expiresAt")
    revoked: bool = False

    model_config = {"populate_by_name": True}


class ChangePinRequest(BaseModel):
    old_pin: Optional[str] = Field(None, alias="oldPin")
    new_pin: str = Field(alias="newPin")

    model_config = {"populate_by_name": True}


class UpdateNameRequest(BaseModel):
    name: str


class CreateFolderRequest(BaseModel):
    path: str


class RenameRequest(BaseModel):
    old_path: str = Field(alias="oldPath")
    new_name: str = Field(alias="newName")

    model_config = {"populate_by_name": True}


class ToggleServiceRequest(BaseModel):
    enabled: bool


class AddFamilyUserRequest(BaseModel):
    name: str


class FirmwareInfo(BaseModel):
    current_version: str
    latest_version: str
    update_available: bool
    changelog: str
    size_mb: float


# ─── Network ─────────────────────────────────────────────────────────────────

class NetworkStatus(BaseModel):
    """Aggregated network state for the Cubie device."""
    wifi_enabled: bool = Field(alias="wifiEnabled")
    wifi_connected: bool = Field(alias="wifiConnected")
    wifi_ssid: Optional[str] = Field(None, alias="wifiSsid")
    wifi_ip: Optional[str] = Field(None, alias="wifiIp")
    hotspot_enabled: bool = Field(alias="hotspotEnabled")
    hotspot_ssid: Optional[str] = Field(None, alias="hotspotSsid")
    bluetooth_enabled: bool = Field(alias="bluetoothEnabled")
    lan_connected: bool = Field(alias="lanConnected")
    lan_ip: Optional[str] = Field(None, alias="lanIp")
    lan_speed: Optional[str] = Field(None, alias="lanSpeed")  # "1000Mb/s"

    model_config = {"populate_by_name": True}


class ToggleRequest(BaseModel):
    """Generic enable/disable toggle for wifi, hotspot, bluetooth."""
    enabled: bool
