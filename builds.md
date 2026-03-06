# CubieCloud App Build Log

> Track every APK build with version, commit, and what changed.
> Update this file **every time** a new APK is built.

---

## Build History

| # | Date | App Version | Build | Commit | Firmware Compat | Notes |
|---|------|-------------|-------|--------|-----------------|-------|
| 1 | 2026-03-06 | 1.0.0+1 | release | `7467985` | 2.1.4 | Last known APK build (audit v2 fixes). Dashboard had system stats + network speed but **silent error hiding** — if WebSocket failed, sections disappeared with no message. No network connectivity status (WiFi/LAN/BT) shown. |

---

## How to Build

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# Output location
# android/app/build/outputs/flutter-apk/app-release.apk
```

## After Building

1. Update this table with: date, version from `pubspec.yaml`, commit hash (`git rev-parse --short HEAD`), and brief notes
2. Bump `version` in `pubspec.yaml` if needed (format: `major.minor.patch+buildNumber`)
3. Note which firmware version the build was tested against

---

## Version Scheme

- **App version**: `pubspec.yaml` → `version: X.Y.Z+buildNumber`
- **Firmware version**: Backend version reported by `/api/v1/system/info` → `firmwareVersion`
- These are independent — app version tracks the Flutter client, firmware tracks the backend
