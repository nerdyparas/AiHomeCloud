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

## Step 2: Fix 1 — Add 4 GB Swap File (CRITICAL)

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

## Step 3: Fix 2 — SSH Keepalive (prevent stale connections)

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

## Step 4: Fix 3 — VS Code Server Memory Limits

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

## Step 5: Fix 4 — Persistent Monitoring (optional but recommended)

Create a lightweight monitoring script that logs resource usage and can auto-kill runaway processes:

```bash
sudo tee /usr/local/bin/cubie-monitor.sh << 'SCRIPT'
#!/bin/bash
# Cubie Resource Monitor
# Logs memory usage and kills VS Code server if memory drops below 500MB

LOG="/var/log/cubie-monitor.log"
MIN_FREE_MB=500

while true; do
    FREE_MB=$(free -m | awk '/^Mem:/{print $7}')
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
        echo "$TIMESTAMP WARNING: Low memory! Free: ${FREE_MB}MB" >> "$LOG"
        
        # Log top memory consumers
        ps aux --sort=-%mem | head -5 >> "$LOG"
        
        # Kill VS Code server if it's the culprit (it will auto-reconnect)
        VSCODE_PID=$(pgrep -f "vscode-server" | head -1)
        if [ -n "$VSCODE_PID" ]; then
            echo "$TIMESTAMP KILLING VS Code server (PID $VSCODE_PID) to free memory" >> "$LOG"
            kill -9 "$VSCODE_PID"
        fi
    fi
    
    # Log every 5 minutes for trend analysis
    if [ $(($(date +%s) % 300)) -lt 10 ]; then
        echo "$TIMESTAMP Memory: ${FREE_MB}MB free | $(uptime)" >> "$LOG"
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

## Step 6: Verification

After applying all fixes, verify:

```bash
# Swap is active
free -h

# Monitor service is running
sudo systemctl status cubie-monitor

# SSH keepalive is configured
grep -i "clientalive\|keepalive" /etc/ssh/sshd_config

# Backend is still running fine
sudo systemctl status cubie-backend
curl -sk https://localhost:8443/health

# Check monitor log
tail -20 /var/log/cubie-monitor.log
```

---

## Post-Crash Analysis

If it crashes again, run these IMMEDIATELY after reconnecting:

```bash
# What caused the crash?
dmesg | grep -i "oom\|killed" | tail -10

# What was running?
last reboot | head -5

# Journal from before the crash
journalctl --since "30 min ago" -p warning --no-pager | head -50

# Was swap being used?
cat /var/log/cubie-monitor.log | tail -50
```

---

## Summary of Root Cause

**Most likely:** OOM (Out of Memory) kill. VS Code Remote SSH spawns a full Node.js server on the Cubie (~1-2 GB). With Copilot agent, it can spike to 3-4 GB. Combined with the cubie-backend, system services, and any file operations, the 8 GB RAM gets exhausted. Linux kernel's OOM killer then kills processes, potentially including critical ones, causing a freeze.

**The swap file is the single most important fix.** It gives the system breathing room when RAM fills up.
