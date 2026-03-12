# API Contracts — AiHomeCloud

> Authoritative reference for every backend endpoint.
> Verified against source code as of 2025-07-25.
> **62 endpoints** across 14 route files.

---

## Auth (`auth_routes.py` — prefix `/api/v1`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/pair/qr` | None | Generate QR pairing payload with OTP |
| POST | `/pair` | None | Pair device with serial + key → JWT |
| POST | `/pair/complete` | None | Complete pairing with OTP verification |
| GET | `/auth/cert-fingerprint` | None | TLS certificate fingerprint for TOFU |
| GET | `/auth/users/names` | None | List user names + avatars (no auth needed for PIN screen) |
| POST | `/users` | User* | Create user (first user requires no auth, becomes admin) |
| POST | `/auth/login` | None | Login with name + PIN → access + refresh tokens |
| POST | `/auth/logout` | User | Invalidate current session |
| POST | `/auth/refresh` | None | Refresh access token (body: `refreshToken`) |
| PUT | `/users/pin` | User | Set/change PIN (body: `oldPin?`, `newPin`) |
| GET | `/users/me` | User | Get current user profile |
| PUT | `/users/me` | User | Update profile (body: `name?`, `iconEmoji?`) |
| DELETE | `/users/me` | User | Delete own account |
| DELETE | `/users/pin` | User | Remove PIN |

**Key models:**
- Request `POST /pair`: `{ serial: string, key: string }`
- Response `POST /pair`: `{ token: string }`
- Request `POST /auth/login`: `{ name: string, pin: string }`
- Response `POST /auth/login`: `{ accessToken, refreshToken, user: { id, name, isAdmin } }`
- Response `GET /auth/users/names`: `{ users: [{ name, has_pin, icon_emoji }] }`
- Response `GET /users/me`: `{ id, name, icon_emoji, has_pin, is_admin }`

---

## System (`system_routes.py` — prefix `/api/v1/system`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/info` | User | Device info: serial, name, IP, firmware, board model |
| GET | `/firmware` | User | Firmware version check (current, latest, changelog) |
| POST | `/update` | Admin | Trigger OTA firmware update (TODO: not yet implemented) |
| PUT | `/name` | Admin | Rename device (body: `{ name }`) |
| POST | `/shutdown` | Admin | Shutdown the Cubie |
| POST | `/reboot` | Admin | Reboot the Cubie |

**Key models:**
- Response `GET /info` (`CubieDevice`): `{ serial, name, ip, firmwareVersion, boardModel }`

---

## Monitor (`monitor_routes.py` — WebSocket)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| WS | `/ws/monitor` | Token (query param) | Real-time system stats stream (~2s interval) |

**Stream payload:**
```json
{
  "cpuPercent": 12.5,
  "ramPercent": 45.2,
  "tempCelsius": 52.0,
  "uptimeSeconds": 86400,
  "networkUpMbps": 1.2,
  "networkDownMbps": 5.8,
  "networkInterface": "eth0",
  "storage": { "totalGB": 500.0, "usedGB": 123.4 }
}
```

---

## Files (`file_routes.py` — prefix `/api/v1/files`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/list` | User | Paginated file listing with sort |
| POST | `/mkdir` | User | Create directory (body: `{ path }`) |
| DELETE | `/delete` | User | Move file/folder to trash (query: `path`) |
| GET | `/trash` | User | List trash items |
| POST | `/trash/{item_id}/restore` | User | Restore item from trash |
| DELETE | `/trash/{item_id}` | User | Permanently delete trash item |
| GET | `/trash/prefs` | User | Get trash preferences (auto-delete toggle) |
| PUT | `/trash/prefs` | User | Set trash preferences (body: `{ autoDelete: bool }`) |
| PUT | `/rename` | User | Rename file/folder (body: `{ oldPath, newName }`) |
| POST | `/upload` | User | Upload file (multipart, query: `path`) |
| GET | `/download` | User | Download file (query: `path`) |
| GET | `/search` | User | FTS5 document search (query: `q`, `limit?`) |
| POST | `/sort-now` | User | Auto-sort files by type (query: `path`) |
| GET | `/roots` | User | List storage roots with device info |

**Key models:**
- Response `GET /list`: `{ items: [FileItem], totalCount, page, pageSize }`
- `FileItem`: `{ name, path, isDirectory, sizeBytes, modified, mimeType? }`
- `TrashItem`: `{ id, originalPath, trashPath, filename, deletedAt, sizeBytes, deletedBy }`
- Query params `GET /list`: `path`, `page`, `page_size`, `sort_by`, `sort_dir`

---

