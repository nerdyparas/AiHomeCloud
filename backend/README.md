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
sudo mkdir -p /var/lib/cubie
sudo chown -R $USER:$USER /srv/nas /var/lib/cubie

# Run the server
uvicorn app.main:app --host 0.0.0.0 --port 8443 --reload
```

API docs will be at: **http://\<cubie-ip\>:8443/docs**

## Deploy on the Cubie A7Z

```bash
# 1. Copy backend/ to the Cubie
scp -r backend/ cubie@<cubie-ip>:/opt/cubie/backend/

# 2. SSH into the Cubie
ssh cubie@<cubie-ip>

# 3. Set up Python venv
cd /opt/cubie/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 4. Create NAS storage directories
sudo mkdir -p /srv/nas/{shared,personal}
sudo mkdir -p /var/lib/cubie
sudo chown -R cubie:cubie /srv/nas /var/lib/cubie

# 5. Install systemd service
sudo cp cubie-backend.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable cubie-backend
sudo systemctl start cubie-backend

# 6. Check status
sudo systemctl status cubie-backend
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CUBIE_HOST` | `0.0.0.0` | Bind address |
| `CUBIE_PORT` | `8443` | Bind port |
| `CUBIE_JWT_SECRET` | `change-me-in-production` | JWT signing secret |
| `CUBIE_DEVICE_SERIAL` | `CUBIE-A7A-2025-001` | Device serial number |
| `CUBIE_PAIRING_KEY` | `default-pair-key` | Pairing key (from QR code) |
| `CUBIE_NAS_ROOT` | `/srv/nas` | Root directory for file storage |
| `CUBIE_DATA_DIR` | `/var/lib/cubie` | Directory for config JSON files |
| `CUBIE_TOTAL_STORAGE_GB` | `500.0` | Total storage capacity for display |

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
