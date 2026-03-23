# AiHomeCloud

Your family's private cloud. One device, one price, no subscriptions.

[![Backend Tests](https://github.com/nerdyparas/AiHomeCloud/actions/workflows/backend-tests.yml/badge.svg)](https://github.com/nerdyparas/AiHomeCloud/actions/workflows/backend-tests.yml)
[![Flutter Analyze](https://github.com/nerdyparas/AiHomeCloud/actions/workflows/flutter-analyze.yml/badge.svg)](https://github.com/nerdyparas/AiHomeCloud/actions/workflows/flutter-analyze.yml)

---

## What is AiHomeCloud?

AiHomeCloud is a personal home NAS appliance that gives Indian families a private, self-hosted cloud — no monthly fees, no third-party accounts. Plug in a USB/NVMe drive, pair with the mobile app, and your family's files are organized, backed up, and accessible from anywhere.

## Hardware

- **Radxa Cubie A5E / A7Z** — ARM Cortex-A55 SoC, 2–8 GB RAM
- microSD for OS, external USB/NVMe for storage
- Ethernet + Wi-Fi + Bluetooth LE (for initial pairing)

## Project Structure

| Component | Path | Stack |
|---|---|---|
| Mobile app | `lib/` | Flutter, Dart, Riverpod, GoRouter |
| Backend | `backend/` | Python, FastAPI, Pydantic v2 |
| CI | `.github/workflows/` | GitHub Actions |

## First-Time Setup

Once your device is powered on and connected to your network:

```bash
sudo bash scripts/setup-wizard.sh
```

The interactive wizard walks you through naming your device, creating an admin PIN, and optionally setting up a storage drive — all in about 3 minutes.

For manual / headless setup, see [`kb/setup-instructions.md`](kb/setup-instructions.md).

## Development

### Backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m app.main
```

### Backend Tests

```bash
cd backend
python -m pytest tests/ -q
```

### Flutter App

```bash
flutter pub get
flutter build apk
```

### Flutter Tests

```bash
flutter analyze
flutter test
```

## Screenshots

<!-- TODO: Add screenshots -->

## License

Proprietary — all rights reserved.
