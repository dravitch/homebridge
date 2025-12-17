# HomeBridge Troubleshooting Guide

Complete guide to diagnose and fix common issues with HomeBridge.

## 📋 Table of Contents

- [Windows Issues](#windows-issues)
  - [Tunnel Not Starting](#tunnel-not-starting)
  - [SSH Service Issues](#ssh-service-issues)
  - [RDP Not Working](#rdp-not-working)
- [Relay Issues](#relay-issues)
  - [Tunnel Port Not Listening](#tunnel-port-not-listening)
  - [Fail2ban Blocking Legitimate IPs](#fail2ban-blocking-legitimate-ips)
- [Linux Client Issues](#linux-client-issues)
  - [SSH Asks for Password](#ssh-asks-for-password)
  - [Connection Timeout](#connection-timeout)
  - [RDP Connection Fails](#rdp-connection-fails)
- [Network Issues](#network-issues)
- [Performance Issues](#performance-issues)

---

## Windows Issues

### Tunnel Not Starting

**Symptoms:**
- Scheduled task shows "Running" but no ssh.exe process
- Cannot connect from Linux client
- Port 2222 not listening on relay

**Diagnosis:**

```powershell
# Check scheduled task status
Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
Get-ScheduledTaskInfo -TaskName "SSH-Reverse-Tunnel"

# Check if ssh.exe is running
Get-Process ssh -ErrorAction SilentlyContinue

# Check task logs
Get-EventLog -LogName Application -Source "Task Scheduler" -Newest 10 | Where-Object {$_.Message -like "*SSH-Reverse-Tunnel*"}
```

**Solutions:**

**1. Restart the scheduled task:**
```powershell
Stop-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName "SSH-Reverse-Tunnel"

# Wait and verify
Start-Sleep -Seconds 5
Get-Process ssh
```

**2. Test tunnel manually:**
```powershell
# Test as SYSTEM account (requires PsExec from Sysinternals)
# Download: https://download.sysinternals.com/files/PSTools.zip

psexec -i -s powershell.exe

# Then test connection
ssh -i "C:\Windows\System32\config\systemprofile\.ssh\id_rsa" tunnel@YOUR_RELAY_IP
```

**3. Verify SYSTEM SSH key:**
```powershell
# Check if key exists
Test-Path "C:\Windows\System32\config\systemprofile\.ssh\id_rsa"

# Check key permissions
icacls "C:\Windows\System32\config\systemprofile\.ssh\id_rsa"
```

**4. Check known_hosts:**
```powershell
# Regenerate known_hosts
$systemSshDir = "C:\Windows\System32\config\systemprofile\.ssh"
$knownHostsPath = "$systemSshDir\known_hosts"
$relayServer = "YOUR_RELAY_IP"

ssh-keyscan -H $relayServer > $knownHostsPath
```

**5. Re-run setup if all else fails:**
```powershell
.\1-windows\setup-windows.ps1 -RelayServer "YOUR_RELAY_IP"
```

---

### SSH Service Issues

**Symptoms:**
- sshd service not running
- Cannot connect to Windows from relay
- Port 22 not listening

**Diagnosis:**

```powershell
# Check SSH service
Get-Service sshd

# Check if port 22 is listening
Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue

# Check firewall rules
Get-NetFirewallRule -DisplayName "*SSH*" | Select-Object DisplayName, Enabled, Direction
```

**Solutions:**

**1. Restart SSH service:**
```powershell
Restart-Service sshd
Start-Sleep -Seconds 2
Get-Service sshd
```

**2. Reinstall OpenSSH:**
```powershell
# Remove
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Reinstall
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Configure
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
```

**3. Fix firewall:**
```powershell
# Remove existing rules
Remove-NetFirewallRule -DisplayName "*OpenSSH*" -ErrorAction SilentlyContinue

# Create new rule
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

**4. Check SSH configuration:**
```powershell
# View config
Get-Content "C:\ProgramData\ssh\sshd_config"

# Test config
& "C:\Windows\System32\OpenSSH\sshd.exe" -t
```

---

### RDP Not Working

**Symptoms:**
- Port 3389 not listening
- RDP connection refused
- TermService running but RDP not accessible

**Diagnosis:**

```powershell
# Check RDP service
Get-Service TermService

# Check if port 3389 is listening
Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue

# Check Windows version
(Get-WmiObject -Class Win32_OperatingSystem).Caption

# Check RDP registry settings
Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections"
```

**Solutions:**

**For Windows 11 HOME (RDP Wrapper required):**

**1. Verify RDP Wrapper installation:**
```powershell
# Check if installed
Test-Path "C:\Program Files\RDP Wrapper"

# Check service
Get-Service "RDP Wrapper" -ErrorAction SilentlyContinue

# Run diagnostic tool
& "C:\Program Files\RDP Wrapper\RDPCheck.exe"
```

**2. Update RDP Wrapper configuration:**
```powershell
# Download latest rdpwrap.ini
$iniUrl = "https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini"
$iniPath = "$env:ProgramFiles\RDP Wrapper\rdpwrap.ini"

Invoke-WebRequest -Uri $iniUrl -OutFile $iniPath -UseBasicParsing

# Restart services
Restart-Service TermService
Restart-Service "RDP Wrapper" -ErrorAction SilentlyContinue
```

**3. Verify RDPConf shows all green:**
```powershell
& "C:\Program Files\RDP Wrapper\RDPConf.exe"
```

**4. If RDP Wrapper fails, reinstall:**
```powershell
# Download and extract
$url = "https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip"
$zip = "$env:TEMP\RDPWrap.zip"
$dir = "$env:TEMP\RDPWrap"

Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $dir -Force

# Run installer
Stop-Service TermService -Force
& "$dir\install.bat"

# Restart Windows (required!)
Restart-Computer -Force
```

**For Windows PRO/Enterprise:**

**1. Enable RDP via registry:**
```powershell
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0

# Disable Network Level Authentication (if issues)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0
```

**2. Enable firewall rules:**
```powershell
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

**3. Restart service:**
```powershell
Restart-Service TermService
```

---

## Relay Issues

### Tunnel Port Not Listening

**Symptoms:**
- Port 2222 not listening on relay
- Cannot connect to targetpc-windows from Linux
- `ss -tlnp | grep 2222` shows nothing

**Diagnosis:**

```bash
# Check if port is listening
sudo ss -tlnp | grep 2222

# Check active SSH connections
sudo ss -tnp | grep sshd

# Check auth logs
sudo tail -50 /var/log/auth.log | grep tunnel

# Check if tunnel user exists
id tunnel
```

**Solutions:**

**1. Verify Windows is connecting:**
```bash
# Watch auth log in real-time
sudo tail -f /var/log/auth.log | grep tunnel
```

Look for:
- `Accepted publickey for tunnel` → Good, key authentication works
- `Connection reset by authenticating user tunnel` → Windows is trying but failing
- No logs at all → Windows not reaching the relay

**2. Check SSH configuration on relay:**
```bash
# Verify SSH config allows reverse tunnels
sudo grep -E "GatewayPorts|ClientAlive" /etc/ssh/sshd_config

# Should show:
# GatewayPorts no  (or commented)
# ClientAliveInterval 60
# ClientAliveCountMax 3
```

**3. Verify tunnel user's authorized_keys:**
```bash
# Check if Windows key is present
sudo cat /home/tunnel/.ssh/authorized_keys

# Check permissions
sudo ls -la /home/tunnel/.ssh/
# Should show:
# drwx------ tunnel tunnel .ssh/
# -rw------- tunnel tunnel authorized_keys
```

**4. Test manual connection from relay to Windows:**
```bash
# This should fail (expected), but shows if port opens
ssh -p 2222 localhost

# If Windows tunnel is active, this connects to Windows SSH
# If nothing, Windows tunnel is not established
```

---

### Fail2ban Blocking Legitimate IPs

**Symptoms:**
- Cannot connect to relay from known IPs
- "Connection refused" or timeout
- Previously working connections suddenly fail

**Diagnosis:**

```bash
# Check banned IPs
sudo fail2ban-client status sshd

# Check your current IP
curl ifconfig.me

# Check if you're banned
sudo fail2ban-client status sshd | grep "Banned IP list"
```

**Solutions:**

**1. Unban your IP:**
```bash
sudo fail2ban-client set sshd unbanip YOUR_IP_ADDRESS
```

**2. Add your IP to whitelist:**
```bash
# Edit fail2ban config
sudo nano /etc/fail2ban/jail.local

# Add your IP to ignoreip line:
# ignoreip = 127.0.0.1/8 ::1 YOUR_IP_ADDRESS

# Restart fail2ban
sudo systemctl restart fail2ban
```

**3. Check fail2ban logs:**
```bash
sudo tail -100 /var/log/fail2ban.log | grep Ban
```

**4. Temporarily disable fail2ban (for testing):**
```bash
sudo systemctl stop fail2ban

# Test your connection

# Re-enable when done
sudo systemctl start fail2ban
```

---

## Linux Client Issues

### SSH Asks for Password

**Symptoms:**
- `ssh targetpc-windows` asks for password
- Should use key authentication
- Multiple password prompts

**Diagnosis:**

```bash
# Test SSH with verbose output
ssh -v targetpc-windows 2>&1 | grep -i "auth\|key\|identity"

# Check if your key is loaded
ssh-add -l

# Check SSH config
cat ~/.ssh/config | grep -A10 "targetpc-windows"
```

**Solutions:**

**1. Verify your key is on Windows:**
```bash
# Connect with password one last time
ssh targetpc-windows

# On Windows, check:
Get-Content "$env:USERPROFILE\.ssh\authorized_keys"
```

**2. Add your key to Windows:**
```bash
# From Linux, copy your public key
cat ~/.ssh/id_rsa.pub

# Connect to Windows (with password)
ssh targetpc-windows

# In Windows PowerShell:
$key = "PASTE_YOUR_PUBLIC_KEY_HERE"
mkdir "$env:USERPROFILE\.ssh" -Force
Add-Content -Path "$env:USERPROFILE\.ssh\authorized_keys" -Value $key
icacls.exe "$env:USERPROFILE\.ssh\authorized_keys" /inheritance:r
icacls.exe "$env:USERPROFILE\.ssh\authorized_keys" /grant "${env:USERNAME}:(F)"
Restart-Service sshd
exit

# Test again from Linux
ssh targetpc-windows whoami
# Should work without password
```

**3. Check SSH agent:**
```bash
# Start SSH agent if not running
eval "$(ssh-agent -s)"

# Add your key
ssh-add ~/.ssh/id_rsa

# Verify
ssh-add -l
```

**4. Fix SSH config permissions:**
```bash
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
chmod 700 ~/.ssh
```

---

### Connection Timeout

**Symptoms:**
- `ssh targetpc-windows` hangs then times out
- "Connection timed out" error
- Cannot reach relay or Windows

**Diagnosis:**

```bash
# Test relay connection
ssh relay "echo 'OK'"

# Test with timeout
timeout 10 ssh -v targetpc-windows 2>&1 | tail -20

# Check if tunnel is active on relay
ssh relay "ss -tlnp | grep 2222"
```

**Solutions:**

**1. Verify relay is reachable:**
```bash
# Ping test
ping -c 4 RELAY_IP

# SSH test
ssh relay
```

**2. Verify Windows tunnel is active:**
```bash
# On relay, check for active tunnels
ssh relay "sudo ss -tnp | grep ':2222'"

# Should show ESTABLISHED connection from Windows
```

**3. Check firewall on relay:**
```bash
ssh relay "sudo ufw status"

# Verify SSH port is allowed
```

**4. Restart Windows tunnel:**
Connect via alternative method (AnyDesk, physical access) and restart:
```powershell
Restart-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
```

---

### RDP Connection Fails

**Symptoms:**
- `./rdp.sh` creates tunnel but xfreerdp fails
- "Connection refused" or "Connection reset"
- Authentication errors

**Diagnosis:**

```bash
# Check if tunnel is created
ss -tlnp | grep 13389

# Test RDP port on Windows (via SSH)
ssh targetpc-windows 'powershell.exe -Command "Get-NetTCPConnection -LocalPort 3389"'

# Test RDP connection manually
xfreerdp /v:127.0.0.1:13389 /u:username /cert:ignore
```

**Solutions:**

**1. Verify RDP is running on Windows:**
```bash
ssh targetpc-windows 'powershell.exe -Command "Get-Service TermService"'
ssh targetpc-windows 'powershell.exe -Command "netstat -an | findstr 3389"'
```

**2. Check tunnel is working:**
```bash
# Verify SSH master connection
ssh -O check targetpc-windows

# Create tunnel manually
ssh -f -N -L 13389:127.0.0.1:3389 targetpc-windows

# Test
ss -tlnp | grep 13389
```

**3. Test with minimal xfreerdp options:**
```bash
xfreerdp /v:127.0.0.1:13389 /u:username /cert:ignore
```

**4. Check Windows RDP logs:**
```bash
ssh targetpc-windows 'powershell.exe -Command "Get-EventLog -LogName System -Source TermService -Newest 10"'
```

---

## Network Issues

### Behind Multiple NATs

**Symptom:** Reverse tunnel works intermittently or not at all

**Solution:**
```bash
# On relay, check SSH config for keep-alive
sudo grep ClientAlive /etc/ssh/sshd_config

# Should have:
# ClientAliveInterval 60
# ClientAliveCountMax 3

# On Windows, tunnel script already has:
# -o ServerAliveInterval=60
# -o ServerAliveCountMax=3
```

### Dynamic IP Changes

**Symptom:** Connection breaks when relay IP changes

**Solution:**
```bash
# Use a domain name instead of IP
# Edit config.env:
RELAY_IP=relay.yourdomain.com

# Or use dynamic DNS service (DuckDNS, No-IP, etc.)
```

---

## Performance Issues

### Slow RDP Connection

**Solutions:**

**1. Reduce RDP quality:**
```bash
# Edit rdp.sh
xfreerdp \
    /v:127.0.0.1:13389 \
    /u:username \
    /cert:ignore \
    /compression \
    /network:modem \
    -gfx \
    -wallpaper \
    /bpp:16
```

**2. Check bandwidth:**
```bash
# On relay, monitor bandwidth
sudo iftop -i eth0
```

**3. Optimize SSH compression:**
```bash
# Edit ~/.ssh/config, add to targetpc-windows:
    Compression yes
    CompressionLevel 6
```

### High CPU on Windows

**Solutions:**

**1. Check if multiple SSH processes:**
```powershell
Get-Process ssh | Format-Table Id, CPU, StartTime
```

**2. Restart tunnel task:**
```powershell
Stop-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
Get-Process ssh | Stop-Process -Force
Start-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
```

---

## Emergency Recovery

### Complete Reset - Windows

```powershell
# Stop everything
Stop-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
Get-Process ssh | Stop-Process -Force
Stop-Service sshd

# Clean SSH files
Remove-Item -Path "C:\Windows\System32\config\systemprofile\.ssh" -Recurse -Force
Remove-Item -Path "$env:USERPROFILE\.ssh" -Recurse -Force

# Re-run setup
.\1-windows\setup-windows.ps1 -RelayServer "YOUR_RELAY_IP"
```

### Complete Reset - Relay

```bash
# Stop services
sudo systemctl stop sshd
sudo systemctl stop fail2ban

# Clean tunnel user
sudo deluser --remove-home tunnel
sudo rm -rf /home/tunnel

# Re-run setup
sudo ./2-relay/setup-relay.sh
```

### Complete Reset - Linux Client

```bash
# Backup old config
cp ~/.ssh/config ~/.ssh/config.backup

# Clean
rm -f ~/.ssh/id_rsa*
rm -rf ~/.ssh/control

# Re-run setup
./3-linux/setup-linux.sh
```

---

## Getting Help

If you've tried everything and still have issues:

1. **Collect logs:**
   - Windows: Event Viewer → Application → Task Scheduler
   - Relay: `/var/log/auth.log`
   - Linux: `ssh -vvv targetpc-windows` output

2. **Open an issue on GitHub** with:
   - Description of the problem
   - Steps to reproduce
   - Logs (remove sensitive information!)
   - Your environment (OS versions, network setup)

3. **Check existing issues:**
   - https://github.com/YOUR_USERNAME/homebridge/issues

---

## Preventive Maintenance

### Weekly Checks

```bash
# From Linux client
ssh targetpc-windows 'powershell.exe -Command "Get-Process ssh"'
ssh relay "ss -tlnp | grep 2222"
```

### Monthly Checks

```bash
# Check fail2ban status
ssh relay "sudo fail2ban-client status"

# Check disk space
ssh relay "df -h"
ssh targetpc-windows 'powershell.exe -Command "Get-PSDrive C"'
```

### When to Restart

- After Windows updates
- After network changes
- If tunnel disconnects frequently (> 3 times/day)

---

**Remember:** Most issues are solved by verifying SSH keys are in the right place with correct permissions!