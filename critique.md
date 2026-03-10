# AiHomeCloud — Full Project Audit & Critique

> **Comprehensive audit of the entire codebase.** Covers backend bugs, Flutter bugs, and non-technical user UX critique.
> Each finding references exact files and line numbers so another LLM can fix it by reading only those files.
> Severity: 🔴 CRITICAL · 🟠 HIGH · 🟡 MEDIUM · 🟢 LOW
> Last updated: 2025-03-10

---

## Table of Contents

1. [Backend Code Audit](#1-backend-code-audit)
2. [Flutter Code Audit](#2-flutter-code-audit)
3. [UX Critique (Non-Technical User Perspective)](#3-ux-critique-non-technical-user-perspective)
4. [Suggestions](#4-suggestions)

---

## 1. Backend Code Audit

### BUG-B01 — 🔴 CRITICAL: Pairing OTP Flow — Plaintext OTP Never Returned to Caller

**File:** `backend/app/routes/auth_routes.py` lines 35–49

**Problem:** The `/pair/qr` endpoint generates a 6-digit OTP, hashes it with SHA-256, and stores the hash — but the **plaintext OTP is never returned** in the response. The device console or admin UI has no way to display the OTP to the user for manual entry. The QR payload doesn't include it either.

**Code:**
```python
otp = f"{secrets.randbelow(10**6):06d}"
otp_hash = hashlib.sha256(otp.encode()).hexdigest()
await store.save_otp(otp_hash, expires_at)
# ... response does NOT contain `otp`
return {"qrValue": qr_value, "serial": serial, "ip": ip, "host": host, "expiresAt": expires_at}
```

**Impact:** Users cannot complete pairing if QR scanning fails (e.g. broken camera).

**Fix:** Add `"otp": otp` to the JSON response for display on the Cubie's console/web UI.

---

### BUG-B02 — 🟠 HIGH: Branding "CubieCloud"/"Cubie" in Backend User-Facing Strings (11+ instances)

**Files & Lines:**
| File | Line | String | Context |
|---|---|---|---|
| `backend/app/config.py` | 42 | `"My CubieCloud"` | Default device_name |
| `backend/app/config.py` | 45 | `"CubieCloud"` | Default hotspot_ssid |
| `backend/app/models.py` | 128 | `"CubieNAS"` | Default ext4 label for format |
| `backend/app/main.py` | 83 | `"CubieCloud backend starting..."` | Startup log message |
| `backend/app/main.py` | 176–177 | `"CubieCloud API"` / `"Backend API for the CubieCloud home NAS"` | OpenAPI title & description |
| `backend/app/tls.py` | (cert generation) | `"CubieCloud"` | TLS certificate organization name |
| `backend/app/auto_ap.py` | (docstrings) | `"CubieCloud"` | Module documentation |

**Impact:** Brand inconsistency — project was renamed to "AiHomeCloud" but backend still says "CubieCloud" in many places.

**Fix:** Replace all instances with "AiHomeCloud". For `hotspot_ssid`, use `"AiHomeCloud"`. For log messages, use `"AiHomeCloud backend"`.

---

### BUG-B03 — 🟡 MEDIUM: Overly Permissive `except Exception` in main.py Lifespan (8+ catches)

**File:** `backend/app/main.py` lines 85–130

**Problem:** The lifespan startup function wraps 8+ initialization blocks in bare `except Exception` handlers that log the error and continue. This masks critical failures (e.g. database corruption, permission denied, missing config) and lets the app start in a silently degraded state.

**Locations:** Lines 88-89, 94-95, 101-102, 106-107, 111-112, 116-117, 123-124, 129-130.

**Impact:** A critical error (e.g. FTS5 database corruption) is logged but the app keeps running with broken search. Operators won't notice until a user reports it.

**Fix:** Replace `except Exception` with specific exception types (`OSError`, `FileNotFoundError`, `asyncio.TimeoutError`, etc.) for each block. Let unexpected errors propagate and fail the health check.

---

### BUG-B04 — 🟡 MEDIUM: `_safe_resolve()` Uses `startswith()` for Path Validation

**File:** `backend/app/routes/file_routes.py` lines 36–62

**Problem:** Path sandboxing uses `str(resolved).startswith(str(nas_resolved) + os.sep)` which is a string prefix check. If `nas_root` is `/srv/nas`, a request for `/srv/nasty/secret` would pass the check because `"/srv/nasty"` starts with `"/srv/nas"`.

**Code (line 60-61):**
```python
if resolved != nas_resolved and not str(resolved).startswith(str(nas_resolved) + os.sep):
    raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")
```

**Impact:** Potential path traversal if there are directories at the same level with similar prefixes.

**Fix:** Use `Path.relative_to()` with a try/except `ValueError` instead:
```python
try:
    resolved.relative_to(nas_resolved)
except ValueError:
    raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")
```

---

### BUG-B05 — 🟡 MEDIUM: QR URL Parameters Not URL-Encoded

**File:** `backend/app/routes/auth_routes.py` lines 41–47

**Problem:** The QR value string is built by string concatenation without URL-encoding the parameters. If `host` or `serial` contains special characters (`&`, `=`, spaces), the QR payload will be malformed.

**Code:**
```python
qr_value = (
    f"cubie://pair"
    f"?serial={serial}"
    f"&key={key}"
    f"&host={host}"
    f"&expiresAt={expires_at}"
)
```

**Fix:** Use `urllib.parse.urlencode()` or `urllib.parse.quote()` for parameter values.

---

### BUG-B06 — 🟡 MEDIUM: TLS Certificate Organization Name Still "CubieCloud"

**File:** `backend/app/tls.py` (cert generation function)

**Problem:** Self-signed TLS cert has `O=CubieCloud` in the subject. Not user-visible normally, but shows in browser warnings and cert inspection.

**Fix:** Change organization to `"AiHomeCloud"`.

---

### BUG-B07 — 🟡 MEDIUM: Store Token Write Outside Lock — Potential Race Condition

**File:** `backend/app/store.py`

**Problem:** The token cache write happens outside the asyncio.Lock guard, meaning two concurrent token operations could cause a race condition on the JSON file write.

**Fix:** Move the token cache write inside the lock context manager.

---

### BUG-B08 — 🟡 MEDIUM: Legacy Plaintext PIN Support Still Active With No Expiry

**File:** `backend/app/routes/auth_routes.py`

**Problem:** The login flow still supports plaintext PIN comparison as a fallback (checking if PIN doesn't start with `$2b$`). While the migration in P1-05 hashes all existing PINs, the fallback code path remains, meaning any new bug that stores a plaintext PIN would be silently accepted.

**Fix:** Remove the plaintext fallback. All PINs should be bcrypt-hashed after migration. If a non-bcrypt PIN is encountered at login, reject it and log a warning.

---

### BUG-B09 — 🟢 LOW: Inefficient `_folder_size_gb_sync()` for Large Directories

**File:** `backend/app/routes/storage_routes.py`

**Problem:** `_folder_size_gb_sync()` walks the entire NAS directory tree synchronously via `run_in_executor`. On a NAS with thousands of files, this blocks a thread pool worker for seconds.

**Fix:** Use `shutil.disk_usage()` for partition-level size (instant), or cache the result with a TTL.

---

### BUG-B10 — 🟢 LOW: Hardcoded `/var/lib/cubie/` Paths in Some Files

**Files:** Various backend files

**Problem:** Some files reference `/var/lib/cubie/` directly instead of using `settings.data_dir`. If the config changes, these paths won't follow.

**Fix:** Use `settings.data_dir` from config everywhere.

---

### BUG-B11 — 🟢 LOW: Missing Type Hints in EventBus

**File:** `backend/app/events.py` (if it exists) or event-related code

**Problem:** Event bus callback types are `Any`, making it harder for IDEs and LLMs to understand the code.

**Fix:** Add typed callback signatures.

---

### BUG-B12 — 🟢 LOW: WebSocket Monitor Missing `asyncio.CancelledError` Catch

**File:** `backend/app/routes/monitor_routes.py`

**Problem:** The WebSocket monitor loop catches `WebSocketDisconnect` but not `asyncio.CancelledError`, which can occur when the server shuts down while a client is connected. This causes noisy tracebacks in logs.

**Fix:** Add `except asyncio.CancelledError: break` to the WebSocket loop.

---

### BUG-B13 — 🟢 LOW: Config Defaults Still Have "Cubie" Branding

**File:** `backend/app/config.py`

**Problem:** Several default config values still reference "Cubie" brand (covered in BUG-B02 but noting separately for the config file).

**Fix:** Update all defaults to "AiHomeCloud" equivalents.

---

### BUG-B14 — 🟢 LOW: Unused Imports in store.py

**File:** `backend/app/store.py`

**Problem:** Some imports are unused (visible in linting output).

**Fix:** Remove unused imports.

---

## 2. Flutter Code Audit

### BUG-F01 — 🔴 CRITICAL: `qr_scan_screen.dart` Back Button Navigates to `/welcome` (Removed Route — CRASH)

**File:** `lib/screens/onboarding/qr_scan_screen.dart` line 149

**Problem:** The back button's `onPressed` calls `context.go('/welcome')`, but the `/welcome` route was removed from `app_router.dart` during the onboarding merge. Pressing the back button on the QR scan screen will crash the app or show a blank page.

**Code:**
```dart
leading: IconButton(
  icon: const Icon(Icons.arrow_back_rounded),
  onPressed: () => context.go('/welcome'),
),
```

**Fix:** Change to `context.go('/')` (splash screen) or `context.go('/scan-network')`.

---

### BUG-F02 — 🔴 CRITICAL: `network_scanner.dart` Checks `json['service'] == 'CubieCloud'`

**File:** `lib/services/network_scanner.dart` line 136

**Problem:** The network scanner checks for a hardcoded service name `'CubieCloud'`. If the backend returns `'AiHomeCloud'` (or any other value), devices will not be recognized during discovery.

**Code:**
```dart
if (json['service'] == 'CubieCloud') {
  deviceName = json['deviceName'] as String?;
  serial = json['serial'] as String?;
}
```

**Fix:** Update to match the actual backend service identifier, or accept both `'CubieCloud'` and `'AiHomeCloud'`.

---

### BUG-F03 — 🟠 HIGH: Raw `e.toString()` Instead of `friendlyError(e)` — 5 Locations

All of these show raw exception text to users instead of user-friendly messages.

| # | File | Line | Code |
|---|---|---|---|
| 1 | `lib/widgets/folder_view.dart` | 77 | `_error = e.toString();` |
| 2 | `lib/screens/main/storage_explorer_screen.dart` | 58 | `_error = e.toString();` |
| 3 | `lib/screens/main/storage_explorer_screen.dart` | 71 | `_error = e.toString();` |
| 4 | `lib/screens/main/file_preview_screen.dart` | 47 | `_error = e.toString();` |
| 5 | `lib/providers/discovery_providers.dart` | 73 | `statusMessage: e.toString(),` |

**Fix:** Replace every `e.toString()` with `friendlyError(e)` and add `import 'package:aihomecloud/core/error_utils.dart';` where missing.

---

### BUG-F04 — 🟠 HIGH: Branding "CubieCloud"/"Cubie" in `error_utils.dart` (10+ instances)

**File:** `lib/core/error_utils.dart` lines 17–52

**Problem:** Error messages mix "CubieCloud", "AiHomeCloud", and "Cubie" inconsistently:
- Line 17: `"CubieCloud is not reachable..."`
- Line 21: `"...the same network as your Cubie..."`
- Line 52: `"...Please set up your Cubie first."`

**Impact:** Every network error shown to users has inconsistent branding.

**Fix:** Standardize all error messages to use "AiHomeCloud" consistently.

---

### BUG-F05 — 🟠 HIGH: "Find Cubie" Button in Disconnect Banner

**File:** `lib/navigation/main_shell.dart` line 111

**Problem:** The disconnect banner button says "Find Cubie" instead of "Find AiHomeCloud" or "Reconnect".

**Code:**
```dart
label: const Text('Find Cubie', style: TextStyle(fontSize: 12)),
```

**Fix:** Change to `'Reconnect'` or `'Find Device'`.

---

### BUG-F06 — 🟡 MEDIUM: `welcome_screen.dart` is Dead Code

**File:** `lib/screens/onboarding/welcome_screen.dart` (entire file)

**Problem:** The file exists with a fully implemented `WelcomeScreen` widget, but it is not registered as a route in `app_router.dart` and cannot be reached by any navigation. The splash screen (merged in the onboarding overhaul) replaced its functionality.

**Fix:** Delete `welcome_screen.dart` entirely. Also remove any imports referencing it.

---

### BUG-F07 — 🟡 MEDIUM: `cubie_card.dart` File Name Doesn't Match Class `AppCard`

**File:** `lib/widgets/cubie_card.dart`

**Problem:** After the P9-04 rename, the class was renamed from `CubieCard` to `AppCard`, but the file is still named `cubie_card.dart`. Other widgets follow the convention of matching file name to class name.

**Fix:** Rename file to `app_card.dart` and update all imports.

---

### BUG-F08 — 🟡 MEDIUM: Hardcoded Port in Discovery/Scanner

**File:** `lib/services/network_scanner.dart`

**Problem:** The scanner uses a hardcoded port number for HTTPS probing. If the backend port ever changes, the scanner breaks silently.

**Fix:** Use the port constant from `lib/core/constants.dart`.

---

---

## 3. UX Critique (Non-Technical User Perspective)

> Reviewed from the perspective of a non-technical Indian family: parents (40–60), teens, grandparents.
> These are NOT bugs — they are usability issues that make the product confusing or scary for real users.

---

### UX-01 — 🔴 CRITICAL: Onboarding QR Scan — "OTP" Jargon & Timer Anxiety

**Screens:** QR Scan → Discovery flow

**What the user sees:** "OTP expires in MM:SS" with a progress bar. No explanation of what "OTP" is. Timer creates urgency and confusion. If expired, must re-scan.

**Why it's bad:** A 50-year-old parent doesn't know what OTP means. The timer feels like a security checkpoint, not a pairing experience.

**Suggestion:** Replace "OTP" with "Pairing code". Change timer message to "Pairing code valid for X minutes". Auto-retry instead of forcing re-scan.

---

### UX-02 — 🔴 CRITICAL: Network Scan — IP Address Jargon

**Screen:** Network Scan (`lib/screens/onboarding/network_scan_screen.dart`)

**What the user sees:** "Scanning from 192.168.0.105" — pure jargon. Devices listed by IP address only.

**Suggestion:** Change subtitle to "Looking for your device on Wi-Fi..." (hide IP). Show device names, not IPs. Add help: "Can't find your device? Make sure it's powered on and on the same Wi-Fi."

---

### UX-03 — 🔴 CRITICAL: Storage Management — Terrifying Language

**Screen:** Storage Explorer (`lib/screens/main/storage_explorer_screen.dart`)

**What the user sees:** "Format Device" button, "ERASE ALL DATA" warning, "Mount"/"Unmount"/"Eject" jargon, technical specs like "NVMe", "SSD".

**Suggestion:**
- "Mount" → "Connect" / "Use this device"
- "Unmount" → "Stop using"
- "Eject" → "Remove safely"
- "Format" → "Prepare device for first use" with softer warning
- Hide technical steps; show "Preparing to remove... Done! Safe to unplug."

---

### UX-04 — 🔴 CRITICAL: Family Member Removal — Emotionally Scary

**Screen:** Family management

**What the user sees:** "This will remove their account and all their files. This action cannot be undone." + Red "Remove" button.

**Suggestion:** Reframe: "Remove {name} from your family?" + "Move their files to a backup folder?" Offer preview of files before removal. Show count: "42 photos, 12 videos".

---

### UX-05 — 🟠 HIGH: Dashboard Stats — Jargon Without Context

**Screen:** Dashboard (`lib/screens/main/dashboard_screen.dart`)

**What the user sees:** "CPU: 45%", "Memory: 2.1 GB / 8 GB", "Temperature: 62°C" — no labels saying if these are good/bad.

**Suggestion:** Add context labels: "CPU: 45% — Normal" (green), "Temperature: 62°C — Cool". Move stats to "Device Health" in Settings for advanced users. Or add help icon explaining what they mean.

---

### UX-06 — 🟠 HIGH: Disconnect Banner — No Recovery Path

**Screen:** Any tab when disconnected (`lib/navigation/main_shell.dart`)

**What the user sees:** Red banner "AiHomeCloud is unreachable." + "Find Cubie" button. No explanation of WHY or what to do.

**Suggestion:** Add checklist tips: "Is your device powered on? Are you on the same Wi-Fi?" Change button to "Reconnect" (not "Find Cubie"). If reconnect fails 3x, offer re-pairing flow.

---

### UX-07 — 🟠 HIGH: Upload Feedback — Background Upload Confuses Families

**Screen:** File upload flow (`lib/widgets/folder_view.dart`)

**What the user sees:** "Uploading 3 of 5 file(s)…" banner at top while browsing. No in-folder feedback when done.

**Suggestion:** Show progress overlay during upload. When done, show "Just uploaded" section in the file list. Add "New photo from today" grouping.

---

### UX-08 — 🟠 HIGH: Telegram Bot Setup — Non-Obvious for Non-Tech Users

**Screen:** Telegram setup (`lib/screens/main/telegram_setup_screen.dart`)

**What the user sees:** Instructions to use @BotFather, enter "bot token", etc. 95% of families have no idea what this means.

**Suggestion:** Move to "Advanced" section or hide from non-admins. Add explainer: "Get instant alerts via Telegram (optional)." Replace raw instructions with "Click here for help" link. Validate token on input.

---

### UX-09 — 🟠 HIGH: Wi-Fi Settings — Password Confusion

**Screen:** Wi-Fi settings

**What the user sees:** Network list with "Open", "WPA2", "WPA3" labels. Wrong password gives generic "Failed to connect."

**Suggestion:** Show "Connected" badge on current network. Replace "Open" with "No password required". Simplify: show lock icon or "Secure". On failure: "Password wasn't correct. Try again."

---

### UX-10 — 🟡 MEDIUM: Folder Structure Confusion (.inbox visible)

**Screen:** My Files tab

**What the user sees:** ".inbox" folder alongside Photos, Videos, Documents, Others. ".inbox" is a technical name.

**Suggestion:** Rename ".inbox" → "Inbox" or "Uploads" in UI. Add section headers: "Your Files", "Family Files". Hide technical folder names.

---

### UX-11 — 🟡 MEDIUM: File Preview — No Video/Audio Playback

**Screen:** File preview (`lib/screens/main/file_preview_screen.dart`)

**What the user sees:** "Video preview not supported yet. Download the file to view it." Users don't understand why they need to "download" their own file.

**Suggestion:** Show video thumbnail + "Tap to download and play." Auto-open downloaded files. Show progress during download.

---

### UX-12 — 🟡 MEDIUM: Empty States — Not Helpful Enough

**Screens:** Empty folder views, Storage Explorer with no devices

**What the user sees:** "This folder is empty" + "Upload files or create a folder to get started" — but no visible buttons.

**Suggestion:** Add [+ Upload] and [+ New Folder] buttons directly below the message. Add illustrations. In Storage Explorer: add image of USB stick/SSD.

---

### UX-13 — 🟡 MEDIUM: Bottom Nav "More" Label — Vague

**Screen:** Main navigation bar (`lib/navigation/main_shell.dart`)

**What the user sees:** "More" tab — unclear what's inside. Mixes unrelated categories (TV Streaming, Device, Account, Network).

**Suggestion:** Replace "More" with "Settings". Reorganize into groups: "Sharing", "Device", "Network", "Security".

---

### UX-14 — 🟡 MEDIUM: Settings — Too Many Technical Options

**Screen:** Device/Network settings

**What the user sees:** Serial number, IP address, firmware version, Ethernet toggle (irrelevant for mobile user).

**Suggestion:** Hide IP or add "This is your device's address on Wi-Fi." Remove Ethernet toggle for mobile. Add tooltips to advanced settings.

---

### UX-15 — 🟡 MEDIUM: Error Messages — Generic, No Actionable Steps

**File:** `lib/core/error_utils.dart`

**What the user sees:** "Cannot connect to AiHomeCloud. Check your network connection." Users don't know HOW to check their network.

**Suggestion:** Add specific steps: "Is your device powered on? → Is it on your home Wi-Fi? → Try restarting your device." For timeout: "Device is slow. Try again in 30 seconds."

---

### UX-16 — 🟢 LOW: Button Label Inconsistency (Splash vs QR Scan)

**Screens:** Splash screen vs QR scan screen

**What the user sees:** "Find My AiHomeCloud" on splash but "Scan QR Code" on the next step. Different labels for similar actions.

**Suggestion:** Unify: always use "Scan QR Code" or "Find My Device".

---

### UX-17 — 🟢 LOW: Dark Theme Low Contrast for Older Users

**File:** `lib/core/theme.dart`

**What the user sees:** Gray secondary text on dark cards — hard to read for 45+ users on OLED screens in sunlight.

**Suggestion:** Increase contrast ratio. Test with WCAG AA minimum standards.

---

### UX-18 — 🟢 LOW: Splash Animation Too Long (1.5s delay)

**File:** `lib/screens/onboarding/splash_screen.dart`

**What the user sees:** 1.5s animation before the button appears. Older users find animations disorienting.

**Suggestion:** Respect system `prefers-reduced-motion`. Reduce to 200ms. Let users tap through.

---

### UX-19 — 🟡 MEDIUM: No Demo Mode for Store/YouTube Demos

**File:** `lib/screens/onboarding/qr_scan_screen.dart` (has `_useDemoQr()` but hidden in production)

**Problem:** No way to demonstrate the app without real hardware. Stores and reviewers can't show off the product.

**Suggestion:** Add a demo mode that shows recorded UI or connects to a cloud demo device.

---

### UX-20 — 🟡 MEDIUM: No Help/FAQ Section in the App

**Screens:** All — no Help link anywhere

**Problem:** Non-technical families have no way to get help within the app. Errors don't link to support.

**Suggestion:** Add "Help" section in Settings with FAQs for pairing, storage, family management, troubleshooting.

---

### UX-21 — 🟡 MEDIUM: No Device Rename on First Setup

**Screen:** Setup complete flow

**Problem:** Device defaults to "My AiHomeCloud". Multi-device households need custom names ("Dad's Cloud", "Study Cubie"). Users must navigate to Settings after pairing.

**Suggestion:** Add device naming step in setup flow: "What do you want to call your AiHomeCloud?"

---

## 4. Suggestions

### Quick Wins (Do First)
1. **Fix the crash** — BUG-F01 (`/welcome` navigation) is a one-line fix
2. **Fix discovery** — BUG-F02 (service name check) is a one-line fix
3. **Fix raw exceptions** — BUG-F03 (5 files, s/e.toString()/friendlyError(e)/)
4. **Branding sweep** — BUG-B02 + BUG-F04 + BUG-F05 (search-and-replace across ~20 files)
5. **Delete dead code** — BUG-F06 (remove welcome_screen.dart)

### Architecture Suggestions
- **Path safety:** Replace `startswith()` with `Path.relative_to()` in `_safe_resolve()` (BUG-B04)
- **Specific exception handling:** Replace bare `except Exception` in lifespan with specific types (BUG-B03)
- **OTP return:** Add plaintext OTP to `/pair/qr` response for fallback pairing (BUG-B01)
- **Token lock:** Move token cache write inside the asyncio.Lock (BUG-B07)

### UX Priorities for Family Product
1. **Replace all technical jargon** — Mount/Unmount/Eject/OTP/NVMe/SSD (UX-03, UX-01)
2. **Add recovery context to errors** — "Is device on? Same Wi-Fi?" (UX-06, UX-15)
3. **Soften scary operations** — Format, Family Remove (UX-03, UX-04)
4. **Add in-app Help** — FAQ + troubleshooting (UX-20)
5. **Dashboard context** — Is CPU/Temp/RAM good/bad? (UX-05)

### Testing Gaps
- No Flutter test for QR scan screen navigation
- No Flutter test for network scanner service name matching
- No integration test for full pairing flow (QR → pair → login → browse)
- Backend: no test verifying OTP is returned in `/pair/qr` response

---

## Finding Summary

| Category | 🔴 Critical | 🟠 High | 🟡 Medium | 🟢 Low | Total |
|---|---|---|---|---|---|
| Backend Bugs | 1 | 1 | 5 | 5 | 12 |
| Flutter Bugs | 2 | 3 | 3 | 0 | 8 |
| UX Issues | 4 | 5 | 8 | 3 | 20 |
| **Total** | **7** | **9** | **16** | **8** | **40** |

---

*AiHomeCloud Audit — Generated 2025-03-10*
