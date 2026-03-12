# CubieCloud — Setup & Pairing Instructions

## Part 1: Backend Setup on a Fresh Cubie A7Z

### Prerequisites
- Radxa Cubie A7Z with a freshly flashed SD card (Debian/Ubuntu ARM image)
- Cubie connected to your local network (Ethernet or Wi-Fi)
- SSH access to the Cubie (default user: `cubie`)

### Step 1 — SSH into the Cubie

```bash
ssh cubie@<cubie-ip>
# Find the IP from your router's DHCP table, or plug in a monitor
```

### Step 2 — Install system dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-venv python3-pip openssl \
    samba nfs-kernel-server avahi-daemon lsof udevadm
```

| Package | Why |
|---|---|
| `python3`, `python3-venv`, `python3-pip` | Backend runtime |
| `openssl` | Auto-generates self-signed TLS cert on first boot |
| `samba` | SMB file sharing (Windows/Mac) |
| `nfs-kernel-server` | NFS file sharing (Linux/Mac) |
| `avahi-daemon` | mDNS discovery (`_cubie-nas._tcp`) |
| `lsof` | Open file-handle check before unmount |
| `udevadm` | USB hot-plug detection / rescan |

### Step 3 — Create the system user (if not already present)

```bash
sudo useradd -r -m -s /bin/bash cubie 2>/dev/null || true
```

### Step 4 — Create required directories

```bash
# NAS mount point + default folders
sudo mkdir -p /srv/nas/personal /srv/nas/family /srv/nas/entertainment

# Backend persistent data directory
sudo mkdir -p /var/lib/cubie/tls

# Application code directory
sudo mkdir -p /opt/cubie/backend

