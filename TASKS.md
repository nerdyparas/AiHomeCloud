# AiHomeCloud — Open Tasks

Last updated: 2026-03-15

---

## In Progress

- **Profile edit screen** — Screen exists (`profile_edit_screen.dart`, route `/profile-edit`), backend `PUT /users/me` works. Needs integration testing on device.

---

## Up Next (Prioritised)

1. **Telegram large file receive (Task 13)** — Enable file receive up to 2 GB via Telegram Local Bot API server. Parts: setup script for Docker-based local API, backend config fields (`telegram_api_id`, `telegram_api_hash`, `telegram_local_api_url`), bot code for `_handle_incoming_file` saving to `/srv/nas/shared/Inbox/`, Flutter setup screen with large file mode toggle. See `TASK_13_TELEGRAM_LARGE_FILES.md` for full spec.

2. **Fix deploy.sh health check** — `curl` against self-signed cert always fails. Must add `--cacert cert.pem` or `--insecure` with fingerprint check. (critique B2)

3. **OTA firmware update** — `POST /api/v1/system/update` exists but is a stub (`TODO: Implement real OTA update logic` in `system_routes.py` line 54). Design and implement actual update mechanism.

4. **Auto AP fallback** — `auto_ap.py` exists but needs integration testing. When no network is available, the board should create a Wi-Fi access point for initial setup.

---

## Backlog

- **Cursor-based pagination** — Current offset pagination lacks sort stability guarantees. (critique S3)
- **Incremental document indexing** — FTS5 re-scan is O(library size) on startup. Add incremental indexing via file watcher or modification time tracking. (critique S4)
- **WebSocket reconnect improvements** — `ConnectionNotifier` has exponential backoff but error recovery for `FutureProvider` is limited. (critique S1, S2)
- **Job tracking for all long-running ops** — Only storage format uses job tracking. Extend to OTA update, large file operations. (critique A2)
- **JSON store caching** — `store.py` has 1s TTL cache, but high-frequency reads on every authenticated request could be optimised. (critique A1)
- **Samba configuration docs** — Manual steps needed on board: `smb.conf` with `[Shared]` and `[Personal]` sections, `smbpasswd`, enable smbd + nmbd.
- **OTP persistence** — OTP is in-memory; lost on restart. Consider persisting to disk for pairing resilience.

---

## Deferred

- **Multi-SBC support** — No HAL abstraction; device paths hardcoded to specific boards. Would require abstracting board detection, device paths, thermal zones. (critique A4)
- **AI file categorization** — RAM budget on ARM too tight for on-device ML (≤256 MB constraint). Deferred until edge AI becomes more memory-efficient.
- **iOS app** — Flutter supports iOS but no testing, signing, or App Store submission done.
- **Multi-device management** — Managing multiple boards from one app. Would need device registry and switching.
- **QR pairing TOFU hardening** — Re-pair is a potential downgrade vector. TOFU window reduced but not eliminated. (critique A5)

---

## Done (Recent)

- [x] **Backend bring-up on Rock Pi 4A** — Fixed missing service, avahi mDNS, `sudo -n` invariant, asyncio deprecation, evil_link test bug; `scripts/dev-setup.sh` rewritten for new hardware; `board.py` now recognises Rock Pi 4A (2026-03-15)
- [x] **Telegram approval flow (Task 9)** — `/auth` now queues pending approval instead of auto-linking; admin gets approve/deny inline keyboard; updated test (2026-03-15)
- [x] **Trash overhaul** — Moved Trash to Files tab, auto-delete toggle, Telegram weekly warning (2025-07-25)
- [x] **v5 Sprint Tasks 0–7** — Network status endpoint, StatTile fix, family folder sizes, upload speed, 3-tab nav, 2-folder explorer, Netflix picker, DLNA+SMB merge (2025-07-25)
- [x] **asyncio.Lock migration** — `store.py` converted from `threading.Lock` to `asyncio.Lock` (fixes critique B1)
- [x] **bcrypt offloading** — `auth.py` hash/verify now use `run_in_executor` (fixes critique B3)
- [x] **Profile edit** — `PUT /users/me` endpoint + `profile_edit_screen.dart` + `UpdateProfileRequest` model
- [x] **Emoji avatar system** — `EmojiPickerGrid` + `UserAvatar` widgets, `icon_emoji` field in user model
- [x] **KB rebuild** — Full documentation audit, `copilot-instructions.md` rewritten, all `kb/` files verified (2025-07-25)
