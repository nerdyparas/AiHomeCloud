#!/usr/bin/env bash
# =============================================================================
# AiHomeCloud â€” First Boot Setup Script
# Target: Ubuntu 24 ARM64 (Radxa Cubie A7Z or compatible SBC)
#
# Usage:
#   sudo bash scripts/first-boot-setup.sh
#
# This script is IDEMPOTENT â€” safe to run multiple times.
# It will not overwrite existing config, secrets, or user data.
# =============================================================================

set -euo pipefail

# â”€â”€ Colour helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[AiHomeCloud]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# â”€â”€ Must run as root â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
[[ $EUID -eq 0 ]] || die "Run this script with sudo: sudo bash $0"

# â”€â”€ Repo root (script lives in scripts/ one level below) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# â”€â”€ Configurable paths â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
APP_USER="${APP_USER:-aihomecloud}"
APP_HOME="/opt/aihomecloud"
BACKEND_SRC="$APP_HOME/backend"
VENV_DIR="$BACKEND_SRC/venv"
DATA_DIR="/var/lib/aihomecloud"
NAS_ROOT="/srv/nas"
SERVICE_NAME="aihomecloud"
SERVICE_DST="/etc/systemd/system/${SERVICE_NAME}.service"
POLKIT_DIR="/etc/polkit-1/localauthority/50-local.d"
POLKIT_FILE="$POLKIT_DIR/50-aihomecloud-network.pkla"
MIN_PYTHON_VER="3.12"

# =============================================================================
log "=== AiHomeCloud First Boot Setup ==="
log "Repo root : $REPO_ROOT"
log "App user  : $APP_USER"
log "Backend   : $BACKEND_SRC"
log ""

# â”€â”€ Step 1: Install system packages â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log "[1/9] Installing system packages..."

apt-get update -qq

PKGS=(
    python3
    python3-venv
    python3-pip
    openssl
    samba
    nfs-kernel-server
    avahi-daemon
    lsof
    udevadm
    curl
    git
    tesseract-ocr
    tesseract-ocr-hin
    poppler-utils          # provides pdftotext
    minidlna               # DLNA / Smart TV streaming
)

# Install only missing packages to keep re-runs fast
TO_INSTALL=()
for pkg in "${PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null || TO_INSTALL+=("$pkg")
done

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    log "  Installing: ${TO_INSTALL[*]}"
    apt-get install -y --no-install-recommends "${TO_INSTALL[@]}"
else
    log "  All packages already installed."
fi

# â”€â”€ Step 2: Verify Python version â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log "[2/9] Checking Python version..."

PYTHON_BIN="$(command -v python3)"
PYTHON_VER="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

# Compare versions using sort -V
if [[ "$(printf '%s\n' "$MIN_PYTHON_VER" "$PYTHON_VER" | sort -V | head -1)" != "$MIN_PYTHON_VER" ]]; then
    die "Python $MIN_PYTHON_VER+ required. Found: $PYTHON_VER"
fi
log "  Python $PYTHON_VER â€” OK"

# â”€â”€ Step 3: Create system user â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log "[3/9] Ensuring system user '$APP_USER' exists..."

if id "$APP_USER" &>/dev/null; then
    log "  User '$APP_USER' already exists."
else
    useradd -r -m -s /bin/bash "$APP_USER"
    log "  Created user '$APP_USER'."
fi

# â”€â”€ Step 4: Create required directories â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log "[4/9] Creating directories..."

DIRS=(
    "$NAS_ROOT/personal"
    "$NAS_ROOT/family"
    "$NAS_ROOT/entertainment"
    "$NAS_ROOT/entertainment/Movies"
    "$NAS_ROOT/entertainment/Series"
    "$NAS_ROOT/entertainment/Anime"
    "$NAS_ROOT/entertainment/Music"
    "$NAS_ROOT/entertainment/Others"
    "$DATA_DIR/tls"
    "$APP_HOME"
    "$BACKEND_SRC"
)

for d in "${DIRS[@]}"; do
    if [[ ! -d "$d" ]]; then
        mkdir -p "$d"
        log "  Created: $d"
    else
        log "  Exists : $d"
    fi
done

chown -R "$APP_USER:$APP_USER" "$NAS_ROOT" "$DATA_DIR" "$APP_HOME"
chmod 750 "$DATA_DIR"   # restrict data dir â€” service user + root only

# â”€â”€ Step 5: Deploy backend code â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log "[5/9] Deploying backend code..."

