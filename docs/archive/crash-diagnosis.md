# Cubie Crash Diagnosis & Fix Prompt

**Purpose:** Paste this into a Copilot/terminal session immediately after SSH reconnection to diagnose why the Cubie freezes and apply permanent fixes.

---

## Step 1: Immediate Diagnostics (run FIRST, before anything else)

```bash
# Memory status
free -h

# Check for OOM kills in kernel log
dmesg | grep -i "oom\|out of memory\|killed process" | tail -20

# Check temperature (overheating?)
cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null || echo "No thermal zones found"

# System load
uptime

# Current swap status
swapon --show

# Top memory consumers RIGHT NOW
ps aux --sort=-%mem | head -15

# Check if VS Code server is running and how much RAM
ps aux | grep -i "vscode\|code-server\|copilot" | grep -v grep

# Recent kernel messages (crashes, hardware errors)
dmesg | tail -30

# Disk space (full disk can cause freezes too)
df -h

# Check systemd journal for recent errors
journalctl -p err --since "1 hour ago" --no-pager | tail -30
```

---

## Step 2: Fix 1 — Thermal Management (MOST CRITICAL)

The tiny heatsink can't dissipate enough heat under sustained VS Code + backend load.

### Diagnose thermal status
```bash
# Read all thermal zones (temps in millidegrees — divide by 1000)
for zone in /sys/class/thermal/thermal_zone*/; do
    TEMP=$(cat ${zone}temp 2>/dev/null)
    TYPE=$(cat ${zone}type 2>/dev/null)
    echo "$TYPE: $((TEMP/1000))°C (raw: $TEMP)"
done

# Check thermal trip points (where throttling/shutdown kicks in)
for zone in /sys/class/thermal/thermal_zone*/; do
    TYPE=$(cat ${zone}type 2>/dev/null)
    echo "=== $TYPE ==="
    for trip in ${zone}trip_point_*_temp; do
        [ -f "$trip" ] && echo "  $(basename $trip): $(($(cat $trip)/1000))°C"
    done
done

# Check current CPU frequency (throttled = lower than max)
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null

# Check kernel thermal messages
dmesg | grep -i "thermal\|temperature\|trip\|throttl\|overheat" | tail -20
```

### Fix: Limit CPU frequency to reduce heat
```bash
# See available frequencies or governors
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies 2>/dev/null
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null

# Option A: Switch to powersave governor (reduces max freq)
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "powersave" | sudo tee $cpu
done

# Option B: Hard-cap CPU frequency (e.g., to 1.2 GHz instead of max)
# First check what frequencies are available, then pick one below max:
# cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
# Then set it (example — replace 1200000 with an actual available freq):
# for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
#     echo "1200000" | sudo tee $cpu
# done
```

### Fix: Make CPU governor persistent across reboots
```bash
# Create a startup script to set powersave governor on boot
sudo tee /etc/rc.local << 'EOF'
#!/bin/bash
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "powersave" > $cpu
done
exit 0
EOF
sudo chmod +x /etc/rc.local
```

### Fix: Add thermal logging to the monitor script
```bash
# This will be included in cubie-monitor.sh below — it logs temps every 5 min
# and warns if approaching critical threshold
```

### Physical improvements (highly recommended)
- **Bigger heatsink** — get a 40x40mm aluminum heatsink with thermal pad
- **Small 5V fan** — even a 30mm fan makes a huge difference on ARM SoCs
- **Ventilation** — don't enclose the board; keep it in open air
- **Orientation** — heatsink fins pointing up for natural convection
- **Ambient temp** — keep away from other heat sources

---

## Step 3: Fix 2 — Add 4 GB Swap File

The Cubie has 8 GB RAM and likely no swap. VS Code Remote SSH + Copilot agent can easily consume 4+ GB alone, leaving nothing for the system.

```bash
# Check if swap already exists
swapon --show

# If no swap exists, create one:
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Verify it's active
free -h

# Make it permanent (survives reboot)
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Set swappiness (prefer keeping stuff in RAM but use swap when needed)
echo 'vm.swappiness=30' | sudo tee -a /etc/sysctl.conf
sudo sysctl vm.swappiness=30
```

---

## Step 4: Fix 3 — SSH Keepalive (prevent stale connections)

```bash
# Server-side SSH keepalive config
sudo tee -a /etc/ssh/sshd_config << 'EOF'

# Keepalive settings to prevent disconnects
ClientAliveInterval 30
ClientAliveCountMax 5
TCPKeepAlive yes
EOF

sudo systemctl restart sshd
```

**Also on your Windows machine** — add to `~/.ssh/config`:
```
Host cubie
    HostName 192.168.0.212
    User cubie
    ServerAliveInterval 15
    ServerAliveCountMax 4
    TCPKeepAlive yes
```

---

## Step 5: Fix 4 — VS Code Server Memory Limits

In VS Code on Windows, add to your Settings JSON (`Ctrl+Shift+P` → "Preferences: Open User Settings (JSON)"):

```json
{
    "remote.SSH.maxReconnectionAttempts": 3,
    "remote.SSH.connectTimeout": 30,
    "extensions.experimental.affinity": {
        "github.copilot": 1
    }
}
```