# Set ownership
sudo chown -R cubie:cubie /srv/nas /var/lib/cubie /opt/cubie
```

### Step 5 — Deploy backend code

From your **development machine** (Windows/Mac):

```bash
# From the repo root
scp -r backend/* cubie@<cubie-ip>:/opt/cubie/backend/
```

Or, on the Cubie, clone the repo directly:

```bash
cd /opt/cubie
git clone https://github.com/nerdyparas/AiHomeCloud.git
ln -s /opt/cubie/AiHomeCloud/backend /opt/cubie/backend
```

### Step 6 — Create Python virtual environment & install deps

```bash
cd /opt/cubie/backend
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### Step 7 — Configure environment

Edit the systemd service file to set your **unique** pairing credentials:

```bash
sudo cp /opt/cubie/backend/cubie-backend.service /etc/systemd/system/
sudo nano /etc/systemd/system/cubie-backend.service
```

**Change these lines** (under `[Service]`):

```ini
Environment=CUBIE_DEVICE_SERIAL=CUBIE-A7A-2025-001   # Your device serial
Environment=CUBIE_PAIRING_KEY=your-pairing-key        # Change to a real secret
Environment=CUBIE_NAS_ROOT=/srv/nas
Environment=CUBIE_DATA_DIR=/var/lib/cubie
Environment=CUBIE_TLS_ENABLED=true
```

> **Security note:** The JWT secret is auto-generated on first boot and saved to
> `/var/lib/cubie/jwt_secret`. You do NOT need to set `CUBIE_JWT_SECRET` manually.

### Step 8 — Configure polkit for NetworkManager

The backend runs as the `radxa` user (not root). Wi-Fi operations (connect, disconnect, toggle, hotspot) require polkit authorization for NetworkManager.

> **Note:** Radxa OS ships polkit **0.105**, which uses the legacy `.pkla` INI format — **not** the `.rules` JavaScript format (that's polkit 0.106+).

```bash
sudo tee /etc/polkit-1/localauthority/50-local.d/50-cubie-network.pkla << 'EOF'
[Allow NetworkManager for cubie backend]
Identity=unix-group:sudo;unix-group:netdev
Action=org.freedesktop.NetworkManager.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

sudo systemctl restart polkit
```

`ResultInactive=yes` is required because the backend runs as a daemon (no interactive session).

### Step 9 — Register mDNS advertisement

This enables instant LAN discovery (~1-2 s) in the app. Without it, the app
falls back to a slower /24 TCP subnet scan.

```bash
sudo cp backend/scripts/aihomecloud-mdns.service /etc/avahi/services/aihomecloud.service
sudo systemctl reload avahi-daemon
```

Verify it's broadcasting:
```bash
sudo journalctl -u avahi-daemon -n 5 --no-pager
# Should show: Service "AiHomeCloud on <hostname>" successfully established.
```

### Step 10 — Start the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable cubie-backend
sudo systemctl start cubie-backend
```

### Step 10 — Verify

```bash
# Check service status
sudo systemctl status cubie-backend

# Check logs
sudo journalctl -u cubie-backend -f --no-pager -n 50

# Health check (from the Cubie itself)
curl -k https://localhost:8443/api/health
# Expected: {"status": "ok"}
```

### What happens on first boot

The backend's startup lifespan hook automatically:

1. Creates `/var/lib/cubie/` subdirectories if missing
2. Generates a random JWT secret → saves to `/var/lib/cubie/jwt_secret`
3. Auto-generates a self-signed TLS certificate (10-year validity) → `/var/lib/cubie/tls/cert.pem` + `key.pem`
4. Starts listening on `https://0.0.0.0:8443`
5. Registers mDNS service `_cubie-nas._tcp` via avahi (if available)

---

## Part 2: QR Code Pairing Flow

### How pairing works (end to end)

```
┌──────────────┐                           ┌──────────────┐
│  Cubie A7Z   │                           │  Flutter App  │
│  (backend)   │                           │  (Android)    │
├──────────────┤                           ├──────────────┤
│              │                           │              │
│ 1. GET /api/v1/pair/qr                   │              │
│    → generates QR payload string         │              │
│    → generates 6-digit OTP               │              │
│    → stores OTP hash in pairing.json     │              │
│    → returns qrValue URL                 │              │
│                                          │              │
│ 2. Display QR code on screen / web UI    │              │
│    (QR encodes the cubie:// URL)         │              │
│                                          │              │
│              │                           │ 3. User opens app
│              │                           │    → Onboarding flow
│              │                           │    → QR scan screen
│              │                           │    → Camera scans QR
│              │                           │              │
│              │                           │ 4. App parses:
│              │                           │    cubie://pair?
│              │                           │      serial=...
│              │                           │      &key=...
│              │                           │      &host=...
│              │                           │      &expiresAt=...
│              │                           │              │
│              │  POST /api/v1/pair        │ 5. App calls pair
│              │  {serial, key}            │    endpoint with
│              │  ◄─────────────────────── │    parsed credentials
│              │                           │              │
│ 6. Validate  │                           │              │
│    serial +  │  {token: "jwt..."}        │              │
│    key match │  ──────────────────────►  │ 7. App stores JWT
│              │                           │    + device info
│              │                           │    in SharedPrefs
│              │                           │              │
│              │                           │ 8. Navigate to
│              │                           │    main dashboard
└──────────────┘                           └──────────────┘
```

### QR payload format

```
cubie://pair?serial=CUBIE-A7A-2025-001&key=your-pairing-key&host=cubie-CUBIE-A7A-2025-001.local&expiresAt=1741276800
```

| Param | Purpose |
|---|---|
| `serial` | Device identity — must match `CUBIE_DEVICE_SERIAL` env var |
| `key` | Pairing secret — must match `CUBIE_PAIRING_KEY` env var |
| `host` | mDNS hostname for network discovery |
| `expiresAt` | Unix timestamp — QR valid for 5 minutes |

### Backend endpoints involved

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/pair/qr` | GET | Generate QR payload + OTP (no auth required) |
| `/api/v1/pair` | POST | Fast pair with serial + key → returns JWT |
| `/api/v1/pair/complete` | POST | Full pair with serial + key + OTP → returns JWT |
| `/api/v1/auth/cert-fingerprint` | GET | TLS cert SHA-256 for pinning |

### Flutter side (what the app does)

1. **QR scan screen** (`lib/screens/onboarding/qr_scan_screen.dart`) uses `mobile_scanner` to read the QR code
2. Parses the `cubie://pair?...` URI into a `QrPairPayload` model
3. Stores payload in `qrPayloadProvider` (Riverpod)
4. **Discovery screen** (`lib/screens/onboarding/discovery_screen.dart`) reads the payload and:
   - Calls `ApiService.pairDevice(serial, key)` → `POST /api/v1/pair`
   - Receives JWT token
   - Fetches TLS cert fingerprint for future pinning
   - Saves everything to SharedPreferences
5. Navigates to dashboard

---

## Part 3: QR Code Generation for Testing

Since the QR code is generated by the **backend** (not a physical display), you have several options for testing:

### Option A — curl the QR endpoint directly (simplest)

```bash
# On the Cubie (or from any machine on the same network)
curl -k https://<cubie-ip>:8443/api/v1/pair/qr | python3 -m json.tool
```

Response:
```json
{
    "qrValue": "cubie://pair?serial=CUBIE-A7A-2025-001&key=your-pairing-key&host=cubie-CUBIE-A7A-2025-001.local&expiresAt=1741277100",
    "serial": "CUBIE-A7A-2025-001",
    "ip": "192.168.0.212",
    "host": "cubie-CUBIE-A7A-2025-001.local",
    "expiresAt": 1741277100
}
```

Take the `qrValue` string and generate a QR image from it (next options).

### Option B — Generate a QR image with Python (on the Cubie or your PC)

```bash
pip install qrcode[pil]
```

```python
import qrcode, requests, json

# Fetch the payload from the running backend
r = requests.get("https://<cubie-ip>:8443/api/v1/pair/qr", verify=False)
qr_value = r.json()["qrValue"]

# Generate QR image
img = qrcode.make(qr_value)
img.save("cubie-pair.png")
print(f"QR saved. Scan cubie-pair.png with the app.")
print(f"Payload: {qr_value}")
```

Open `cubie-pair.png` on any screen and scan it with the Flutter app.

### Option C — Use an online QR generator (quick & dirty)

1. Run `curl -k https://<cubie-ip>:8443/api/v1/pair/qr`
2. Copy the `qrValue` string
3. Paste it into any QR code generator (e.g., browser search "qr code generator")
4. Scan the result with the Flutter app

> **Note:** The QR payload contains the pairing key, so don't use public QR generators for production secrets. Fine for development/testing.

### Option D — Skip QR entirely (dev shortcut)

The app already has a dev shortcut in `lib/main.dart` that bypasses QR scanning:

```dart
const devMode = true;
if (devMode && !prefs.containsKey(CubieConstants.prefIsSetupDone)) {
    const cubieIp = '192.168.0.212';
    final token = await ApiService.instance
        .pairDevice('CUBIE-A7A-2025-001', 'your-pairing-key',
            hostOverride: cubieIp);
    // ... stores token, serial, name in SharedPreferences
}
```

This auto-pairs on first launch without scanning anything. Set `devMode = false` to test the real QR flow.

### Option E — curl pair directly (no QR, no app)

Test just the pairing API without any QR or Flutter involvement:

```bash
# Fast pair (no OTP)
curl -k -X POST https://<cubie-ip>:8443/api/v1/pair \
  -H "Content-Type: application/json" \
  -d '{"serial": "CUBIE-A7A-2025-001", "key": "your-pairing-key"}'

# Response: {"token": "eyJ..."}
```

Use the returned token for all subsequent API calls:

```bash
TOKEN="eyJ..."
curl -k https://<cubie-ip>:8443/api/v1/system/info \
  -H "Authorization: Bearer $TOKEN"
```

---

## Quick Reference: File Locations on the Cubie

```
/opt/cubie/backend/              # Backend source + venv
/etc/systemd/system/cubie-backend.service  # Systemd unit

/var/lib/cubie/                  # Persistent data (owned by cubie:cubie)
├── jwt_secret                   # Auto-generated JWT signing key
├── users.json                   # User accounts
├── storage.json                 # Mount state (activeDevice, fstype, etc.)
├── services.json                # NAS service toggles
├── tokens.json                  # Refresh token records
├── device.json                  # Device display name
├── pairing.json                 # OTP hash + expiry (5 min TTL)
└── tls/
    ├── cert.pem                 # Self-signed TLS certificate
    └── key.pem                  # TLS private key

/srv/nas/                        # NAS mount point (external storage)
├── personal/{username}/         # Per-user private folders
├── family/                      # Family shared folder
└── entertainment/               # Entertainment media (Music, Videos, etc.)
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `curl: (7) Failed to connect` | Check `sudo systemctl status cubie-backend` and firewall (`sudo ufw allow 8443`) |
| `403 Unknown serial` | Serial in curl/app doesn't match `CUBIE_DEVICE_SERIAL` in service file |
| `403 Invalid pairing key` | Key doesn't match `CUBIE_PAIRING_KEY` in service file |
| TLS cert errors in Flutter | App uses `_CubieHttpOverrides` to trust self-signed certs — ensure it's active |
| `lsblk` not found | Install `util-linux`: `sudo apt install util-linux` |
| Backend won't start | Check `sudo journalctl -u cubie-backend -e` for Python tracebacks |
| QR expired | QR payloads expire after 5 minutes — re-fetch from `/api/v1/pair/qr` |
