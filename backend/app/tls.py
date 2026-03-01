"""
TLS certificate management for CubieCloud.
Auto-generates a self-signed certificate on first boot.
"""

import datetime
import logging
import socket
import subprocess
from pathlib import Path

from .config import settings

logger = logging.getLogger("cubie.tls")


def _get_local_ips() -> list[str]:
    """Gather all local IPv4 addresses for SAN entries."""
    ips = {"127.0.0.1"}
    try:
        # Connect to an external address to find our primary IP
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            ips.add(s.getsockname()[0])
    except Exception:
        pass
    return sorted(ips)


def ensure_tls_cert() -> tuple[Path, Path]:
    """
    Return (cert_path, key_path), generating a self-signed certificate
    if one does not already exist.
    """
    cert_path = settings.tls_cert_path
    key_path = settings.tls_key_path

    if cert_path.exists() and key_path.exists():
        logger.info("TLS cert already exists at %s", cert_path)
        return cert_path, key_path

    logger.info("Generating self-signed TLS certificate…")
    cert_path.parent.mkdir(parents=True, exist_ok=True)

    # Build SAN entries for local IPs + hostname
    hostname = socket.gethostname()
    ips = _get_local_ips()
    san_entries = [f"DNS:{hostname}", "DNS:localhost"]
    for ip in ips:
        san_entries.append(f"IP:{ip}")

    san_string = ",".join(san_entries)

    # Use openssl (available on every Linux)
    cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", str(key_path),
        "-out", str(cert_path),
        "-days", "3650",
        "-nodes",
        "-subj", f"/CN={hostname}/O=CubieCloud",
        "-addext", f"subjectAltName={san_string}",
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            logger.error("openssl failed: %s", result.stderr)
            raise RuntimeError(f"openssl cert generation failed: {result.stderr}")
        logger.info("✅ TLS cert generated: %s", cert_path)
    except FileNotFoundError:
        logger.error("openssl not found — cannot generate TLS certificate")
        raise RuntimeError("openssl is required for TLS cert generation")

    return cert_path, key_path