if [[ -d "$REPO_ROOT/backend" ]]; then
    # Running from the cloned repo â€” symlink instead of copying so git pull updates it
    if [[ -L "$BACKEND_SRC" ]]; then
        log "  Symlink already exists: $BACKEND_SRC â†’ $(readlink "$BACKEND_SRC")"
    elif [[ ! -e "$BACKEND_SRC" ]]; then
        rm -rf "$BACKEND_SRC"
        ln -s "$REPO_ROOT/backend" "$BACKEND_SRC"
        log "  Created symlink: $BACKEND_SRC â†’ $REPO_ROOT/backend"
    else
        warn "  $BACKEND_SRC exists and is not a symlink. Skipping â€” manage manually."
    fi
else
    warn "  Backend source not found at $REPO_ROOT/backend"
    warn "  Clone the repo to /opt/aihomecloud/AiHomeCloud or run from the repo root."
fi

# â”€â”€ Step 6: Create Python virtual environment â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log "[6/9] Setting up Python venv at $VENV_DIR..."

if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
    sudo -u "$APP_USER" "$PYTHON_BIN" -m venv "$VENV_DIR"
    log "  Venv created."
else
    log "  Venv already exists."
fi

VENV_PIP="$VENV_DIR/bin/pip"
VENV_PYTHON="$VENV_DIR/bin/python"

REQUIREMENTS="$REPO_ROOT/backend/requirements.txt"
if [[ -f "$REQUIREMENTS" ]]; then
    log "  Installing Python dependencies..."
    sudo -u "$APP_USER" "$VENV_PIP" install --quiet --upgrade pip
    sudo -u "$APP_USER" "$VENV_PIP" install --quiet -r "$REQUIREMENTS"
    log "  Dependencies installed."
else
    warn "  requirements.txt not found at $REQUIREMENTS â€” skipping pip install."
fi

# â”€â”€ Step 7: Install + enable systemd service â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log "[7/9] Configuring systemd service '$SERVICE_NAME'..."

SERVICE_SRC="$REPO_ROOT/backend/aihomecloud.service"

if [[ ! -f "$SERVICE_SRC" ]]; then
    die "Service file not found: $SERVICE_SRC"
fi

# Only copy if the installed file doesn't exist (don't overwrite admin edits)
if [[ ! -f "$SERVICE_DST" ]]; then
    cp "$SERVICE_SRC" "$SERVICE_DST"
    chmod 644 "$SERVICE_DST"
    log "  Installed service file: $SERVICE_DST"

    # Prompt for hostname-based serial if it looks like the template default
    CURRENT_SERIAL=$(grep -Po 'AHC_DEVICE_SERIAL=\K[^"]+' "$SERVICE_DST" 2>/dev/null || echo "AHC-A7A-2025-001")
    if [[ "$CURRENT_SERIAL" == "AHC-A7A-2025-001" ]]; then
        # Auto-generate a serial from the hostname + last 4 hex of MAC
        MAC=$(ip link show | awk '/ether / {print $2}' | head -1 | tr -d ':' | tr '[:lower:]' '[:upper:]')
        AUTO_SERIAL="AHC-$(hostname -s | tr '[:lower:]' '[:upper:]')-${MAC: -4}"
        sed -i "s/AHC_DEVICE_SERIAL=AHC-A7A-2025-001/AHC_DEVICE_SERIAL=$AUTO_SERIAL/" "$SERVICE_DST"
        log "  Auto-set device serial: $AUTO_SERIAL"
    fi

    # Auto-generate a random pairing key if still default
    CURRENT_KEY=$(grep -Po 'AHC_PAIRING_KEY=\K[^"]+' "$SERVICE_DST" 2>/dev/null || echo "your-pairing-key")
    if [[ "$CURRENT_KEY" == "your-pairing-key" ]]; then
        RANDOM_KEY=$(openssl rand -hex 16)
        sed -i "s/AHC_PAIRING_KEY=your-pairing-key/AHC_PAIRING_KEY=$RANDOM_KEY/" "$SERVICE_DST"
        log "  Auto-generated pairing key (stored in $SERVICE_DST)."
    fi
else
    log "  Service file already exists â€” skipping copy to preserve your edits."
    log "  To reset: sudo rm $SERVICE_DST && sudo bash $0"
fi

systemctl daemon-reload

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    log "  Service already enabled."
else
    systemctl enable "$SERVICE_NAME"
    log "  Service enabled."
fi

# â”€â”€ Step 8: Configure polkit for NetworkManager â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log "[8/9] Configuring polkit for NetworkManager..."

