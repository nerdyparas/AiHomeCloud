#!/usr/bin/env bash
# =============================================================================
# AiHomeCloud — Universal Installer
# Supports: Ubuntu 22+, Debian 12+, Armbian (aarch64, armv7l, x86_64)
#
# Usage:
#   curl -sSL https://install.aihomecloud.app | sudo bash
#   # or
#   sudo bash install.sh
#
# This script is IDEMPOTENT — safe to run multiple times.
# It will not overwrite existing config, secrets, or user data.
# =============================================================================

set -euo pipefail

VERSION="1.0.0"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[AiHomeCloud]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; cleanup_on_error; exit 1; }

# ── Configurable paths ───────────────────────────────────────────────────────
APP_USER="${APP_USER:-aihomecloud}"
APP_HOME="/opt/aihomecloud"
BACKEND_SRC="$APP_HOME/backend"
VENV_DIR="$BACKEND_SRC/venv"
DATA_DIR="/var/lib/aihomecloud"
NAS_ROOT="/srv/nas"
SERVICE_NAME="aihomecloud"
SERVICE_DST="/etc/systemd/system/${SERVICE_NAME}.service"
MIN_PYTHON_VER="3.12"
MIN_DISK_MB=500
PORT=8443
AVAHI_SVC="/etc/avahi/services/aihomecloud.service"
SUDOERS_FILE="/etc/sudoers.d/aihomecloud"

INSTALL_LOG="/tmp/aihomecloud-install-$(date +%Y%m%d%H%M%S).log"

# Track what we've created so we can clean up on failure
_CREATED_DIRS=()
_CREATED_FILES=()

cleanup_on_error() {
    if [[ ${#_CREATED_FILES[@]} -gt 0 || ${#_CREATED_DIRS[@]} -gt 0 ]]; then
        warn "Installation failed. Cleaning up partial install..."
        for f in "${_CREATED_FILES[@]}"; do
            [[ -f "$f" ]] && rm -f "$f" && warn "  Removed: $f"
        done
        for d in "${_CREATED_DIRS[@]}"; do
            [[ -d "$d" ]] && rmdir --ignore-fail-on-non-empty "$d" 2>/dev/null && warn "  Removed: $d"
        done
    fi
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

preflight() {
    log "=== AiHomeCloud Installer v${VERSION} ==="
    log "Running pre-flight checks..."

    # 1. Root / sudo access
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Use: sudo bash install.sh"
    fi

    # 2. Architecture detection
    ARCH="$(uname -m)"
    case "$ARCH" in
        aarch64|arm64)  ARCH="aarch64" ;;
        armv7l|armhf)   ARCH="armv7l" ;;
        x86_64|amd64)   ARCH="x86_64" ;;
        *)              die "Unsupported architecture: $ARCH. Supported: aarch64, armv7l, x86_64" ;;
    esac
    log "  Architecture: $ARCH"

    # 3. OS detection
    if [[ ! -f /etc/os-release ]]; then
        die "Cannot detect OS — /etc/os-release not found."
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-0}"
    OS_NAME="${PRETTY_NAME:-$OS_ID $OS_VERSION}"
    log "  OS: $OS_NAME"

    case "$OS_ID" in
        ubuntu)
            [[ "${OS_VERSION%%.*}" -ge 22 ]] || die "Ubuntu 22.04+ required. Found: $OS_VERSION"
            ;;
        debian)
            [[ "${OS_VERSION%%.*}" -ge 12 ]] || die "Debian 12+ required. Found: $OS_VERSION"
            ;;
        armbian)
            log "  Armbian detected — proceeding."
            ;;
        *)
            warn "Untested OS: $OS_NAME — proceeding with caution."
            ;;
    esac

    # 4. Disk space check
    local avail_mb
    avail_mb=$(df -m /opt 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
    if [[ "$avail_mb" -lt "$MIN_DISK_MB" ]]; then
        die "Insufficient disk space on /opt: ${avail_mb}MB available, ${MIN_DISK_MB}MB required."
    fi
    log "  Disk space: ${avail_mb}MB available"

    # 5. Internet connectivity
    if ! ping -c1 -W3 8.8.8.8 &>/dev/null && ! ping -c1 -W3 1.1.1.1 &>/dev/null; then
        die "No internet connectivity. Check your network connection."
    fi
    log "  Internet: OK"

    # 6. Port conflict check
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} " ; then
        local conflict
        conflict=$(ss -tlnp | grep ":${PORT} " | awk '{print $6}' | head -1)
        die "Port ${PORT} is already in use by: $conflict. Stop the conflicting service first."
    fi
    log "  Port ${PORT}: available"

    # 7. Python availability
    if command -v python3 &>/dev/null; then
        local py_ver
        py_ver="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
        if [[ "$(printf '%s\n' "$MIN_PYTHON_VER" "$py_ver" | sort -V | head -1)" != "$MIN_PYTHON_VER" ]]; then
            log "  Python $py_ver found — will install $MIN_PYTHON_VER+"
            NEED_PYTHON=true
        else
            log "  Python: $py_ver"
            NEED_PYTHON=false
        fi
    else
        NEED_PYTHON=true
        log "  Python: not found — will install"
    fi

    log "Pre-flight checks passed!"
    echo ""
}

