"""
AiHomeCloud backend configuration.
All settings can be overridden via environment variables prefixed with AHC_.
"""

import os
import secrets
import socket
from pathlib import Path
from typing import Any

from pydantic import field_validator
from pydantic_settings import BaseSettings

JWT_SECRET_FILE = Path("/var/lib/aihomecloud/jwt_secret")
PAIRING_KEY_FILE = Path("/var/lib/aihomecloud/pairing_key")
DEFAULT_CORS_ORIGINS = ["http://localhost", "http://localhost:3000"]


def generate_jwt_secret(secret_file: Path = JWT_SECRET_FILE) -> str:
    """Return the existing JWT secret or generate and atomically persist one.

    Uses O_CREAT|O_EXCL to avoid a TOCTOU race between checking existence and
    writing — only one concurrent starter writes the file; the other reads it.
    """
    secret_file.parent.mkdir(parents=True, exist_ok=True)
    secret = secrets.token_hex(32)
    tmp = secret_file.with_suffix(".tmp")
    try:
        fd = os.open(str(secret_file), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        try:
            os.write(fd, secret.encode())
        finally:
            os.close(fd)
        return secret
    except FileExistsError:
        return secret_file.read_text().strip()
    except Exception:
        # Clean up partial tmp if it exists, then re-raise
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass
        raise


def generate_pairing_key(key_file: Path = PAIRING_KEY_FILE) -> str:
    """Return the existing pairing key or generate and atomically persist one."""
    key_file.parent.mkdir(parents=True, exist_ok=True)
    key = secrets.token_urlsafe(16)
    try:
        fd = os.open(str(key_file), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        try:
            os.write(fd, key.encode())
        finally:
            os.close(fd)
        return key
    except FileExistsError:
        return key_file.read_text().strip()


def generate_device_serial() -> str:
    """Generate a device serial from the machine's MAC address."""
    import uuid
    mac = uuid.getnode()
    mac_hex = f"{mac:012x}".upper()
    return f"AHC-{mac_hex[-6:]}"


def generate_hotspot_password() -> str:
    """Generate a random 12-character hotspot password."""
    return secrets.token_urlsafe(9)  # yields 12 chars


def get_local_ip() -> str:
    """Get the device's primary local IP address.

    Tries interface enumeration first (works on LAN-only devices with no internet
    route).  Falls back to routing-based discovery, then 127.0.0.1.
    """
    # Method 1: Enumerate interfaces — works even without a default route.
    try:
        hostname = socket.gethostname()
        addrs = socket.getaddrinfo(hostname, None, socket.AF_INET)
        for addr in addrs:
            ip = addr[4][0]
            if not ip.startswith("127.") and not ip.startswith("169.254."):
                return ip
    except Exception:
        pass

    # Method 2: Routing-based (original approach — requires default route).
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
        finally:
            s.close()
    except Exception:
        return "127.0.0.1"


class Settings(BaseSettings):
    model_config = {"env_prefix": "AHC_"}

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
    family_dir: str = "family"
    entertainment_dir: str = "entertainment"
    total_storage_gb: float = 500.0
    skip_mount_check: bool = False  # set True in tests to bypass is_mount()

    # ── Upload ────────────────────────────────────────────────────────────────
    upload_chunk_size: int = 4 * 1024 * 1024  # 4 MB — fewer async cycles on ARM
    max_upload_bytes: int = 25 * 1024 * 1024 * 1024  # 25 GB (0 = unlimited)

    # ── Document indexing / OCR ────────────────────────────────────────────────
    # Enabled by default — tesseract (images) + pdftotext (PDFs) must be installed.
    # Disable via AHC_OCR_ENABLED=false if tools are not available.
    ocr_enabled: bool = True
    ocr_languages: str = "eng+hin"             # AHC_OCR_LANGUAGES — tesseract lang codes ('+' separated)
    document_index_pool_size: int = 3          # AHC_DOCUMENT_INDEX_POOL_SIZE — SQLite connection pool
    document_index_cache_ttl: int = 300        # AHC_DOCUMENT_INDEX_CACHE_TTL — search cache TTL (seconds)
    document_index_interval: int = 20          # AHC_DOCUMENT_INDEX_INTERVAL — watcher polling interval (seconds)

    # ── Auth ───────────────────────────────────────────────────────────────────
    bcrypt_rounds: int = 10                    # AHC_BCRYPT_ROUNDS — bcrypt work factor (10 ≈ 0.1s on ARM)

    # ── Event bus ─────────────────────────────────────────────────────────────
    event_queue_size: int = 100               # AHC_EVENT_QUEUE_SIZE — per-subscriber queue depth
    event_max_recent: int = 50                # AHC_EVENT_MAX_RECENT — recent events kept in memory

    # ── Job store ─────────────────────────────────────────────────────────────
    job_max_count: int = 100                  # AHC_JOB_MAX_COUNT — max tracked jobs
    job_ttl_hours: int = 1                    # AHC_JOB_TTL_HOURS — job retention window

    # ── File auto-sorting ──────────────────────────────────────────────────────
    # Disabled by default — polls every 30s and walks .inbox/ directories.
    # Enable via AHC_AUTO_SORT_ENABLED=true or use the /files/sort-now endpoint.
    auto_sort_enabled: bool = False

    # ── Telegram Bot (optional — disabled if token is empty) ─────────────────
    telegram_bot_token: str = ""   # AHC_TELEGRAM_BOT_TOKEN
    telegram_allowed_ids: str = ""  # AHC_TELEGRAM_ALLOWED_IDS — comma-sep chat IDs; empty = no restriction
    telegram_api_id: int = 0          # from my.telegram.org — needed for local server
    telegram_api_hash: str = ""       # from my.telegram.org — needed for local server
    telegram_local_api_enabled: bool = False   # True when local server is running
    telegram_local_api_url: str = "http://127.0.0.1:8081"  # local server address
    telegram_download_timeout: int = 600  # AHC_TELEGRAM_DOWNLOAD_TIMEOUT — seconds for file transfers


    # ── Data (JSON-file-based persistence for users, services, etc.) ─────────
    data_dir: Path = Path("/var/lib/aihomecloud")

    @property
    def personal_path(self) -> Path:
        return self.nas_root / self.personal_base

    @property
    def family_path(self) -> Path:
        return self.nas_root / self.family_dir

    @property
    def entertainment_path(self) -> Path:
        return self.nas_root / self.entertainment_dir

    @property
    def shared_path(self) -> Path:
        # Alias for family_path — use family_path in new code
        return self.nas_root / self.family_dir

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
        return self.nas_root / ".ahc_trash"

    @property
    def trash_file(self) -> Path:
        """JSON metadata file for trash items."""
        return self.data_dir / "trash.json"

    @property
    def index_watcher_state_file(self) -> Path:
        """JSON snapshot of document index watcher state (persisted across restarts)."""
        return self.data_dir / "index_watcher_state.json"

    @property
    def jobs_file(self) -> Path:
        """JSON file for persisting long-running job status across restarts."""
        return self.data_dir / "jobs.json"

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, value: Any) -> list[str]:
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
if not os.getenv("AHC_JWT_SECRET") and settings.jwt_secret == "change-me-in-production":
    try:
        settings.jwt_secret = generate_jwt_secret()
    except PermissionError:
        # CI / test environment — can't write to disk, use in-memory secret
        settings.jwt_secret = secrets.token_hex(32)
    except Exception:
        import logging as _logging
        _logging.getLogger("aihomecloud.config").critical(
            "FATAL: Cannot generate JWT secret and no AHC_JWT_SECRET env var set. "
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
