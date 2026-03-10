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

## Getting Started

### Backend

```bash
cd backend
python -m pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8443 --ssl-keyfile certs/key.pem --ssl-certfile certs/cert.pem
```

### Run Backend Tests

```bash
cd backend
pytest -q tests --ignore=tests/test_hardware_integration.py
```

### Flutter App

```bash
flutter pub get
flutter build apk
```

### Run Flutter Tests

```bash
flutter analyze
flutter test
```

## Screenshots

<!-- TODO: Add screenshots -->

## License

Proprietary — all rights reserved.
