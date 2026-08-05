#!/usr/bin/env bash
# ====================================================================
# Configuration initiale NixOS pour accès à TargetPC-windows
# ====================================================================

set -e

echo "======================================"
echo "Configuration NixOS - TargetPC Windows"
echo "======================================"
echo ""

# Variables à personnaliser
read -p "Adresse IP du relay: " RELAY_IP
read -p "Nom d'utilisateur Windows [tunnel-admin]: " WINDOWS_USER
WINDOWS_USER=${WINDOWS_USER:-tunnel-admin}

SSH_CONFIG="$HOME/.ssh/config"
SSH_DIR="$HOME/.ssh"

# ====================================================================
# 1. Vérifier les prérequis
# ====================================================================
echo "[1/6] Vérification des prérequis..."

# Vérifier que ssh existe
if ! command -v ssh &> /dev/null; then
    echo "❌ OpenSSH client non installé"
    exit 1
fi

# Vérifier que xfreerdp existe
if ! command -v xfreerdp &> /dev/null; then
    echo "⚠️  xfreerdp non installé (nécessaire pour RDP)"
    echo "   Installer avec: nix-env -iA nixpkgs.freerdp"
fi

echo "✅ Prérequis OK"

# ====================================================================
# 2. Créer/vérifier la clé SSH
# ====================================================================
echo "[2/6] Vérification de la clé SSH..."

if [ ! -f "$SSH_DIR/id_rsa" ]; then
    echo "Génération d'une nouvelle clé SSH..."
    ssh-keygen -t rsa -b 4096 -C "nixos-to-relay" -f "$SSH_DIR/id_rsa" -N ""
fi

echo "✅ Clé SSH présente"

# ====================================================================
# 3. Sauvegarder l'ancienne config SSH
# ====================================================================
echo "[3/6] Configuration SSH..."

if [ -f "$SSH_CONFIG" ]; then
    cp "$SSH_CONFIG" "${SSH_CONFIG}.backup.$(date +%s)"
    echo "✅ Sauvegarde créée: ${SSH_CONFIG}.backup.*"
fi

# ====================================================================
# 4. Créer la nouvelle configuration SSH
# ====================================================================
echo "[4/6] Création de ~/.ssh/config..."

# Créer le répertoire de contrôle pour multiplexing
mkdir -p "$SSH_DIR/control"
chmod 700 "$SSH_DIR/control"

# Écrire la configuration
cat > "$SSH_CONFIG" << EOF
# ====================================================================
# Configuration SSH - TargetPC Windows
# Générée par setup-nixos.sh
# ====================================================================

# SSH Multiplexing - Éviter les authentifications multiples
Host *
    ControlMaster auto
    ControlPath ~/.ssh/control/%r@%h:%p
    ControlPersist 10m
    Compression yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    NumberOfPasswordPrompts 1
    PreferredAuthentications publickey,password
    PubkeyAuthentication yes

# ====================================================================
# Serveur Relay
# ====================================================================
Host relay
    HostName $RELAY_IP
    User tunnel
    Port 22
    IdentityFile ~/.ssh/id_rsa

# ====================================================================
# PC Windows via tunnel reverse
# ====================================================================
Host targetpc-windows
    HostName localhost
    User $WINDOWS_USER
    Port 2222
    ProxyJump relay
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking accept-new
    PasswordAuthentication no
    PubkeyAuthentication yes
EOF

chmod 600 "$SSH_CONFIG"

echo "✅ Configuration SSH créée"

# ====================================================================
# 5. Afficher les instructions
# ====================================================================
echo "[5/6] Instructions pour finaliser la configuration..."
echo ""
echo "════════════════════════════════════════════════════"
echo "VOTRE CLÉ PUBLIQUE (à copier):"
echo "════════════════════════════════════════════════════"
cat "$SSH_DIR/id_rsa.pub"
echo "════════════════════════════════════════════════════"
echo ""
echo "ÉTAPES À SUIVRE:"
echo ""
echo "1️⃣  Sur le RELAY ($RELAY_IP):"
echo "   ssh root@$RELAY_IP"
echo "   # Puis exécuter:"
echo "   echo 'COLLER_LA_CLE_CI-DESSUS' >> /home/tunnel/.ssh/authorized_keys"
echo ""
echo "2️⃣  Sur WINDOWS (via le tunnel reverse après configuration):"
echo "   ssh -p 2222 $WINDOWS_USER@$RELAY_IP"
echo "   # Puis dans PowerShell:"
echo '   $key = "COLLER_LA_CLE_CI-DESSUS"'
echo '   mkdir "$env:USERPROFILE\.ssh" -Force'
echo '   Add-Content -Path "$env:USERPROFILE\.ssh\authorized_keys" -Value $key'
echo '   icacls.exe "$env:USERPROFILE\.ssh\authorized_keys" /inheritance:r'
echo '   icacls.exe "$env:USERPROFILE\.ssh\authorized_keys" /grant "${env:USERNAME}:(F)"'
echo '   Restart-Service sshd'
echo ""

# ====================================================================
# 6. Tests
# ====================================================================
echo "[6/6] Tests de connexion..."
echo ""

read -p "Voulez-vous tester la connexion au relay maintenant? (y/N): " TEST_RELAY
if [[ "$TEST_RELAY" =~ ^[Yy]$ ]]; then
    echo "Test de connexion au relay..."
    if ssh -o ConnectTimeout=5 relay "echo 'Connexion OK'"; then
        echo "✅ Connexion au relay réussie"
    else
        echo "❌ Impossible de se connecter au relay"
        echo "   Vérifier que votre clé publique est bien ajoutée sur le relay"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════"
echo "Configuration terminée !"
echo "════════════════════════════════════════════════════"
echo ""
echo "Prochaines étapes:"
echo "  1. Configurer Windows avec windows-tunnel-complete-setup.ps1"
echo "  2. Tester: ssh targetpc-windows whoami"
echo "  3. RDP: ./rdp.sh"
echo ""
echo "Documentation complète dans README.md"
echo ""