## Family (`family_routes.py` — prefix `/api/v1/users`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/family` | User | List all family members with folder sizes |
| POST | `/family` | Admin | Add family member (body: `{ name }`) |
| DELETE | `/family/{user_id}` | Admin | Remove family member |

**Key models:**
- `FamilyUser`: `{ id, name, isAdmin, folderSizeGB, avatarColor, iconEmoji }`

---

## Services (`service_routes.py` — prefix `/api/v1/services`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/` | User | List all managed services |
| POST | `/{service_id}/toggle` | Admin | Enable/disable service (body: `{ enabled: bool }`) |

**Key models:**
- `ServiceInfo`: `{ id, name, description, isEnabled }`
- Service IDs: `ssh`, `nfs`, `media` (controls smbd + nmbd + minidlna)

---

## Storage (`storage_routes.py` — prefix `/api/v1/storage`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/devices` | User | List all storage devices (excludes OS disk) |
| GET | `/scan` | User | Re-scan and list storage devices |
| POST | `/smart-activate` | Admin | Auto-detect best action: mount, or format if needed |
| GET | `/check-usage` | User | Check for mount blockers before unmount |
| POST | `/format` | Admin | Format device as ext4 (body: `device`, `label`, `confirm_device`) |
| POST | `/mount` | Admin | Mount storage device (body: `{ device }`) |
| POST | `/unmount` | Admin | Safe unmount with service stop (query: `force?`) |
| POST | `/eject` | Admin | Unmount + power off USB port (body: `{ device }`) |
| GET | `/stats` | User | Total/used storage in GB |

**Key models:**
- `StorageDevice`: `{ name, path, sizeBytes, sizeDisplay, fstype?, label?, model?, transport, mounted, mountPoint?, isNasActive, isOsDisk, displayName, bestPartition? }`
- `displayName` is user-friendly — never shows `/dev/` paths

**Format flow:** `POST /format` returns `{ jobId }` → poll `GET /api/v1/jobs/{jobId}` for status.

---

## Network (`network_routes.py` — prefix `/api/v1`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/network/status` | User | Full network status (Wi-Fi, LAN, hotspot, BT) |
| GET | `/network/wifi` | User | Wi-Fi connection details |
| PUT | `/network/wifi` | User | Enable/disable Wi-Fi (body: `{ enabled: bool }`) |

**Key models:**
- `NetworkStatus`: `{ wifiEnabled, wifiConnected, wifiSsid?, wifiIp?, hotspotEnabled, hotspotSsid?, bluetoothEnabled, lanConnected, lanIp?, lanSpeed?, gateway?, dns? }`

---

## AdGuard (`adguard_routes.py` — prefix `/api/v1/adguard`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/stats` | User | Ad blocking statistics |
| POST | `/pause` | User | Pause protection (body: `{ minutes: 5|30|60 }`) |
| POST | `/toggle` | Admin | Enable/disable protection (body: `{ enabled: bool }`) |

**Response `GET /stats`:** `{ dns_queries, blocked_today, blocked_percent, top_blocked, protection_enabled }`

---

## Tailscale (`tailscale_routes.py` — prefix `/api/v1/system`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/tailscale-status` | User | VPN connection status |
| POST | `/tailscale-up` | Admin | Bring up Tailscale VPN |

**Response `GET /tailscale-status`:** `{ installed, connected, tailscaleIp? }`

---

## Telegram (`telegram_routes.py` — prefix `/api/v1/telegram`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/config` | Admin | Bot configuration and status |
| POST | `/config` | Admin | Set bot token and local API config |
| DELETE | `/linked/{chat_id}` | Admin | Unlink a Telegram chat |

**Request `POST /config`:** `{ bot_token, api_id?, api_hash?, local_api_enabled? }`
**Response `GET /config`:** `{ configured, token_preview, linked_count, bot_running, local_api_enabled, api_id, max_file_mb }`

---

## Telegram Upload (`telegram_upload_routes.py`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/telegram-upload/{token}` | Token in URL | HTML upload form for browser |
| POST | `/api/telegram-upload/{token}` | Token in URL | File upload via browser form |

Token-based auth — no JWT required. Token is single-use, generated by the Telegram bot.

---

## Jobs (`jobs_routes.py` — prefix `/api/v1/jobs`)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/{job_id}` | User | Poll long-running job status |

**Response:** `{ id, status, startedAt, result?, error? }`
Used by: storage format operations.

---

## Events (`event_routes.py` — WebSocket)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| WS | `/ws/events` | Token (query param) | Real-time notification stream |

**Stream payload:**
```json
{
  "type": "storage_mounted",
  "title": "Storage Ready",
  "body": "NAS storage has been mounted",
  "severity": "info",
  "timestamp": 1700000000.0,
  "data": {}
}
```

Severity levels: `info`, `warning`, `error`.
