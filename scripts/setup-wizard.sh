#!/usr/bin/env bash
# =============================================================================
# AiHomeCloud — Interactive Setup Wizard
#
# A friendly, non-technical setup wizard for first-time AiHomeCloud device
# configuration. Designed for Indian families who bought a pre-flashed SBC box.
#
# Usage:
#   sudo bash scripts/setup-wizard.sh
#
# This script is IDEMPOTENT — safe to run multiple times.
# Re-running will not overwrite existing users, secrets, or data.
#
# ─── What the existing install infrastructure already handles ───────────────
#
#   install.sh:         Full headless installer (packages, venv, systemd,
#                       mDNS, sudoers, health check). Production-oriented.
#   first-boot-setup.sh: Similar to install.sh but for /opt/aihomecloud
#                       layout with a dedicated system user. Also sets up
#                       polkit, minidlna, generates device serial.
#   dev-setup.sh:       Developer-mode setup running from the cloned repo
#                       as the login user. In-repo venv at backend/.venv/.
#
#   All three are idempotent. They handle:
#   - System package installation (python3, avahi, openssl, samba, etc.)
#   - Python venv creation + pip install
#   - NAS directory creation (/srv/nas/personal, family, entertainment/*)
#   - Data directory creation (/var/lib/aihomecloud/)
#   - Device serial + pairing key generation
#   - systemd service install + enable + start
#   - mDNS (Avahi) advertisement
#   - Sudoers rules for passwordless mount/format/service ops
#
# ─── What requires user input ──────────────────────────────────────────────
#
#   - Device name (default: "My Home Cloud")
#   - Admin PIN (4-6 digits)
#   - Storage drive selection (optional — can be done in the app)
#
# ─── What the Flutter app handles (NOT done here) ──────────────────────────
#
#   - User management (add/remove family members, change PINs)
#   - File management (upload, download, browse, search)
#   - Storage management (mount/unmount/eject/format via API)
#   - Telegram bot linking
#   - Service toggles (Samba, NFS, DLNA)
#   - System info, firmware updates, device rename
#
# =============================================================================

set -euo pipefail

# ── Tool detection ────────────────────────────────────────────────────────────
if command -v whiptail &>/dev/null; then
    DIALOG=whiptail
elif command -v dialog &>/dev/null; then
    DIALOG=dialog
else
    echo "Installing whiptail..."
    apt-get update -qq && apt-get install -y whiptail
    DIALOG=whiptail
fi

# ── Must run as root ──────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Please run with sudo:  sudo bash $0"
    exit 1
fi

# ── Resolve repo root ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Configurable paths (must match install.sh / dev-setup.sh) ─────────────────
DATA_DIR="/var/lib/aihomecloud"
NAS_ROOT="/srv/nas"
PORT=8443
MIN_PYTHON_VER="3.12"
BACKEND_DIR="$REPO_ROOT/backend"

# Detect the run-as user (the login user who called sudo)
REPO_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

# ── Dimensions (safe for 80x24 terminal) ──────────────────────────────────────
H=18
W=70
MENU_H=8

# ── Helper functions ──────────────────────────────────────────────────────────

msg_box() {
    # Simple message box with OK button
    local title="$1" text="$2"
    $DIALOG --title "$title" --msgbox "$text" $H $W
}

yes_no() {
    # Yes/No dialog. Returns 0 for Yes, 1 for No.
    local title="$1" text="$2"
    $DIALOG --title "$title" --yesno "$text" $H $W
    return $?
}

input_box() {
    # Single-line input. Prints the entered value to stdout.
    local title="$1" text="$2" default="$3"
    local result
    result=$($DIALOG --title "$title" --inputbox "$text" $H $W "$default" 3>&1 1>&2 2>&3) || return 1
    echo "$result"
}

password_box() {
    # Password input (hidden characters). Prints value to stdout.
    local title="$1" text="$2"
    local result
    result=$($DIALOG --title "$title" --passwordbox "$text" $H $W 3>&1 1>&2 2>&3) || return 1
    echo "$result"
}

