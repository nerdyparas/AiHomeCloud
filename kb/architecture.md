# Architecture Map — AiHomeCloud

> Verified against source code as of 2026-03-13.
> See also `kb/api-contracts.md` for the full endpoint reference.

---

## System Overview

AiHomeCloud is a personal home NAS appliance built on the **Radxa Cubie A7Z** (ARM Rockchip, 8 GB RAM). It consists of two halves:

- **FastAPI backend** (`backend/`) — Python server running on the Cubie hardware, providing REST + WebSocket APIs for file management, system monitoring, user auth, storage management, and service control. Persists state as JSON files in `/var/lib/cubie/`. Serves files from `/srv/nas/`.
- **Flutter app** (`lib/`) — Android mobile client that discovers the Cubie via mDNS/BLE, pairs via QR code, authenticates via JWT, and provides the UI for all NAS operations. Uses Riverpod for state, GoRouter for navigation, and a dark theme with `AppColors`/`CubieRadii`/`AppTheme`.

Communication is HTTPS (self-signed TLS, trust-on-first-use pinning) on port 8443, plus two WebSocket channels for real-time monitoring and notifications.

---

## Backend Route Inventory

| File | Prefix | Auth | Purpose |
|------|--------|------|---------|
| `auth_routes.py` | `/api/v1` | Mixed | 14 endpoints: QR pairing, user CRUD, login/logout, refresh, PIN, profile |
| `system_routes.py` | `/api/v1/system` | User/Admin | 6 endpoints: info, firmware, OTA update, rename, shutdown, reboot |
| `monitor_routes.py` | `/ws` | Token | 1 WS: real-time CPU/RAM/temp/network/storage stats (~2s) |
| `file_routes.py` | `/api/v1/files` | User | 14 endpoints: list, mkdir, delete, trash CRUD, rename, upload, download, search, sort, roots |
| `family_routes.py` | `/api/v1/users/family` | User/Admin | 3 endpoints: list, add, remove family members |
| `service_routes.py` | `/api/v1/services` | User/Admin | 2 endpoints: list services, toggle on/off |
| `storage_routes.py` | `/api/v1/storage` | User/Admin | 9 endpoints: devices, scan, smart-activate, check-usage, format, mount, unmount, eject, stats |
| `network_routes.py` | `/api/v1` | User | 3 endpoints: network status, Wi-Fi get/set |
| `adguard_routes.py` | `/api/v1/adguard` | User/Admin | 4 endpoints: status, stats, pause, toggle protection |
| `tailscale_routes.py` | `/api/v1/system` | User/Admin | 2 endpoints: VPN status, bring up |
| `telegram_routes.py` | `/api/v1/telegram` | Admin | 3 endpoints: config get/set, unlink chat |
| `telegram_upload_routes.py` | `/telegram-upload` | Token URL | 2 endpoints: browser upload form + POST |
| `jobs_routes.py` | `/api/v1/jobs` | User | 1 endpoint: poll long-running job status |
| `event_routes.py` | `/ws` | Token | 1 WS: real-time notification stream |

**Total: 63 endpoints across 14 files.**

---

## Frontend Screen Inventory

### Onboarding Screens

| Screen | File | Route | Purpose |
|--------|------|-------|---------|
| Splash | `screens/onboarding/splash_screen.dart` | `/` | Boot screen, auth check, route to setup or dashboard |
| Network Scan | `screens/onboarding/network_scan_screen.dart` | `/scan-network` | mDNS + subnet sweep to find Cubie |
| User Picker / PIN | `screens/onboarding/pin_entry_screen.dart` | `/user-picker` | Netflix-style avatar circles, optional PIN entry |
| Profile Creation | `screens/onboarding/profile_creation_screen.dart` | `/profile-creation` | First user creates name + emoji avatar |

### Main Screens

