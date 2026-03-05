# Quick Start Guide - Run CubieCloud App

## TL;DR - 3 Minutes to Running App

```bash
# 1. Open Terminal in your project directory
cd c:\Dropbox\AiHomeCloud

# 2. Get dependencies
flutter pub get

# 3. Run the app
flutter run

# 4. Select your device when prompted
# App launches in 1-2 minutes
```

## Running in Android Studio (Recommended)

1. **Open Project:** File → Open → select `c:\Dropbox\AiHomeCloud`
2. **Click Play Button (▶)** in top toolbar
3. **Select Device** from dropdown
4. **Wait** for build (1-2 minutes first time)
5. **App launches!** 🎉

## What to Expect

### Dev Mode (Enabled by Default)
- App **auto-connects** to `192.168.0.212:8443` (Cubie backend)
- **Auto-login** as user "paras" (admin)
- Skips onboarding, goes straight to dashboard
- Edit `lib/main.dart` to disable or change IP

### First Launch
1. **Splash screen** (2 seconds)
2. **Dashboard loads** (shows device stats if backend running)
3. **5 bottom nav tabs:**
   - Dashboard (home)
   - My Folder (file browser)
   - Shared Folder
   - Family (user management)
   - Settings

## Testing All Functions

See **TESTING_GUIDE.md** for complete checklist including:
- ✅ Onboarding flow
- ✅ Navigation between tabs
- ✅ Dashboard stats
- ✅ File management
- ✅ User management
- ✅ Settings
- ✅ Error handling
- ✅ Performance

## Keyboard Shortcuts (While Running)

| Key | Action |
|-----|--------|
| `r` | Hot reload (quick update) |
| `R` | Hot restart (full rebuild) |
| `d` | Detach / stop |
| `q` | Quit |
| `s` | Screenshot |

## Debugging

### View App Logs
- **Android Studio:** View → Tool Windows → Logcat (Alt+6)
- **Terminal:** `flutter logs`

### Common Issues

**App won't start?**
```bash
flutter clean
flutter pub get
flutter run -v  # verbose to see errors
```

**Device not found?**
```bash
flutter devices
# Make sure device is listed
adb kill-server
adb start-server
```

**UI looks wrong?**
- Press `r` to hot reload
- Press `R` to hot restart
- Close and run again

## Project Structure

```
lib/
├── main.dart              # App entry, dev mode shortcut
├── navigation/            # Routes, bottom nav
├── screens/               # UI screens
│   ├── main/             # Dashboard, files, family, settings
│   └── onboarding/       # Splash, welcome, discovery
├── widgets/              # Reusable components
├── services/             # API, auth, discovery
├── providers.dart        # State management (Riverpod)
├── models/models.dart    # Data classes
└── core/                 # Theme, constants, utils
```

## Features Overview

### 🏠 Dashboard
- Device name and stats
- CPU, memory, temperature
- Storage usage
- Service status (SMB, SSH, HTTP)

### 📁 File Browser (My Folder)
- Browse NAS root directory
- Navigate folders
- View file details
- (Upload/download when backend ready)

### 👥 Family Management
- Add/remove users
- User settings
- Admin privileges

### ⚙️ Settings
- Network info (IP, port)
- System info
- Change PIN
- Certificate management

## Development

**Tech Stack:**
- **Framework:** Flutter 3.19
- **Language:** Dart
- **State:** Riverpod
- **Routing:** GoRouter
- **Backend:** FastAPI (Python)
- **Auth:** JWT

**Dark Theme:**
- Primary: Warm amber (#E8A84C)
- Secondary: Blue (#4C9BE8)
- Error: Red (#E85C5C)
- Success: Green (#4CE88A)

## Backend (For Full Testing)

To test all features, you need the backend running:

1. **Check if backend is running:**
   - Open Settings in app
   - Should show IP/port/status
   - If empty, backend not connected

2. **Start backend** (on Cubie hardware or dev machine):
   ```bash
   cd backend
   python -m pip install -r requirements.txt
   python app/main.py
   # Backend runs on http://localhost:8443
   ```

3. **Update dev IP** if needed:
   - Edit `lib/main.dart`
   - Change `const cubieIp = '192.168.0.212';` to your IP
   - Press `r` to reload

## Full Documentation

- **Testing:** See `TESTING_GUIDE.md`
- **Android Studio:** See `ANDROID_STUDIO_RUN_GUIDE.md`
- **Architecture:** See `kb/engineering-blueprint.md`
- **API:** See `kb/api-contracts.md`
- **Tasks:** See `tasks.md`
- **CI/CD:** See `gitfixes.md`

## Support

- **Flutter:** https://flutter.dev/docs
- **Dart:** https://dart.dev
- **Riverpod:** https://riverpod.dev
- **GoRouter:** https://pub.dev/packages/go_router

---

**Ready to test?** → Open Android Studio and click the green play button! 🚀
