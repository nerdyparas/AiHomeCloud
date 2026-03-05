# CubieCloud App Testing Guide

## Quick Start: Running the App

### Option 1: Run in Android Studio (Recommended)
```bash
# From project root:
flutter pub get
flutter run
```

Or use Android Studio UI:
1. Open `pubspec.yaml` in Android Studio
2. Click "Get Dependencies" when prompted
3. Click green play button (Run) in the top toolbar
4. Select your device (emulator or physical Android device)

### Option 2: Command Line
```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d emulator-5554
# or
flutter run -d your-physical-device
```

---

## Testing Checklist

### Phase 1: Onboarding Flow (First Launch)

**Expected Behavior:**
- [ ] Splash screen appears with CubieCloud logo (2s)
- [ ] Welcome screen shows with onboarding steps
- [ ] "Scan QR" button is clickable
- [ ] "Manual Setup" button is clickable

**Test Steps:**
1. **QR Code Scanning:**
   - Tap "Scan QR Code"
   - Grant camera permission when prompted
   - Camera opens (should see preview)
   - Try to scan a QR code (or tap X to go back)
   
2. **Manual Discovery:**
   - Tap "Manual Discovery"
   - Should show network scan interface
   - Should attempt to find devices on network
   - If device found: should show connection dialog

3. **Device Pairing:**
   - After device is discovered, should show fingerprint dialog
   - Tap "Trust Fingerprint" to accept
   - Should create session and proceed to main app

---

### Phase 2: Main App Navigation (After Onboarding)

**Bottom Navigation (5 Tabs):**
- [ ] Dashboard tab (home icon)
- [ ] My Folder tab (folder icon)
- [ ] Shared Folder tab (shared icon)
- [ ] Family tab (people icon)
- [ ] Settings tab (gear icon)

**Test Navigation:**
1. Tap each tab and verify screen loads
2. Verify bottom nav highlights current tab
3. Verify back button / navigation works correctly

---

### Phase 3: Dashboard Screen

**Expected Features:**
- [ ] Displays device name (should be "CubieCloud" or device IP)
- [ ] Shows system stats:
  - CPU usage percentage
  - Memory usage (GB / Total GB)
  - Temperature (if available)
- [ ] Storage status card
  - Total/Used/Available space
  - Progress bar showing used space
- [ ] Services status:
  - SMB (file sharing)
  - SSH (remote access)
  - HTTP (web interface)
- [ ] Refresh button to update stats

**Test Steps:**
1. Verify all stats display (may show 0 if backend not running)
2. Tap refresh button
3. Check that values update (or stay consistent)
4. Verify no crashes/errors appear

---

### Phase 4: File Management (My Folder)

**Expected Features:**
- [ ] Shows NAS root directory contents
- [ ] Displays files and folders
- [ ] Shows file icons, names, sizes, modified dates
- [ ] Can navigate into folders (tap folder to open)
- [ ] Breadcrumb navigation shows current path
- [ ] Back button goes to parent folder

**Test Steps:**
1. Tap "My Folder" tab
2. Verify file list loads
3. Tap a folder to navigate into it
4. Check breadcrumb shows path
5. Tap back button to return
6. Test root directory button (home icon) to return to NAS root

---

### Phase 5: Shared Folder

**Expected Features:**
- [ ] Similar to My Folder but shows shared directory
- [ ] May be empty if no shared folder configured

**Test Steps:**
1. Tap "Shared Folder" tab
2. Verify it loads without crashing
3. Observe content (may be empty)

---

### Phase 6: Family Management

**Expected Features:**
- [ ] Shows list of family users
- [ ] Add User button (+)
- [ ] User cards show:
  - User name
  - Admin badge (if admin)
  - Actions menu

**Test Steps:**
1. Tap "Family" tab
2. Verify user list loads
3. Tap "+" button to add user
4. Enter user name and PIN
5. Verify new user appears in list

---

### Phase 7: Settings Screen

**Expected Features:**
- [ ] Network section:
  - Device IP address
  - Network status
  - Connection type (Wi-Fi/Ethernet)
  
