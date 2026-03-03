#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# CubieCloud deploy helper
#
# Required env vars:
#   TARGET_HOST   - Cubie host or IP (e.g. 192.168.0.212)
#
# Optional env vars:
#   TARGET_PORT   - API port (default: 8443)
#   CUBIE_CERT    - Path to server certificate PEM for TLS verification
#
# Health check behavior:
#   - If CUBIE_CERT is set: curl --cacert "$CUBIE_CERT" https://...
#   - If CUBIE_CERT is not set: warns loudly and uses curl -k (insecure)
# -----------------------------------------------------------------------------

TARGET_HOST="${TARGET_HOST:-}"
TARGET_PORT="${TARGET_PORT:-8443}"

if [[ -z "$TARGET_HOST" ]]; then
  echo "ERROR: TARGET_HOST is required"
  exit 1
fi

HEALTH_URL="https://${TARGET_HOST}:${TARGET_PORT}/api/health"

echo "Checking backend health at: ${HEALTH_URL}"

if [[ -n "${CUBIE_CERT:-}" ]]; then
  echo "Using CA cert: ${CUBIE_CERT}"
  curl --fail --silent --show-error --max-time 10 \
    --cacert "${CUBIE_CERT}" \
    "${HEALTH_URL}" >/dev/null
else
  echo "WARNING: CUBIE_CERT is not set. Falling back to insecure TLS verification bypass (-k)."
  echo "WARNING: This should only be used for local/dev workflows."
  curl --fail --silent --show-error --max-time 10 \
    -k \
    "${HEALTH_URL}" >/dev/null
fi

echo "Health check passed."