| Screen | File | Route | Tab |
|--------|------|-------|-----|
| Dashboard | `screens/main/dashboard_screen.dart` | `/dashboard` | Home |
| Files | `screens/main/files_screen.dart` | `/files` | Files |
| More | `screens/main/more_screen.dart` | `/more` | More |
| Family | `screens/main/family_screen.dart` | `/family` | — |
| Storage Explorer | `screens/main/storage_explorer_screen.dart` | `/storage-explorer` | — |
| Telegram Setup | `screens/main/telegram_setup_screen.dart` | `/telegram-setup` | — |
| File Preview | `screens/main/file_preview_screen.dart` | `/file-preview` | — |
| Folder View | `screens/main/folder_view_screen.dart` | `/folder-view` | — |
| Profile Edit | `screens/main/profile_edit_screen.dart` | `/profile-edit` | — |
| Device Settings | `screens/main/settings/device_settings_screen.dart` | `/settings/device` | — |
| Services Settings | `screens/main/settings/services_settings_screen.dart` | `/settings/services` | — |

---

## Widget Inventory

| Widget | File | Purpose |
|--------|------|---------|
| `AppCard` | `widgets/app_card.dart` | Standard card container used across screens |
| `StatTile` | `widgets/stat_tile.dart` | Dashboard metric tile (CPU, RAM, temp, etc.) |
| `FileListTile` | `widgets/file_list_tile.dart` | File/folder row in file listings |
| `FolderView` | `widgets/folder_view.dart` | Full file browser with breadcrumbs, upload, sort, pagination (~730 lines) |
| `StorageDonutChart` | `widgets/storage_donut_chart.dart` | Circular storage usage chart |
| `AdBlockStatsWidget` | `widgets/adblock_stats_widget.dart` | Reusable AdGuard stats row for dashboard network card |
| `CubieNotificationOverlay` | `widgets/notification_listener.dart` | Toast-style notification overlay from WebSocket events |
| `EmojiPickerGrid` | `widgets/emoji_picker_grid.dart` | 32-emoji avatar picker (16 people + 16 misc) with custom input |
| `UserAvatar` | `widgets/user_avatar.dart` | Circular emoji/initial avatar with 8-color cycling |

---

## Provider Inventory

### Core (`core_providers.dart`)

| Provider | Type | Purpose |
|----------|------|---------|
| `sharedPreferencesProvider` | `Provider<SharedPreferences>` | Persistent app preferences |
| `certFingerprintProvider` | `StateProvider<String?>` | TLS cert fingerprint (TOFU) |
| `authSessionProvider` | `StateNotifierProvider<AuthSessionNotifier, AuthSession?>` | JWT auth state, refresh tokens |
| `apiServiceProvider` | `Provider<ApiService>` | HTTP client singleton with cert pinning |
| `discoveryServiceProvider` | `Provider<DiscoveryService>` | mDNS + BLE device discovery |
| `isSetupDoneProvider` | `StateProvider<bool>` | Whether initial pairing is complete |

### Data (`data_providers.dart`)

| Provider | Type | Purpose |
|----------|------|---------|
| `familyUsersProvider` | `FutureProvider<List<FamilyUser>>` | Family member list from API |
| `networkStatusProvider` | `FutureProvider<NetworkStatus>` | Network connectivity info |
| `servicesProvider` | `FutureProvider<List<ServiceInfo>>` | Managed services list |
| `tailscaleStatusProvider` | `FutureProvider<Map<String, dynamic>>` | VPN status |
| `notificationStreamProvider` | `StreamProvider<AppNotification>` | Real-time notification stream (WS) |
| `notificationHistoryProvider` | `StateNotifierProvider` | Last 50 notifications |
| `adGuardStatsSilentProvider` | `FutureProvider<Map<String, dynamic>?>` | Ad blocker stats (null if unavailable) |

### Device (`device_providers.dart`)

| Provider | Type | Purpose |
|----------|------|---------|
| `deviceInfoProvider` | `FutureProvider<CubieDevice>` | Board model, serial, IP, firmware |
| `systemStatsStreamProvider` | `StreamProvider<SystemStats>` | Real-time CPU/RAM/temp via WS |
| `connectionProvider` | `StateNotifierProvider<ConnectionNotifier, ConnectionStatus>` | Connection state with exponential backoff |
| `storageStatsProvider` | `FutureProvider<StorageStats>` | Total/used/free disk space |
| `storageDevicesProvider` | `FutureProvider<List<StorageDevice>>` | Mounted storage devices |

