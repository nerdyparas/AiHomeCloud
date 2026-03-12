"""
AiHomeCloud backend configuration.
All settings can be overridden via environment variables prefixed with CUBIE_.
"""

import os
import secrets
import socket
import stat
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings

JWT_SECRET_FILE = Path("/var/lib/cubie/jwt_secret")
PAIRING_KEY_FILE = Path("/var/lib/cubie/pairing_key")
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


def generate_pairing_key(key_file: Path = PAIRING_KEY_FILE) -> str:
    """Return the existing pairing key or generate one and persist it."""
    key_file.parent.mkdir(parents=True, exist_ok=True)
    if key_file.exists():
        return key_file.read_text().strip()

    key = secrets.token_urlsafe(16)
    key_file.write_text(key)
    key_file.chmod(stat.S_IRUSR | stat.S_IWUSR)
    return key


def generate_device_serial() -> str:
    """Generate a device serial from the machine's MAC address."""
    import uuid
    mac = uuid.getnode()
    mac_hex = f"{mac:012x}".upper()
    return f"CUBIE-{mac_hex[-6:]}"


def generate_hotspot_password() -> str:
    """Generate a random 12-character hotspot password."""
    return secrets.token_urlsafe(9)  # yields 12 chars


def get_local_ip() -> str:
    """Get the device's primary local IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


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
    jwt_expire_hours: int = 1  # 1 hour — use refresh tokens for longer sessions

    # ── Device ────────────────────────────────────────────────────────────────
    device_serial: str = ""  # auto-generated from MAC address if empty
    device_name: str = "My AiHomeCloud"
    firmware_version: str = "2.1.4"
    pairing_key: str = ""  # auto-generated and persisted if empty

    # ── Storage ───────────────────────────────────────────────────────────────
    nas_root: Path = Path("/srv/nas")
    personal_base: str = "personal"
    shared_dir: str = "shared"
    total_storage_gb: float = 500.0
    skip_mount_check: bool = False  # set True in tests to bypass is_mount()

    # ── Upload ────────────────────────────────────────────────────────────────
    upload_chunk_size: int = 4 * 1024 * 1024  # 4 MB — fewer async cycles on ARM
    max_upload_bytes: int = 5 * 1024 * 1024 * 1024  # 5 GB (0 = unlimited)

    # ── AdGuard Home (optional — proxy disabled when False) ───────────────────
    adguard_enabled: bool = False   # CUBIE_ADGUARD_ENABLED
    adguard_password: str = ""      # CUBIE_ADGUARD_PASSWORD — AdGuard admin password

    # ── Telegram Bot (optional — disabled if token is empty) ─────────────────
    telegram_bot_token: str = ""   # CUBIE_TELEGRAM_BOT_TOKEN
    telegram_allowed_ids: str = ""  # CUBIE_TELEGRAM_ALLOWED_IDS — comma-sep chat IDs; empty = no restriction
    telegram_api_id: int = 0          # from my.telegram.org — needed for local server
    telegram_api_hash: str = ""       # from my.telegram.org — needed for local server
    telegram_local_api_enabled: bool = False   # True when local server is running
    telegram_local_api_url: str = "http://127.0.0.1:8081"  # local server address

    # ── SQLite file index (feature-flagged — off by default) ──────────────────
    enable_sqlite: bool = False   # CUBIE_ENABLE_SQLITE — creates file_index + ai_jobs tables when True

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
    def tokens_file(self) -> Path:
        return self.data_dir / "tokens.json"

    @property
    def cert_dir(self) -> Path:
        return self.data_dir / "tls"

    @property
    def tls_cert_path(self) -> Path:
        return Path(self.tls_cert_file) if self.tls_cert_file else self.cert_dir / "cert.pem"

    @property
    def tls_key_path(self) -> Path:
        return Path(self.tls_key_file) if self.tls_key_file else self.cert_dir / "key.pem"

    @property
    def trash_dir(self) -> Path:
        """Hidden trash directory at the root of the NAS mount."""
        return self.nas_root / ".cubie_trash"

    @property
    def trash_file(self) -> Path:
        """JSON metadata file for trash items."""
        return self.data_dir / "trash.json"

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
if not os.getenv("CUBIE_JWT_SECRET") and settings.jwt_secret == "change-me-in-production":
    try:
        settings.jwt_secret = generate_jwt_secret()
    except Exception:
        import logging as _logging
        _logging.getLogger("cubie.config").critical(
            "FATAL: Cannot generate JWT secret and no CUBIE_JWT_SECRET env var set. "
            "Refusing to start with insecure default."
        )
        raise SystemExit(1)

# Auto-generate pairing key if not provided.
if not settings.pairing_key:
    try:
        settings.pairing_key = generate_pairing_key()
    except PermissionError:
        settings.pairing_key = secrets.token_urlsafe(16)

# Auto-generate device serial from MAC address if not provided.
if not settings.device_serial:
    settings.device_serial = generate_device_serial()
