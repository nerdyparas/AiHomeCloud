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

    # ── TLS ────────────────────────────────────────────────────────────────────
    tls_enabled: bool = True
    tls_cert_file: str = ""  # auto-resolved to cert_dir/cert.pem if empty
    tls_key_file: str = ""   # auto-resolved to cert_dir/key.pem if empty

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

    @property
    def storage_file(self) -> Path:
        return self.data_dir / "storage.json"

    @property
    def cert_dir(self) -> Path:
        return self.data_dir / "tls"

    @property
    def tls_cert_path(self) -> Path:
        return Path(self.tls_cert_file) if self.tls_cert_file else self.cert_dir / "cert.pem"

    @property
    def tls_key_path(self) -> Path:
        return Path(self.tls_key_file) if self.tls_key_file else self.cert_dir / "key.pem"


settings = Settings()