### Files (`file_providers.dart`)

| Provider | Type | Purpose |
|----------|------|---------|
| `fileListProvider` | `AsyncNotifierProvider.family` | Paginated file listing with 30s cache |
| `uploadTasksProvider` | `StateNotifierProvider` | Upload task tracking (progress, status) |
| `docSearchResultsProvider` | `FutureProvider.family<List<SearchResult>, String>` | FTS5 document search |
| `trashItemsProvider` | `FutureProvider<List<TrashItem>>` | Trash bin contents |
| `trashAutoDeleteProvider` | `FutureProvider<bool>` | 30-day auto-delete toggle |

### Discovery (`discovery_providers.dart`)

| Provider | Type | Purpose |
|----------|------|---------|
| `qrPayloadProvider` | `StateProvider<QrPairPayload?>` | Scanned QR code data |
| `discoveryNotifierProvider` | `StateNotifierProvider<DiscoveryNotifier, DiscoveryState>` | Device discovery flow orchestration |

---

## API Service Structure

The API client is a singleton (`ApiService`) defined in `lib/services/api_service.dart` (~316 lines) with TLS pinning and a 10-second timeout. It uses Dart's `part`/`part of` mechanism to split endpoints across 6 extension files:

| File | Domain | Key methods |
|------|--------|-------------|
| `api/auth_api.dart` | Auth | `pair()`, `login()`, `logout()`, `refresh()`, `createUser()`, `updateProfile()`, PIN ops |
| `api/family_api.dart` | Family | `getFamilyUsers()`, `addFamilyUser()`, `removeFamilyUser()` |
| `api/files_api.dart` | Files | `listFiles()`, `mkdir()`, `delete()`, `rename()`, `upload()`, `download()`, `search()`, trash ops |
| `api/system_api.dart` | System | `getDeviceInfo()`, `getFirmware()`, `rename()`, `shutdown()`, `reboot()` |
| `api/storage_api.dart` | Storage | `getDevices()`, `scan()`, `smartActivate()`, `format()`, `mount()`, `unmount()`, `eject()` |
| `api/services_network_api.dart` | Services + Network | `getServices()`, `toggleService()`, `getNetworkStatus()`, `getWifi()`, AdGuard, Tailscale, Telegram |

All methods use `.timeout(ApiService._timeout)` — no raw HTTP client calls.

---

## Navigation Structure

**Router:** GoRouter with `ShellRoute` wrapping the 3 main tabs.

**Bottom nav tabs (3):**
1. **Home** → `/dashboard` — system stats, storage chart, quick actions
2. **Files** → `/files` — Personal + Shared folder cards, inline FolderView, Trash
3. **More** → `/more` — Family management, services, network, settings links

**Key named routes:**
- `/` → Splash (auth check)
- `/scan-network` → First-time device discovery
- `/user-picker` → User selection with PIN
- `/profile-creation` → First user onboarding
- `/dashboard`, `/files`, `/more` → Main shell tabs
- `/family`, `/storage-explorer`, `/telegram-setup`, `/file-preview`, `/folder-view`, `/profile-edit` → Push routes
- `/settings/device`, `/settings/services` → Settings sub-screens

**Disconnected banner:** `main_shell.dart` shows a persistent banner when WebSocket connection is lost (12s debounce, 2-miss threshold).

---

## State Management Patterns

| Pattern | When to use | Example |
|---------|-------------|---------|
| `FutureProvider` | One-shot data fetch, no mutation needed | `deviceInfoProvider`, `familyUsersProvider` |
| `StreamProvider` | Real-time continuous data | `systemStatsStreamProvider`, `notificationStreamProvider` |
| `StateNotifierProvider` | Complex state with mutations | `authSessionProvider`, `connectionProvider`, `uploadTasksProvider` |
| `StateProvider` | Simple mutable value | `certFingerprintProvider`, `isSetupDoneProvider` |
| `AsyncNotifierProvider.family` | Parameterized async with cache | `fileListProvider` (path + sort params) |

**Invalidation pattern:** After mutations (upload, delete, rename), invalidate the relevant `FutureProvider` with `ref.invalidate(provider)` to trigger re-fetch.