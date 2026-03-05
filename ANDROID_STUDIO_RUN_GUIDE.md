# Running CubieCloud in Android Studio - Step by Step

## Prerequisites

✅ **Installed:**
- Flutter SDK
- Android SDK / Android Studio
- Android device or emulator running Android 5.0+
- Network connection to backend (if testing with real device)

---

## Step 1: Open Project in Android Studio

### Option A: From Android Studio
1. Click **File → Open**
2. Navigate to `c:\Dropbox\AiHomeCloud`
3. Click **OK**
4. Wait for Android Studio to index the project (~30 seconds)

### Option B: From Command Line
```bash
cd c:\Dropbox\AiHomeCloud
android-studio .
```

---

## Step 2: Verify Environment

1. **Check Flutter is recognized:**
   - Go to **Tools → Flutter → Flutter Doctor**
   - Look for ✓ (checkmark) next to all items
   - If any ✗, run `flutter doctor -v` in terminal for details

2. **Check Device is Connected:**
   - Go to **Tools → AVD Manager** to start Android emulator, OR
   - Connect physical Android phone via USB
   - Click **View → Tool Windows → Logcat** to see device logs

3. **Check Device shows in Flutter:**
   - Open **Terminal** (in Android Studio bottom panel)
   - Run: `flutter devices`
   - Should show emulator or physical device

---

## Step 3: Prepare the App

1. **Get Dependencies:**
   - Terminal → `flutter pub get`
   - Wait for completion (usually 30-60 seconds)

2. **Clean Build (First Time Only):**
   - Terminal → `flutter clean`
   - Terminal → `flutter pub get` (again)

---

## Step 4: Run the App

### Using Android Studio UI (Easiest)

1. **Select Target Device:**
   - Look at top toolbar
   - Click device dropdown (shows "emulator-5554" or device name)
   - Select your device

2. **Run the App:**
   - Click green **▶ (Play)** button in toolbar
   - Or press **Shift + F10**
   - Watch build progress in bottom panel

3. **Wait for Build:**
   - First run takes 1-2 minutes
   - Watch for: `Built and installed app on device` message
   - App should automatically launch

### Using Terminal (Alternative)

```bash
# List devices
flutter devices

# Run on device
flutter run

# Run with verbose output (useful for debugging)
flutter run -v
```

---

## Step 5: Interact with the Running App

### Hot Reload (Fast Code Changes)
- **In Android Studio:** Click reload icon (⟲) in toolbar
- **In Terminal:** Press `r`
- Changes reload in ~1 second (keeps app state)

### Hot Restart (Full Recompile)
- **In Terminal:** Press `R`
- Fully restarts app (loses state, takes ~5 seconds)

### Stop the App
- **In Terminal:** Press `q`
- Or: Click red square **⏹** button in toolbar

### Detach from Debugger
- **In Terminal:** Press `d`
- App keeps running but no debug connection

---

## Step 6: View Device Logs

### In Android Studio
1. **View → Tool Windows → Logcat** (or press `Alt + 6`)
2. Shows all app output in real-time
3. Filter by app name or search for errors
4. Look for `[DEV]` messages for app-specific logging

### In Terminal
```bash
flutter logs
```

---

## Step 7: Testing Workflow

### First Test: Verify App Launches
1. **Run app**
2. **Expected:** 
   - Splash screen for 2 seconds
   - Then main app loads
   - Dashboard or onboarding appears

### If Using Dev Mode (Recommended for Testing)
- **App auto-connects to:**
  - IP: `192.168.0.212` (Cubie backend)
  - Port: `8443`
  - User: `paras`
  - Admin: `true`

- **To modify dev settings:**
  - Edit `lib/main.dart`
  - Change `const cubieIp = '192.168.0.212';` to your Cubie IP
  - Hot reload (press `r`)

### Second Test: Navigate the UI
1. Check bottom navigation tabs load
2. Check each screen renders correctly
3. Use **View → Inspect Layout Bounds** to debug UI issues

### Third Test: User Interactions
1. Try all buttons
2. Try navigation
3. Look for crashes in Logcat

---

## Debugging Tips

