# CubieCloud App - Ready to Test

## ✅ Current Status

- ✅ All dependencies installed
- ✅ Flutter/Dart compilation working  
- ✅ Code linting passed
- ✅ Critical bugs fixed
- ✅ App ready to run

---

## 🚀 Quick Start (3 Minutes)

1. **Open Android Studio**
2. **File → Open** → select: `c:\Dropbox\AiHomeCloud`
3. **Click GREEN PLAY BUTTON** (▶) in toolbar
4. **Select your device** (emulator or physical)
5. **Wait 1-2 minutes** for first build
6. **App launches!** 🎉

---

## 📚 Documentation Created

### 1. QUICK_START.md
- 3-minute setup guide
- What to expect on first launch
- Dev mode explanation (auto-connects to 192.168.0.212)

### 2. TESTING_GUIDE.md
- Complete testing checklist for all features
- 7-phase testing (Onboarding → Navigation → Dashboard → Files → Shared → Family → Settings)
- Error handling & performance tests
- Known limitations & troubleshooting

### 3. ANDROID_STUDIO_RUN_GUIDE.md
- Step-by-step guide to run in Android Studio
- Debugging tips & keyboard shortcuts
- 5 troubleshooting scenarios
- DevTools and Logcat setup

### 4. run_app.sh
- Bash script to automate: clean → pub get → device list → run

---

## ✨ Features to Test

| Dashboard | File Browser | User Management | Settings |
|-----------|--------------|-----------------|----------|
| Device info | Browse NAS root | Add user | Network |
| CPU usage | Navigate folders | Remove user | System |
| Memory usage | File details | User roles | Services |
| Temperature | File operations | Admin privileges | Security |
| Storage usage | | | About |
| Service status | | | |

---

## 🎯 Dev Mode (Enabled by Default)

When you run the app:
- **Automatically skips onboarding**
- **Auto-connects to:** `192.168.0.212:8443` (Cubie backend)
- **Auto-logs in as:** `paras` (admin user)
- **Goes straight to:** Dashboard

### To Change Backend IP:
1. Edit: `lib/main.dart` line ~51
2. Change: `const cubieIp = '192.168.0.212';`
3. Hot reload: press `r` while app is running

---

## ⌨️ Keyboard Shortcuts (While App Running)

| Key | Action |
|-----|--------|
| `r` | Hot reload (quick code update) |
| `R` | Hot restart (full rebuild) |
| `d` | Detach / stop debugging |
| `q` | Quit |
| `s` | Take screenshot |
| `h` | Help |
| `w` | Show widget inspector |

---

## 🐛 Debugging

### View Logs:
- **Android Studio:** View → Tool Windows → Logcat (Alt+6)
- **Terminal:** `flutter logs`

### See Errors:
- Search Logcat for red text / "Exception" / "Error"
- Look for "[DEV]" messages for app-specific logging

### Troubleshoot:
- **App won't start?** → `flutter clean && flutter pub get && flutter run -v`
- **Device not found?** → `flutter devices`
- **UI looks wrong?** → Press `r` to hot reload, `R` to hot restart

---

## 📊 Recent Fixes (Latest Session)

### ✅ Fixed 63 Critical Flutter Analyze Errors
- `Color.withValues()` → `Color.withOpacity()`
- `CardThemeData` → `CardTheme`
- `DialogThemeData` → `DialogTheme`
- Removed unused crypto import

### ✅ Fixed Backend Test Authentication (47 tests)
- Created `authenticated_client` fixture
- Fixed admin token PIN limits (bcrypt 72-byte limit)
- Proper JWT Bearer headers

### ✅ Fixed intl Version Conflicts
- Updated to `intl ^0.20.2` (matches Flutter SDK)
- Fixed pub gate in CI pipeline

### ✅ Fixed Critical Dart Compilation Errors
- Color references (withValues → withOpacity)
- Type mismatches (String | Color issues)
- Deprecated API usage

---

## 📝 Testing Workflow

1. **Launch app** (see QUICK_START.md)
2. **Verify splash screen & dashboard load**
3. **Test each tab** (see TESTING_GUIDE.md for detailed checks)
4. **Check error handling** (disconnect network, invalid server, auth errors)
5. **Verify performance** (smooth navigation, no lag)
6. **Check visual design** (colors, fonts, spacing match theme)

### For Detailed Checklist:
See **TESTING_GUIDE.md** for complete 7-phase testing with expected behaviors

---

## 🔗 Resources

- **Flutter:** https://flutter.dev/docs
- **Dart:** https://dart.dev
- **Riverpod:** https://riverpod.dev
- **GoRouter:** https://pub.dev/packages/go_router
- **Android Studio:** https://developer.android.com/studio

---

## Next Steps

1. Open Android Studio
2. Click the green play button ▶
3. Select your device
4. Wait for the build to complete
5. Follow TESTING_GUIDE.md for comprehensive testing

**Ready to test? Click play button! 🚀**
