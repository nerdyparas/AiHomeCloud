# AiHomeCloud — Agent Task List (All 10)

## How to use this file

Give Claude Sonnet 4.6 one task at a time. After each task, run
`flutter analyze` and `pytest backend/tests/` before moving to the next.
Each task is self-contained and has clear acceptance criteria.

**Global rules that apply to every task:**
- Read files before editing. Do not guess at structure.
- Make the smallest change that satisfies acceptance criteria.
- Do not reformat unrelated code.
- Do not add new packages unless the task explicitly permits it.
- `run_command()` in the backend always returns a tuple — unpack as
  `rc, stdout, stderr`.
- `friendlyError(e)` is the only error surface in Flutter UI strings.
- `settings.nas_root` and `settings.data_dir` are the only path references
  in backend.
- `store.py` is the only JSON persistence layer in backend.
- No technical terms (`/dev/` paths, ext4, NAS, Samba, partition) in any
  user-facing UI string.

---

## Task 1 — Fix Profile Selection First-Tap Bug

### Problem

On cold app launch the user-picker screen shows a spinner while fetching users
from the backend. A tap during that window fails silently. The second tap works
because the in-memory cache is warm. Root cause: `_userPickerCache` in
`lib/screens/onboarding/pin_entry_screen.dart` does not survive process death.

### Fix

Persist the user list to `SharedPreferences`.

On screen load:
1. Read the persisted list from `SharedPreferences` and render avatars
   immediately — no spinner if cached data exists.
2. Always refresh from the backend in the background.
3. On a successful backend response, write the updated list back to
   `SharedPreferences`.

### Files to read first

- `lib/screens/onboarding/pin_entry_screen.dart`
- `lib/providers/core_providers.dart`
- `lib/core/constants.dart` — add the new prefs key here

### Acceptance criteria

- Second launch shows profile avatars instantly with no spinner.
- Background refresh runs silently and updates the list if it changed.
- If backend is unreachable, cached list is shown with no error.
- Error is shown only when cache is also empty.
- No new packages. Use the `shared_preferences` package already in the project.

---

## Task 2 — Fix Gray Screen on Dashboard Launch

### Problem

After login, the app navigates to `/dashboard` while `deviceInfoProvider`,
`systemStatsStreamProvider`, and `storageDevicesProvider` are all cold
FutureProviders. The dashboard Scaffold briefly renders with no content —
appearing as a gray/blank screen. Clearing the app from recents and
re-launching fixes it because the OS cold-starts Flutter again.

### Fix

Two-part fix:

1. In `lib/screens/onboarding/splash_screen.dart`, after confirming the session
   exists, call `ref.read()` on `deviceInfoProvider` and `storageDevicesProvider`
   to warm them before calling `context.go('/dashboard')`.

2. In `lib/screens/main/dashboard_screen.dart`, replace blank/null loading
   states with shimmer skeleton placeholders so the screen never looks empty.
   Use `flutter_animate` (already in project) with a fade shimmer on the card
   shapes — no new packages needed.

### Files to read first

- `lib/screens/onboarding/splash_screen.dart`
- `lib/screens/main/dashboard_screen.dart`
- `lib/providers/device_providers.dart`

### Acceptance criteria

- Launching the app when already logged in never shows a gray/blank dashboard.
- A visible skeleton or loading card is shown for each section while data loads.
- No new packages.

---

## Task 3 — Remove Adblock / AdGuard Feature

### Problem

The AdGuard/adblock feature is being removed from the product.

### Delete entirely

- `lib/widgets/adblock_stats_widget.dart`
- `backend/app/routes/adguard_routes.py`
- `backend/tests/test_adguard.py`
- `FIX_ADBLOCKING.md`

### Partially clean

Read each file and remove only adblock-related sections:

- `lib/screens/main/more_screen.dart` — remove `_AdBlockingCard` widget class
  and its call site; keep the "Privacy & Security" section label only if other
  items remain under it
