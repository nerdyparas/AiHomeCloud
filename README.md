# AiHomeCloud

Your family's private cloud. One device, one price, no subscriptions.

[![Backend Tests](https://github.com/nerdyparas/AiHomeCloud/actions/workflows/backend-tests.yml/badge.svg)](https://github.com/nerdyparas/AiHomeCloud/actions/workflows/backend-tests.yml)
[![Flutter Analyze](https://github.com/nerdyparas/AiHomeCloud/actions/workflows/flutter-analyze.yml/badge.svg)](https://github.com/nerdyparas/AiHomeCloud/actions/workflows/flutter-analyze.yml)

---

## What is AiHomeCloud?

AiHomeCloud turns a small ARM single-board computer into a private family NAS — no cloud accounts, no monthly fees, no data leaving your home. Plug in a USB or NVMe drive, run the setup wizard once, pair the Android app, and your family's files are organized, searchable, and accessible from any device on your LAN.

---

## Features

### File Management
- Browse, upload, download, rename, delete files and folders
- Paginated folder view with sort by name, size, or date
- Per-user **Personal** folder + shared **Family** and **Entertainment** folders
- Soft-delete to trash with restore, permanent delete, and auto-purge (30-day, opt-in)
- Chunked upload (4 MB) for the mobile app; streaming upload (up to 25 GB) for the web portal
- Full-text search across documents (SQLite FTS5, optional OCR via Tesseract)
- Auto-sort: watches inbox directories and moves files into subfolders by type

### Web Upload Portal
- Drag-and-drop upload page accessible at `https://<device-ip>:8443/web` from any browser on your LAN
- Three upload zones: Personal, Family, Entertainment
- Live progress with transfer rate and transferred/total size display
- Duplicate detection with warning modal before overwriting
- Per-file cancel (✕) and Cancel All button
- Clear button to dismiss completed entries

### Mobile App (Android)
- Netflix-style user picker with optional PIN per user
- Real-time dashboard: CPU, RAM, temperature, storage donut chart
- File browser with image and text preview
- Storage device management: hot-plug USB drives, format, mount, unmount, safe eject
- Phone auto-backup every 6 hours over Wi-Fi (WorkManager, SHA-256 dedup)
- Family member management (admin adds/removes users)
- Service toggles: SSH, NFS, DLNA/Samba (TV & computer sharing)
- Network status, Wi-Fi toggle
- Telegram bot setup screen

### Telegram Bot (optional)
- Link a Telegram chat to your device with `/auth <pairing-key>`
- Send any file to the bot → saved directly to your NAS
- Commands: `/list`, `/recent`, `/storage`, `/duplicates`, `/scan`, `/mount`, `/whoami`, `/unlink`, `/keep`, `/skip`
- Admin approval flow for new users
- Weekly trash warning if trash exceeds 10 GB
- Optional local Bot API server removes the 20 MB Telegram file size limit (raises it to 2 GB)

### Security
- Self-signed TLS on port 8443 with Trust-on-First-Use (TOFU) certificate pinning in the app
- QR code pairing: OTP + device serial + pairing key
- JWT access tokens (1-hour expiry) + refresh tokens
- Per-user bcrypt-hashed PINs
- Rate limiting on all API endpoints
- Systemd sandboxing (MemoryMax=1G, CPUQuota=80%)

---

## Hardware

| Device | SoC | RAM | Notes |
|---|---|---|---|
| Radxa Cubie A7Z | Rockchip (ARM64) | 8 GB | Production target |
| Radxa Cubie A7A | Allwinner A527 | 8 GB | Alternate production |
| Radxa ROCK Pi 4A | RK3399 | 4 GB | Dev/test hardware |
| Raspberry Pi 4B | BCM2711 | 2–8 GB | Supported |

**Storage:** microSD for OS only. Plug in USB 3.0 drives or M.2 NVMe for NAS storage.

**Network:** Gigabit Ethernet recommended. Wi-Fi and Bluetooth LE also supported.

---

## First-Time Setup

SSH into your device, then run the interactive wizard:

```bash
sudo bash scripts/setup-wizard.sh
```

The wizard takes about 3 minutes and walks you through:
1. Naming your device
2. Creating an admin PIN
3. Optionally activating a connected storage drive

For headless / manual setup, see [`kb/setup-instructions.md`](kb/setup-instructions.md).

### Verify the installation

```bash
curl -sk https://localhost:8443/api/health   # should return {"status":"ok"}
sudo systemctl status aihomecloud           # should show "active (running)"
```

---

## Pairing the App

1. Open the AiHomeCloud app on your Android phone
2. Tap **Scan QR** on the welcome screen
3. On your device, visit `https://<device-ip>:8443/web` or run:
   ```bash
   curl -sk https://localhost:8443/api/v1/pair/qr
   ```
4. Accept the TLS certificate fingerprint shown by the app — this pins the cert for future connections

---

## Web Upload Portal

Open a browser on any device on your LAN and navigate to:

```
https://<device-ip>:8443/web
```

Select your user, enter your PIN, then drag files into the Personal, Family, or Entertainment zones.

> **Note:** Your browser will show a TLS warning (self-signed cert). This is expected — click **Advanced → Proceed** to continue.

---

## Development

### Repository structure

```
AiHomeCloud/
├── backend/           # FastAPI backend (Python 3.12)
│   ├── app/
│   │   ├── main.py            # Entry point + lifespan management
│   │   ├── config.py          # Settings (AHC_* env vars)
│   │   ├── routes/            # API route modules
│   │   └── telegram/          # Telegram bot implementation
│   ├── tests/                 # Pytest test suite
│   └── aihomecloud.service    # Systemd unit file
├── lib/               # Flutter app (Dart)
│   ├── screens/       # App screens
│   ├── providers/     # Riverpod state
│   ├── models/        # Data models
│   └── services/      # Background workers
├── scripts/           # Setup and dev scripts
├── kb/                # Reference documentation
├── install.sh         # Universal installer
└── pubspec.yaml       # Flutter dependencies
```

### Backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m app.main
```

Run tests (requires SSH to Radxa for full suite):

```bash
python -m pytest tests/ -q --ignore=tests/test_hardware_integration.py
```

### Flutter app

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk
```

---

## Configuration

All settings are controlled via environment variables prefixed with `AHC_`. Key options:

| Variable | Default | Description |
|---|---|---|
| `AHC_NAS_ROOT` | `/srv/nas` | Root path of the NAS storage mount |
| `AHC_DATA_DIR` | `/var/lib/aihomecloud` | State files, TLS certs, user data |
| `AHC_PORT` | `8443` | HTTPS listen port |
| `AHC_DEVICE_NAME` | `My AiHomeCloud` | Display name shown in the app |
| `AHC_MAX_UPLOAD_BYTES` | `26843545600` | Max single-file upload size (25 GB; 0 = unlimited) |
| `AHC_JWT_EXPIRE_HOURS` | `1` | JWT access token lifetime |
| `AHC_BCRYPT_ROUNDS` | `10` | bcrypt work factor |
| `AHC_OCR_ENABLED` | `false` | Enable full-text OCR indexing (requires Tesseract) |
| `AHC_AUTO_SORT_ENABLED` | `false` | Auto-sort inbox directories by file type |
| `AHC_TELEGRAM_BOT_TOKEN` | *(empty)* | Set to enable the Telegram bot |
| `AHC_TELEGRAM_LOCAL_API_ENABLED` | `false` | Use local Bot API server (2 GB file limit) |

See [`backend/app/config.py`](backend/app/config.py) for the full list.

---

## API

The backend exposes a versioned REST API at `/api/v1/` plus two WebSocket streams:

| Stream | Path | Description |
|---|---|---|
| Monitor | `wss://<device>/ws/monitor` | System stats every ~2 s (CPU, RAM, temp, network) |
| Events | `wss://<device>/ws/events` | Real-time notifications (upload done, trash warnings, etc.) |

Full API reference: [`kb/api-contracts.md`](kb/api-contracts.md)

---

## Documentation

| Doc | Description |
|---|---|
| [`kb/setup-instructions.md`](kb/setup-instructions.md) | Full deployment guide |
| [`kb/hardware.md`](kb/hardware.md) | SBC specs, storage, network services, key paths |
| [`kb/features.md`](kb/features.md) | Complete feature inventory |
| [`kb/api-contracts.md`](kb/api-contracts.md) | API endpoint reference |
| [`kb/architecture.md`](kb/architecture.md) | System architecture overview |
| [`RELEASE_PROCESS.md`](RELEASE_PROCESS.md) | Release workflow |

---

## License

Proprietary — all rights reserved.