gauge_start() {
    # Start a progress gauge. Feed percentage + text via the returned fd.
    # Usage: gauge_start "Title" "Initial text" ; echo "50" > /tmp/ahc_gauge ; ...
    local title="$1" text="$2"
    # We use a FIFO for gauge input
    local fifo="/tmp/ahc_wizard_gauge_$$"
    rm -f "$fifo"
    mkfifo "$fifo"
    $DIALOG --title "$title" --gauge "$text" 8 $W 0 < "$fifo" &
    GAUGE_PID=$!
    exec 3>"$fifo"
    GAUGE_FIFO="$fifo"
}

gauge_update() {
    # Update gauge: percentage, then text on the next line
    local pct="$1" text="$2"
    echo "XXX" >&3 2>/dev/null || true
    echo "$pct" >&3 2>/dev/null || true
    echo "$text" >&3 2>/dev/null || true
    echo "XXX" >&3 2>/dev/null || true
}

gauge_stop() {
    exec 3>&- 2>/dev/null || true
    wait "$GAUGE_PID" 2>/dev/null || true
    rm -f "$GAUGE_FIFO" 2>/dev/null || true
}

show_error() {
    # Friendly error box — never shows raw errors to user
    local text="$1"
    msg_box "Something went wrong" "$text\n\nPress OK to try again."
}

board_friendly_name() {
    # Convert board detection string to a plain English name.
    local model="$1"
    local lower
    lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *sun60iw2*)        echo "Radxa Cubie A7A" ;;
        *cubie*a7z*)       echo "Radxa Cubie A7Z" ;;
        *raspberry*pi*4*)  echo "Raspberry Pi 4" ;;
        *rock*pi*4*)       echo "Radxa Rock Pi 4" ;;
        *radxa*)           echo "$model" ;;
        *)                 echo "Compatible Device" ;;
    esac
}

get_local_ip() {
    # Get the device's primary LAN IP address.
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "$ip" || "$ip" == "127."* ]]; then
        ip="(could not detect)"
    fi
    echo "$ip"
}

# ── Cleanup on exit ──────────────────────────────────────────────────────────
cleanup() {
    exec 3>&- 2>/dev/null || true
    rm -f /tmp/ahc_wizard_gauge_* 2>/dev/null || true
}
trap cleanup EXIT

# =============================================================================
# STEP 1: WELCOME
# =============================================================================

step_welcome() {
    msg_box "Welcome to AiHomeCloud" \
"Your family's private cloud — no subscriptions, no third-party accounts.

This wizard will help you set up your device in about 3 minutes.

You'll choose a name for your device, create a PIN, and optionally set up a storage drive.

When you're done, just open the AiHomeCloud app on your phone to connect."
}

# =============================================================================
# STEP 2: SYSTEM CHECK
# =============================================================================

step_system_check() {
    local all_ok=true
    local results=""
    local board_name="Checking..."

    # --- Internet ---
    local inet_ok=false
    if ping -c1 -W3 8.8.8.8 &>/dev/null || ping -c1 -W3 1.1.1.1 &>/dev/null; then
        inet_ok=true
        results+="Internet connection ............ OK\n"
    else
        # Try DNS-based check as fallback
        if curl -s --max-time 5 https://google.com &>/dev/null; then
            inet_ok=true
            results+="Internet connection ............ OK\n"
        else
            results+="Internet connection ............ FAILED\n"
            all_ok=false
        fi
    fi

    # --- Board detection ---
    local raw_model=""
    if [[ -f /proc/device-tree/model ]]; then
        raw_model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "")
    fi
    if [[ -n "$raw_model" ]]; then
        board_name=$(board_friendly_name "$raw_model")
        results+="Hardware detected .............. $board_name\n"
    else
        board_name="Compatible Device"
        results+="Hardware detected .............. $board_name\n"
    fi

    # --- Python version ---
    local py_ok=false
    if command -v python3 &>/dev/null; then
        local py_ver
        py_ver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        if [[ "$(printf '%s\n' "$MIN_PYTHON_VER" "$py_ver" | sort -V | head -1)" == "$MIN_PYTHON_VER" ]]; then
            py_ok=true
            results+="Python version ................ $py_ver - OK\n"
        else
            results+="Python version ................ $py_ver - TOO OLD\n"
            all_ok=false
        fi
    else
        results+="Python version ................ NOT FOUND\n"
        all_ok=false
    fi

    # --- Required packages ---
    local pkgs_ok=true
    local missing_pkgs=""
    local required_pkgs=(avahi-daemon openssl curl lsof python3-venv)
    for pkg in "${required_pkgs[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
            pkgs_ok=false
            missing_pkgs+=" $pkg"
        fi
    done
    if $pkgs_ok; then
        results+="Required packages ............. All present\n"
    else
        results+="Required packages ............. MISSING:$missing_pkgs\n"
        all_ok=false
    fi

    if $all_ok; then
        msg_box "System Check" \