When connecting via SSH, you can also limit Node.js memory for the VS Code server:
```bash
# Add to ~/.bashrc on the Cubie
export NODE_OPTIONS="--max-old-space-size=512"
```

---

## Step 6: Fix 5 — Persistent Monitoring (optional but recommended)

Create a lightweight monitoring script that logs resource usage, temperature, and can auto-kill runaway processes:

```bash
sudo tee /usr/local/bin/cubie-monitor.sh << 'SCRIPT'
#!/bin/bash
# Cubie Resource & Thermal Monitor
# Logs memory + temperature and takes action on critical thresholds

LOG="/var/log/cubie-monitor.log"
MIN_FREE_MB=500
MAX_TEMP_C=80        # Warn threshold (degrees C)
CRITICAL_TEMP_C=85   # Kill VS Code server above this temp

get_temp() {
    # Read primary thermal zone temp in degrees C
    local raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    echo $((raw / 1000))
}

while true; do
    FREE_MB=$(free -m | awk '/^Mem:/{print $7}')
    TEMP_C=$(get_temp)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # THERMAL CHECK — most critical
    if [ "$TEMP_C" -ge "$CRITICAL_TEMP_C" ]; then
        echo "$TIMESTAMP CRITICAL TEMP: ${TEMP_C}°C — killing VS Code server!" >> "$LOG"
        pkill -9 -f "vscode-server" 2>/dev/null
        pkill -9 -f "copilot" 2>/dev/null
        # Also throttle CPU immediately
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo "powersave" > $cpu 2>/dev/null
        done
    elif [ "$TEMP_C" -ge "$MAX_TEMP_C" ]; then
        echo "$TIMESTAMP WARNING: High temp: ${TEMP_C}°C" >> "$LOG"
    fi
    
    # MEMORY CHECK
    if [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
        echo "$TIMESTAMP WARNING: Low memory! Free: ${FREE_MB}MB, Temp: ${TEMP_C}°C" >> "$LOG"
        ps aux --sort=-%mem | head -5 >> "$LOG"
        
        VSCODE_PID=$(pgrep -f "vscode-server" | head -1)
        if [ -n "$VSCODE_PID" ]; then
            echo "$TIMESTAMP KILLING VS Code server (PID $VSCODE_PID) to free memory" >> "$LOG"
            kill -9 "$VSCODE_PID"
        fi
    fi
    
    # Log every 5 minutes for trend analysis
    if [ $(($(date +%s) % 300)) -lt 10 ]; then
        echo "$TIMESTAMP Temp: ${TEMP_C}°C | Mem free: ${FREE_MB}MB | $(uptime)" >> "$LOG"
    fi
    
    sleep 10
done
SCRIPT

sudo chmod +x /usr/local/bin/cubie-monitor.sh
```

Create the systemd service:
```bash
sudo tee /etc/systemd/system/cubie-monitor.service << 'SERVICE'
[Unit]
Description=Cubie Resource Monitor
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cubie-monitor.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable cubie-monitor
sudo systemctl start cubie-monitor
```

---

## Step 7: Verification

After applying all fixes, verify:

```bash
# Temperature right now
for zone in /sys/class/thermal/thermal_zone*/; do
    TEMP=$(cat ${zone}temp 2>/dev/null)
    TYPE=$(cat ${zone}type 2>/dev/null)
    echo "$TYPE: $((TEMP/1000))°C"
done

# CPU governor is powersave
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Swap is active
free -h

# Monitor service is running
sudo systemctl status cubie-monitor

# SSH keepalive is configured
grep -i "clientalive\|keepalive" /etc/ssh/sshd_config

# Backend is still running fine
sudo systemctl status cubie-backend
curl -sk https://localhost:8443/health

# Check monitor log (should show temp readings)
tail -20 /var/log/cubie-monitor.log
```

---

## Post-Crash Analysis

If it crashes again, run these IMMEDIATELY after reconnecting:

```bash
# Check temperature RIGHT NOW (if it's hot, thermal was the cause)
for zone in /sys/class/thermal/thermal_zone*/; do
    TEMP=$(cat ${zone}temp 2>/dev/null)
    TYPE=$(cat ${zone}type 2>/dev/null)
    echo "$TYPE: $((TEMP/1000))°C"
done

# Check for thermal shutdown in kernel log
dmesg | grep -i "thermal\|overheat\|trip\|critical.*temp\|oom\|killed" | tail -20

# What was running?
last reboot | head -5

# Journal from before the crash
journalctl --since "30 min ago" -p warning --no-pager | head -50

# Check monitor log for temp trend leading up to crash
cat /var/log/cubie-monitor.log | tail -50
```

---

## Summary of Root Cause

**Most likely: Thermal shutdown.** The Radxa Cubie A7Z with a tiny heatsink overheats under sustained CPU load from VS Code Remote SSH server + Copilot agent + cubie-backend. ARM SoCs will thermal throttle first, then hard-freeze or shutdown if temps exceed the critical threshold (typically 85-105°C depending on SoC).

**Secondary possibility:** OOM (Out of Memory) kill — VS Code server + Copilot can consume 3-4 GB, exhausting the 8 GB RAM.

**Priority of fixes:**
1. **Thermal management** — better cooling + CPU frequency limits (most critical)
2. **Swap file** — breathing room for memory spikes
3. **Reduce VS Code overhead** — use plain SSH when possible
