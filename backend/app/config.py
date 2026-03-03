"""
CubieCloud backend configuration.
All settings can be overridden via environment variables prefixed with CUBIE_.
"""

import os
import secrets
import stat
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings

JWT_SECRET_FILE = Path("/var/lib/cubie/jwt_secret")
DEFAULT_CORS_ORIGINS = ["http://localhost", "http://localhost:3000"]


def generate_jwt_secret(secret_file: Path = JWT_SECRET_FILE) -> str:
    """Return the existing JWT secret or generate one and persist it."""
    secret_file.parent.mkdir(parents=True, exist_ok=True)
    if secret_file.exists():
        return secret_file.read_text().strip()

    secret = secrets.token_hex(32)
    secret_file.write_text(secret)
    secret_file.chmod(stat.S_IRUSR | stat.S_IWUSR)
    return secret


class Settings(BaseSettings):
    model_config = {"env_prefix": "CUBIE_"}

    # ── Server ────────────────────────────────────────────────────────────────
    # Intentional for appliance-style LAN service exposure.
    host: str = "0.0.0.0"  # nosec B104
    port: int = 8443
    log_level: str = "INFO"
    cors_origins: list[str] = DEFAULT_CORS_ORIGINS.copy()

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

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, value):
        """Accept comma-separated env var values for CORS origins."""
        if value is None:
            return DEFAULT_CORS_ORIGINS.copy()

        if isinstance(value, str):
            origins = [item.strip() for item in value.split(",") if item.strip()]
            return origins or DEFAULT_CORS_ORIGINS.copy()

        if isinstance(value, list):
            return value or DEFAULT_CORS_ORIGINS.copy()

        return DEFAULT_CORS_ORIGINS.copy()


settings = Settings()

# Ensure a persistent JWT secret exists when the env var is not provided.
# Priority: CUBIE_JWT_SECRET env var > persisted file > default placeholder.
if not os.getenv("CUBIE_JWT_SECRET") and settings.jwt_secret == "change-me-in-production":
    settings.jwt_secret = generate_jwt_secret()