mkdir -p "$POLKIT_DIR"

if [[ ! -f "$POLKIT_FILE" ]]; then
    cat > "$POLKIT_FILE" << 'EOF'
[Allow NetworkManager for aihomecloud backend]
Identity=unix-group:sudo;unix-group:netdev
Action=org.freedesktop.NetworkManager.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
    chmod 644 "$POLKIT_FILE"
    log "  Polkit rule created: $POLKIT_FILE"
    systemctl restart polkit 2>/dev/null || warn "  polkit not running â€” skipping restart."
else
    log "  Polkit rule already exists."
fi

# -- Step 8b: Sudoers for passwordless storage/service management ---------------
SUDOERS_FILE="/etc/sudoers.d/aihomecloud"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    log "[8b] Creating sudoers rules for passwordless storage management..."
    cat > "$SUDOERS_FILE" << EOF
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/mount, /usr/bin/umount, /usr/bin/udevadm, /usr/sbin/sgdisk, /usr/sbin/mkfs.ext4, /usr/bin/udisksctl, /usr/bin/nmcli, /usr/bin/lsof, /usr/bin/fuser, /usr/bin/systemctl start smbd, /usr/bin/systemctl stop smbd, /usr/bin/systemctl start nmbd, /usr/bin/systemctl stop nmbd, /usr/bin/systemctl start nfs-kernel-server, /usr/bin/systemctl stop nfs-kernel-server, /usr/bin/systemctl start minidlna, /usr/bin/systemctl stop minidlna, /usr/bin/systemctl start minidlnad, /usr/bin/systemctl stop minidlnad, /usr/bin/sync
EOF
    chmod 440 "$SUDOERS_FILE"
    if visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
        log "  Sudoers rules installed: $SUDOERS_FILE"
    else
        warn "  Sudoers validation failed -- removing to avoid lockout."
        rm -f "$SUDOERS_FILE"
    fi
else
    log "  Sudoers rules already exist."
fi

# â”€â”€ Step 9: Start the service â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log "[9/9] Starting '$SERVICE_NAME'..."

if systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl restart "$SERVICE_NAME"
    log "  Service restarted."
else
    systemctl start "$SERVICE_NAME"
    log "  Service started."
fi

# Give it a moment to come up, then do a quick health check
sleep 3
if curl -sk --max-time 5 https://localhost:8443/api/health | grep -q '"ok"' 2>/dev/null; then
    log "  Health check PASSED âœ“"
else
    warn "  Health check did not return OK yet â€” check: sudo journalctl -u $SERVICE_NAME -n 30"
fi

# â”€â”€ Configure minidlna â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
MINIDLNA_CONF="/etc/minidlna.conf"
if command -v minidlnad &>/dev/null && [[ ! -f "${MINIDLNA_CONF}.ahc_configured" ]]; then
    log "Configuring minidlna for NAS media directories..."
    cat > "$MINIDLNA_CONF" << EOF
media_dir=V,${NAS_ROOT}/entertainment/Movies
media_dir=V,${NAS_ROOT}/entertainment/Series
media_dir=V,${NAS_ROOT}/entertainment/Anime
media_dir=V,${NAS_ROOT}/family/Videos
media_dir=P,${NAS_ROOT}/family/Photos
media_dir=P,${NAS_ROOT}/personal
media_dir=A,${NAS_ROOT}/entertainment/Music
friendly_name=AiHomeCloud
db_dir=/var/cache/minidlna
log_dir=/var/log
inotify=yes
EOF
    touch "${MINIDLNA_CONF}.ahc_configured"
    systemctl restart minidlna 2>/dev/null || true
    log "  minidlna configured and restarted."
fi

# =============================================================================
echo ""
log "=== Setup complete! ==="
echo ""
echo -e "  ${GREEN}Backend URL  :${NC} https://$(hostname -I | awk '{print $1}'):8443"
echo -e "  ${GREEN}Health check :${NC} curl -k https://localhost:8443/api/health"
echo -e "  ${GREEN}Logs         :${NC} sudo journalctl -u $SERVICE_NAME -f"
echo -e "  ${GREEN}Service file :${NC} $SERVICE_DST"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo "  1. Edit $SERVICE_DST if you need to customise AHC_DEVICE_SERIAL or AHC_PAIRING_KEY"
echo "  2. Open the AiHomeCloud app on your phone and scan the QR code to pair"
echo "  3. Mount your external NAS drive to $NAS_ROOT (see kb/setup-instructions.md)"
echo ""
