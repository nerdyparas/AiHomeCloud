#!/usr/bin/env bash
# =============================================================================
# AiHomeCloud — AdGuard Home Install Script
# Target: Ubuntu 24 ARM64 (Radxa Cubie A7Z or compatible SBC)
#
# Usage:
#   sudo bash scripts/install-adguard.sh
#
# This script is IDEMPOTENT — safe to run multiple times.
# Recommended: run AFTER scripts/first-boot-setup.sh
#
# What it does:
#   1. Downloads and installs the AdGuard Home binary (ARM64)
#   2. Creates a dedicated 'adguard' system user
#   3. Writes initial config: DNS on port 5353, admin UI on localhost:3000
#   4. Generates a random admin password (bcrypt-hashed)
#   5. Creates and enables a systemd service unit
#   6. Updates cubie-backend.service with CUBIE_ADGUARD_ENABLED/PASSWORD
#   7. Starts the service and runs a health check
#   8. Prints router DNS configuration instructions
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[AdGuard]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Must run as root ──────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run with sudo: sudo bash $0"

# ── Repo root (script lives in scripts/ one level below) ─────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Configurable vars ─────────────────────────────────────────────────────────
AGH_DIR="${AGH_DIR:-/opt/AdGuardHome}"
AGH_BIN="$AGH_DIR/AdGuardHome"
AGH_CONF="$AGH_DIR/AdGuardHome.yaml"
AGH_USER="${AGH_USER:-adguard}"
AGH_ADMIN_PORT="${AGH_ADMIN_PORT:-3000}"
AGH_DNS_PORT="${AGH_DNS_PORT:-5353}"
AGH_ADMIN_USER="admin"
SERVICE_NAME="AdGuardHome"
CUBIE_SERVICE="/etc/systemd/system/cubie-backend.service"
VENV_PYTHON="/opt/cubie/backend/venv/bin/python"

# ── Architecture detection ────────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64) AGH_ARCH="arm64" ;;
    armv7l)        AGH_ARCH="armv7" ;;
    x86_64)        AGH_ARCH="amd64" ;;
    *)             die "Unsupported architecture: $ARCH" ;;
esac

log "=== AdGuard Home Install ==="
log "Install dir : $AGH_DIR"
log "DNS port    : $AGH_DNS_PORT  (point your router's DNS here)"
log "Admin port  : $AGH_ADMIN_PORT (localhost only — proxied by AiHomeCloud)"
log "Architecture: $AGH_ARCH"
log ""

# =============================================================================
# Step 1: Download and install binary
# =============================================================================
log "[1/5] Installing AdGuard Home binary..."

if [[ -x "$AGH_BIN" ]]; then
    CURRENT_VER=$("$AGH_BIN" --version 2>/dev/null | grep -oP 'v[\d.]+' | head -1 || echo "unknown")
    log "  Already installed: $CURRENT_VER — skipping download."
    log "  To upgrade, delete $AGH_BIN and re-run this script."
else
    log "  Fetching latest release download URL for linux_${AGH_ARCH}..."

    GITHUB_API="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest"
    DOWNLOAD_URL=$(
        curl -fsSL --max-time 30 "$GITHUB_API" \
        | grep -oP '"browser_download_url":\s*"\K[^"]+AdGuardHome_linux_'"$AGH_ARCH"'\.tar\.gz'
    ) || die "Failed to fetch release info from GitHub. Check internet connectivity."

    [[ -n "$DOWNLOAD_URL" ]] || die "Could not find download URL for AdGuardHome_linux_${AGH_ARCH}.tar.gz"

    TMP_DIR=$(mktemp -d)
    # shellcheck disable=SC2064
    trap 'rm -rf "$TMP_DIR"' EXIT

    log "  Downloading: $DOWNLOAD_URL"
    curl -fsSL --max-time 120 --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/adguard.tar.gz"

    log "  Extracting..."
    tar -xzf "$TMP_DIR/adguard.tar.gz" -C "$TMP_DIR"

    mkdir -p "$AGH_DIR"
    cp "$TMP_DIR/AdGuardHome/AdGuardHome" "$AGH_BIN"
    chmod 755 "$AGH_BIN"

    NEW_VER=$("$AGH_BIN" --version 2>/dev/null | grep -oP 'v[\d.]+' | head -1 || echo "unknown")
    log "  Installed AdGuard Home $NEW_VER"
