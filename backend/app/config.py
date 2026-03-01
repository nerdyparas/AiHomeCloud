"""
CubieCloud backend configuration.
All settings can be overridden via environment variables prefixed with CUBIE_.
"""

from pathlib import Path
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    model_config = {"env_prefix": "CUBIE_"}

    # ── Server ────────────────────────────────────────────────────────────────
    host: str = "0.0.0.0"
    port: int = 8443

    # ── JWT ────────────────────────────────────────────────────────────────────
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_hours: int = 720  # 30 days

    # ── Device ────────────────────────────────────────────────────────────────
    device_serial: str = "CUBIE-A7A-2025-001"
    device_name: str = "My CubieCloud"
    firmware_version: str = "2.1.4"
    pairing_key: str = "default-pair-key"

    # ── Storage ───────────────────────────────────────────────────────────────
    nas_root: Path = Path("/srv/nas")
    personal_base: str = "personal"
    shared_dir: str = "shared"
    total_storage_gb: float = 500.0

    # ── Upload ────────────────────────────────────────────────────────────────
    upload_chunk_size: int = 1024 * 1024  # 1 MB

    # ── Data (JSON-file-based persistence for users, services, etc.) ─────────
    data_dir: Path = Path("/var/lib/cubie")

    @property
    def personal_path(self) -> Path:
        return self.nas_root / self.personal_base

    @property
    def shared_path(self) -> Path:
        return self.nas_root / self.shared_dir

    @property
    def users_file(self) -> Path:
        return self.data_dir / "users.json"

    @property
    def services_file(self) -> Path:
        return self.data_dir / "services.json"


settings = Settings()