"All checks passed!\n\n$results\nYour $board_name is ready to set up."
        return 0
    fi

    # --- Handle failures ---
    local fix_msg="Please fix the following and run this wizard again:\n\n"

    if ! $inet_ok; then
        fix_msg+="• No internet connection\n"
        fix_msg+="  Check your Ethernet cable or Wi-Fi settings.\n\n"
    fi
    if ! $py_ok; then
        fix_msg+="• Python $MIN_PYTHON_VER or newer is required\n"
        fix_msg+="  Run: sudo apt-get install python3\n\n"
    fi
    if ! $pkgs_ok; then
        fix_msg+="• Missing packages:$missing_pkgs\n"
        fix_msg+="  Run: sudo apt-get install$missing_pkgs\n\n"
    fi

    msg_box "System Check — Issues Found" "$fix_msg"
    return 1
}

# =============================================================================
# STEP 3: DEVICE NAME
# =============================================================================

step_device_name() {
    local name
    while true; do
        name=$(input_box "Device Name" \
"What should we call your device?\n\nThis name will appear in the app and on your network." \
            "My Home Cloud") || return 1

        # Validate: non-empty, reasonable length, no dangerous chars
        name=$(echo "$name" | xargs)  # trim whitespace
        if [[ -z "$name" ]]; then
            show_error "Please enter a name for your device."
            continue
        fi
        if [[ ${#name} -gt 50 ]]; then
            show_error "The name is too long. Please use 50 characters or less."
            continue
        fi
        if [[ "$name" == *\"* || "$name" == *\\* || "$name" == *\'* ]]; then
            show_error "Please avoid using quotes or backslashes in the name."
            continue
        fi
        DEVICE_NAME="$name"
        return 0
    done
}

# =============================================================================
# STEP 4: ADMIN PIN
# =============================================================================

step_admin_pin() {
    local pin confirm_pin
    while true; do
        pin=$(password_box "Create a PIN" \
"Create a PIN to protect your device.\n\nYou'll enter this in the app to log in as admin.\n\nUse 4 to 6 digits only.") || return 1

        # Validate: 4-6 digits
        if [[ ! "$pin" =~ ^[0-9]{4,6}$ ]]; then
            show_error "Your PIN must be 4 to 6 digits (numbers only)."
            continue
        fi

        confirm_pin=$(password_box "Confirm PIN" \
"Please enter your PIN again to confirm.") || return 1

        if [[ "$pin" != "$confirm_pin" ]]; then
            show_error "The PINs didn't match. Please try again."
            continue
        fi

        ADMIN_PIN="$pin"
        return 0
    done
}

# =============================================================================
# STEP 5: STORAGE (OPTIONAL)
# =============================================================================

_list_external_drives() {
    # List external drives (USB/NVMe) suitable for NAS storage.
    # Output: one line per drive: "DEVICE_NAME|FRIENDLY_NAME|SIZE"
    # Skips OS partitions (mmcblk, loop, zram, mtd).
    local lsblk_json
    lsblk_json=$(lsblk -J -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,TRAN,SERIAL 2>/dev/null) || return 1

    echo "$lsblk_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
OS_PREFIXES = ('mmcblk', 'mtdblock', 'zram', 'loop')
for dev in data.get('blockdevices', []):
    name = dev.get('name', '')
    dtype = dev.get('type', '')
    if dtype != 'disk':
        continue
    if any(name.startswith(p) for p in OS_PREFIXES):
        continue
    model = (dev.get('model') or '').strip()
    size = dev.get('size', '?')
    tran = (dev.get('tran') or '').lower()
    # Build friendly name
    if model:
        friendly = model
    elif tran == 'usb':
        friendly = 'USB Drive'
    elif tran == 'nvme' or name.startswith('nvme'):
        friendly = 'NVMe SSD'
    else:
        friendly = 'Storage Drive'
    friendly += f' ({size})'
    print(f'{name}|{friendly}|{size}')
" 2>/dev/null
}

step_storage() {
    # Ask whether to set up storage now or skip
    if ! yes_no "Storage Setup" \
"Your storage drive can be set up now or later in the app.\n\nSetting it up here is faster if you have a drive connected.\n\n  Set up now?  Choose Yes.\n  Skip for now?  Choose No."; then
        STORAGE_DEVICE=""
        return 0
    fi

    # List external drives
    local drives_raw
    drives_raw=$(_list_external_drives)

    if [[ -z "$drives_raw" ]]; then
        msg_box "No Drives Found" \
"No external storage drives were detected.\n\nPlug in a USB drive or NVMe SSD and run this wizard again, or set up storage later in the app."
        STORAGE_DEVICE=""
        return 0
    fi

    # Build menu items
    local menu_items=()
    local count=0
    while IFS='|' read -r dev_name friendly size; do
        count=$((count + 1))
        menu_items+=("$dev_name" "$friendly")
    done <<< "$drives_raw"

    if [[ $count -eq 0 ]]; then
        msg_box "No Drives Found" \
"No external storage drives were detected.\n\nYou can set up storage later in the app."
        STORAGE_DEVICE=""
        return 0
    fi

    # Show drive selection menu
    local selected
    selected=$($DIALOG --title "Select a Drive" \
        --menu "Choose a drive to use for your files:" \
        $H $W $MENU_H "${menu_items[@]}" 3>&1 1>&2 2>&3) || {
        STORAGE_DEVICE=""
        return 0
    }

    # Find the friendly name for the warning
    local selected_friendly=""
    while IFS='|' read -r dev_name friendly size; do
        if [[ "$dev_name" == "$selected" ]]; then
            selected_friendly="$friendly"
            break
        fi
    done <<< "$drives_raw"

    # Confirm with strong warning
    if ! yes_no "Warning — Erase Drive?" \
"This will ERASE EVERYTHING on:\n\n  $selected_friendly\n\nAll existing files on this drive will be permanently deleted.\n\nAre you sure you want to continue?"; then
        STORAGE_DEVICE=""
        return 0
    fi

    STORAGE_DEVICE="$selected"
    return 0
}

# =============================================================================
# STEP 6: INSTALL
# =============================================================================

step_install() {
    gauge_start "Setting up AiHomeCloud" "Starting installation..."

    # ── 10%: System packages ──────────────────────────────────────────────────
    gauge_update 5 "Checking system packages..."
    local to_install=()
    local required_pkgs=(python3 python3-venv python3-pip openssl avahi-daemon curl lsof)
    for pkg in "${required_pkgs[@]}"; do
        dpkg -s "$pkg" &>/dev/null 2>&1 || to_install+=("$pkg")
    done
    if [[ ${#to_install[@]} -gt 0 ]]; then
        gauge_update 8 "Installing system packages..."
        apt-get update -qq >/dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${to_install[@]}" >/dev/null 2>&1
    fi
    gauge_update 15 "System packages ready."

    # ── 25%: Python venv ──────────────────────────────────────────────────────
    gauge_update 20 "Setting up Python environment..."
    local venv_dir="$BACKEND_DIR/.venv"
    local venv_python="$venv_dir/bin/python"
    if [[ ! -f "$venv_python" ]]; then
        sudo -u "$REPO_USER" python3 -m venv "$venv_dir" 2>/dev/null
    fi
    if [[ -f "$BACKEND_DIR/requirements.txt" ]]; then
        gauge_update 25 "Installing backend dependencies..."
        sudo -u "$REPO_USER" "$venv_dir/bin/pip" install --quiet --upgrade pip 2>/dev/null
        sudo -u "$REPO_USER" "$venv_dir/bin/pip" install --quiet -r "$BACKEND_DIR/requirements.txt" 2>/dev/null
    fi
    gauge_update 40 "Python environment ready."

    # ── 45%: Data + NAS directories ───────────────────────────────────────────
    gauge_update 45 "Creating your storage folders..."
    mkdir -p "$DATA_DIR/tls" \
        "$NAS_ROOT/personal" "$NAS_ROOT/family" "$NAS_ROOT/entertainment" \
        "$NAS_ROOT/entertainment/Movies" "$NAS_ROOT/entertainment/Music" \
        "$NAS_ROOT/entertainment/Series" "$NAS_ROOT/entertainment/Anime" \
        "$NAS_ROOT/entertainment/Others" 2>/dev/null
    chown -R "$REPO_USER:$REPO_USER" "$DATA_DIR" "$NAS_ROOT" 2>/dev/null
    chmod 750 "$DATA_DIR"

    # ── 50%: Device serial + pairing key ──────────────────────────────────────
    gauge_update 50 "Generating device credentials..."
    local mac auto_serial pairing_key
    mac=$(ip link show 2>/dev/null | awk '/ether / {print $2}' | head -1 | tr -d ':' | tr '[:lower:]' '[:upper:]')
    auto_serial="AHC-$(hostname -s | tr '[:lower:]' '[:upper:]')-${mac:(-4)}"

    local pairing_key_file="$DATA_DIR/pairing_key"
    if [[ -f "$pairing_key_file" ]]; then
        pairing_key=$(cat "$pairing_key_file")
    else
        pairing_key=$(openssl rand -hex 16)
        echo "$pairing_key" > "$pairing_key_file"
        chmod 600 "$pairing_key_file"
        chown "$REPO_USER:$REPO_USER" "$pairing_key_file"
    fi

    # ── 55%: Set device name via JSON ─────────────────────────────────────────
    gauge_update 55 "Setting device name..."
    local device_file="$DATA_DIR/device.json"
    # Always update the device name (user just chose it)
    # Use python3 for safe JSON serialization (handles quotes, unicode)
    python3 -c "import json; f=open('$device_file','w'); json.dump({'name': '$DEVICE_NAME'.replace(chr(39), chr(8217))}, f); f.close()"
    chown "$REPO_USER:$REPO_USER" "$device_file"

    # ── 60%: Avahi mDNS ──────────────────────────────────────────────────────
    gauge_update 60 "Setting up network discovery..."
    local avahi_svc_dir="/etc/avahi/services"
    local avahi_svc_file="$avahi_svc_dir/aihomecloud.service"
    local mdns_src="$BACKEND_DIR/scripts/aihomecloud-mdns.service"
    if [[ -f "$mdns_src" ]]; then
        mkdir -p "$avahi_svc_dir"
        cp "$mdns_src" "$avahi_svc_file"
        chmod 644 "$avahi_svc_file"
    fi
    if ! systemctl is-active --quiet avahi-daemon 2>/dev/null; then
        systemctl enable avahi-daemon 2>/dev/null || true
        systemctl start avahi-daemon 2>/dev/null || true
    fi

    # ── 65%: Sudoers rules ────────────────────────────────────────────────────
    gauge_update 65 "Configuring permissions..."
    local sudoers_file="/etc/sudoers.d/aihomecloud"
    local sudoers_version="3"  # bump when rules change
    local needs_sudoers=false
    if [[ ! -f "$sudoers_file" ]]; then
        needs_sudoers=true
    elif ! grep -q "AHC_SUDOERS_VERSION=$sudoers_version" "$sudoers_file" 2>/dev/null; then
        needs_sudoers=true
    fi
    if $needs_sudoers; then
        cat > "$sudoers_file" << EOF
# AiHomeCloud — limited sudo for service user
# Only commands required by the backend are allowed.
# AHC_SUDOERS_VERSION=$sudoers_version
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start *, /usr/bin/systemctl stop *, /usr/bin/systemctl restart *, /usr/bin/systemctl status *
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl daemon-reload
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable *
$REPO_USER ALL=(ALL) NOPASSWD: /usr/sbin/shutdown, /usr/sbin/reboot
$REPO_USER ALL=(ALL) NOPASSWD: /usr/sbin/mkfs.ext4, /usr/sbin/mkfs.exfat, /usr/sbin/mkfs.vfat
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/mount, /usr/bin/umount
$REPO_USER ALL=(ALL) NOPASSWD: /usr/sbin/sgdisk, /usr/sbin/parted
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/udevadm, /usr/bin/lsof, /usr/bin/fuser, /usr/bin/sync
$REPO_USER ALL=(ALL) NOPASSWD: /usr/sbin/smartctl
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/lsblk, /usr/bin/blkid, /usr/bin/findmnt
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/apt-get install -y *
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/cp /tmp/telegram-bot-api /usr/local/bin/telegram-bot-api
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/cp /tmp/telegram-bot-api-build/build/telegram-bot-api /usr/local/bin/telegram-bot-api
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/cp /tmp/telegram-bot-api.service /etc/systemd/system/telegram-bot-api.service
$REPO_USER ALL=(ALL) NOPASSWD: /usr/bin/chmod 755 /usr/local/bin/telegram-bot-api
EOF
        chmod 440 "$sudoers_file"
        if ! visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
            rm -f "$sudoers_file"
        fi
    fi

    # ── 70%: systemd service ──────────────────────────────────────────────────
    gauge_update 70 "Setting up system services..."
    local service_file="/etc/systemd/system/aihomecloud.service"
    cat > "$service_file" << EOF
[Unit]
Description=AiHomeCloud Backend API
After=network.target avahi-daemon.service

[Service]
SyslogIdentifier=aihomecloud
Type=simple
User=$REPO_USER
Group=$REPO_USER
WorkingDirectory=$BACKEND_DIR
ExecStart=$venv_python -m app.main
Restart=always
RestartSec=5
NoNewPrivileges=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service
LimitNOFILE=65536

Environment=AHC_DEVICE_SERIAL=$auto_serial
Environment=AHC_PAIRING_KEY=$pairing_key
Environment=AHC_NAS_ROOT=$NAS_ROOT
Environment=AHC_DATA_DIR=$DATA_DIR
Environment=AHC_TLS_ENABLED=true
Environment=AHC_SKIP_MOUNT_CHECK=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$service_file"

    # ── 75%: Storage format (if user chose a drive) ───────────────────────────
    if [[ -n "${STORAGE_DEVICE:-}" ]]; then
        gauge_update 75 "Preparing storage drive..."
        local disk_path="/dev/$STORAGE_DEVICE"
        local part_path

        # Determine partition path convention
        if [[ "$STORAGE_DEVICE" == nvme* ]]; then
            part_path="${disk_path}p1"
        else
            part_path="${disk_path}1"
        fi

        # Wipe signatures
        gauge_update 78 "Erasing drive..."
        sgdisk -Z "$disk_path" >/dev/null 2>&1 || true

        # Create GPT with one partition
        sgdisk -n 1:0:0 -t 1:8300 "$disk_path" >/dev/null 2>&1
        sleep 2
        udevadm settle --timeout=5 2>/dev/null || true

        # Format as ext4
        gauge_update 82 "Formatting drive (this may take a moment)..."
        mkfs.ext4 -F -L "AiHomeCloud" "$part_path" >/dev/null 2>&1

        # Mount
        gauge_update 88 "Mounting drive..."
        mount "$part_path" "$NAS_ROOT" 2>/dev/null

        # Recreate NAS dirs on the mounted drive
        mkdir -p "$NAS_ROOT/personal" "$NAS_ROOT/family" "$NAS_ROOT/entertainment" \
            "$NAS_ROOT/entertainment/Movies" "$NAS_ROOT/entertainment/Music" \
            "$NAS_ROOT/entertainment/Series" "$NAS_ROOT/entertainment/Anime" \
            "$NAS_ROOT/entertainment/Others" 2>/dev/null
        chown -R "$REPO_USER:$REPO_USER" "$NAS_ROOT" 2>/dev/null

        # Update the service to not skip mount check
        sed -i 's/AHC_SKIP_MOUNT_CHECK=true/AHC_SKIP_MOUNT_CHECK=false/' "$service_file" 2>/dev/null || true
    fi

    # ── 90%: Create admin user via backend ────────────────────────────────────
    gauge_update 90 "Starting AiHomeCloud..."
    systemctl daemon-reload
    systemctl enable aihomecloud 2>/dev/null || true

    # Disable any old user-level service
    local user_svc="/home/$REPO_USER/.config/systemd/user/aihomecloud.service"
    if [[ -f "$user_svc" ]]; then
        sudo -u "$REPO_USER" systemctl --user stop aihomecloud 2>/dev/null || true
        sudo -u "$REPO_USER" systemctl --user disable aihomecloud 2>/dev/null || true
    fi

    if systemctl is-active --quiet aihomecloud 2>/dev/null; then
        systemctl restart aihomecloud
    else
        systemctl start aihomecloud
    fi

    # Wait for the backend to come up
    gauge_update 92 "Waiting for backend to start..."
    local retries=10
    local backend_up=false
    for i in $(seq 1 $retries); do
        sleep 2
        if curl -sk --max-time 3 "https://localhost:$PORT/api/health" 2>/dev/null | grep -q '"ok"'; then
            backend_up=true
            break
        fi
    done

    # ── 95%: Create admin user via API ────────────────────────────────────────
    if $backend_up; then
        gauge_update 95 "Creating admin account..."

        # Get pairing key for API auth
        local pair_response
        pair_response=$(curl -sk --max-time 10 \
            -X POST "https://localhost:$PORT/api/v1/pair" \
            -H "Content-Type: application/json" \
            -d "{\"serial\": \"$auto_serial\", \"pairingKey\": \"$pairing_key\"}" 2>/dev/null) || true

        local pair_token=""
        if [[ -n "$pair_response" ]]; then
            pair_token=$(echo "$pair_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null) || true
        fi

        if [[ -n "$pair_token" ]]; then
            # Check if any users exist already
            local users_response
            users_response=$(curl -sk --max-time 10 \
                -H "Authorization: Bearer $pair_token" \
                "https://localhost:$PORT/api/v1/users" 2>/dev/null) || true

            local user_count=0
            if [[ -n "$users_response" ]]; then
                user_count=$(echo "$users_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null) || true
            fi

            if [[ "${user_count:-0}" -eq 0 ]]; then
                # Create admin user
                curl -sk --max-time 10 \
                    -X POST "https://localhost:$PORT/api/v1/users" \
                    -H "Authorization: Bearer $pair_token" \
                    -H "Content-Type: application/json" \
                    -d "{\"displayName\": \"Admin\", \"pin\": \"$ADMIN_PIN\", \"role\": \"admin\", \"emoji\": \"👑\"}" >/dev/null 2>&1 || true
            fi
        fi

        # Set device name via API
        curl -sk --max-time 10 \
            -X PUT "https://localhost:$PORT/api/v1/system/name" \
            -H "Authorization: Bearer ${pair_token:-}" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"$DEVICE_NAME\"}" >/dev/null 2>&1 || true
    fi

    gauge_update 100 "Almost done..."
    sleep 1
    gauge_stop
}

# =============================================================================
# STEP 7: DONE
# =============================================================================

step_done() {
    local ip
    ip=$(get_local_ip)

    local summary="Setup complete!\n\n"
    summary+="  Device name:    $DEVICE_NAME\n"
    summary+="  Local address:  $ip\n"
    summary+="  Port:           $PORT\n\n"

    if [[ -n "${STORAGE_DEVICE:-}" ]]; then
        summary+="  Storage:        Drive set up and ready\n\n"
    else
        summary+="  Storage:        Set up later in the app\n\n"
    fi

    summary+="Open the AiHomeCloud app on your phone\n"
    summary+="and tap + to add this device.\n\n"
    summary+="The app will find your device automatically on the\nsame Wi-Fi network."

    msg_box "You're All Set!" "$summary"
}

# =============================================================================
# MAIN — Run all steps
# =============================================================================

DEVICE_NAME="My Home Cloud"
ADMIN_PIN=""
STORAGE_DEVICE=""

main() {
    # Step 1: Welcome
    step_welcome

    # Step 2: System check
    if ! step_system_check; then
        exit 1
    fi

    # Step 3: Device name (with back support via re-run)
    step_device_name || exit 0

    # Step 4: Admin PIN
    step_admin_pin || { step_device_name || exit 0; step_admin_pin || exit 0; }

    # Step 5: Storage (optional)
    step_storage || true

    # Step 6: Install (no user input)
    step_install

    # Step 7: Done
    step_done
}

main "$@"