### Find a Crash
1. Look in **Logcat** (Ctrl+Alt+L)
2. Search for "Exception" or "Error"
3. Look for red text lines
4. Copy stack trace and search online

### Debug Layout Issues
1. **View → Inspect Layout Bounds** in Android Studio
2. Click on widget to see its dimensions
3. Use **View → Show System Properties** for device info

### Check Device Connection
```bash
adb devices
adb shell getprop ro.product.model
```

### View App Preferences (SharedPreferences)
```bash
adb shell "run-as com.example.cubie_cloud cat /data/data/com.example.cubie_cloud/shared_prefs/FlutterSharedPreferences.xml"
```

---

## Testing Checklist

### Onboarding (If dev mode disabled)
- [ ] Splash screen appears
- [ ] Welcome screen shows
- [ ] QR scan button works (opens camera)
- [ ] Manual discovery button works
- [ ] Device pairing succeeds
- [ ] Main app loads after pairing

### Main App
- [ ] All 5 bottom nav tabs clickable
- [ ] Dashboard tab shows stats (or placeholder)
- [ ] My Folder tab shows file list (or empty)
- [ ] Shared Folder tab loads
- [ ] Family tab shows users
- [ ] Settings tab shows device info

### Error Handling
- [ ] Disconnect network → app shows error gracefully
- [ ] Invalid IP → connection error message
- [ ] No crash with invalid input

### Performance
- [ ] App launches in < 3 seconds
- [ ] Navigation between tabs is smooth
- [ ] File list scrolls smoothly
- [ ] No memory leaks (check RAM in device settings)

---

## Troubleshooting

### "Device not found"
```bash
flutter devices
# Should list your device
# If not, run:
adb kill-server
adb start-server
flutter devices
```

### "Build fails"
```bash
flutter clean
flutter pub get
flutter run -v  # Shows detailed error
```

### "App crashes on startup"
1. Check **Logcat** for exception
2. Look for "Error:", "Exception:", or red text
3. Check if backend is running (if testing with real device)

### "UI looks wrong"
1. Hot reload: Press `r`
2. Hot restart: Press `R`
3. Full clean build: `flutter clean && flutter pub get && flutter run`

### "Emulator won't start"
1. **AVD Manager** → Select emulator → **Play** button
2. Wait 30-60 seconds for emulator to boot
3. Then `flutter run`

---

## Testing Without Backend

The app **can run without backend**, but features will be limited:

- ✅ **Works:** UI, navigation, local settings
- ❌ **Won't work:** File listing, device stats, user management

To test with placeholder data:
1. Edit `lib/providers.dart`
2. Mock the API responses
3. Or: Run real backend on device (see deployment docs)

---

## Keyboard Shortcuts (While App Running)

| Key | Action |
|-----|--------|
| `r` | Hot reload (quick code update) |
| `R` | Hot restart (full rebuild) |
| `h` | Show help |
| `d` | Detach (stop debugging) |
| `q` | Quit |
| `s` | Screenshot |
| `w` | Show widget tree inspector |

---

## Android Studio Tips

### Pin Logcat
1. Open **Logcat** (Ctrl+Alt+L)
2. Click **Pin Tab** (pushpin icon)
3. Shows all app output in separate window

### Set Breakpoints
1. Click line number in code editor
2. Red circle appears
3. Run app, execution pauses at breakpoint
4. Inspect variables in **Variables** panel

### Use Flutter Inspector
1. **View → Tool Windows → Flutter Inspector** (Alt+Shift+9)
2. Shows widget hierarchy
3. Click widgets to highlight in app

---

## Next Steps After Testing

1. **Document Issues:** Note any crashes or UI problems
2. **Update Backend:** If testing with real device, ensure backend is running
3. **Test Full Features:** Once backend ready, test file operations, user management
4. **Performance Profile:** Use **Dart DevTools** for profiling
   ```bash
   flutter pub global activate devtools
   devtools
   # Open http://localhost:9100
   ```

---

## Need Help?

- **Flutter Docs:** https://flutter.dev/docs
- **Android Docs:** https://developer.android.com/docs
- **Dart Docs:** https://dart.dev/guides
- **Check app logs:** Most errors show in Logcat with clear messages

Good luck testing! 🚀
