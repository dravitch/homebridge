#!/usr/bin/env bash
# ====================================================================
# HomeBridge - Add fille-windows to SSH config
# Execute on NixOS to add SSH configuration for fille-windows
# ====================================================================

set -euo pipefail

SSH_CONFIG="$HOME/.ssh/config"
FILLE_USER="${FILLE_USER:-tunnel}"  # Change if different

echo "🔧 HomeBridge - Add fille-windows SSH config"
echo "============================================="
echo ""

# Vérifier que le fichier existe
if [[ ! -f "$SSH_CONFIG" ]]; then
    echo "❌ $SSH_CONFIG n'existe pas"
    exit 1
fi

# Vérifier si fille-windows existe déjà
if grep -q "^Host fille-windows$" "$SSH_CONFIG"; then
    echo "⚠️  Configuration fille-windows existe déjà"
    echo ""
    read -p "Remplacer ? (y/n): " replace
    if [[ "$replace" != "y" ]]; then
        echo "❌ Opération annulée"
        exit 0
    fi
    
    # Supprimer l'ancienne config
    sed -i '/^Host fille-windows$/,/^$/d' "$SSH_CONFIG"
    echo "✅ Ancienne configuration supprimée"
fi

# Ajouter la nouvelle configuration
echo ""
echo "📝 Ajout de la configuration fille-windows..."

cat >> "$SSH_CONFIG" << 'EOF'

# ====================================================================
# Machine fille-windows (HomeBridge v1.2)
# Port reverse tunnel: 2223
# ====================================================================
Host fille-windows
    HostName localhost
    User tunnel
    Port 2223
    ProxyJump relay
    IdentityFile ~/.ssh/id_rsa
    ServerAliveInterval 60
    ServerAliveCountMax 3
    StrictHostKeyChecking accept-new

# Tunnel direct pour RDP (méthode alternative)
Host fille-windows-direct
    HostName localhost
    User tunnel
    Port 2223
    ProxyCommand ssh -W %h:%p relay
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking accept-new

# Configuration VNC pour fille-windows
Host fille-windows-vnc
    HostName localhost
    User tunnel
    Port 2223
    ProxyJump relay
    LocalForward 15901 localhost:5900
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking accept-new
EOF

echo "✅ Configuration ajoutée"
echo ""

# Afficher la config
echo "📋 Configuration SSH fille-windows:"
echo "-----------------------------------"
sed -n '/^Host fille-windows$/,/^$/p' "$SSH_CONFIG" | sed 's/^/  /'
echo ""

# Tester la connexion
echo "🧪 Test de connexion..."
echo ""

if timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes fille-windows exit 2>/dev/null; then
    echo "✅ Connexion SSH réussie!"
    echo ""
    echo "Test complet:"
    ssh fille-windows "whoami; hostname"
else
    echo "❌ Connexion échoue (Permission denied)"
    echo ""
    echo "💡 Actions requises:"
    echo "   1. Ajouter votre clé publique sur fille-windows"
    echo "   2. Exécuter sur fille-windows:"
    echo ""
    echo "PowerShell (en tant qu'Administrateur):"
    cat << 'EOFPS'
$key = "VOTRE_CLE_PUBLIQUE_ICI"
$authKeysPath = "$env:USERPROFILE\.ssh\authorized_keys"
New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh" -Force
Add-Content -Path $authKeysPath -Value $key
icacls.exe $authKeysPath /inheritance:r
icacls.exe $authKeysPath /grant "${env:USERNAME}:(F)"
icacls.exe $authKeysPath /grant "SYSTEM:(F)"
Restart-Service sshd
EOFPS
    echo ""
    echo "   Votre clé publique:"
    cat ~/.ssh/id_rsa.pub
fi

echo ""
echo "=========================================="
echo "✅ CONFIGURATION TERMINÉE"
echo "=========================================="
echo ""
echo "📊 Commandes disponibles:"
echo "   ssh fille-windows              # Connexion SSH"
echo "   ssh fille-windows whoami       # Test rapide"
echo ""
echo "🔜 Prochaines étapes:"
echo "   1. Ajouter votre clé sur fille-windows (si pas déjà fait)"
echo "   2. Créer rdp-fille.sh pour connexion RDP"
echo "   3. Créer vnc-fille.sh pour connexion VNC"
echo ""