# =============================================================================
# INSTALLATION STEPS
# =============================================================================

install_packages() {
    log "[1/10] Installing system packages..."
    apt-get update -qq

    local pkgs=(
        python3 python3-venv python3-pip
        openssl curl git lsof
        avahi-daemon
        samba nfs-kernel-server
        tesseract-ocr poppler-utils
        minidlna
        smartmontools
    )

    if [[ "$NEED_PYTHON" == true ]]; then
        pkgs+=(software-properties-common)
    fi

    local to_install=()
    for pkg in "${pkgs[@]}"; do
        dpkg -s "$pkg" &>/dev/null || to_install+=("$pkg")
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        log "  Installing: ${to_install[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${to_install[@]}"
    else
        log "  All packages already installed."
    fi
}

verify_python() {
    log "[2/10] Verifying Python version..."
    local py_bin py_ver
    py_bin="$(command -v python3)"
    py_ver="$("$py_bin" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

    if [[ "$(printf '%s\n' "$MIN_PYTHON_VER" "$py_ver" | sort -V | head -1)" != "$MIN_PYTHON_VER" ]]; then
        die "Python ${MIN_PYTHON_VER}+ required after package install. Found: $py_ver"
    fi
    log "  Python $py_ver — OK"
    PYTHON_BIN="$py_bin"
}

create_user() {
    log "[3/10] Ensuring system user '$APP_USER' exists..."
    if id "$APP_USER" &>/dev/null; then
        log "  User '$APP_USER' already exists."
    else
        useradd -r -m -s /usr/sbin/nologin -d "$APP_HOME" "$APP_USER"
        log "  Created system user '$APP_USER'."
    fi
}

