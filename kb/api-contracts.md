# API Contract Reference

All endpoints are under `http://<cubie-ip>:8443`. Auth via `Authorization: Bearer <jwt>`.

---

## Auth (`backend/app/routes/auth_routes.py`)

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| POST | `/api/v1/pair` | No | `{serial, key}` | `{token}` |
| POST | `/api/v1/users` | Yes | `{name, pin?}` | `{id, name}` |
| POST | `/api/v1/auth/logout` | Yes | — | 204 |
| PUT | `/api/v1/users/pin` | Yes | `{oldPin, newPin}` | 204 |

## System (`backend/app/routes/system_routes.py`)

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| GET | `/api/v1/system/info` | Yes | — | `{serial, name, ip, firmwareVersion}` |
| GET | `/api/v1/system/firmware` | Yes | — | `{current_version, latest_version, update_available, changelog, size_mb}` |
| POST | `/api/v1/system/update` | Yes | — | `{status}` |
| PUT | `/api/v1/system/name` | Yes | `{name}` | 204 |

## Monitor (`backend/app/routes/monitor_routes.py`)

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| WS | `/ws/monitor` | No | — | Stream: `{cpuPercent, ramPercent, tempCelsius, uptimeSeconds, networkUpMbps, networkDownMbps, storage: {totalGB, usedGB}}` every 2s |

## Storage (`backend/app/routes/storage_routes.py`)

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| GET | `/api/v1/storage/stats` | Yes | — | `{totalGB, usedGB}` |

> **Current issue:** Reports SD card stats (OS partition). Needs rework for external storage.

## Files (`backend/app/routes/file_routes.py`)

| Method | Path | Auth | Body/Query | Response |
|---|---|---|---|---|
| GET | `/api/v1/files/list?path=` | Yes | query: path | `[{name, path, isDirectory, sizeBytes, modified, mimeType}]` |
| POST | `/api/v1/files/mkdir` | Yes | `{path}` | `{path}` |
| DELETE | `/api/v1/files/delete?path=` | Yes | query: path | 204 |
| PUT | `/api/v1/files/rename` | Yes | `{oldPath, newName}` | 204 |
| POST | `/api/v1/files/upload?path=` | Yes | multipart: file | 201 |

## Family (`backend/app/routes/family_routes.py`)

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| GET | `/api/v1/users/family` | Yes | — | `[{id, name, isAdmin, folderSizeGB, avatarColor}]` |
| POST | `/api/v1/users/family` | Yes | `{name}` | `{id, name, isAdmin, folderSizeGB, avatarColor}` |
| DELETE | `/api/v1/users/family/{id}` | Yes | — | 204 |

## Services (`backend/app/routes/service_routes.py`)

| Method | Path | Auth | Body | Response |
|---|---|---|---|---|
| GET | `/api/v1/services` | Yes | — | `[{id, name, description, isEnabled}]` |
| POST | `/api/v1/services/{id}/toggle` | Yes | `{enabled}` | 204 |

---

## Planned: Storage Device Management

These endpoints will be added for external storage management:

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/storage/devices` | List connected block devices (USB, NVMe, SD) |
| POST | `/api/v1/storage/format` | Format a device (ext4) |
| POST | `/api/v1/storage/mount` | Mount a device as NAS root |
| POST | `/api/v1/storage/unmount` | Safely unmount (stop SMB first) |
| GET | `/api/v1/storage/scan` | Re-scan for newly connected devices |
| POST | `/api/v1/storage/eject` | Safe eject (unmount + power off USB port) |
