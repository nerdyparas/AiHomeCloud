#!/usr/bin/env bash
# AiHomeCloud — Telegram Local Bot API Server setup
# Run once on the SBC to enable file uploads larger than 20MB.
# Requires: TELEGRAM_API_ID and TELEGRAM_API_HASH from https://my.telegram.org
#
# Usage:
#   TELEGRAM_API_ID=12345 TELEGRAM_API_HASH=abcdef ./setup-telegram-local-api.sh

set -euo pipefail

API_ID="${TELEGRAM_API_ID:-}"
API_HASH="${TELEGRAM_API_HASH:-}"
DATA_DIR="/var/lib/telegram-bot-api"
SERVICE_NAME="telegram-bot-api"
PORT=8081

if [[ -z "$API_ID" || -z "$API_HASH" ]]; then
  echo "ERROR: Set TELEGRAM_API_ID and TELEGRAM_API_HASH before running."
  echo "Get them at https://my.telegram.org → API development tools"
  exit 1
fi

echo "==> Creating data directory..."
sudo mkdir -p "$DATA_DIR"
sudo chown "$USER:$USER" "$DATA_DIR"

# ── Try Docker first (easiest on ARM64) ──────────────────────────────────────
if command -v docker &>/dev/null; then
  echo "==> Docker found — using container image..."

  sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Telegram Local Bot API Server
After=network.target docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=5
ExecStartPre=-/usr/bin/docker rm -f ${SERVICE_NAME}
ExecStart=/usr/bin/docker run --rm \
  --name ${SERVICE_NAME} \
  -p ${PORT}:8081 \
  -v ${DATA_DIR}:/var/lib/telegram-bot-api \
  -e TELEGRAM_API_ID=${API_ID} \
  -e TELEGRAM_API_HASH=${API_HASH} \
  aiogram/telegram-bot-api:latest \
  --local
ExecStop=/usr/bin/docker stop ${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

else
  echo "==> Docker not found — building from source (takes ~15 min on ARM)..."
  sudo apt-get install -y cmake g++ libssl-dev zlib1g-dev gperf

  BUILD_DIR="/tmp/telegram-bot-api-build"
  rm -rf "$BUILD_DIR"
  git clone --recursive https://github.com/tdlib/telegram-bot-api.git "$BUILD_DIR"
  cd "$BUILD_DIR"
  mkdir build && cd build
  cmake -DCMAKE_BUILD_TYPE=Release ..
  cmake --build . --target telegram-bot-api -j"$(nproc)"
  sudo cp telegram-bot-api /usr/local/bin/
  cd / && rm -rf "$BUILD_DIR"

  sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Telegram Local Bot API Server
After=network.target

[Service]
User=$USER
Restart=always
RestartSec=5
ExecStart=/usr/local/bin/telegram-bot-api \
  --api-id=${API_ID} \
  --api-hash=${API_HASH} \
  --http-port=${PORT} \
  --dir=${DATA_DIR} \
  --local
Environment=HOME=/var/lib/telegram-bot-api

[Install]
WantedBy=multi-user.target
EOF
fi

sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}

echo ""
echo "==> Waiting for local API server to start..."
sleep 5
if curl -sf "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
  echo "✅ Local Bot API Server is running on port ${PORT}"
else
  echo "⚠️  Server may still be starting — check: systemctl status ${SERVICE_NAME}"
fi

echo ""
echo "==> Done. Now set these in your AiHomeCloud app:"
echo "    API ID:   ${API_ID}"
echo "    API Hash: ${API_HASH}"
echo "    Enable 'Large file uploads' toggle in Telegram Bot settings."