create_directories() {
    log "[4/10] Creating directories..."
    local dirs=(
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

    for d in "${dirs[@]}"; do
        if [[ ! -d "$d" ]]; then
            mkdir -p "$d"
            _CREATED_DIRS+=("$d")
            log "  Created: $d"
        fi
    done

    chown -R "$APP_USER:$APP_USER" "$NAS_ROOT" "$DATA_DIR" "$APP_HOME"
    chmod 750 "$DATA_DIR"
}

deploy_backend() {
    log "[5/10] Deploying backend code..."
    local script_dir repo_root
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # If run from within the repo, use it directly
    if [[ -d "$script_dir/backend" ]]; then
        repo_root="$script_dir"
    elif [[ -d "$script_dir/../backend" ]]; then
        repo_root="$(cd "$script_dir/.." && pwd)"
    else
        die "Cannot find backend/ directory. Run this script from the repo root."
    fi

    REPO_ROOT="$repo_root"

    if [[ -L "$BACKEND_SRC" ]]; then
        log "  Symlink already exists: $BACKEND_SRC -> $(readlink "$BACKEND_SRC")"
    elif [[ -d "$BACKEND_SRC" && -f "$BACKEND_SRC/app/main.py" ]]; then
        log "  Backend already deployed at $BACKEND_SRC"
    else
        rm -rf "$BACKEND_SRC"
        ln -s "$REPO_ROOT/backend" "$BACKEND_SRC"
        log "  Created symlink: $BACKEND_SRC -> $REPO_ROOT/backend"
    fi
}

setup_venv() {
    log "[6/10] Setting up Python virtual environment..."
    if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
        sudo -u "$APP_USER" "$PYTHON_BIN" -m venv "$VENV_DIR"
        log "  Venv created."
    else
        log "  Venv already exists."
    fi

    local requirements="$BACKEND_SRC/requirements.txt"
    if [[ -f "$requirements" ]]; then
        log "  Installing Python dependencies..."
        sudo -u "$APP_USER" "$VENV_DIR/bin/pip" install --quiet --upgrade pip
        sudo -u "$APP_USER" "$VENV_DIR/bin/pip" install --quiet -r "$requirements"
        log "  Dependencies installed."
    else
        warn "  requirements.txt not found — skipping pip install."
    fi
}

configure_mdns() {
    log "[7/10] Configuring mDNS (Avahi)..."
    if [[ ! -f "$AVAHI_SVC" ]]; then
        cat > "$AVAHI_SVC" << EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">AiHomeCloud on %h</name>
  <service>
    <type>_aihomecloud._tcp</type>
    <port>${PORT}</port>
    <txt-record>version=${VERSION}</txt-record>
  </service>
</service-group>
EOF
        _CREATED_FILES+=("$AVAHI_SVC")
        systemctl restart avahi-daemon 2>/dev/null || true
        log "  mDNS service registered: _aihomecloud._tcp"
    else
        log "  mDNS service already configured."
    fi
}

install_service() {
    log "[8/10] Installing systemd service..."
    local service_src="$BACKEND_SRC/aihomecloud.service"

    if [[ ! -f "$service_src" ]]; then
        die "Service template not found: $service_src"
    fi

    if [[ ! -f "$SERVICE_DST" ]]; then
        cp "$service_src" "$SERVICE_DST"
        _CREATED_FILES+=("$SERVICE_DST")
        chmod 644 "$SERVICE_DST"

        # Auto-generate unique device serial from hostname + MAC
        local mac auto_serial
        mac=$(ip link show 2>/dev/null | awk '/ether / {print $2}' | head -1 | tr -d ':' | tr '[:lower:]' '[:upper:]')
        auto_serial="AHC-$(hostname -s | tr '[:lower:]' '[:upper:]')-${mac:(-4)}"
        sed -i "s/AHC_DEVICE_SERIAL=AHC-A7A-2025-001/AHC_DEVICE_SERIAL=$auto_serial/" "$SERVICE_DST" 2>/dev/null || true
        log "  Device serial: $auto_serial"

        # Auto-generate pairing key
        local pairing_key
        pairing_key=$(openssl rand -hex 16)
        sed -i "s/AHC_PAIRING_KEY=your-pairing-key/AHC_PAIRING_KEY=$pairing_key/" "$SERVICE_DST" 2>/dev/null || true
        log "  Pairing key generated."
    else
        log "  Service file exists — preserving your edits."
    fi

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" 2>/dev/null || true
}

configure_sudoers() {
    log "[9/10] Configuring sudoers whitelist..."
    if [[ ! -f "$SUDOERS_FILE" ]]; then
        cat > "$SUDOERS_FILE" << EOF
# AiHomeCloud — limited sudo for service user
# Only commands required by the backend are allowed.
${APP_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start *, /usr/bin/systemctl stop *, /usr/bin/systemctl restart *, /usr/bin/systemctl status *
${APP_USER} ALL=(ALL) NOPASSWD: /usr/sbin/shutdown, /usr/sbin/reboot
${APP_USER} ALL=(ALL) NOPASSWD: /usr/sbin/mkfs.ext4, /usr/bin/mount, /usr/bin/umount
${APP_USER} ALL=(ALL) NOPASSWD: /usr/sbin/smartctl
${APP_USER} ALL=(ALL) NOPASSWD: /usr/bin/lsblk, /usr/bin/blkid, /usr/bin/findmnt
${APP_USER} ALL=(ALL) NOPASSWD: /usr/bin/docker *
EOF
        _CREATED_FILES+=("$SUDOERS_FILE")
        chmod 440 "$SUDOERS_FILE"
        visudo -cf "$SUDOERS_FILE" || die "Invalid sudoers syntax — aborting."
        log "  Sudoers whitelist installed."
    else
        log "  Sudoers whitelist already exists."
    fi
}

start_and_verify() {
    log "[10/10] Starting service and verifying..."

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        systemctl restart "$SERVICE_NAME"
        log "  Service restarted."
    else
        systemctl start "$SERVICE_NAME"
        log "  Service started."
    fi

    # Health check with retry
    local retries=5
    local ok=false
    for i in $(seq 1 $retries); do
        sleep 2
        if curl -sk --max-time 5 "https://localhost:${PORT}/api/health" 2>/dev/null | grep -q '"ok"'; then
            ok=true
            break
        fi
        log "  Waiting for service... (attempt $i/$retries)"
    done

    if $ok; then
        log "  Health check PASSED!"
    else
        warn "  Health check did not return OK. Check: sudo journalctl -u $SERVICE_NAME -n 30"
    fi
}

print_summary() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

    echo ""
    log "=== Installation Complete! ==="
    echo ""
    echo -e "  ${CYAN}Backend URL  :${NC} https://${ip}:${PORT}"
    echo -e "  ${CYAN}Health check :${NC} curl -k https://localhost:${PORT}/api/health"
    echo -e "  ${CYAN}Logs         :${NC} sudo journalctl -u ${SERVICE_NAME} -f"
    echo -e "  ${CYAN}Service file :${NC} ${SERVICE_DST}"
    echo -e "  ${CYAN}Data dir     :${NC} ${DATA_DIR}"
    echo -e "  ${CYAN}NAS root     :${NC} ${NAS_ROOT}"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo "  1. Open the AiHomeCloud app on your phone"
    echo "  2. Scan the network to discover this device"
    echo "  3. Mount your external storage to ${NAS_ROOT}"
    echo ""
    echo -e "  ${YELLOW}To uninstall:${NC} sudo bash uninstall.sh"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    preflight
    install_packages
    verify_python
    create_user
    create_directories
    deploy_backend
    setup_venv
    configure_mdns
    install_service
    configure_sudoers
    start_and_verify
    print_summary
}

main "$@" 2>&1 | tee "$INSTALL_LOG"
