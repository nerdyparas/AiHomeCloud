# Changelog

---

## 2025-07-25 — Repository audit and KB rebuild

**Changes:** `copilot-instructions.md` rewritten from scratch. All `kb/` files verified against source code and updated. Created `kb/architecture.md`, `kb/features.md`, `kb/flutter-patterns.md`, `kb/backend-patterns.md`, `kb/changelog.md`. Rebuilt `kb/api-contracts.md` from 78 lines to full 62-endpoint reference. Created `tasks.md`. Removed stale root-level prompt artifacts.

**Key decisions:**
- `kb/changelog.md` replaces `logs.md` as the permanent record
- `tasks.md` replaces the non-existent `TASKSv2.md` reference
- Hardware doc corrected from "A7A" to "A7Z"
- Hardcoded IP `192.168.0.212` removed from documentation

**Inaccuracies corrected:**
- api-contracts.md had only 15 of 62 endpoints documented
- hardware.md title said "A7A" but board is Radxa Cubie A7Z
- copilot-instructions.md referenced non-existent `TASKSv2.md`
- copilot-instructions.md listed wrong onboarding screen names
- copilot-instructions.md missing 4 route files (adguard, tailscale, telegram, telegram_upload)
- critique.md bugs B1 (threading.Lock) and B3 (bcrypt blocking) already fixed in code

---

## 2025-07-25 — Trash overhaul

**Features completed:** Moved Trash from More tab to Files tab. Added auto-delete toggle (30-day limit, off by default). Added Telegram weekly trash warning (Saturday 10AM, >10 GB threshold).

**Key decisions:**
- Trash lives in Files tab, not More
- Auto-delete is opt-in, not default
- Quota-overflow purge always runs regardless of auto-delete setting

**Backend changes:** `file_routes.py` added `GET/PUT /api/v1/files/trash/prefs`. `telegram_bot.py` added `_trash_warning_loop()`.

**Frontend changes:** `files_screen.dart` got Trash card + `_TrashScreen`. `more_screen.dart` lost Trash section.

---

## 2025-07-25 — v5 Sprint (Tasks 0–7 + DLNA/SMB merge)

**Features completed:**
- `GET /network/status` endpoint
- StatTile overflow fix (aspect ratio 1.45→1.25)
- Family folder size fix (ensure personal folders exist before computing)
- Upload speed boost (chunk 1→4 MB, write buffer 256 KB→2 MB)
- Family tab moved into More screen, bottom nav reduced to 3 tabs
- Files tabs replaced with 2-folder explorer (Personal + Shared)
- Netflix-style avatar user picker on PIN entry screen
- DLNA + SMB merged into unified "TV & Computer Sharing" toggle

**Key decisions:**
- 3-tab nav: Home, Files, More (Family moved into More)
- Merged `samba` + `dlna` service toggles into single `media` service
- PIN entry uses avatar circles, not dropdown
- Files screen uses 2 folder cards, not 3-segment tab bar

**Commits:** `2fd4d7d`, `9640204`, `af399cb`, `9f0c835`, `fe674ee`, `22109d3`, `e3e139d`, `141d727`