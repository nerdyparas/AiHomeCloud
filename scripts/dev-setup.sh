#!/usr/bin/env bash
# =============================================================================
# AiHomeCloud — Dev-mode backend setup
#
# Use this script when the backend is run directly from the cloned repo
# (no /opt/aihomecloud install) as the current login user.
#
# Tested on: Radxa ROCK Pi 4A — Armbian Ubuntu 24.04 Noble (kernel 6.x rockchip64)
# Also works on: Radxa Cubie A7Z, Raspberry Pi 4, or any Ubuntu/Debian ARM64 SBC.
#
# Usage:
#   sudo bash scripts/dev-setup.sh
#
# What it does (idempotent — safe to re-run):
#   1. Installs system packages: avahi-daemon, avahi-utils, openssl, and optionally
#      samba/minidlna/tesseract if not already present
#   2. Deploys the Avahi mDNS service definition → instant LAN discovery in app
#   3. Creates Python venv and installs dependencies if not already present
#   4. Generates a persistent pairing key in $DATA_DIR if not present
#   5. Installs /etc/systemd/system/aihomecloud.service (system-level, survives reboot)
#   6. Disables the user-level (~/.config/systemd/user/) service to avoid conflicts
#   7. Adds /etc/sudoers.d/aihomecloud for passwordless storage/service ops
#   8. Ensures data dirs and NAS dirs exist, owned by repo user
#   9. Cleans up any path-traversal artifacts (evil_link from pytest)
#  10. Enables + starts (or restarts) the service and runs a health check
#
# Key lessons from first-run on Rock Pi 4A (2026-03-15):
#   - avahi-daemon was pre-installed but service definition wasn't deployed
#   - The aihomecloud systemd user (and /opt/aihomecloud) does NOT exist on a fresh clone
#   - sudo calls in route handlers MUST use -n (non-interactive) to avoid 30s hangs
#   - /var/lib/aihomecloud and /srv/nas must be owned by the repo user (not root)
#   - User-level systemd service (loginctl linger) works for dev; system-level is preferred
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[AiHomeCloud]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run with sudo: sudo bash $0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
VENV_DIR="$BACKEND_DIR/.venv"
VENV_PYTHON="$VENV_DIR/bin/python"
# The login user who owns the repo (caller before sudo escalation)
REPO_USER="${SUDO_USER:-$(logname 2>/dev/null || echo paras)}"
SERVICE_FILE="/etc/systemd/system/aihomecloud.service"
AVAHI_SVC_DIR="/etc/avahi/services"
AVAHI_SVC_FILE="$AVAHI_SVC_DIR/aihomecloud.service"
DATA_DIR="/var/lib/aihomecloud"
NAS_ROOT="/srv/nas"

log "=== AiHomeCloud Dev Setup ==="
log "Repo     : $REPO_ROOT"
log "Backend  : $BACKEND_DIR"
log "Run-as   : $REPO_USER"
log "OS       : $(lsb_release -ds 2>/dev/null || uname -r)"
log "Board    : $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo 'unknown')"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────────
[[ -d "$BACKEND_DIR" ]] || die "Backend directory not found: $BACKEND_DIR"

# ── Step 1: Install system packages ──────────────────────────────────────────
log "[1/10] Installing system packages..."

REQUIRED_PKGS=(avahi-daemon avahi-utils openssl python3 python3-venv python3-pip lsof curl)
OPTIONAL_PKGS=(samba minidlna tesseract-ocr poppler-utils)

TO_INSTALL=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null 2>&1 || TO_INSTALL+=("$pkg")
done
if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    apt-get update -qq
    apt-get install -y --no-install-recommends "${TO_INSTALL[@]}"
    log "  Installed: ${TO_INSTALL[*]}"
else
    log "  Required packages already installed."
fi