- `lib/providers/data_providers.dart` — remove `adGuardStatsSilentProvider`
- `lib/screens/main/dashboard_screen.dart` — remove adblock badge import and
  widget usage
- `backend/app/main.py` — remove adguard router include and registration
- `backend/app/routes/__init__.py` — remove adguard import if present
- `lib/services/api_service.dart` and its part files — remove `getAdGuardStatus`,
  `getAdGuardStats`, `toggleAdGuard`, `pauseAdGuard` methods
- `backend/app/routes/service_routes.py` — remove any adguard-specific endpoints

### Acceptance criteria

- `flutter analyze` passes with zero new errors.
- `pytest backend/tests/` passes.
- More screen renders without the AdGuard card.
- No `adguard` or `adblock` symbol remains imported or referenced in any
  non-documentation file.

---

## Task 4 — Remove All "Cubie" Remnants

### Problem

The old product name "CubieCloud" and hardware name "Cubie" appear in live code
files. Documentation and `.md` files can keep the word in historical context
but all code, config, service files, and Android package identifiers must be
clean.

### Files and what to change

- `android/app/build.gradle` — `namespace` and `applicationId`:
  `com.cubiecloud.cubie_cloud` → `com.aihomecloud.app`
- `android/app/src/main/kotlin/com/cubiecloud/cubie_cloud/MainActivity.kt` —
  package declaration; also move the file to the new package folder path
  `com/aihomecloud/app/`
- `android/app/src/main/AndroidManifest.xml` — deep link scheme:
  `android:scheme="cubie"` → `android:scheme="aihomecloud"`
- `backend/cubie-backend.service` — rename file to `aihomecloud.service`;
  update `Description=`, `ExecStart=`, and `SyslogIdentifier=` inside
- `deploy.sh` — replace `cubie-backend` service name, `CUBIE_CERT` variable
  name and references, `TARGET_USER` default value
- `lib/providers/device_providers.dart` — model named `CubieDevice` is imported
  from models; check `lib/models/device_models.dart` and rename to
  `AhcDevice` or `HomeDevice`, updating all references across the codebase
- `lib/navigation/main_shell.dart` — `CubieNotificationOverlay` widget: check
  its definition file and rename it to `AhcNotificationOverlay`
- `backend/app/telegram_bot.py` — logger name `"cubie.telegram_bot"` →
  `"aihomecloud.telegram_bot"`
- `backend/scripts/50-cubie-network.rules` — rename file and update its content
- `backend/README.md` — update service name references

### Acceptance criteria

- `grep -r "cubie\|CubieCloud\|CUBIE" --include="*.dart" --include="*.py"
  --include="*.kt" --include="*.gradle" --include="*.sh" --include="*.service"
  --include="*.rules" --include="*.xml"` returns zero results.
- `flutter analyze` passes.
- `pytest backend/tests/` passes.

---

## Task 5 — Away-From-Home Graceful Handling

### Problem

When the device running the app is outside the home WiFi network, the app shows
only a thin "Reconnecting…" banner after 12 seconds and no further guidance.
Users are confused about why the app is not working.

### Fix

When `ConnectionStatus.disconnected` persists for more than 10 seconds, show a
bottom sheet (not a dialog) from the `MainShell`. The bottom sheet must:

1. Explain in plain language that the home cloud is not reachable.
2. Suggest checking that the phone is on the home WiFi.
3. Offer a "Notify me when I'm back" toggle. When enabled, start a periodic
   background ping to the stored host IP every 60 seconds using an `Isolate`
   or `Timer`. When the ping succeeds, fire a local notification using the
   `flutter_local_notifications` package (check if already in project first;
   add only if not present).
4. Offer a "Dismiss" action that suppresses the sheet for the rest of the
   session.

The bottom sheet must not re-appear if the user dismissed it, until the
connection is re-established and lost again.

### Files to read first

