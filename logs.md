# CubieCloud — Development Log

---

## 2025-07-25 — Trash overhaul: Files tab, auto-delete toggle, Telegram weekly warning

### Summary
Moved Trash from More tab to Files tab. Verified soft-delete works (shutil.move to `.cubie_trash/`). Added user-controlled auto-delete toggle (30-day limit only runs when ON). Added Telegram weekly trash warning (Saturday 10AM, once per ISO week, only when >10 GB).

### Changes

**Backend:**
- `routes/file_routes.py` — added `GET/PUT /api/v1/files/trash/prefs`; modified `_purge_trash_if_needed()` to gate 30-day age purge on `trash_auto_delete` KV flag; quota-overflow purge still always runs
- `telegram_bot.py` — added `_trash_warning_loop()` async task (hourly tick, Saturday 10AM check, once-per-ISO-week via KV `trash_warn_week`, >10 GB threshold); wired into `start_bot()`/`stop_bot()`
- `tests/test_trash.py` — added 3 new tests: `test_get_trash_prefs_default_false`, `test_set_trash_prefs_and_read_back`, `test_age_purge_skipped_when_auto_delete_off`

**Frontend:**
- `services/api/files_api.dart` — added `getTrashAutoDelete()` and `setTrashAutoDelete(bool)`
- `providers/file_providers.dart` — added `trashAutoDeleteProvider`
- `screens/main/files_screen.dart` — replaced import with barrel `providers.dart`; added `_trashOpen` state; added Trash card (4th entry); added `_TrashScreen` ConsumerWidget with auto-delete toggle + item list + restore/delete/empty-all; added `_TrashItemTile`
- `screens/main/more_screen.dart` — removed Trash section (ListView entry + `_TrashCard` class)

### Test Results
- All 12 `test_trash.py` tests pass
- `flutter analyze` — 0 errors (45 pre-existing info warnings unchanged)

---

## 2025-07-25 — v5 Sprint: Tasks 0–7 + DLNA/SMB Merge

### Summary
Implemented all tasks from MASTER_PROMPT_v5.md sprint (Tasks 0–7) and merged DLNA+SMB into a single toggle. Each task was committed and pushed individually.

### Commits (oldest → newest)
| Commit | Description |
|--------|-------------|
| `2fd4d7d` | Disconnect banner SafeArea fix + `GET /network/status` endpoint |
| `9640204` | StatTile overflow — aspect ratio 1.45→1.25, reduced font/padding sizes |
| `af399cb` | Ensure personal folders exist before computing family sizes |
| `9f0c835` | Upload chunk 1→4 MB, write buffer 256 KB→2 MB |
| `fe674ee` | Family tab moved into More screen, bottom nav reduced to 3 tabs |
| `22109d3` | Files tabs replaced with 2-folder explorer + onBack on FolderView |
| `e3e139d` | Netflix-style avatar user picker on PIN entry screen |
| `141d727` | Merge DLNA+SMB into unified "TV & Computer Sharing" toggle |

### Key Decisions
- **3-tab nav:** Home, Files, More — Family moved into More screen to reduce clutter.
- **Files screen rewrite:** Removed 3-segment tab bar; replaced with 2 folder cards (Personal + Shared) that open inline FolderView with back navigation.
- **PIN entry UX:** Replaced dropdown user selector with Netflix-style avatar circles with color cycling.
- **Unified media service:** Merged separate `samba` and `dlna` service toggles into single `media` service controlling minidlna + smbd + nmbd together. Backend store includes migration logic for old config.
- **StatTile sizing:** All metrics reduced (fonts, padding, spacing) plus aspect ratio change to prevent overflow on smaller screens.

### Files Modified
**Backend:**
- `routes/network_routes.py` — new `GET /network/status`
- `routes/family_routes.py` — `_ensure_personal_folder()` helper
- `routes/file_routes.py` — write buffer 256 KB→2 MB
- `routes/service_routes.py` — `media` service maps to `[minidlna, smbd, nmbd]`
- `routes/storage_helpers.py` — `start_nas_services()` includes minidlna
- `config.py` — upload chunk 1→4 MB
- `store.py` — merged samba+dlna defaults into `media`, migration logic

**Frontend:**
- `navigation/main_shell.dart` — SafeArea wrap, 12 s debounce, 3-tab nav
- `screens/main/dashboard_screen.dart` — childAspectRatio 1.25
- `screens/main/files_screen.dart` — 2-folder card explorer rewrite
- `screens/main/more_screen.dart` — Family section + "TV & Computer Sharing" toggle
- `screens/onboarding/pin_entry_screen.dart` — Netflix-style avatar picker
- `widgets/stat_tile.dart` — reduced all sizes
- `widgets/folder_view.dart` — added `onBack` callback
- `services/api_service.dart` — `media` icon mapping
- `services/mock_api_service.dart` — single `media` service

### Pending (manual on Cubie)
- Configure `/etc/samba/smb.conf` with `[Shared]` and `[Personal]` share sections
- Set Samba password: `sudo smbpasswd -a radxa`
- Enable/start smbd + nmbd via systemctl
- Delete old `services.json` so migration regenerates it
- Deploy updated backend: `git pull origin main && sudo systemctl restart cubie-backend`