# Install optional packages silently (best-effort)
OPT_MISSING=()
for pkg in "${OPTIONAL_PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null 2>&1 || OPT_MISSING+=("$pkg")
done
if [[ ${#OPT_MISSING[@]} -gt 0 ]]; then
    log "  Optional packages not installed (install manually if needed): ${OPT_MISSING[*]}"
fi

# Ensure avahi-daemon is running
if ! systemctl is-active --quiet avahi-daemon; then
    systemctl enable avahi-daemon
    systemctl start avahi-daemon
    log "  avahi-daemon started."
else
    log "  avahi-daemon running."
fi

# ── Step 2: Deploy Avahi mDNS service definition ─────────────────────────────
log "[2/10] Deploying Avahi mDNS service definition..."
MDNS_SRC="$REPO_ROOT/backend/scripts/aihomecloud-mdns.service"
[[ -f "$MDNS_SRC" ]] || die "mDNS service file not found: $MDNS_SRC"
mkdir -p "$AVAHI_SVC_DIR"
cp "$MDNS_SRC" "$AVAHI_SVC_FILE"
chmod 644 "$AVAHI_SVC_FILE"
# Avahi hot-reloads service files via inotify — no explicit reload needed
log "  Deployed: $AVAHI_SVC_FILE"
log "  mDNS type: _aihomecloud-nas._tcp on port 8443"

# ── Step 3: Create Python venv + install dependencies ────────────────────────
log "[3/10] Setting up Python venv..."
if [[ ! -f "$VENV_PYTHON" ]]; then
    log "  Creating venv at $VENV_DIR ..."
    sudo -u "$REPO_USER" python3 -m venv "$VENV_DIR"
    log "  Venv created."
else
    log "  Venv already exists."
fi

REQUIREMENTS="$BACKEND_DIR/requirements.txt"
if [[ -f "$REQUIREMENTS" ]]; then
    log "  Installing Python dependencies (this may take a few minutes)..."
    sudo -u "$REPO_USER" "$VENV_DIR/bin/pip" install --quiet --upgrade pip
    sudo -u "$REPO_USER" "$VENV_DIR/bin/pip" install --quiet -r "$REQUIREMENTS"
    log "  Dependencies installed."
else
    warn "  requirements.txt not found — skipping pip install."
fi

# ── Step 4: Ensure data/NAS dirs owned by repo user ──────────────────────────
log "[4/10] Creating data directories..."
mkdir -p "$DATA_DIR/tls" \
    "$NAS_ROOT/personal" "$NAS_ROOT/family" "$NAS_ROOT/entertainment" \
    "$NAS_ROOT/entertainment/Movies" "$NAS_ROOT/entertainment/Music"
chown -R "$REPO_USER:$REPO_USER" "$DATA_DIR" "$NAS_ROOT"
chmod 750 "$DATA_DIR"
log "  Data dir : $DATA_DIR (owned by $REPO_USER)"
log "  NAS root : $NAS_ROOT (owned by $REPO_USER)"

# ── Step 5: Generate device serial + pairing key ─────────────────────────────
log "[5/10] Generating device credentials..."
MAC=$(ip link show | awk '/ether / {print $2}' | head -1 | tr -d ':' | tr '[:lower:]' '[:upper:]')
AUTO_SERIAL="AHC-$(hostname -s | tr '[:lower:]' '[:upper:]')-${MAC: -4}"

PAIRING_KEY_FILE="$DATA_DIR/pairing_key"
if [[ -f "$PAIRING_KEY_FILE" ]]; then
    PAIRING_KEY="$(cat "$PAIRING_KEY_FILE")"
    log "  Pairing key: existing (from $PAIRING_KEY_FILE)"
else
    PAIRING_KEY="$(openssl rand -hex 16)"
    echo "$PAIRING_KEY" > "$PAIRING_KEY_FILE"
    chmod 600 "$PAIRING_KEY_FILE"
    chown "$REPO_USER:$REPO_USER" "$PAIRING_KEY_FILE"
    log "  Pairing key: generated → $PAIRING_KEY_FILE"
fi
log "  Device serial: $AUTO_SERIAL"

# ── Step 6: Install system-level systemd service ─────────────────────────────
log "[6/10] Installing systemd service (system-level)..."

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=AiHomeCloud Backend API
After=network.target avahi-daemon.service

[Service]
SyslogIdentifier=aihomecloud
Type=simple
User=$REPO_USER
Group=$REPO_USER
WorkingDirectory=$BACKEND_DIR
ExecStart=$VENV_PYTHON -m app.main
Restart=always
RestartSec=5
NoNewPrivileges=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service

Environment=AHC_DEVICE_SERIAL=$AUTO_SERIAL
Environment=AHC_PAIRING_KEY=$PAIRING_KEY
Environment=AHC_NAS_ROOT=$NAS_ROOT
Environment=AHC_DATA_DIR=$DATA_DIR
Environment=AHC_TLS_ENABLED=true
# /srv/nas is a plain directory in dev (no physical drive mounted)
Environment=AHC_SKIP_MOUNT_CHECK=true

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$SERVICE_FILE"
log "  Service file written: $SERVICE_FILE"

# ── Step 7: Disable conflicting user-level service ───────────────────────────
log "[7/10] Ensuring no duplicate user-level service conflicts..."
USER_SERVICE_FILE="/home/$REPO_USER/.config/systemd/user/aihomecloud.service"
if [[ -f "$USER_SERVICE_FILE" ]]; then
    sudo -u "$REPO_USER" systemctl --user stop aihomecloud 2>/dev/null || true
    sudo -u "$REPO_USER" systemctl --user disable aihomecloud 2>/dev/null || true
    log "  Disabled user-level service (replaced by system-level)."
else
    log "  No user-level service found."
fi

# ── Step 8: Add sudoers rules for storage operations ─────────────────────────
log "[8/10] Installing sudoers rules..."
SUDOERS_FILE="/etc/sudoers.d/aihomecloud"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    cat > "$SUDOERS_FILE" << EOF
# AiHomeCloud backend — passwordless sudo for storage and service management
# These rules are required because run_command() uses sudo -n (non-interactive).
# Without NOPASSWD, all storage operations silently fail (sudo -n exits immediately
# when a password would be required, returning rc=1 instead of blocking).
$REPO_USER ALL=(root) NOPASSWD: /bin/mount, /bin/umount, /usr/bin/mount, /usr/bin/umount
$REPO_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start minidlna, /usr/bin/systemctl stop minidlna, /usr/bin/systemctl restart minidlna, /usr/bin/systemctl enable minidlna
$REPO_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start smbd, /usr/bin/systemctl stop smbd, /usr/bin/systemctl restart smbd, /usr/bin/systemctl start nmbd, /usr/bin/systemctl stop nmbd
$REPO_USER ALL=(root) NOPASSWD: /sbin/mkfs.ext4, /sbin/mkfs.exfat, /sbin/mkfs.vfat, /sbin/mkfs.ntfs
$REPO_USER ALL=(root) NOPASSWD: /sbin/parted, /usr/sbin/parted
$REPO_USER ALL=(root) NOPASSWD: /sbin/sgdisk, /usr/sbin/sgdisk
EOF
    chmod 440 "$SUDOERS_FILE"
    log "  Sudoers rules installed: $SUDOERS_FILE"
else
    log "  Sudoers rules already exist."
fi

# ── Step 9: Remove path-traversal test artifact ───────────────────────────────
log "[9/10] Cleaning up security artifacts..."
EVIL="$NAS_ROOT/evil_link"
if [[ -L "$EVIL" ]] || [[ -e "$EVIL" ]]; then
    rm -f "$EVIL"
    log "  Removed path-traversal artifact: $EVIL"
else
    log "  No artifacts found."
fi

# ── Step 10: Enable and start service ────────────────────────────────────────
log "[10/10] Starting aihomecloud service..."
systemctl daemon-reload
systemctl enable aihomecloud

if systemctl is-active --quiet aihomecloud; then
    systemctl restart aihomecloud
    log "  Service restarted."
else
    systemctl start aihomecloud
    log "  Service started."
fi

sleep 3

# ── Health check ──────────────────────────────────────────────────────────────
echo ""
if curl -sk --max-time 5 "https://localhost:8443/api/health" | grep -q '"ok"'; then
    log "  Health check PASSED ✓"
    log "  Identity:"
    curl -sk "https://localhost:8443/" | python3 -m json.tool 2>/dev/null || true
else
    warn "  Health check failed. Check logs:"
    warn "    sudo journalctl -u aihomecloud -n 40 --no-pager"
fi

# ── mDNS verification ─────────────────────────────────────────────────────────
echo ""
log "  mDNS advertisement:"
if command -v avahi-browse &>/dev/null; then
    avahi-browse -t _aihomecloud-nas._tcp 2>/dev/null | head -5 || true
fi

echo ""
log "=== Setup Complete ==="
echo ""
echo -e "  ${GREEN}Backend URL  :${NC} https://$(hostname -I | awk '{print $1}'):8443"
echo -e "  ${GREEN}Device serial:${NC} $AUTO_SERIAL"
echo -e "  ${GREEN}Health check :${NC} curl -sk https://localhost:8443/api/health"
echo -e "  ${GREEN}Logs (live)  :${NC} sudo journalctl -u aihomecloud -f"
echo -e "  ${GREEN}mDNS type    :${NC} _aihomecloud-nas._tcp (Flutter fast discovery)"
echo -e "  ${GREEN}mDNS verify  :${NC} avahi-browse -t _aihomecloud-nas._tcp"
echo ""

