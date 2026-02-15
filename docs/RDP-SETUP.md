# HomeBridge RDP Setup Guide

**Version 1.0** - Secure Remote Desktop via SSH Tunnel

## 📋 Table of Contents

- [What is HomeBridge RDP?](#what-is-homebridge-rdp)
- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Security](#security)

---

## What is HomeBridge RDP?

**HomeBridge RDP** enables secure Remote Desktop Protocol (RDP) connections to Windows machines through an SSH tunnel and relay server. This provides:

- ✅ **Secure access** from anywhere without exposing RDP to the internet
- ✅ **Works with Windows Home** (via RDP Wrapper)
- ✅ **Persistent connection** through automatic SSH reverse tunnel
- ✅ **Single authentication** using SSH keys (no VPN required)

### Key Features

| Feature | Description |
|---------|-------------|
| **Performance** | ⭐⭐⭐⭐⭐ Native RDP speed |
| **Security** | All traffic encrypted via SSH tunnel |
| **Session Type** | Dedicated remote session |
| **Audio** | Full audio redirection support |
| **Clipboard** | Bidirectional clipboard sharing |
| **Best for** | Daily remote work, full system control |

---

## Architecture Overview

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  Linux Client   │         │  Relay Server   │         │  Windows PC     │
│                 │         │   (VPS/Cloud)   │         │                 │
│  Port 13389     │◄────────┤  Port 2222      │◄────────┤  Port 3389      │
│  (RDP Local)    │  SSH    │  (Reverse)      │  Tunnel │  (RDP Server)   │
└─────────────────┘         └─────────────────┘         └─────────────────┘
```

**Flow:**
1. Windows establishes **reverse SSH tunnel** to relay (Windows:22 → Relay:2222)
2. Linux client connects to relay via SSH
3. Traffic forwarded: Linux:13389 → Relay:2222 → Windows:3389
4. RDP session established securely

**Advantages:**
- No open ports on Windows firewall to internet
- No dynamic DNS required
- Works behind NAT/CGNAT
- Single point of access (relay server)

---

## Prerequisites

### Required

1. **Windows Machine (Target)**
   - Windows 10/11 (Home, Pro, or Enterprise)
   - PowerShell 5.1 or higher
   - Administrator privileges
   - Internet connection

2. **Relay Server (VPS)**
   - Ubuntu 20.04+ or Debian 11+
   - Public IP address
   - SSH access (port 22)
   - Root or sudo privileges

3. **Linux Client (Your Machine)**
   - Any Linux distribution
   - SSH client installed
   - Remmina or FreeRDP installed

### Recommended

- **Relay Server:** 1GB RAM, 1 CPU core (minimal resource usage)
- **Network:** Stable internet on all machines
- **Knowledge:** Basic command line usage

---

## Installation

### Step 1: Windows RDP Setup (15 min)

#### 1.1 Download and Prepare Configuration

Open PowerShell as **Administrator**:

```powershell
# Create working directory
New-Item -Path "C:\HomeBridge" -ItemType Directory -Force
Set-Location "C:\HomeBridge"

# Download setup script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/YOUR_USERNAME/homebridge/main/1-windows/setup-windows.ps1" -OutFile "setup-windows.ps1"

# Download config template
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/YOUR_USERNAME/homebridge/main/config.env.template" -OutFile "config.env"
```

#### 1.2 Configure Settings

Edit `config.env` with your values:

```powershell
notepad config.env
```

**Required changes:**
```ini
# Relay server IP or domain (YOUR VPS IP)
RELAY_IP=172.234.175.48

# User created on relay for tunnels
RELAY_USER=tunnel

# Unique port per Windows machine (2222, 2223, 2224, etc.)
REVERSE_PORT=2222

# Windows user for RDP (existing user with password)
WINDOWS_USER=YourWindowsUsername

# Other defaults are usually fine
LOCAL_SSH_PORT=22
WINDOWS_RDP_PORT=3389
LOCAL_RDP_PORT=13389
TASK_NAME=SSH-Reverse-Tunnel
```

#### 1.3 Run Setup Script

```powershell
# Execute setup with config
.\setup-windows.ps1
```

**The script will:**
1. ✅ Install OpenSSH Client and Server
2. ✅ Generate SSH key pair for SYSTEM account
3. ✅ Configure SSH reverse tunnel (auto-restart)
4. ✅ Enable RDP (install RDP Wrapper on Home editions)
5. ✅ Create Windows scheduled tasks (auto-start at boot)
6. ✅ Configure firewall rules
7. ✅ Display SSH public key to copy

**IMPORTANT:** Copy the displayed SSH public key - you'll need it in Step 2.

**Example output:**
```
========================================
CONFIGURATION TERMINÉE
========================================

CLÉ PUBLIQUE À AJOUTER SUR LE RELAY:
========================================
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... windows-to-relay
========================================
```

#### 1.4 Verify Windows Setup

```powershell
# Check SSH service
Get-Service sshd

# Check scheduled task
Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel"

# Verify SSH tunnel process (wait 30 seconds after setup)
Get-Process ssh

# Expected: Status=Running for all
```

---

### Step 2: Relay Server Configuration (10 min)

#### 2.1 Connect to Relay

```bash
# From Linux client
ssh root@YOUR_RELAY_IP
```

#### 2.2 Download Setup Script

```bash
# Download relay setup
wget https://raw.githubusercontent.com/YOUR_USERNAME/homebridge/main/2-relay/setup-relay.sh
chmod +x setup-relay.sh
```

#### 2.3 Run Setup Script

```bash
# Execute setup
./setup-relay.sh
```

**You'll be prompted for:**
1. **Relay IP address** (your VPS public IP)
2. **Windows SSH public key** (from Step 1.3)

**The script will:**
1. ✅ Create dedicated `tunnel` user
2. ✅ Configure SSH for tunnel user
3. ✅ Add Windows public key to authorized_keys
4. ✅ Set up monitoring scripts
5. ✅ Configure logging

#### 2.4 Verify Relay Setup

```bash
# Check tunnel user exists
id tunnel

# Wait 60 seconds, then check if Windows connected
sudo ss -tlnp | grep 2222

# Expected output:
# LISTEN 0 128 127.0.0.1:2222 0.0.0.0:* users:(("sshd",pid=XXXXX))
```

**If port 2222 is listening:** ✅ Windows tunnel is active!

---

### Step 3: Linux Client Configuration (5 min)

#### 3.1 Download Setup Script

```bash
# On your Linux machine
cd ~
wget https://raw.githubusercontent.com/YOUR_USERNAME/homebridge/main/3-linux/setup-linux.sh
chmod +x setup-linux.sh
```

#### 3.2 Download SSH Config Template

```bash
wget https://raw.githubusercontent.com/YOUR_USERNAME/homebridge/main/ssh_config.template -O ~/.ssh/config.template
```

#### 3.3 Configure SSH

Edit the template with your values:

```bash
cp ~/.ssh/config.template ~/.ssh/config.homebridge
nano ~/.ssh/config.homebridge
```

**Replace placeholders:**
```
Host relay
    HostName YOUR_RELAY_IP              # Your VPS IP
    User tunnel
    Port 22
    IdentityFile ~/.ssh/id_rsa
    # ... rest stays the same

Host targetpc-windows
    HostName localhost
    User YOUR_WINDOWS_USER              # Your Windows username
    Port 2222                           # Same as REVERSE_PORT in config.env
    ProxyJump relay
    # ... rest stays the same

Host targetpc-windows-rdp-tunnel
    # ... (update User and Port as above)
```

**Append to main SSH config:**
```bash
cat ~/.ssh/config.homebridge >> ~/.ssh/config
```

#### 3.4 Run Setup Script

```bash
./setup-linux.sh
```

**The script will:**
1. ✅ Install Remmina and FreeRDP
2. ✅ Configure SSH key authentication
3. ✅ Create RDP connection script
4. ✅ Test connectivity to relay and Windows

#### 3.5 Verify Client Setup

```bash
# Test SSH connection to relay
ssh relay "echo Relay OK"

# Test SSH connection to Windows
ssh targetpc-windows "echo Windows OK"

# Both should return "OK"
```

---

## Usage

### Method 1: CLI Script (Recommended)

```bash
cd 3-linux
./rdp.sh
```

The script will:
1. ✅ Verify SSH tunnel is active
2. ✅ Create local RDP tunnel on port 13389
3. ✅ Launch Remmina with optimal settings

### Method 2: Remmina GUI

```bash
# Using the connection profile
remmina -c ~/.local/share/remmina/targetpc-rdp.remmina

# Or launch Remmina and select "TargetPC Windows RDP"
remmina
```

**First connection:**
- Enter your Windows password when prompted
- Check "Save password" for automatic login

### Method 3: Manual Connection

```bash
# 1. Create SSH tunnel
ssh -f -N targetpc-windows-rdp-tunnel

# 2. Connect with FreeRDP
xfreerdp /v:localhost:13389 /u:YOUR_WINDOWS_USER /cert:ignore
```

### Useful Commands

```bash
# Check tunnel status on relay
ssh relay "ss -tlnp | grep 2222"

# Restart Windows SSH tunnel (from Windows)
Restart-ScheduledTask -TaskName "SSH-Reverse-Tunnel"

# Close SSH master connection
ssh -O exit targetpc-windows

# View Windows tunnel logs
ssh targetpc-windows 'powershell Get-Content C:\HomeBridge\logs\tunnel.log -Tail 20'
```

---

## Troubleshooting

### Windows Tunnel Not Connecting

**Symptoms:**
- `ss -tlnp | grep 2222` on relay shows nothing
- Cannot SSH to `targetpc-windows`

**Solutions:**

```powershell
# 1. On Windows - Check scheduled task
Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
# State should be "Running"

# 2. Check SSH process
Get-Process ssh
# Should show ssh.exe process

# 3. Check tunnel logs
Get-Content C:\HomeBridge\logs\tunnel.log -Tail 50

# 4. Manually restart tunnel
Stop-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
Start-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
Start-Sleep -Seconds 10

# 5. Test SSH key manually
ssh -i "C:\Windows\System32\config\systemprofile\.ssh\id_rsa" tunnel@YOUR_RELAY_IP
# Should connect without password
```

**Check relay logs:**
```bash
# On relay
sudo tail -f /var/log/auth.log | grep tunnel
# Should show successful authentications
```

### RDP Connection Refused

**Symptoms:**
- SSH tunnel works
- RDP connection fails or times out

**Solutions:**

```powershell
# 1. On Windows - Verify RDP is enabled
Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections"
# Should return 0 (enabled)

# 2. Check RDP service
Get-Service TermService
# Status should be "Running"

# 3. Verify port 3389 listening
Get-NetTCPConnection -LocalPort 3389 -State Listen

# 4. For Windows Home - Check RDP Wrapper
# Open RDPConf.exe from Start Menu
# All should show [Fully supported]

# 5. Test RDP locally
mstsc /v:localhost
# Should open RDP login
```

### Authentication Issues

**Symptom:** RDP asks for credentials but rejects them

**Solutions:**

```powershell
# 1. Verify Windows user has password set
net user YOUR_WINDOWS_USER
# Check if password is required

# 2. Enable Network Level Authentication (optional)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1

# 3. Allow RDP in user properties
# Control Panel → User Accounts → Manage User Accounts
# Add user to "Remote Desktop Users" group
net localgroup "Remote Desktop Users" YOUR_WINDOWS_USER /add
```

### Port Already in Use

**Symptom:** Local port 13389 already occupied

**Solutions:**

```bash
# 1. Find process using port
sudo lsof -i :13389

# 2. Kill existing tunnel
pkill -f "13389:localhost:3389"

# 3. Use different local port
ssh -L 13390:localhost:3389 targetpc-windows-rdp-tunnel
xfreerdp /v:localhost:13390 /u:YOUR_WINDOWS_USER
```

### Windows Home Edition Issues

**RDP Wrapper not working after Windows Update:**

```powershell
# 1. Download latest rdpwrap.ini
$iniUrl = "https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini"
Invoke-WebRequest -Uri $iniUrl -OutFile "$env:ProgramFiles\RDP Wrapper\rdpwrap.ini"

# 2. Restart Terminal Services
Stop-Service TermService -Force
Start-Service TermService

# 3. Run RDPConfig to verify
& "$env:ProgramFiles\RDP Wrapper\RDPConf.exe"

# 4. If still not working, reinstall RDP Wrapper
# Download from: https://github.com/stascorp/rdpwrap/releases
```

---

## Security

### Best Practices

1. ✅ **Use strong passwords** for Windows accounts
2. ✅ **Keep SSH keys secure** - never share private keys
3. ✅ **Regular updates** - keep Windows and relay updated
4. ✅ **Firewall rules** - only allow SSH (port 22) on relay
5. ✅ **Monitor logs** - check relay auth.log regularly

### SSH Key Management

**Rotate SSH keys periodically:**

```powershell
# On Windows - Generate new key
Remove-Item "C:\Windows\System32\config\systemprofile\.ssh\id_rsa*"
ssh-keygen -t rsa -b 4096 -C "windows-to-relay-new" -f "C:\Windows\System32\config\systemprofile\.ssh\id_rsa" -N '""'

# Display new public key
Get-Content "C:\Windows\System32\config\systemprofile\.ssh\id_rsa.pub"
```

```bash
# On relay - Update authorized_keys
nano /home/tunnel/.ssh/authorized_keys
# Replace old key with new key
```

```powershell
# On Windows - Restart tunnel
Restart-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
```

### Relay Server Hardening

```bash
# 1. Disable password authentication
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
# Set: PubkeyAuthentication yes

# 2. Limit SSH access to tunnel user
# Add to sshd_config:
# AllowUsers tunnel

# 3. Install fail2ban (optional)
sudo apt install fail2ban
sudo systemctl enable fail2ban

# 4. Enable UFW firewall
sudo ufw allow 22/tcp
sudo ufw enable
```

### Network Isolation

**Windows RDP only listens on localhost:**
```powershell
# Verify RDP is not exposed
Get-NetFirewallRule -DisplayName "*Remote Desktop*" | Select-Object DisplayName, Enabled

# Disable external RDP access (security layer)
New-NetFirewallRule -Name "Block-RDP-External" -DisplayName "Block RDP from Internet" -Enabled True -Direction Inbound -Protocol TCP -Action Block -LocalPort 3389 -RemoteAddress 0.0.0.0/0
```

---

## Advanced Configuration

### Multiple Windows Machines

**Use different reverse ports for each machine:**

**Machine 1 (config.env):**
```ini
REVERSE_PORT=2222
```

**Machine 2 (config.env):**
```ini
REVERSE_PORT=2223
```

**Update Linux SSH config:**
```
Host targetpc-windows-1
    Port 2222
    # ...

Host targetpc-windows-2
    Port 2223
    # ...
```

### Custom RDP Settings

**Higher resolution:**
```bash
xfreerdp /v:localhost:13389 /u:USER /size:1920x1080 /cert:ignore
```

**Fullscreen:**
```bash
xfreerdp /v:localhost:13389 /u:USER /f /cert:ignore
```

**Audio redirection:**
```bash
xfreerdp /v:localhost:13389 /u:USER /sound:sys:pulse /cert:ignore
```

### Persistent SSH Tunnel

**Auto-reconnect on Linux client:**

Create systemd service:
```bash
sudo nano /etc/systemd/system/homebridge-rdp-tunnel.service
```

```ini
[Unit]
Description=HomeBridge RDP Tunnel
After=network.target

[Service]
Type=simple
User=YOUR_LINUX_USER
ExecStart=/usr/bin/ssh -N -T -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes targetpc-windows-rdp-tunnel
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable homebridge-rdp-tunnel.service
sudo systemctl start homebridge-rdp-tunnel.service
```

---

## Performance Tuning

### Optimize RDP Experience

**Low bandwidth connections:**
```bash
xfreerdp /v:localhost:13389 /u:USER \
    /compression \
    /network:modem \
    /gfx:AVC444 \
    /cert:ignore
```

**High bandwidth connections:**
```bash
xfreerdp /v:localhost:13389 /u:USER \
    /network:lan \
    /gfx:AVC444 \
    /rfx \
    /cert:ignore
```

### SSH Tunnel Optimization

**Edit `~/.ssh/config`:**
```
Host targetpc-windows-rdp-tunnel
    # ... existing config ...
    Compression yes
    CompressionLevel 6
    TCPKeepAlive yes
```

---

## Uninstallation

### Windows

```powershell
# Stop and remove scheduled task
Stop-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
Unregister-ScheduledTask -TaskName "SSH-Reverse-Tunnel" -Confirm:$false

# Disable RDP (optional)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1

# Remove HomeBridge directory
Remove-Item -Path "C:\HomeBridge" -Recurse -Force

# Uninstall RDP Wrapper (Windows Home)
& "$env:ProgramFiles\RDP Wrapper\uninstall.bat"
```

### Relay

```bash
# Remove tunnel user
sudo userdel -r tunnel

# Remove monitoring scripts
sudo rm /usr/local/bin/check-tunnel-status.sh
```

### Linux Client

```bash
# Remove Remmina profile
rm ~/.local/share/remmina/targetpc-rdp.remmina

# Remove SSH config entries (manual edit)
nano ~/.ssh/config
# Delete HomeBridge sections
```

---

## Getting Help

**Logs locations:**
- **Windows:** `C:\HomeBridge\logs\tunnel.log`
- **Relay:** `/var/log/auth.log` and `/var/log/homebridge/`
- **Linux:** `~/.local/share/remmina/remmina.log`

**Common issues:**
- Tunnel not connecting → Check Windows scheduled task
- RDP refused → Verify RDP service and port 3389
- Authentication failed → Check Windows user password

**For more help:**
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. GitHub Issues: https://github.com/YOUR_USERNAME/homebridge/issues
3. Include logs when reporting issues

---

**HomeBridge v1.0** - Secure remote access, simplified.