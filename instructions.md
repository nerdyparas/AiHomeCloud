# AiHomeCloud — Deployment & Testing Instructions

> Step-by-step guide for deploying the backend on Cubie hardware
> and validating every feature before user testing.
> Last updated: 2026-03-10

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Backend Deployment on Cubie](#2-backend-deployment-on-cubie)
3. [Flutter App Build](#3-flutter-app-build)
4. [Testing Methodology](#4-testing-methodology)
5. [Backend Test Suite](#5-backend-test-suite)
6. [Hardware Validation Checklist](#6-hardware-validation-checklist)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Prerequisites

### Hardware
- **Radxa Cubie A7A** (ARM64, Allwinner A527, 8 GB RAM) with Ubuntu/Debian ARM64
- **microSD card** (≥16 GB) — OS + config
- **USB HDD/SSD** (any size) — NAS storage, mounted at `/srv/nas/`
- **Ethernet** connection to home router (Wi-Fi optional)

### Development Machine
- Windows 10/11 (or macOS/Linux)
- **Flutter SDK** ≥3.2.0 (for app builds)
- **Python** ≥3.11 (for running backend tests locally)
- **Git**
- **Android phone** with camera (for QR pairing)

### Cubie Software Dependencies
```bash
sudo apt update && sudo apt install -y \
    python3 python3-venv python3-pip openssl \
    samba nfs-kernel-server avahi-daemon lsof udevadm \
    tesseract-ocr tesseract-ocr-eng tesseract-ocr-hin \
    poppler-utils minidlna
```

| Package | Purpose |
|---------|---------|
| `python3`, `python3-venv`, `python3-pip` | Backend runtime |
| `openssl` | TLS cert auto-generation |
| `samba`, `nfs-kernel-server` | File sharing services |
| `avahi-daemon` | mDNS discovery |
| `lsof`, `udevadm` | Unmount safety, USB hot-plug |
| `tesseract-ocr`, `tesseract-ocr-eng`, `tesseract-ocr-hin` | Document OCR (optional — degrades gracefully) |
| `poppler-utils` | PDF text extraction (`pdftotext`) |
| `minidlna` | Smart TV streaming (DLNA) |

---

## 2. Backend Deployment on Cubie

### 2a. First-Time Setup (Fresh Device)

Use the automated setup script:

```bash
ssh radxa@<cubie-ip>
cd /opt/cubie/AiHomeCloud
sudo bash scripts/first-boot-setup.sh
```

Or manually (see `kb/setup-instructions.md` for full steps):

```bash
# Clone repo
sudo mkdir -p /opt/cubie && sudo chown radxa:radxa /opt/cubie
cd /opt/cubie
git clone https://github.com/nerdyparas/AiHomeCloud.git
cd AiHomeCloud/backend

# Create venv and install deps
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Create directories
sudo mkdir -p /var/lib/cubie/tls /srv/nas/personal /srv/nas/shared
sudo chown -R radxa:radxa /var/lib/cubie /srv/nas

# Install systemd service
sudo cp cubie-backend.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable cubie-backend
sudo systemctl start cubie-backend
```

### 2b. Updating Existing Deployment

```bash
ssh radxa@<cubie-ip>
cd /opt/cubie/AiHomeCloud

# Pull latest code
git pull

# Install any new dependencies
cd backend
source venv/bin/activate
pip install -r requirements.txt

# Restart service
sudo systemctl restart cubie-backend

# Verify startup
sudo journalctl -u cubie-backend --no-pager -n 30
```

### 2c. Verify Backend is Running

```bash
# Health check
curl -sk https://localhost:8443/api/health
# Expected: {"status":"ok"}

# System info
curl -sk https://localhost:8443/api/v1/system/info | python3 -m json.tool
# Expected: boardModel, cpuTemp, memTotal, etc.

# Service status
sudo systemctl status cubie-backend
```

### 2d. Environment Variables

Set in `/etc/systemd/system/cubie-backend.service` under `[Service]`:

| Variable | Default | Description |
|----------|---------|-------------|
| `CUBIE_NAS_ROOT` | `/srv/nas` | NAS storage root |
| `CUBIE_DATA_DIR` | `/var/lib/cubie` | Persistent config/data |
| `CUBIE_TLS_ENABLED` | `true` | Enable HTTPS |
| `CUBIE_JWT_SECRET` | (auto-generated) | JWT signing key |
| `CUBIE_CORS_ORIGINS` | `http://localhost,http://localhost:3000` | Allowed CORS origins |
| `CUBIE_TELEGRAM_BOT_TOKEN` | (empty) | Telegram bot token |
| `CUBIE_TELEGRAM_ALLOWED_IDS` | (empty) | Comma-sep chat IDs |
| `CUBIE_ADGUARD_ENABLED` | `false` | Enable AdGuard proxy |
| `CUBIE_ADGUARD_PASSWORD` | (empty) | AdGuard admin password |

After changing env vars: `sudo systemctl daemon-reload && sudo systemctl restart cubie-backend`

### 2e. Optional: AdGuard Home

```bash
sudo bash scripts/install-adguard.sh
```

This installs AdGuard Home, configures DNS on port 5353, and sets up a systemd service. Point your router's DHCP DNS to the Cubie's LAN IP for whole-network ad blocking.

---

## 3. Flutter App Build

### Development (Debug)

```bash
cd /path/to/AiHomeCloud
flutter pub get
flutter run          # launches on connected device/emulator
```

### Release APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Install on phone:
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

Or copy the APK to the phone and install manually.

### Pre-Build Checks

```bash
flutter analyze          # must show 0 errors, 0 warnings
flutter test             # must pass all tests
```

---

## 4. Testing Methodology

### Test Pyramid

```
         ┌──────────┐
         │  Manual   │  ← Phase 10: hardware validation
         │  E2E      │     (QR pairing, full UI flow)
        ┌┴──────────┴┐
        │ Integration │  ← test_hardware_integration.py
        │   Tests     │     (runs on Cubie only)
       ┌┴────────────┴┐
       │  Unit Tests   │  ← pytest (backend), flutter test (frontend)
       │  (automated)  │     (runs on dev machine + CI)
       └──────────────┘
```

### Environments

| Environment | Backend Tests | Hardware Tests | App UI Tests |
|-------------|:---:|:---:|:---:|
| Windows (dev) | ✅ (238+ pass) | ❌ (skipped) | ✅ (emulator) |
| Cubie (ARM64) | ✅ (270+ pass) | ✅ (28+ pass) | ❌ |
| Android phone | ❌ | ❌ | ✅ (manual) |

### Testing Sequence

1. **Dev machine** — run unit tests after every code change
2. **Deploy to Cubie** — run full backend + hardware integration suite
3. **Build APK** — install on phone, run through full UI flow
4. **User acceptance** — non-developer family member tests basic flows

---

## 5. Backend Test Suite

### Running on Dev Machine (Windows)

```bash
cd backend
python -m pytest tests/ -q --ignore=tests/test_hardware_integration.py
# Expected: 238+ passed, 2 skipped, 0 failed
# (2 pre-existing Windows-only failures in test_subprocess_and_jobs.py are known)
```

### Running on Cubie (Hardware)

```bash
cd /opt/cubie/AiHomeCloud/backend
source venv/bin/activate
python -m pytest tests/ -q
# Expected: 270+ passed, ≤4 skipped, 0 failed
```

### Test Files Reference

| File | Tests | Coverage Area |
|------|-------|---------------|
| `test_auth.py` | ~21 | Login, JWT, refresh, token revocation, lockout |
| `test_endpoints.py` | ~40 | All API endpoints (system, family, services, etc.) |
| `test_file_routes.py` | ~14 | File upload, download, delete, blocked extensions |
| `test_path_safety.py` | ~8 | Path traversal prevention, sandbox enforcement |
| `test_storage.py` | ~12 | Mount/unmount, format protection, OS disk blocking |
| `test_store.py` | ~6 | JSON store read/write, cache invalidation |
| `test_trash.py` | ~9 | Soft delete, restore, permanent delete, quota cleanup |
| `test_file_sorter.py` | ~17 | InboxWatcher auto-sort, keyword detection, dedup |
| `test_document_index.py` | ~17 | FTS5 indexing, search, OCR extraction, scope |
| `test_telegram_bot.py` | ~20 | Bot commands, search, file send, auth checks |
| `test_board_and_config.py` | ~15 | Board detection, config validation, security audits |
| `test_config.py` | ~3 | Settings defaults, env var loading |
| `test_auto_ap.py` | ~18 | Auto-AP hotspot activation |
| `test_subprocess_and_jobs.py` | ~5 | Command execution, job tracking |
| `test_hardware_integration.py` | ~30 | End-to-end on real hardware (Cubie only) |

---

## 6. Hardware Validation Checklist

> Run through this entire checklist on the Cubie **before** handing the app to users.
> Maps to Phase 10 tasks in TASKSv2.md.

### 6a. Deployment Verification (P10-01)

- [ ] `git pull` on Cubie succeeds
- [ ] `pip install -r requirements.txt` succeeds
- [ ] `sudo systemctl restart cubie-backend` — no errors
- [ ] `journalctl -u cubie-backend --no-pager -n 50` — clean startup
- [ ] `curl -sk https://localhost:8443/api/v1/system/info` — valid JSON

### 6b. Test Suite (P10-02)

- [ ] `python -m pytest tests/ -q` — all pass (270+ pass, ≤4 skip, 0 fail)
- [ ] Hardware integration tests pass (28+ pass)
- [ ] Results logged in `logs.md`

### 6c. System Detection (P10-03)

- [ ] Board model: `"Radxa CUBIE A7A"` (not "unknown")
- [ ] CPU temp: valid reading (20–80°C)
- [ ] LAN interface: `eth0` detected
- [ ] Memory/disk stats: realistic values

### 6d. Storage Lifecycle (P10-04)

- [ ] `GET /storage/devices` — USB drive listed, NOT marked as OS
- [ ] `POST /storage/format` — USB drive formatted with ext4
- [ ] `POST /storage/mount` — mounts at `/srv/nas/`
- [ ] `GET /storage/stats` — correct capacity shown
- [ ] `POST /storage/unmount` — clean unmount
- [ ] `POST /storage/eject` — USB powered off
- [ ] Auto-remount after service restart works
- [ ] OS partitions (mmcblk0, mtdblock0, zram) blocked from format

### 6e. File Pipeline (P10-05)

- [ ] Upload `.jpg` → auto-sorts to `Photos/` within 30s
- [ ] Upload small `.jpg` (<800KB) named "aadhaar_card.jpg" → sorts to `Documents/`
- [ ] Upload `.pdf` → sorts to `Documents/` → indexed (if pdftotext installed)
- [ ] Upload `.mp4` → sorts to `Videos/`
- [ ] Search `q=aadhaar` → returns the document
- [ ] Download sorted file works
- [ ] Soft-delete → appears in trash listing
- [ ] Restore from trash → file at original path
- [ ] Permanent delete → file removed

### 6f. Service Toggles (P10-06)

- [ ] Samba ON → `systemctl is-active smbd` = `active`
- [ ] Samba OFF → `systemctl is-active smbd` = `inactive`
- [ ] SSH toggle works
- [ ] DLNA toggle works (if minidlna installed)
- [ ] AdGuard toggle works (if installed)
- [ ] States persist after restart

### 6g. Network (P10-07)

- [ ] Network status returns correct LAN IP, gateway, DNS
- [ ] Wi-Fi scan returns nearby networks
- [ ] Auto-AP activates when no network (if configured)

### 6h. App Full Flow (P10-08)

- [ ] Release APK built and installed on phone
- [ ] QR scan → pairing completes → JWT received
- [ ] Dashboard shows real system stats
- [ ] File browser shows sorted folders
- [ ] Upload from phone → auto-sorts
- [ ] Document search finds uploaded docs
- [ ] Family member creation works
- [ ] Member login with separate account works
- [ ] Admin-only features restricted for members
- [ ] App reconnects after Cubie restart

### 6i. Telegram Bot (P10-09)

- [ ] Bot token configured via API
- [ ] Bot comes online in Telegram
- [ ] `/start` → welcome message
- [ ] `/list` → recent documents
- [ ] Text search → finds documents
- [ ] Number reply → sends file
- [ ] Unauthorized user → rejection

### 6j. Stress Test (P10-10)

- [ ] 10 concurrent file-list requests < 2s, no deadlock
- [ ] 5 simultaneous uploads don't crash
- [ ] RAM stays under 500MB (`free -h`)
- [ ] CPU temp under 70°C under load
- [ ] WebSocket monitor stable for 5+ minutes

### 6k. Security Smoke Test (P10-11)

- [ ] Expired JWT → 401 (not 500)
- [ ] Wrong PIN → 401
- [ ] 10+ failed logins → 429 lockout
- [ ] Path traversal (`../../../etc/passwd`) → 403
- [ ] Blocked extension (`.sh`, `.py`) upload → 415
- [ ] Evil CORS origin not reflected
- [ ] TLS cert served on port 8443
- [ ] JWT secret file has mode 600
- [ ] No plaintext PINs in `users.json`

---

## 7. Troubleshooting

### Backend won't start

```bash
# Check logs
sudo journalctl -u cubie-backend -n 100 --no-pager

# Common issues:
# - Missing requirements → pip install -r requirements.txt
# - Port 8443 in use → sudo ss -tlnp | grep 8443
# - Permission denied on /var/lib/cubie → sudo chown -R radxa:radxa /var/lib/cubie
```

### Import errors after git pull

```bash
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart cubie-backend
```

### Tests fail with event loop errors

```bash
# Ignore hardware integration tests on Windows
python -m pytest tests/ -q --ignore=tests/test_hardware_integration.py
```

### USB drive not detected

```bash
# Check if device is visible
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,TRAN
# USB drives show tran=usb

# Trigger rescan
sudo udevadm trigger --subsystem-match=block
sudo udevadm settle
```

### TLS certificate issues

```bash
# Regenerate cert
rm /var/lib/cubie/tls/cert.pem /var/lib/cubie/tls/key.pem
sudo systemctl restart cubie-backend
# Backend auto-generates new cert on startup
```

### App can't connect to Cubie

1. Ensure phone is on the same Wi-Fi/LAN as the Cubie
2. Verify backend is running: `curl -sk https://<cubie-ip>:8443/api/health`
3. Check firewall: `sudo ufw status` — port 8443 must be open
4. Re-pair if cert changed (app stores cert fingerprint from initial pairing)

### InboxWatcher not sorting files

```bash
# Check watcher is running
journalctl -u cubie-backend | grep -i inbox

# Files must be 5+ seconds old before sorting (prevents mid-upload moves)
# Check file mtime: stat /srv/nas/personal/<user>/.inbox/<file>
```

### OCR not working

```bash
# Check if tesseract is installed
which tesseract
tesseract --version

# Install: sudo apt install tesseract-ocr tesseract-ocr-eng tesseract-ocr-hin
# OCR is optional — files still get indexed by filename without it
```

---

*AiHomeCloud — Deployment & Testing Instructions*
*Updated: 2026-03-10*
