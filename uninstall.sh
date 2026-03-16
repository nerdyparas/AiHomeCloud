#!/usr/bin/env bash
# =============================================================================
# AiHomeCloud — Uninstall Script
#
# Usage:
#   sudo bash uninstall.sh           # Remove code only, keep data
#   sudo bash uninstall.sh --purge   # Remove everything including user data
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[AiHomeCloud]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

APP_USER="aihomecloud"
APP_HOME="/opt/aihomecloud"
DATA_DIR="/var/lib/aihomecloud"
NAS_ROOT="/srv/nas"
SERVICE_NAME="aihomecloud"
SERVICE_DST="/etc/systemd/system/${SERVICE_NAME}.service"
AVAHI_SVC="/etc/avahi/services/aihomecloud.service"
SUDOERS_FILE="/etc/sudoers.d/aihomecloud"

PURGE=false
[[ "${1:-}" == "--purge" ]] && PURGE=true

# ── Must run as root ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Run with sudo: sudo bash uninstall.sh" >&2
    exit 1
fi

log "=== AiHomeCloud Uninstaller ==="
$PURGE && warn "PURGE mode — all data will be removed!"
echo ""

# 1. Stop and disable service
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME"
    log "Stopped service."
fi
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME"
    log "Disabled service."
fi

# 2. Remove service file
if [[ -f "$SERVICE_DST" ]]; then
    rm -f "$SERVICE_DST"
    systemctl daemon-reload
    log "Removed systemd service file."
fi

# 3. Remove code directory (but not data)
if [[ -d "$APP_HOME" || -L "$APP_HOME/backend" ]]; then
    rm -rf "$APP_HOME"
    log "Removed application directory: $APP_HOME"
fi

# 4. Remove Avahi mDNS service
if [[ -f "$AVAHI_SVC" ]]; then
    rm -f "$AVAHI_SVC"
    systemctl restart avahi-daemon 2>/dev/null || true
    log "Removed mDNS service."
fi

# 5. Remove sudoers rules
if [[ -f "$SUDOERS_FILE" ]]; then
    rm -f "$SUDOERS_FILE"
    log "Removed sudoers whitelist."
fi

# 6. Purge-only: remove data directories and system user
if $PURGE; then
    if [[ -d "$DATA_DIR" ]]; then
        rm -rf "$DATA_DIR"
        log "Removed data directory: $DATA_DIR"
    fi
    if [[ -d "$NAS_ROOT" ]]; then
        warn "NAS root $NAS_ROOT was NOT removed (may contain user files)."
        warn "Remove manually if desired: sudo rm -rf $NAS_ROOT"
    fi
    if id "$APP_USER" &>/dev/null; then
        userdel -r "$APP_USER" 2>/dev/null || userdel "$APP_USER" 2>/dev/null || true
        log "Removed system user: $APP_USER"
    fi
else
    log "Data preserved at: $DATA_DIR"
    log "NAS preserved at:  $NAS_ROOT"
    log "User preserved:    $APP_USER"
    echo ""
    warn "To remove all data, re-run with: sudo bash uninstall.sh --purge"
fi

echo ""
log "=== Uninstall complete ==="
echo ""
echo "Removed:"
echo "  - Systemd service ($SERVICE_NAME)"
echo "  - Application directory ($APP_HOME)"
echo "  - Avahi mDNS service"
echo "  - Sudoers whitelist"
$PURGE && echo "  - Data directory ($DATA_DIR)" && echo "  - System user ($APP_USER)"
echo ""
