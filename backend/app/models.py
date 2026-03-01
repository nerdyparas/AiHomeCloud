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


# ─── Request / Response helpers ──────────────────────────────────────────────

class PairRequest(BaseModel):
    serial: str
    key: str


class TokenResponse(BaseModel):
    token: str


class CreateUserRequest(BaseModel):
    name: str
    pin: Optional[str] = None


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