- [ ] System section:
  - OS info
  - Uptime
  - Temperature (if available)
  
- [ ] Services section:
  - Toggle services on/off
  - SMB, SSH, HTTP status
  
- [ ] Security section:
  - Server fingerprint display
  - Trust/Forget certificate button
  - Change PIN button
  
- [ ] About section:
  - App version
  - Build number

**Test Steps:**
1. Tap "Settings" tab
2. Scroll through each section
3. Verify values display correctly
4. Tap "Change PIN" and test PIN update
5. Tap "Trust Fingerprint" (if needed)
6. Check all toggles work

---

## Error Handling Tests

### Test Network Errors
1. **Disconnect from network:**
   - Turn off Wi-Fi or unplug ethernet
   - Try to refresh dashboard
   - Should show "No connection" or timeout error

2. **Invalid server:**
   - Go to Settings → Debug (if available)
   - Change server IP to invalid address
   - Try to refresh
   - Should show connection error gracefully

### Test Auth Errors
1. **Wrong PIN:**
   - If prompted for PIN
   - Enter incorrect PIN
   - Should show error and ask again

2. **Session timeout:**
   - Leave app idle for ~30 minutes
   - Try to access protected endpoint
   - Should prompt to log in again

---

## Performance Tests

- [ ] App starts in < 2 seconds
- [ ] Dashboard loads in < 1 second
- [ ] File list loads smoothly (no janky animations)
- [ ] Navigation between tabs is smooth
- [ ] No memory leaks (check RAM usage in system settings)
- [ ] No excessive battery drain

---

## Visual Tests

- [ ] Dark theme is applied throughout
- [ ] Colors match design system:
  - Primary: Warm amber (#E8A84C)
  - Secondary: Blue (#4C9BE8)
  - Error: Red (#E85C5C)
  - Success: Green (#4CE88A)
  
- [ ] Typography looks good:
  - Headings: Sora font
  - Body: DM Sans font
  
- [ ] Layout is responsive:
  - Works on small phones (360px)
  - Works on large phones (600px+)
  - No UI cutoff or overlapping text

---

## Troubleshooting

### If app won't start:
```bash
flutter clean
flutter pub get
flutter run -v  # verbose mode to see errors
```

### If app crashes on startup:
1. Check console for stack trace
2. Look for "Exception" or "Error" messages
3. Check if backend server is running (if testing with real backend)

### If UI looks wrong:
1. Hot reload: `r` (in terminal) or click reload button
2. Hot restart: `R` in terminal
3. Full rebuild: `flutter run --no-fast-start`

### If device not found:
1. Ensure device is on same network as development machine
2. Check IP address in Settings → Network
3. Try manual IP entry instead of QR code
4. Check firewall isn't blocking port 8443

---

## Debug Features

**Enable verbose logging:**
```bash
flutter run -v
```

**Take screenshot:**
- Press `s` while app is running in terminal

**Open DevTools:**
```bash
flutter pub global activate devtools
devtools
# Then open http://localhost:9100 and connect app
```

---

## Test Results Checklist

After testing, mark results:
- ✅ Passed (works as expected)
- ⚠️ Warning (works but with minor issues)
- ❌ Failed (doesn't work)

**Summary:**
- [ ] Onboarding flow
- [ ] Navigation
- [ ] Dashboard
- [ ] File management
- [ ] Family management
- [ ] Settings
- [ ] Error handling
- [ ] Performance
- [ ] Visual design

---

## Known Limitations

1. **Backend Required:** Many features require the CubieCloud backend running on device
2. **Network Required:** App must be on same network as device (or VPN access configured)
3. **Test Data:** File lists and stats will be empty until backend is running
4. **No Offline Mode:** App requires network connection to device

---

## Notes for Testing

- **Device IP:** Look in Settings → Network section
- **Server Port:** Default is 8443 (HTTPS)
- **Test Device:** Works with any Android 5.0+ device or emulator
- **Real Backend:** For full testing, run backend on Cubie hardware or mock server
