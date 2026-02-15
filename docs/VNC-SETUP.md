# HomeBridge VNC Setup Guide

**Version 1.1** - VNC Support for Collaborative Remote Access

## 📋 Table of Contents

- [What is VNC?](#what-is-vnc)
- [RDP vs VNC: When to Use What](#rdp-vs-vnc-when-to-use-what)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)

---

## What is VNC?

**VNC (Virtual Network Computing)** is a graphical desktop-sharing protocol that allows you to remotely control a computer. Unlike RDP, VNC:

- **Shares the existing session** (you see what's on the physical screen)
- **Supports view-only mode** (watch without controlling)
- **Allows multiple simultaneous viewers**
- **Works cross-platform** (Windows, Linux, macOS)

### RDP vs VNC: When to Use What

| Feature | RDP (Default) | VNC (v1.1) |
|---------|---------------|------------|
| **Performance** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐ Good |
| **Bandwidth** | Low (optimized) | Medium-High |
| **Session Type** | New dedicated session | Shares physical screen |
| **Multi-user** | No (one at a time) | Yes (collaborative) |
| **View-only** | No | Yes |
| **Best for** | Daily work, full control | Support, training, troubleshooting |

**Use RDP when:**
- You need best performance
- You want a dedicated session
- You're working alone
- You need audio/video redirection

**Use VNC when:**
- You want to see/share the physical screen
- Multiple people need to view simultaneously
- You're providing remote support
- You need view-only mode (demonstration)

---

## Prerequisites

### Option A: Fresh VNC-Only Install

- Windows 10/11 (Home or Pro)
- PowerShell 5.1+
- Administrator rights
- Relay server (Ubuntu/Debian with SSH)

### Option B: Add VNC to Existing HomeBridge RDP Setup

If you already have HomeBridge RDP configured:
- ✅ Windows with `setup-windows.ps1` completed
- ✅ Relay with `setup-relay.sh` completed
- ✅ Linux client with `setup-linux.sh` completed

**You just need to add VNC on top!**

---

## Installation

### Step 1: Windows VNC Setup (10 min)

Open PowerShell as **Administrator**:

```powershell
# Download the VNC setup script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dravitch/main/1-windows/setup-windows-vnc.ps1" -OutFile "setup-windows-vnc.ps1"

# Execute with your relay IP
.\setup-windows-vnc.ps1 -RelayServer "YOUR_RELAY_IP"
```

**What this does:**
1. Installs TigerVNC Server (via Chocolatey or direct download)
2. Configures VNC to listen on `localhost:5900` only
3. Creates automatic SSH reverse tunnel on port `15900`
4. Sets up Windows scheduled tasks for auto-start
5. Configures firewall rules

**You'll be prompted for:**
- VNC password (8+ characters, used to connect)

**Copy the SSH public key displayed at the end.**

### Step 2: Relay VNC Configuration (3 min)

```bash
# Connect to your relay
ssh root@YOUR_RELAY_IP

# Download and execute VNC relay setup
wget https://raw.githubusercontent.com/dravitch/main/2-relay/setup-relay-vnc.sh
chmod +x setup-relay-vnc.sh
./setup-relay-vnc.sh

# Paste the Windows VNC public key when prompted
```

**What this does:**
1. Verifies existing `tunnel` user (from RDP setup)
2. Adds Windows VNC key to authorized_keys
3. Creates monitoring script for VNC tunnel
4. Prepares logging for VNC connections

### Step 3: Linux Client VNC Setup (5 min)

```bash
# Download and execute client setup
wget https://raw.githubusercontent.com/dravitch/main/3-linux/setup-linux-vnc.sh
chmod +x setup-linux-vnc.sh
./setup-linux-vnc.sh

# Enter your relay IP and Windows username when prompted
```

**What this does:**
1. Installs VNC clients (Remmina, TigerVNC viewer)
2. Adds VNC configuration to `~/.ssh/config`
3. Creates Remmina profile for easy connection
4. Tests SSH tunnel connectivity

---

## Usage

### Method 1: CLI Script (Recommended)

```bash
cd 3-linux
./vnc.sh
```

The script will:
1. ✅ Verify SSH tunnel is active
2. ✅ Check VNC server is running on Windows
3. ✅ Create local tunnel on port 15900
4. ✅ Launch VNC client with optimal settings

**Options during connection:**
```
1. Normal quality (default)
2. Low latency (minimal compression)
3. Low bandwidth (maximum compression)
4. View-only (read-only mode)
```

### Method 2: Remmina GUI

```bash
# Using the created profile
remmina -c ~/.local/share/remmina/targetpc-vnc.remmina

# Or launch Remmina and select "TargetPC Windows VNC"
remmina
```

### Method 3: Manual Connection

```bash
# 1. Create SSH tunnel
ssh -f -N targetpc-windows-vnc

# 2. Connect with any VNC client
vncviewer localhost:15900
# or
remmina -c vnc://localhost:15900
```

### Useful Commands

```bash
# Check tunnel status on relay
ssh relay "ss -tlnp | grep 15900"

# Check VNC server on Windows
ssh targetpc-windows-vnc 'powershell Get-ScheduledTask -TaskName "HomeBridge-VNC-Server"'

# View Windows VNC logs
ssh targetpc-windows-vnc 'powershell Get-Content C:\HomeBridge\logs\vnc-server.log -Tail 20'

# Close SSH master connection (forces re-auth)
ssh -O exit targetpc-windows-vnc
```

---

## Troubleshooting

### VNC Server Not Starting on Windows

**Symptoms:**
- Scheduled task shows "Running" but port 5900 not listening
- Cannot connect from Linux client

**Solutions:**

```powershell
# 1. Check scheduled task
Get-ScheduledTask -TaskName "HomeBridge-VNC-Server"
Get-ScheduledTaskInfo -TaskName "HomeBridge-VNC-Server"

# 2. Check VNC logs
Get-Content C:\HomeBridge\logs\vnc-server.log -Tail 50

# 3. Manually restart VNC
Stop-ScheduledTask -TaskName "HomeBridge-VNC-Server"
Start-ScheduledTask -TaskName "HomeBridge-VNC-Server"

# 4. Verify port 5900 listening
Get-NetTCPConnection -LocalPort 5900 -State Listen

# 5. Test VNC manually
& "C:\Program Files\TigerVNC\vncserver.exe" -rfbport 5900 -localhost
```

### VNC Tunnel Not Active on Relay

**Symptoms:**
- `ss -tlnp | grep 15900` shows nothing
- Cannot connect even with VNC server running

**Solutions:**

```bash
# 1. Check Windows tunnel task
ssh targetpc-windows-vnc 'powershell Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC"'

# 2. Check relay auth logs
sudo tail -f /var/log/auth.log | grep tunnel

# 3. Manually test tunnel from Windows
# (On Windows, as Administrator)
ssh -i "C:\Windows\System32\config\systemprofile\.ssh\id_rsa" -N -R 15900:127.0.0.1:5900 tunnel@RELAY_IP

# 4. Restart Windows tunnel
# (On Windows)
Restart-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC"
```

### VNC Connection Slow

**Immediate solutions:**

```bash
# Option 1: Use low bandwidth mode
./vnc.sh
# Then select option 3 (low bandwidth)

# Option 2: Manual vncviewer with compression
vncviewer localhost:15900 CompressLevel=9 Quality=3

# Option 3: Lower resolution
# On Windows, edit C:\HomeBridge\vnc\config
# Change: Geometry=1920x1080
# To: Geometry=1280x720
```

See [Performance Tuning](#performance-tuning) for permanent optimizations.

### Authentication Failed

**Symptom:** VNC asks for password but rejects it

**Solutions:**

```powershell
# On Windows, regenerate VNC password
$vncPassword = Read-Host "New VNC password" -AsSecureString
$vncPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($vncPassword)
)

# Update config
$config = Get-Content C:\HomeBridge\vnc\config
$config -replace "Password=.*", "Password=$vncPasswordPlain" | Set-Content C:\HomeBridge\vnc\config

# Restart VNC
Restart-ScheduledTask -TaskName "HomeBridge-VNC-Server"
```

### Coexistence Issues with RDP

**Both RDP and VNC should work simultaneously without conflicts.**

**Verify both are active:**

```bash
# Check RDP tunnel (port 13389)
ssh relay "ss -tlnp | grep 13389"

# Check VNC tunnel (port 15900)
ssh relay "ss -tlnp | grep 15900"

# Both should show LISTEN
```

**Different ports used:**
- RDP: Local tunnel `13389` → Relay `2222` → Windows `3389`
- VNC: Local tunnel `15900` → Relay `15900` → Windows `5900`

**If conflicts occur:**
```powershell
# On Windows, check both scheduled tasks
Get-ScheduledTask | Where-Object {$_.TaskName -like "*SSH-Reverse-Tunnel*"}

# Both should show "Ready" or "Running"
```

---

## Performance Tuning

### Network Optimization

**For fast connections (100+ Mbps):**
```bash
vncviewer localhost:15900 \
    CompressLevel=0 \
    Quality=9
```

**For medium connections (10-100 Mbps):**
```bash
vncviewer localhost:15900 \
    CompressLevel=6 \
    Quality=6
```

**For slow connections (<10 Mbps):**
```bash
vncviewer localhost:15900 \
    CompressLevel=9 \
    Quality=3
```

### Resolution Optimization

**Edit Windows VNC config:**
```powershell
notepad C:\HomeBridge\vnc\config

# Change resolution based on your needs:
# 1920x1080 - Full HD (high bandwidth)
# 1280x720  - HD (medium bandwidth)
# 1024x768  - Standard (low bandwidth)

# Restart after change
Restart-ScheduledTask -TaskName "HomeBridge-VNC-Server"
```

### Color Depth Optimization

Lower color depth reduces bandwidth significantly:

```powershell
# Edit C:\HomeBridge\vnc\config
# Change: Depth=24 (True Color)
# To: Depth=16 (High Color) or Depth=8 (256 colors)
```

### SSH Tunnel Optimization

**Edit `~/.ssh/config` to add compression:**
```bash
Host targetpc-windows-vnc
    # ... existing config ...
    Compression yes
    CompressionLevel 6
```

### Remmina Quality Presets

**In Remmina GUI:**
1. Open connection profile
2. Go to "Advanced" tab
3. Select quality preset:
   - **Poor** - Maximum compression (slow networks)
   - **Medium** - Balanced
   - **Good** - Minimal compression (fast networks)

---

## Advanced Configuration

### View-Only Mode (Demonstration)

**For presenting without allowing control:**

```bash
# Method 1: Using vnc.sh
./vnc.sh
# Select option 4 (View-only)

# Method 2: Manual
vncviewer localhost:15900 ViewOnly=1
```

### Multiple Simultaneous Viewers

**VNC supports multiple concurrent connections:**

```bash
# Viewer 1 (full control)
vncviewer localhost:15900

# Viewer 2 (view-only, different terminal)
vncviewer localhost:15900 ViewOnly=1

# Both see the same screen simultaneously
```

### Custom Port Configuration

**If port 15900 conflicts with another service:**

**1. On Windows, edit tunnel script:**
```powershell
notepad C:\Windows\System32\config\systemprofile\ssh-reverse-tunnel-vnc.ps1

# Change: $REVERSE_PORT = 15900
# To: $REVERSE_PORT = YOUR_CUSTOM_PORT

Restart-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC"
```

**2. On Linux, edit SSH config:**
```bash
nano ~/.ssh/config

# Change: LocalForward 15900 localhost:5900
# To: LocalForward YOUR_CUSTOM_PORT localhost:5900
```

---

## Security Considerations

### VNC vs RDP Security

- **RDP:** Native Windows authentication, session isolation
- **VNC:** Password-based, shared screen access

**Best practices:**
1. ✅ Use strong VNC password (12+ characters)
2. ✅ VNC only listens on localhost (enforced by setup)
3. ✅ All traffic encrypted via SSH tunnel
4. ✅ No direct VNC port exposure to internet

### Firewall Rules

**Windows firewall allows VNC only on localhost:**
```powershell
Get-NetFirewallRule -Name "HomeBridge-VNC-In"
# LocalAddress should be: 127.0.0.1
```

### Changing VNC Password

```powershell
# On Windows
$newPassword = Read-Host "New VNC password" -AsSecureString
# Update config and restart (see Troubleshooting section)
```

---

## Comparison: RDP vs VNC Usage

### Scenario 1: Daily Remote Work
**Use RDP** ✅
- Dedicated session
- Best performance
- Full audio/video support

### Scenario 2: Helping Family Member
**Use VNC** ✅
- See their actual screen
- Guide them through steps
- View-only mode available

### Scenario 3: Collaborative Coding
**Use VNC** ✅
- Both see same code
- Real-time collaboration
- Pair programming

### Scenario 4: Running Resource-Intensive Apps
**Use RDP** ✅
- Better performance
- Dedicated GPU access
- Lower bandwidth

---

## Uninstallation

**Remove VNC (keep RDP):**

```powershell
# On Windows
Stop-ScheduledTask -TaskName "HomeBridge-VNC-Server"
Stop-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC"
Unregister-ScheduledTask -TaskName "HomeBridge-VNC-Server" -Confirm:$false
Unregister-ScheduledTask -TaskName "SSH-Reverse-Tunnel-VNC" -Confirm:$false
Remove-Item -Path "C:\HomeBridge\vnc" -Recurse -Force
# Optionally uninstall TigerVNC via Control Panel
```

```bash
# On Linux client
rm ~/.local/share/remmina/targetpc-vnc.remmina
# Remove VNC section from ~/.ssh/config
```

---

## Getting Help

**Common issues resolved in minutes:**
- VNC server not starting → Check logs, restart task
- Tunnel not active → Verify Windows scheduled task
- Slow connection → Use low bandwidth mode

**For more help:**
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - VNC section
2. GitHub Issues: https://github.com/YOUR_USERNAME/homebridge/issues
3. Include logs when reporting issues

**Remember:** HomeBridge VNC is designed to coexist with RDP. You can use both simultaneously for different purposes!

---

**HomeBridge v1.1** - Because remote support shouldn't require screen-sharing subscriptions.