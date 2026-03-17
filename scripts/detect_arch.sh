#!/usr/bin/env bash
# =============================================================================
# detect_arch.sh — Map uname -m to the binary suffix used in GitHub Releases
#
# Output: prints one of: linux-amd64 | linux-arm64 | linux-armv7
# Exit 0 on success, exit 1 on unsupported architecture.
#
# Usage (source or subprocess):
#   source scripts/detect_arch.sh && echo "$ARCH_TARGET"
#   TARGET=$(bash scripts/detect_arch.sh) || exit 1
# =============================================================================

set -euo pipefail

_raw=$(uname -m)

case "$_raw" in
  x86_64)          ARCH_TARGET="linux-amd64"  ;;
  aarch64 | arm64) ARCH_TARGET="linux-arm64"  ;;
  armv7l | armv7)  ARCH_TARGET="linux-armv7"  ;;
  armv6l)
    echo "ERROR: armv6 (e.g. Raspberry Pi 1/Zero) is not supported." >&2
    echo "       Compile telegram-bot-api from source on the device." >&2
    exit 1
    ;;
  *)
    echo "ERROR: Unsupported architecture: ${_raw}" >&2
    exit 1
    ;;
esac

echo "$ARCH_TARGET"