fi

# =============================================================================
# Step 2: Create service user and set ownership
# =============================================================================
log "[2/5] Ensuring service user '$AGH_USER' exists..."

if id "$AGH_USER" &>/dev/null; then
    log "  User '$AGH_USER' already exists."
else
    useradd -r -s /sbin/nologin -d "$AGH_DIR" "$AGH_USER"
    log "  Created system user '$AGH_USER'."
fi

chown -R "$AGH_USER:$AGH_USER" "$AGH_DIR"

# =============================================================================
# Step 3: Write initial configuration (only if not already present)
# =============================================================================
log "[3/5] Writing AdGuard Home configuration..."

if [[ -f "$AGH_CONF" ]]; then
    log "  Config already exists — preserving existing settings."
    log "  To reset: sudo rm $AGH_CONF && sudo bash $0"
else
    # Generate a random admin password
    ADMIN_PASS=$(openssl rand -hex 12)

    # Hash with bcrypt — prefer the project venv (bcrypt already in requirements.txt)
    if [[ -x "$VENV_PYTHON" ]]; then
        PYTHON="$VENV_PYTHON"
        log "  Using project venv for bcrypt: $VENV_PYTHON"
    elif python3 -c "import bcrypt" 2>/dev/null; then
        PYTHON="python3"
    else
        log "  Installing bcrypt into system python3..."
        pip3 install --quiet bcrypt
        PYTHON="python3"
    fi

    ADMIN_HASH=$(
        "$PYTHON" -c "
import bcrypt, sys
pw = sys.stdin.read().strip().encode()
print(bcrypt.hashpw(pw, bcrypt.gensalt(10)).decode())
" <<< "$ADMIN_PASS"
    )

    # Write YAML template with placeholders, then substitute values.
    # Single-quoted heredoc (no shell expansion) keeps the content literal.
    cat > "$AGH_CONF" << 'YAML_EOF'
http:
  pprof:
    port: 6060
    enabled: false
  address: 127.0.0.1:__ADMIN_PORT__
  session_ttl: 720h

users:
  - name: __ADMIN_USER__
    password: __ADMIN_HASH__

auth_attempts: 5
block_auth_min: 15

dns:
  bind_hosts:
    - 0.0.0.0
  port: __DNS_PORT__
  upstream_dns:
    - https://dns10.quad9.net/dns-query
    - https://cloudflare-dns.com/dns-query
  bootstrap_dns:
    - 9.9.9.10
    - 149.112.112.10
    - 2620:fe::10
    - 2620:fe::fe:10
  fallback_dns:
    - 94.140.14.140
    - 94.140.14.141
  upstream_mode: parallel
  cache_size: 4194304
  refuse_any: true
  serve_plain_dns: true

statistics:
  interval: 24h
  enabled: true

querylog:
  interval: 24h
  enabled: true
  file_enabled: true

filters:
  - enabled: true
    url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true
    url: https://adaway.org/hosts.txt
    name: AdAway Default Blocklist
    id: 2

dhcp:
  enabled: false
YAML_EOF

    # Substitute placeholders (| delimiter avoids conflicts with / in paths and $ in hashes)
    sed -i "s|__ADMIN_PORT__|${AGH_ADMIN_PORT}|g"  "$AGH_CONF"
    sed -i "s|__DNS_PORT__|${AGH_DNS_PORT}|g"      "$AGH_CONF"
    sed -i "s|__ADMIN_USER__|${AGH_ADMIN_USER}|g"  "$AGH_CONF"
    sed -i "s|__ADMIN_HASH__|${ADMIN_HASH}|g"      "$AGH_CONF"

    chown "$AGH_USER:$AGH_USER" "$AGH_CONF"
    chmod 600 "$AGH_CONF"

    # Save password for final summary (readable by root only)
    echo "$ADMIN_PASS" > "$AGH_DIR/.admin_password"
    chmod 600 "$AGH_DIR/.admin_password"
    chown "$AGH_USER:$AGH_USER" "$AGH_DIR/.admin_password"

    log "  Config written to: $AGH_CONF"
    log "  Admin credentials stored in: $AGH_DIR/.admin_password"

    # Note: port 5353 — avahi-daemon also uses 5353 for mDNS (multicast only).
    # AdGuard listens for unicast DNS on the same port; they coexist because
    # avahi only processes multicast packets (224.0.0.251). If you observe
    # bind errors, stop avahi: sudo systemctl disable --now avahi-daemon
