#!/usr/bin/env bash
# ====================================================================
# HomeBridge VNC Client Setup (Linux)
# Adds VNC configuration to existing SSH setup
# Requires: setup-linux.sh already executed
# ====================================================================

set -e

echo "========================================"
echo "HomeBridge VNC Client Setup"
echo "========================================"
echo ""

# Variables
read -p "Windows host name from SSH config [papa-windows]: " WINDOWS_BASE
WINDOWS_BASE=${WINDOWS_BASE:-papa-windows}
WINDOWS_VNC_HOST="${WINDOWS_BASE}-vnc"

SSH_CONFIG="$HOME/.ssh/config"

# ====================================================================
# 1. CHECK PREREQUISITES
# ====================================================================
echo "[1/4] Checking prerequisites..."

if [ ! -f "$SSH_CONFIG" ]; then
    echo "❌ ~/.ssh/config not found"
    echo "   Run setup-linux.sh first"
    exit 1
fi

if ! grep -q "Host $WINDOWS_BASE" "$SSH_CONFIG"; then
    echo "❌ Base Windows host '$WINDOWS_BASE' not found in SSH config"
    echo "   Run setup-linux.sh first"
    exit 1
fi

echo "✅ Prerequisites OK"

# ====================================================================
# 2. INSTALL VNC VIEWER
# ====================================================================
echo ""
echo "[2/4] Installing VNC viewer..."

# Detect package manager
if command -v apt-get &> /dev/null; then
    PKG_CMD="sudo apt-get install -y tigervnc-viewer"
elif command -v dnf &> /dev/null; then
    PKG_CMD="sudo dnf install -y tigervnc"
elif command -v pacman &> /dev/null; then
    PKG_CMD="sudo pacman -S --noconfirm tigervnc"
elif command -v nix-env &> /dev/null; then
    PKG_CMD="nix-env -iA nixpkgs.tigervnc"
else
    PKG_CMD=""
fi

if command -v vncviewer &> /dev/null; then
    echo "✅ vncviewer already installed"
else
    if [ -n "$PKG_CMD" ]; then
        echo "  Installing vncviewer..."
        eval $PKG_CMD
        echo "✅ vncviewer installed"
    else
        echo "⚠️  Could not detect package manager"
        echo "   Install tigervnc-viewer manually"
    fi
fi

# ====================================================================
# 3. ADD VNC SSH CONFIG
# ====================================================================
echo ""
echo "[3/4] Configuring SSH for VNC..."

# Backup SSH config
cp "$SSH_CONFIG" "${SSH_CONFIG}.backup.vnc.$(date +%s)"

# Check if VNC config already exists
if grep -q "Host $WINDOWS_VNC_HOST" "$SSH_CONFIG"; then
    echo "✅ VNC configuration already exists"
else
    # Add VNC section
    cat >> "$SSH_CONFIG" << EOF

# ====================================================================
# VNC Access (HomeBridge v1.1)
# Screen sharing with existing Windows session
# ====================================================================
Host $WINDOWS_VNC_HOST
    HostName localhost
    Port 2222
    ProxyJump relay
    LocalForward 15900 localhost:5900
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
EOF
    
    chmod 600 "$SSH_CONFIG"
    echo "✅ VNC configuration added"
    echo "   VNC host: $WINDOWS_VNC_HOST"
fi

# ====================================================================
# 4. TEST CONNECTION
# ====================================================================
echo ""
echo "[4/4] Testing connection..."

read -p "Test SSH connection to VNC host? (y/N): " TEST_VNC
if [[ "$TEST_VNC" =~ ^[Yy]$ ]]; then
    echo "Testing SSH connection..."
    if ssh -o ConnectTimeout=5 "$WINDOWS_VNC_HOST" "echo 'OK'" 2>/dev/null; then
        echo "✅ SSH connection successful"
    else
        echo "⚠️  SSH connection failed"
        echo "   This is normal if Windows VNC tunnel not yet configured"
        echo "   Complete Windows setup first"
    fi
fi

# ====================================================================
# SUMMARY
# ====================================================================
echo ""
echo "========================================"
echo "VNC Client Setup Complete"
echo "========================================"
echo ""
echo "VNC Host configured: $WINDOWS_VNC_HOST"
echo ""
echo "Usage:"
echo "  Manual command:"
echo "    vncviewer -SecurityTypes None localhost:15900"
echo ""
echo "  Full control:"
echo "    ssh -f -N $WINDOWS_VNC_HOST"
echo "    vncviewer -SecurityTypes None localhost:15900"
echo ""
echo "  View-only:"
echo "    ssh -f -N $WINDOWS_VNC_HOST"
echo "    vncviewer -SecurityTypes None -ViewOnly localhost:15900"
echo ""
echo "Prerequisites on Windows:"
echo "  1. VNC server must be running"
echo "  2. SSH tunnel task must be active"
echo ""
echo "Check Windows:"
echo "  ssh $WINDOWS_VNC_HOST 'powershell Get-Process winvnc4'"
echo ""