- `lib/navigation/main_shell.dart`
- `lib/providers/device_providers.dart` — `ConnectionNotifier`
- `lib/services/api_service.dart` — see how host IP and timeout work
- `pubspec.yaml` — check existing packages before adding any

### Acceptance criteria

- After 10 seconds disconnected, a bottom sheet appears with the described
  content.
- Dismiss suppresses it for the session.
- "Notify me" toggle triggers a local notification when connection resumes.
- No bottom sheet appears during normal connected use.
- The thin reconnecting banner in `MainShell` can remain alongside this.

---

## Task 6 — TV Sharing Toggle — Optimistic Update

### Problem

`servicesProvider` is a plain `FutureProvider`. When the TV & Computer Sharing
switch is toggled in `more_screen.dart`, the code calls `ref.invalidate(servicesProvider)`
after the API call. This causes the tile to enter a loading/spinner state for
the full network round-trip duration. The switch appears unresponsive.

### Fix

Convert `servicesProvider` to a `StateNotifierProvider` that supports optimistic
updates:

1. When the user toggles the switch, flip the local state immediately so the
   switch moves to its new position right away.
2. Call the API in the background.
3. If the API call fails, roll back the local state to what it was and show a
   snack bar with `friendlyError(e)`.

### Files to read first

- `lib/providers/data_providers.dart`
- `lib/screens/main/more_screen.dart` — the TV sharing tile
- `lib/services/api/services_network_api.dart`

### Acceptance criteria

- Toggle switch moves instantly on tap — no spinner in the tile.
- Failed API call rolls back the switch position and shows a snack bar.
- `flutter analyze` passes.

---

## Task 7 — Server Certificate Popup — Make Instant, Demote Visually

### Problem

In `more_screen.dart`, tapping the "Server Certificate" row opens a popup that
is slow to appear because it makes a network call to fetch the fingerprint on
every tap. The fingerprint is already cached in `certFingerprintProvider`.

Additionally the tile is visually prominent, causing users to worry about it.

### Fix

1. Read the fingerprint synchronously from `ref.read(certFingerprintProvider)`
   and show the dialog immediately — no async call on tap.
2. Demote the tile: make it a smaller text link at the bottom of the Privacy &
   Security card rather than a full `ListTile`.

### Files to read first

- `lib/screens/main/more_screen.dart` — find the certificate tile and dialog
- `lib/providers/core_providers.dart` — `certFingerprintProvider`

### Acceptance criteria

- Tapping the certificate link opens the dialog with no perceptible delay.
- The certificate entry is visually smaller than a standard `ListTile`.
- The fingerprint displayed is the one already stored in `SharedPreferences`.

---

## Task 8 — Telegram: Clean Upload Message Flow

### Problem

When a user sends a file to the Telegram bot, a "Where would you like to save
this?" message with an inline keyboard is posted. After the user picks a
destination, this message is never deleted — it stays in the chat indefinitely.
The desired behaviour is one file → one clean result message only.

### Fix

In `backend/app/telegram_bot.py`, inside `_handle_destination_callback`, after
the user picks a destination and before `_process_upload_choice` is awaited,
delete the original "where to save" message using
`await query.message.delete()`. Wrap it in a try/except so a delete failure
does not break the upload flow.

The final success message (already built in `_process_upload_choice`) is the
only thing that should remain in chat per file. Its format — filename, saved
category, file size, speed, time — is correct and should not change.

### Files to read first

- `backend/app/telegram_bot.py` — `_handle_destination_callback` and
  `_process_upload_choice`

### Acceptance criteria

- After a destination is chosen, the "where to save" keyboard message is
  deleted from Telegram chat.
- The success message with filename, category, speed, and time remains.
- If the delete call fails (e.g. message too old), the upload still completes.

---

## Task 9 — Telegram: User Approval Flow

### Problem

Currently any Telegram user who knows the bot name can send `/auth` and
immediately gain full access to the family cloud. There is no admin approval
step. This is a security gap.

### Fix

**Bot side (`backend/app/telegram_bot.py`):**

