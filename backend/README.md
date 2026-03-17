# AiHomeCloud Backend

FastAPI backend for the AiHomeCloud home NAS, designed to run on the **Radxa Cubie A7A** (ARM, 8 GB RAM).

## Quick Start (Development)

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Create NAS directories (development)
sudo mkdir -p /srv/nas/{shared,personal}
sudo mkdir -p /var/lib/aihomecloud
sudo chown -R $USER:$USER /srv/nas /var/lib/aihomecloud

# Run the server
uvicorn app.main:app --host 0.0.0.0 --port 8443 --reload
```

API docs will be at: **http://\<device-ip\>:8443/docs**

## Deploy on the Cubie A7Z

```bash
# 1. Copy backend/ to the Cubie
scp -r backend/ admin@<device-ip>:/opt/aihomecloud/backend/

# 2. SSH into the Cubie
ssh admin@<device-ip>

# 3. Set up Python venv
cd /opt/aihomecloud/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 4. Create NAS storage directories
sudo mkdir -p /srv/nas/{shared,personal}
sudo mkdir -p /var/lib/aihomecloud
sudo chown -R aihomecloud:aihomecloud /srv/nas /var/lib/aihomecloud

# 5. Install systemd service
sudo cp aihomecloud.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable aihomecloud
sudo systemctl start aihomecloud

# 6. Check status
sudo systemctl status aihomecloud
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `AHC_HOST` | `0.0.0.0` | Bind address |
| `AHC_PORT` | `8443` | Bind port |
| `AHC_JWT_SECRET` | `change-me-in-production` | JWT signing secret |
| `AHC_DEVICE_SERIAL | AHC-A7A-2025-001` | Device serial number |
| `AHC_PAIRING_KEY` | `default-pair-key` | Pairing key (from QR code) |
| `AHC_NAS_ROOT` | `/srv/nas` | Root directory for file storage |
| `AHC_DATA_DIR` | `/var/lib/aihomecloud` | Directory for config JSON files |
| `AHC_TOTAL_STORAGE_GB` | `500.0` | Total storage capacity for display |

## API Endpoints

### Auth
- `POST /api/pair` — Pair device (serial + key → JWT)
- `POST /api/users` — Create user
- `POST /api/auth/logout` — Logout
- `PUT  /api/users/pin` — Change PIN

### System
- `GET  /api/system/info` — Device info
- `GET  /api/system/firmware` — Check firmware update
- `POST /api/system/update` — Trigger OTA update
- `PUT  /api/system/name` — Rename device

### Monitor
- `WS   /ws/monitor` — Live system stats (CPU, RAM, temp, network, storage)

### Files
- `GET    /api/files/list?path=...` — List directory
- `POST   /api/files/mkdir` — Create folder
- `DELETE /api/files/delete?path=...` — Delete file/folder
- `PUT    /api/files/rename` — Rename file/folder
- `POST   /api/files/upload?path=...` — Upload file (multipart)

### Storage
- `GET /api/storage/stats` — Disk usage

### Family
- `GET    /api/users/family` — List family members
- `POST   /api/users/family` — Add family member
- `DELETE /api/users/family/{id}` — Remove family member

### Services
- `GET  /api/services` — List NAS services
- `POST /api/services/{id}/toggle` — Enable/disable service
