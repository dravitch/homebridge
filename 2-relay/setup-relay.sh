#!/usr/bin/env bash
# ====================================================================
# HomeBridge Relay Setup
# Configure SSH relay server with tunneling support
# ====================================================================

set -e

echo "========================================"
echo "HomeBridge Relay Setup"
echo "========================================"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ This script must be run as root"
    echo "   Usage: sudo ./setup-relay.sh"
    exit 1
fi

# ====================================================================
# CONFIGURATION
# ====================================================================
TUNNEL_USER="tunnel"
TUNNEL_PORT=2222

echo "Configuration:"
echo "  Tunnel user: $TUNNEL_USER"
echo "  Tunnel port: $TUNNEL_PORT"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# ====================================================================
# STEP 1: System Update
# ====================================================================
echo ""
echo "[1/9] Updating system..."
apt update && apt upgrade -y
echo "✅ System updated"

# ====================================================================
# STEP 2: Install Required Packages
# ====================================================================
echo ""
echo "[2/9] Installing packages..."
apt install -y \
    openssh-server \
    fail2ban \
    ufw \
    htop \
    net-tools \
    curl \
    vim \
    vnstat

echo "✅ Packages installed"

# ====================================================================
# STEP 3: Create Tunnel User
# ====================================================================
echo ""
echo "[3/9] Creating tunnel user..."

if id "$TUNNEL_USER" &>/dev/null; then
    echo "ℹ️  User $TUNNEL_USER already exists"
else
    useradd -m -s /bin/bash "$TUNNEL_USER"
    echo "✅ User $TUNNEL_USER created"
fi

# Setup SSH directory
mkdir -p /home/$TUNNEL_USER/.ssh
chmod 700 /home/$TUNNEL_USER/.ssh
touch /home/$TUNNEL_USER/.ssh/authorized_keys
chmod 600 /home/$TUNNEL_USER/.ssh/authorized_keys
chown -R $TUNNEL_USER:$TUNNEL_USER /home/$TUNNEL_USER/.ssh

echo "✅ SSH directory configured"

# ====================================================================
# STEP 4: SSH Configuration
# ====================================================================
echo ""
echo "[4/9] Configuring SSH..."

# Backup existing config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Apply optimized SSH config
cat > /etc/ssh/sshd_config << 'EOF'
# HomeBridge SSH Configuration
Port 22
Protocol 2

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# Performance
Compression yes
TCPKeepAlive yes
ClientAliveInterval 60
ClientAliveCountMax 3

# Security
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
UseDNS no

# Tunneling
PermitTunnel yes
GatewayPorts no

# Subsystems
Subsystem sftp /usr/lib/openssh/sftp-server

# Logging
SyslogFacility AUTH
LogLevel INFO

# Limits
MaxAuthTries 3
MaxSessions 10
EOF

echo "✅ SSH configured"

# Restart SSH
systemctl restart sshd
echo "✅ SSH service restarted"

# ====================================================================
# STEP 5: Firewall Configuration (UFW)
# ====================================================================
echo ""
echo "[5/9] Configuring firewall..."

# Reset UFW
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow 22/tcp comment 'SSH'

# Enable UFW
ufw --force enable

echo "✅ Firewall configured"
ufw status

# ====================================================================
# STEP 6: Fail2Ban Configuration
# ====================================================================
echo ""
echo "[6/9] Configuring Fail2Ban..."

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo "✅ Fail2Ban configured"

# ====================================================================
# STEP 7: System Optimizations
# ====================================================================
echo ""
echo "[7/9] Applying system optimizations..."

# File limits
cat >> /etc/security/limits.conf << EOF

# HomeBridge optimizations
* soft nofile 65536
* hard nofile 65536
EOF

# Network optimizations
cat >> /etc/sysctl.conf << EOF

# HomeBridge network optimizations
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF

sysctl -p

echo "✅ Optimizations applied"

# ====================================================================
# STEP 8: Monitoring Scripts
# ====================================================================
echo ""
echo "[8/9] Creating monitoring scripts..."

# Tunnel check script
cat > /usr/local/bin/check-tunnels.sh << 'SCRIPT_EOF'
#!/bin/bash
echo "========================================"
echo "HomeBridge Tunnel Status"
echo "========================================"
echo ""

echo "Active SSH connections:"
ss -tnp | grep sshd | grep ESTAB

echo ""
echo "Forwarded tunnels (listening ports):"
ss -tuln | grep LISTEN | grep -E "127.0.0.1:(2[0-9]{3}|1[0-9]{4})"

echo ""
echo "Connected users:"
who

echo ""
echo "System load:"
uptime
SCRIPT_EOF

chmod +x /usr/local/bin/check-tunnels.sh

# Diagnostic script
cat > /usr/local/bin/diag-tunnel.sh << 'SCRIPT_EOF'
#!/bin/bash
PORT=$1
if [ -z "$PORT" ]; then
    echo "Usage: $0 <port>"
    echo "Example: $0 2222"
    exit 1
fi

echo "Diagnostic for port $PORT"
echo "========================================"

echo ""
echo "Port listening status:"
if ss -tuln | grep -q ":$PORT"; then
    echo "✅ Port $PORT is listening"
    ss -tuln | grep ":$PORT"
else
    echo "❌ Port $PORT NOT listening"
fi

echo ""
echo "Active SSH connections:"
ss -tnp | grep sshd

echo ""
echo "Recent SSH logs:"
tail -n 20 /var/log/auth.log | grep sshd

echo ""
echo "Test local connection:"
if nc -zv localhost $PORT 2>&1 | grep -q succeeded; then
    echo "✅ Port accessible locally"
else
    echo "❌ Port NOT accessible"
fi
SCRIPT_EOF

chmod +x /usr/local/bin/diag-tunnel.sh

echo "✅ Monitoring scripts created"

# ====================================================================
# STEP 9: Setup vnstat
# ====================================================================
echo ""
echo "[9/9] Configuring bandwidth monitoring..."

systemctl enable vnstat
systemctl start vnstat

echo "✅ vnstat configured"

# ====================================================================
# SUMMARY
# ====================================================================
PUBLIC_IP=$(curl -s ifconfig.me)

echo ""
echo "========================================"
echo "Relay Setup Complete!"
echo "========================================"
echo ""
echo "Server Information:"
echo "  Public IP: $PUBLIC_IP"
echo "  Tunnel user: $TUNNEL_USER"
echo "  SSH port: 22"
echo ""
echo "Next Steps:"
echo ""
echo "1. Add Windows SSH key:"
echo "   From Windows, copy public key from:"
echo "   C:\\Users\\USERNAME\\.ssh\\id_rsa.pub"
echo ""
echo "   Then on this server:"
echo "   sudo nano /home/$TUNNEL_USER/.ssh/authorized_keys"
echo "   (paste the key and save)"
echo ""
echo "2. Test connection from Windows:"
echo "   ssh $TUNNEL_USER@$PUBLIC_IP"
echo ""
echo "Useful commands:"
echo "  Check tunnels: /usr/local/bin/check-tunnels.sh"
echo "  Diagnose port: /usr/local/bin/diag-tunnel.sh 2222"
echo "  View logs: tail -f /var/log/auth.log"
echo "  Bandwidth: vnstat"
echo "  Firewall: ufw status"
echo ""