1. When an unknown user sends `/auth`, do not grant access. Instead:
   - Store the request in a pending approvals list in the KV store
     (key: `telegram_pending_approvals`).
   - Reply to the requesting user: access is pending admin approval.
   - Send a message to every currently linked admin chat ID (resolve admins
     from the AiHomeCloud user list via `store.get_users()`, then find their
     linked chat IDs) with the requester's first name, username, and chat ID,
     and two inline buttons: Approve / Deny.

2. Add a callback handler for Approve/Deny buttons:
   - Approve: move the chat ID from pending to `telegram_linked_ids`, notify
     the approved user that they now have access.
   - Deny: remove from pending, notify the requesting user they were not
     approved.

3. Add `/approve <chat_id>` and `/deny <chat_id>` text commands as an
   alternative for admins who prefer typing.

**App side (`lib/screens/main/telegram_setup_screen.dart` and
`backend/app/routes/telegram_routes.py`):**

Add a "Pending Requests" section to the Telegram setup screen (admin only)
showing pending approvals with Approve / Deny buttons. Add the corresponding
backend endpoint `GET /api/v1/telegram/pending` and
`POST /api/v1/telegram/pending/{chat_id}/approve` and `.../deny`.

### Acceptance criteria

- An unlinked user sending `/auth` does not gain access — they get a "pending"
  message.
- Admin receives an inline-button Telegram message to approve or deny.
- Approval grants access; denial removes the request.
- App's Telegram settings screen shows pending requests for the admin.
- Existing linked users are unaffected.

---

## Task 10 — Telegram: Duplicate Detection + Useful Extensions

### Problem

Files sent to the bot can create duplicates. Additionally the bot has several
natural extension points that leverage existing backend features but are not yet
exposed over Telegram.

### Fix — Part A: Duplicate Detection

In `backend/app/telegram_bot.py`, inside `_store_private_or_shared_file` and
`_store_entertainment_file`, after the file is downloaded to the inbox but
before `_sort_file` is called:

1. Compute the MD5 hash of the downloaded file.
2. Check it against a hash index stored in the KV store
   (key: `telegram_file_hashes`, value: dict of `{md5: {filename, path, saved_at}}`).
3. If a match exists, do not save the file. Instead reply to the user:
   "This file already exists as `[filename]` saved on `[date]`. Use /keep to
   save anyway or /skip to cancel." Store the pending state per chat ID.
4. If no match, save the file and add its hash to the index.

### Fix — Part B: Bot Extensions

Add the following commands to the bot. Each must call existing backend logic —
do not duplicate business logic:

- `/recent` — list the last 5 files saved via the bot (read from KV store),
  each with an inline "🗑 Delete" button.
- `/storage` — show a text-art storage bar (the `_storage_bar` helper already
  exists) plus top-3 folders by size. Call `GET /api/v1/storage/stats` via the
  backend internals (do not make an HTTP call from the bot to itself — import
  the function directly).
- Trash warning message (already sent by `_trash_warning_loop`) — add an
  inline "Empty Trash" button that calls the existing trash-clear logic.
- When storage exceeds 85%, proactively message all admin chat IDs with storage
  summary. Add this check inside `_trash_warning_loop`'s existing periodic
  cycle.

Update `/help` to list all new commands.

### Files to read first

- `backend/app/telegram_bot.py`
- `backend/app/store.py` — KV store API
- `backend/app/routes/storage_routes.py` — existing storage logic to reuse
- `backend/app/hygiene.py` — existing trash logic to reuse

### Acceptance criteria

- Sending a duplicate file triggers the duplicate warning and does not save
  until the user confirms with `/keep`.
- `/recent` shows last 5 files with working delete buttons.
- `/storage` shows a readable storage summary.
- Trash warning message includes an inline "Empty Trash" button.
- Admin is proactively notified when storage crosses 85%.
- `/help` lists all commands including new ones.
- `pytest backend/tests/` passes.