fi

# =============================================================================
# Step 4: Create and enable systemd service
# =============================================================================
log "[4/5] Configuring systemd service '$SERVICE_NAME'..."

UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if [[ -f "$UNIT_FILE" ]]; then
    log "  Service unit already exists — skipping."
    log "  To recreate: sudo rm $UNIT_FILE && sudo bash $0"
else
    cat > "$UNIT_FILE" << EOF
[Unit]
Description=AdGuard Home: Network-level Ad Blocker
Documentation=https://github.com/AdguardTeam/AdGuardHome
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
User=${AGH_USER}
Group=${AGH_USER}
WorkingDirectory=${AGH_DIR}
ExecStart=${AGH_BIN} --no-check-update --config ${AGH_CONF} --work-dir ${AGH_DIR}
ExecStop=/bin/kill \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=${AGH_DIR}
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$UNIT_FILE"
    log "  Service unit created: $UNIT_FILE"
fi

systemctl daemon-reload

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    log "  Service already enabled."
else
    systemctl enable "$SERVICE_NAME"
    log "  Service enabled (starts on boot)."
fi

# =============================================================================
# Step 5: Update cubie-backend.service env vars
# =============================================================================
log "[5/5] Updating AiHomeCloud backend configuration..."

if [[ ! -f "$CUBIE_SERVICE" ]]; then
    warn "  cubie-backend.service not found at $CUBIE_SERVICE"
    warn "  Run scripts/first-boot-setup.sh first, then re-run this script."
    warn "  Manually set in your service file:"
    warn "    Environment=\"CUBIE_ADGUARD_ENABLED=true\""
    warn "    Environment=\"CUBIE_ADGUARD_PASSWORD=<password from $AGH_DIR/.admin_password>\""
else
    CHANGED=false

    # Enable AdGuard integration
    if grep -q 'CUBIE_ADGUARD_ENABLED=false' "$CUBIE_SERVICE"; then
        sed -i 's|CUBIE_ADGUARD_ENABLED=false|CUBIE_ADGUARD_ENABLED=true|' "$CUBIE_SERVICE"
        log "  Set CUBIE_ADGUARD_ENABLED=true in $CUBIE_SERVICE"
        CHANGED=true
    elif ! grep -q 'CUBIE_ADGUARD_ENABLED' "$CUBIE_SERVICE"; then
        # Not present at all — inject under the [Service] section
        sed -i '/^\[Service\]/a Environment="CUBIE_ADGUARD_ENABLED=true"' "$CUBIE_SERVICE"
        log "  Injected CUBIE_ADGUARD_ENABLED=true into $CUBIE_SERVICE"
        CHANGED=true
    else
        log "  CUBIE_ADGUARD_ENABLED already set."
    fi

    # Set admin password if the saved password file exists
    if [[ -f "$AGH_DIR/.admin_password" ]]; then
        SAVED_PASS=$(cat "$AGH_DIR/.admin_password")

        if grep -q 'CUBIE_ADGUARD_PASSWORD=' "$CUBIE_SERVICE"; then
            CURRENT_VAL=$(grep -oP 'CUBIE_ADGUARD_PASSWORD=\K[^\s"]+' "$CUBIE_SERVICE" | head -1 || true)
            if [[ -z "$CURRENT_VAL" || "$CURRENT_VAL" == '""' ]]; then
                sed -i "s|CUBIE_ADGUARD_PASSWORD=.*|CUBIE_ADGUARD_PASSWORD=$SAVED_PASS|" "$CUBIE_SERVICE"
                log "  Set CUBIE_ADGUARD_PASSWORD in $CUBIE_SERVICE"
                CHANGED=true
            else
                log "  CUBIE_ADGUARD_PASSWORD already set — preserving existing value."
            fi
        else
            sed -i '/^\[Service\]/a Environment="CUBIE_ADGUARD_PASSWORD='"$SAVED_PASS"'"' "$CUBIE_SERVICE"
            log "  Injected CUBIE_ADGUARD_PASSWORD into $CUBIE_SERVICE"
            CHANGED=true
        fi
    fi

    if [[ "$CHANGED" == true ]]; then
        systemctl daemon-reload
        if systemctl is-active --quiet cubie-backend 2>/dev/null; then
            systemctl restart cubie-backend
            log "  Restarted cubie-backend to pick up new env vars."
        fi
    fi
