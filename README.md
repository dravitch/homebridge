![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Shell](https://img.shields.io/badge/shell-bash%20%7C%20powershell-orange)
![Version](https://img.shields.io/badge/version-1.2.0-brightgreen)

![HomeBridge Banner](images/homebridge-banner.png)

# 🏠 HomeBridge - Secure Remote Desktop Access

**Own Your Remote Access. Forever.**

Automated configuration to access a Windows PC from Linux via a relay server, with RDP and VNC support.

> 💡 **Why HomeBridge exists**: In a world of commercial remote desktop solutions with monthly subscriptions and arbitrary limits, HomeBridge is built on open standards (SSH, RDP, VNC) and runs on your infrastructure. Read our [MANIFESTO](MANIFESTO.md) to understand our philosophy of digital self-reliance.

---

## ✨ Features

- 🖥️ **RDP Support** — Full remote desktop with dedicated session
- 👀 **VNC Support** — Screen sharing with existing session
- 🔒 **Secure** — All traffic through encrypted SSH tunnels
- 🔑 **Key-based auth** — No passwords, SSH keys only
- 🚀 **Simple setup** — Automated scripts for all components
- 🌐 **NAT-friendly** — Works behind firewalls and NAT
- 🧩 **Auto-tunnel at startup** — SSH reverse tunnel via SYSTEM account
- 🛡️ **Secure RDP access** — RDP over SSH tunnel
- 🏠 **Win11 HOME support** — Compatible via RDP Wrapper
- 🧱 **Relay protection** — Fail2ban enabled
- 🔄 **SSH multiplexing** — Avoids repeated authentications

---

## 📋 Architecture

```
┌─────────────┐         ┌──────────────┐         ┌──────────────┐
│   Linux     │   SSH   │    Relay     │ Reverse │   Windows    │
│   Client    │────────>│   (VPS)      │<────────│  (TARGETPC)  │
│             │         │              │  Tunnel │              │
└─────────────┘         └──────────────┘         └──────────────┘
                              ↑                         ↑
                         Port 22 SSH              Port 2222 (tunnel)
                                                  Port 22 (SSH local)
                                                  Port 3389 (RDP)
                                                  Port 5900 (VNC)
```

---

## 🚀 Installation in 3 Steps

### Prerequisites

- **Windows**: Windows 10/11, PowerShell 5.1+, administrator rights
- **Relay**: Ubuntu/Debian VPS with root access
- **Linux Client**: Linux with OpenSSH, xfreerdp for RDP, TigerVNC for VNC

---

### Step 1: Windows Configuration (5 min)

Open PowerShell as **Administrator**:

```powershell
# Download the script
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/dravitch/homebridge/main/1-windows/setup-windows.ps1" `
  -OutFile "setup-windows.ps1"

# Execute with your relay server IP
.\setup-windows.ps1 -RelayServer "YOUR_RELAY_IP"
```

The script will:
1. Install/configure OpenSSH
2. Create the reverse tunnel under SYSTEM account
3. Configure RDP (with RDP Wrapper for HOME edition)
4. Display the public key to copy

**⚠️ Copy the displayed public key** — you'll need it in Step 2.

---

### Step 2: Relay Configuration (3 min)

```bash
# Connect to relay as root
ssh root@YOUR_RELAY_IP

# Download the script
wget https://raw.githubusercontent.com/dravitch/homebridge/main/2-relay/setup-relay.sh
chmod +x setup-relay.sh

# Execute
./setup-relay.sh

# Paste the Windows public key when prompted
```

The script will:
1. Create the `tunnel` user
2. Configure SSH for reverse tunnel
3. Install and configure Fail2ban
4. Configure UFW firewall

---

### Step 3: Linux Client Configuration (2 min)

```bash
# Download the script
wget https://raw.githubusercontent.com/dravitch/homebridge/main/3-linux/setup-linux.sh
chmod +x setup-linux.sh

# Execute
./setup-linux.sh

# Follow instructions to add your key on Windows
```

The script will:
1. Create/verify your SSH key
2. Configure SSH with multiplexing
3. Guide you to add your key on Windows

---

## 🔧 Usage

### SSH Connection

```bash
ssh targetpc-windows

# You get a Windows PowerShell prompt
# First connection requires authentication
# Subsequent connections (10 min) are instant thanks to multiplexing
```

### RDP Connection

```bash
cd 3-linux
./rdp.sh

# The script:
# 1. Verifies tunnel is active
# 2. Verifies RDP is working
# 3. Creates a local tunnel
# 4. Launches xfreerdp
```

### VNC Connection

```bash
cd 3-linux
./vnc.sh

# Screen sharing with the active session
# Perfect for helping someone remotely
```

### Useful Commands

```bash
# Check tunnel status from relay
ssh relay "ss -tlnp | grep 2222"

# Check SSH master connection
ssh -O check targetpc-windows

# Close master connection
ssh -O exit targetpc-windows
```

---

## 🔍 Diagnostic Tools

### Linux - SSH Diagnostics

```bash
cd 3-linux
./diagnose-ssh-keys.sh
```

Performs comprehensive SSH configuration check:
- Local SSH keys inventory
- SSH config validation
- Relay connectivity test
- Windows tunnel verification

### Windows - Health Check

```powershell
# On Windows (PowerShell as Administrator)
.\1-windows\windows-health-check.ps1

# With auto-fix:
.\1-windows\windows-health-check.ps1 -AutoFix
```

Checks all components after reboot:
- SSH services and ports
- Tunnel task and processes
- SSH keys and permissions
- RDP/VNC services

---

## 🏢 Multiple Windows Machines

HomeBridge supports multiple Windows PCs through different reverse ports:

| Machine | Reverse Port | SSH Config Host | RDP Local Port |
|---------|--------------|-----------------|----------------|
| PC 1    | 2222         | pc1-windows     | 13389          |
| PC 2    | 2223         | pc2-windows     | 13390          |
| PC 3    | 2224         | pc3-windows     | 13391          |

Each machine uses the same relay but with a unique port. See documentation for setup details.

---

## 🛠️ Troubleshooting

### Windows Tunnel Not Starting

```powershell
# On Windows - check scheduled task
Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
Get-ScheduledTaskInfo -TaskName "SSH-Reverse-Tunnel"

# Start manually
Start-ScheduledTask -TaskName "SSH-Reverse-Tunnel"

# Verify ssh.exe is running
Get-Process ssh
```

### SSH Still Asks for Password

**From Linux client:**
```bash
# Verify your key is on Windows
ssh targetpc-windows "Get-Content `$env:USERPROFILE\.ssh\authorized_keys"
```

**On Windows, add your key:**
```powershell
$key = "ssh-rsa AAAAB3NzaC1yc2E... your-linux-key"
$authorizedKeysPath = "$env:USERPROFILE\.ssh\authorized_keys"
Add-Content -Path $authorizedKeysPath -Value $key
icacls.exe $authorizedKeysPath /inheritance:r
icacls.exe $authorizedKeysPath /grant "${env:USERNAME}:(F)"
icacls.exe $authorizedKeysPath /grant "SYSTEM:(F)"
Restart-Service sshd
```

### RDP Not Working

```powershell
# On Windows - check RDP
Get-Service TermService
Get-NetTCPConnection -LocalPort 3389

# If Windows 11 HOME and port 3389 not listening
# Restart Windows after RDP Wrapper installation
Restart-Computer -Force

# Verify with RDPConf
& "C:\Program Files\RDP Wrapper\RDPConf.exe"
```

**For detailed troubleshooting**, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## 🔒 Security

### Fail2ban Protection

The relay is protected by Fail2ban:
- 5 SSH failures in 10 min → 1 hour ban
- 3 aggressive failures in 5 min → 2 hour ban

```bash
# View banned IPs
sudo fail2ban-client status sshd

# Unban an IP
sudo fail2ban-client set sshd unbanip <IP>
```

### Best Practices

1. **SSH keys only**: No password authentication
2. **Encrypted tunnel**: All traffic goes through SSH
3. **Isolated SYSTEM account**: Windows tunnel runs under SYSTEM
4. **UFW Firewall**: Only SSH port is open on relay
5. **Monitoring**: Fail2ban monitors connection attempts

---

## 📁 Project Structure

```
homebridge/
├── README.md                        # This file
├── LICENSE                          # MIT License
├── MANIFESTO.md                     # Project philosophy
├── TROUBLESHOOTING.md               # Detailed troubleshooting guide
├── CHANGELOG.md                     # Version history
│
├── 1-windows/                       # Windows (execute first)
│   ├── setup-windows.ps1            # Complete Windows configuration
│   └── windows-health-check.ps1    # Post-reboot health check
│
├── 2-relay/                         # Relay (execute second)
│   ├── setup-relay.sh               # Complete relay configuration
│   └── setup_relay_vnc.sh           # VNC-specific relay setup
│
├── 3-linux/                         # Linux Client (execute last)
│   ├── setup-linux.sh               # SSH configuration + keys
│   ├── setup-linux-vnc.sh           # VNC client setup
│   ├── rdp.sh                       # RDP connection script
│   ├── vnc.sh                       # VNC connection script
│   └── diagnose-ssh-keys.sh         # SSH diagnostics tool
│
├── templates/                       # Configuration files
│   ├── config.env.template          # Environment variables
│   └── ssh_config.template          # SSH configuration template
│
└── docs/                            # Additional documentation
    ├── RDP-SETUP.md                 # Detailed RDP setup
    └── VNC-SETUP.md                 # Detailed VNC setup
```

---

## 🎨 Customization

### Using config.env

Create a `config.env` file at the root:

```bash
# Copy the template
cp templates/config.env.template config.env

# Edit with your values
nano config.env
```

Variables:
- `RELAY_IP`: Your relay server IP
- `RELAY_USER`: SSH user on relay (default: tunnel)
- `REVERSE_PORT`: Tunnel port (default: 2222)
- `WINDOWS_USER`: Windows username

---

## 🧪 Testing

### Test Complete Tunnel

```bash
# From Linux client

# 1. SSH test
ssh targetpc-windows whoami
# Should display: targetpc\username

# 2. Test reverse tunnel on relay
ssh relay "ss -tlnp | grep 2222"
# Should show: LISTEN on 127.0.0.1:2222

# 3. RDP test
./3-linux/rdp.sh
# Should open Windows RDP session

# 4. VNC test
./3-linux/vnc.sh
# Should open VNC viewer
```

---

## ❓ FAQ

### Does Windows 11 HOME support RDP?

Not natively, but **RDP Wrapper** enables it. The `setup-windows.ps1` script automatically detects HOME edition and installs RDP Wrapper.

### Can I use a port other than 2222?

Yes, modify `REVERSE_PORT` in `config.env` and re-run the scripts.

### How do I change the relay?

1. Modify `RELAY_IP` in `config.env`
2. Re-run `setup-windows.ps1` with the new IP
3. Re-run `setup-linux.sh`

### Does the tunnel work behind NAT?

Yes, that's the whole point! The **reverse** tunnel is initiated from Windows to the relay, so no port forwarding needed.

### Can I have multiple Windows PCs?

Yes! Use a different port for each PC:
- PC1: port 2222
- PC2: port 2223
- PC3: etc.

---

## 🤝 Contributing

We welcome contributions! HomeBridge is built on the principle of digital self-reliance and community improvement.

**Ways to contribute:**
- 🐛 Report bugs and issues
- 💡 Suggest new features
- 📝 Improve documentation
- 🌍 Translate to other languages
- 🔧 Submit pull requests
- ⭐ Star the repository

**Read our [MANIFESTO](MANIFESTO.md)** to understand our vision and philosophy.

Issues and Pull Requests welcome!

---

## 📄 License

MIT License - see [LICENSE](LICENSE)

---

## 🙏 Acknowledgments

- [OpenSSH](https://www.openssh.com/) - The secure shell that powers everything
- [RDP Wrapper](https://github.com/stascorp/rdpwrap) - Enabling RDP on Windows HOME
- [Fail2ban](https://www.fail2ban.org/) - Protecting against brute force attacks
- [TigerVNC](https://tigervnc.org/) - Open source VNC implementation

---

## 🔗 Links

- **GitHub Repository**: https://github.com/dravitch/homebridge
- **Issues**: https://github.com/dravitch/homebridge/issues
- **Discussions**: https://github.com/dravitch/homebridge/discussions

---

**HomeBridge** - Because helping family remotely shouldn't require a subscription.  
Read our story: [MANIFESTO.md](MANIFESTO.md)

*Version 1.2.0 - Last updated: February 2026*
