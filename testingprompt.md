# CubieCloud Backend Testing Prompt

> **Use this prompt in a Copilot agent chat when SSH'd into the Cubie via VS Code.**

---

I'm SSH'd into my Radxa Cubie A7Z (ARM, 8GB RAM) which runs the CubieCloud FastAPI backend. I need you to systematically test and debug all backend operations on the real hardware. The backend code is at `/opt/cubie/backend/` and runs as systemd service `cubie-backend`.

**Known issues: network toggle doesn't work, storage formatting doesn't work, storage mounting doesn't work.**

**Also: the Cubie likely runs Python 3.9, but the code uses `list[str]`, `dict[str, ...]`, `tuple[int, str, str]` lowercase generics in type annotations which require Python 3.10+. This is probably crashing the backend on import.**

## Step 0 — Environment check

```bash
python3 --version
cat /etc/os-release
systemctl status cubie-backend
journalctl -u cubie-backend --no-pager -n 100
```

Check the Python version. If it's 3.9 or lower, lowercase generics like `list[str]`, `dict[str, list[str]]`, `tuple[int, str, str]` will cause `TypeError` at import time. Every file needs `from __future__ import annotations` at the very top, or must use `List`, `Dict`, `Tuple` from `typing`.

**Files to check and fix for Python 3.9 compatibility:**

- `backend/app/routes/storage_routes.py` — uses `list[StorageDevice]`, `list[dict]`, etc. (partially fixed with `Optional` but still has lowercase generics)
- `backend/app/routes/service_routes.py` — uses `dict[str, list[str]]`, `list[ServiceInfo]`, `list[str]`
- `backend/app/routes/network_routes.py` — uses `list[str]`, `tuple[int, str, str]`
- `backend/app/routes/event_routes.py` — uses `list[asyncio.Queue]`, `list[AppEvent]`
- `backend/app/routes/file_routes.py` — check for lowercase generics too
- `backend/app/routes/monitor_routes.py` — check for lowercase generics too
- `backend/app/auth.py` — already uses `Optional` from typing, likely OK
- `backend/app/store.py` — check for lowercase generics
- `backend/app/config.py` — check for lowercase generics

**The fix:** Add `from __future__ import annotations` as the FIRST import (after docstring) in every `.py` file under `backend/app/`. This makes all annotations strings and avoids runtime `TypeError`. This is the cleanest fix.

## Step 1 — Get a JWT token for curl testing

```bash
# Get the pairing key and serial from the service env
grep CUBIE_ /etc/systemd/system/cubie-backend.service

# Pair to get a token (use actual values from above)
TOKEN=$(curl -sk https://localhost:8443/api/pair \
  -H "Content-Type: application/json" \
  -d '{"serial":"CUBIE-A7A-2025-001","key":"your-pairing-key"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
echo "Token: $TOKEN"
```

## Step 2 — Test network operations

```bash
# Check what network tools are available
which nmcli bluetoothctl ip ethtool

# Test GET /api/network/status
curl -sk https://localhost:8443/api/network/status \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# Test WiFi toggle
curl -sk -X POST https://localhost:8443/api/network/wifi \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}' -w "\nHTTP %{http_code}\n"

# Check nmcli directly
nmcli radio wifi
nmcli general status
nmcli device status

# Test Bluetooth toggle
curl -sk -X POST https://localhost:8443/api/network/bluetooth \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}' -w "\nHTTP %{http_code}\n"

# Check bluetoothctl directly
bluetoothctl show
```

## Step 3 — Test storage operations

```bash
# What block devices exist?
lsblk -J -b -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,LABEL,MODEL,TRAN,SERIAL

# Test GET /api/storage/devices
curl -sk https://localhost:8443/api/storage/devices \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# Test scan
curl -sk https://localhost:8443/api/storage/scan \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# Identify a USB device to test with (e.g. /dev/sda1)
# REPLACE /dev/sda1 with the actual device from lsblk output

# Test format (DESTRUCTIVE — only on test USB!)
curl -sk -X POST https://localhost:8443/api/storage/format \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"device":"/dev/sda1","label":"CubieNAS","confirmDevice":"/dev/sda1"}' \
  -w "\nHTTP %{http_code}\n"

# Try format directly to see if it's a permissions issue
sudo mkfs.ext4 -F -L CubieNAS /dev/sda1

# Test mount
curl -sk -X POST https://localhost:8443/api/storage/mount \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"device":"/dev/sda1"}' \
  -w "\nHTTP %{http_code}\n"

# Try mount directly
sudo mount /dev/sda1 /srv/nas

# Check storage state
cat /var/lib/cubie/storage.json
```

## Step 4 — Test service toggles

```bash
# List services
curl -sk https://localhost:8443/api/services \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# Toggle samba
curl -sk -X POST https://localhost:8443/api/services/samba/toggle \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}' -w "\nHTTP %{http_code}\n"

# Check if systemctl works for the cubie user
systemctl status smbd
sudo systemctl start smbd
```

## Step 5 — Check permissions

The backend runs as user `cubie`. Many operations need `sudo`:

```bash
# Check what user the backend runs as
grep User /etc/systemd/system/cubie-backend.service

# Check if cubie user has passwordless sudo
sudo -l -U cubie

# If cubie can't run mount/umount/mkfs/systemctl without sudo,
# that's why storage/service ops fail! Fix:
sudo visudo -f /etc/sudoers.d/cubie
```

Add this line:

```
cubie ALL=(ALL) NOPASSWD: /usr/bin/mount, /usr/bin/umount, /sbin/mkfs.ext4, /usr/bin/systemctl, /usr/bin/nmcli, /usr/bin/bluetoothctl, /sbin/udevadm, /usr/bin/lsof, /usr/bin/fuser
```

**Then update the backend code** — all `asyncio.create_subprocess_exec()` calls for privileged operations (mount, umount, mkfs.ext4, systemctl, nmcli radio, bluetoothctl power) need `"sudo"` prepended to the command.

Files that need `sudo` prepended:

- `storage_routes.py`: `mkfs.ext4`, `mount`, `umount`, `udevadm`
- `service_routes.py`: `systemctl start/stop`
- `network_routes.py`: `nmcli radio wifi on/off`, `bluetoothctl power on/off`
- `main.py`: auto-remount `mount` call

## Step 6 — TLS verification

```bash
# Check cert exists
ls -la /var/lib/cubie/tls/

# Check TLS fingerprint endpoint
curl -sk https://localhost:8443/api/tls/fingerprint

# Verify HTTPS works
curl -sk https://localhost:8443/api/system/info \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

## Step 7 — After fixes, restart and verify

```bash
sudo systemctl restart cubie-backend
journalctl -u cubie-backend -f --no-pager
```

Then re-run the failing curl commands from Steps 2-4 to confirm they work.

## Summary of likely root causes

1. **Python 3.9 compatibility** — lowercase generics crash on import → add `from __future__ import annotations` to all backend `.py` files
2. **Missing sudo** — `mount`, `mkfs.ext4`, `systemctl`, `nmcli radio`, `bluetoothctl power` need root → add sudoers config + prepend `"sudo"` in subprocess calls
3. **Missing tools** — `nmcli`/`bluetoothctl`/`lsof` may not be installed → install with `apt install network-manager bluez lsof`

**Please run these checks, identify ALL issues, and fix them. After fixing, re-test each endpoint with curl to confirm it works. Commit the fixes from the Cubie.**