fi

# =============================================================================
# Start AdGuard Home and run health check
# =============================================================================
log "Starting AdGuard Home..."

if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl restart "$SERVICE_NAME"
    log "  Service restarted."
else
    systemctl start "$SERVICE_NAME"
    log "  Service started."
fi

# Give it a few seconds to initialise
sleep 3
if curl -s --max-time 5 "http://localhost:${AGH_ADMIN_PORT}/control/status" | grep -q '"running"' 2>/dev/null; then
    log "  Health check PASSED ✓"
else
    warn "  AdGuard not responding yet — it may still be starting up."
    warn "  Check logs: sudo journalctl -u $SERVICE_NAME -n 40"
fi

# =============================================================================
# Summary and router configuration instructions
# =============================================================================
LAN_IP=$(hostname -I | awk '{print $1}')

echo ""
log "=== AdGuard Home installation complete! ==="
echo ""
echo -e "  ${GREEN}Admin UI     :${NC} http://localhost:${AGH_ADMIN_PORT}"
echo -e "              (access via SSH tunnel: ssh user@${LAN_IP} -L ${AGH_ADMIN_PORT}:localhost:${AGH_ADMIN_PORT})"
echo -e "  ${GREEN}Admin user   :${NC} ${AGH_ADMIN_USER}"
if [[ -f "$AGH_DIR/.admin_password" ]]; then
    echo -e "  ${GREEN}Admin pass   :${NC} $(cat "$AGH_DIR/.admin_password")"
    echo -e "               ${YELLOW}^ Change this password after your first login!${NC}"
fi
echo -e "  ${GREEN}DNS address  :${NC} ${LAN_IP}:${AGH_DNS_PORT}"
echo -e "  ${GREEN}Service logs :${NC} sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo -e "  ${CYAN}━━━  CONFIGURE YOUR ROUTER'S DNS  ━━━${NC}"
echo ""
echo "  In your router's admin panel, under LAN / DHCP settings:"
echo ""
echo -e "    Primary DNS server    →  ${GREEN}${LAN_IP}${NC}"
echo -e "    DNS port (if shown)   →  ${GREEN}${AGH_DNS_PORT}${NC}"
echo ""
echo -e "  ${YELLOW}Most home routers only accept DNS on port 53.${NC}"
echo "  If yours doesn't support a custom DNS port, run these commands on the Cubie"
echo "  to redirect incoming port-53 traffic to AdGuard on port ${AGH_DNS_PORT}:"
echo ""
echo "    # Redirect UDP and TCP port 53 → ${AGH_DNS_PORT} (run as root)"
echo "    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-port ${AGH_DNS_PORT}"
echo "    iptables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-port ${AGH_DNS_PORT}"
echo ""
echo "    # Make persistent across reboots:"
echo "    apt-get install -y iptables-persistent"
echo "    netfilter-persistent save"
echo ""
echo "  After saving your router settings, all devices on your network will"
echo "  use AdGuard Home for DNS-based ad blocking."
echo ""
echo "  You can manage Ad Blocking from the AiHomeCloud app:"
echo "    More → Ad Blocking → stats, pause, enable/disable"
echo ""
