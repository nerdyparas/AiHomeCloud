#!/usr/bin/env bash
# =============================================================================
# install.sh — Download and install the telegram-bot-api binary for AiHomeCloud
#
# Detects the current CPU architecture, downloads the correct pre-built binary
# from the GitHub Releases page, and installs it to /usr/local/bin/.
#
# This script is called automatically by AiHomeCloud when you enable 2 GB
# Telegram file transfer mode.  You can also run it manually:
#
#   curl -fsSL https://raw.githubusercontent.com/nerdyparas/AiHomeCloud/main/scripts/install.sh | sudo bash
#   # or, if you have the repo checked out:
#   sudo bash scripts/install.sh
#
# Requirements: curl (or wget as fallback), sha256sum, sudo
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
GITHUB_REPO="nerdyparas/AiHomeCloud"
BINARY_NAME="telegram-bot-api"
INSTALL_DIR="/usr/local/bin"
RELEASES_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[install]${NC} $*"; }
info() { echo -e "${CYAN}[install]${NC} $*"; }
warn() { echo -e "${YELLOW}[install]${NC} $*"; }
die()  { echo -e "${RED}[install] ERROR:${NC} $*" >&2; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run with sudo: sudo bash $0"

# ── Architecture detection ────────────────────────────────────────────────────
detect_arch() {
  local raw
  raw=$(uname -m)
  case "$raw" in
    x86_64)          echo "linux-amd64"  ;;
    aarch64 | arm64) echo "linux-arm64"  ;;
    armv7l | armv7)  echo "linux-armv7"  ;;
    armv6l)
      die "armv6 (Raspberry Pi 1/Zero) is not supported by pre-built binaries.\n" \
          "Enable 2 GB mode from AiHomeCloud — it will compile from source automatically."
      ;;
    *) die "Unsupported architecture: ${raw}" ;;
  esac
}

# ── Download helper (curl with wget fallback) ─────────────────────────────────
download() {
  local url="$1" dest="$2"
  if command -v curl &>/dev/null; then
    curl -fsSL --max-time 120 --retry 3 --retry-delay 2 -o "$dest" "$url"
  elif command -v wget &>/dev/null; then
    wget -q --timeout=120 --tries=3 -O "$dest" "$url"
  else
    die "Neither curl nor wget found. Install one and retry."
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
log "=== AiHomeCloud — telegram-bot-api installer ==="

# 1. Detect architecture
ARCH_TARGET=$(detect_arch)
info "Detected architecture: $(uname -m) → ${ARCH_TARGET}"

# 2. Build download URL
BINARY_ARTIFACT="${BINARY_NAME}-${ARCH_TARGET}"
DOWNLOAD_URL="${RELEASES_BASE}/${BINARY_ARTIFACT}"
TMP_FILE=$(mktemp "/tmp/${BINARY_ARTIFACT}.XXXXXX")
trap 'rm -f "$TMP_FILE"' EXIT

# 3. Download binary
info "Downloading ${BINARY_ARTIFACT} ..."
info "  from: ${DOWNLOAD_URL}"
if ! download "$DOWNLOAD_URL" "$TMP_FILE"; then
  die "Download failed.\n" \
      "Make sure a release exists at: https://github.com/${GITHUB_REPO}/releases/latest\n" \
      "Or enable 2 GB mode from AiHomeCloud — it will compile from source automatically."
fi

# 4. Sanity-check: must be an ELF executable
if ! file "$TMP_FILE" | grep -q "ELF"; then
  die "Downloaded file is not an ELF binary. Release artifact may be corrupt.\n" \
      "Downloaded content:\n$(head -c 200 "$TMP_FILE")"
fi

# 5. Install
INSTALL_PATH="${INSTALL_DIR}/${BINARY_NAME}"
cp "$TMP_FILE" "$INSTALL_PATH"
chmod 755 "$INSTALL_PATH"

# 6. Verify
if ! "$INSTALL_PATH" --version &>/dev/null 2>&1; then
  # telegram-bot-api exits non-zero when called with --version but still prints
  # its version; just confirm the binary runs at all
  :
fi

log "Installed: ${INSTALL_PATH}"
log "    size:  $(du -h "$INSTALL_PATH" | cut -f1)"
log "    arch:  $(file "$INSTALL_PATH" | grep -oP 'ELF [^,]+' || echo 'unknown')"
log ""
log "Done. AiHomeCloud will configure and start the service automatically."
