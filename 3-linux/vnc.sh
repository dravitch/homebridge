#!/usr/bin/env bash
# ====================================================================
# VNC CLIENT - HomeBridge v1.1
# Connexion VNC vers Windows via tunnel SSH
# Usage: ./vnc.sh
# ====================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Configuration
SSH_HOST="papa-windows-vnc"
REMOTE_VNC_PORT=5900
LOCAL_VNC_PORT=15900
VNC_VIEWER_TIMEOUT=300  # 5 minutes

echo -e "${CYAN}"
echo "========================================"
echo "VNC CLIENT - HomeBridge v1.1"
echo "Connexion vers Windows via tunnel SSH"
echo "========================================"
echo -e "${NC}"

# ====================================================================
# [1/6] Vérification client VNC
# ====================================================================
echo -e "\n${YELLOW}[1/6] Vérification du client VNC...${NC}"

VNC_CLIENT=""
VNC_COMMAND=""

# Detect available VNC client
if command -v vncviewer &> /dev/null; then
    VNC_CLIENT="TigerVNC (vncviewer)"
    VNC_COMMAND="vncviewer"
    echo -e "${GREEN}  [OK] TigerVNC détecté${NC}"
elif command -v remmina &> /dev/null; then
    VNC_CLIENT="Remmina"
    VNC_COMMAND="remmina"
    echo -e "${GREEN}  [OK] Remmina détecté${NC}"
else
    echo -e "${RED}  [ERREUR] Aucun client VNC trouvé${NC}"
    echo -e "${YELLOW}  Installez TigerVNC ou Remmina:${NC}"
    echo -e "${CYAN}    # NixOS${NC}"
    echo -e "    nix-env -iA nixos.tigervnc"
    echo -e "${CYAN}    # Ubuntu/Debian${NC}"
    echo -e "    sudo apt install tigervnc-viewer"
    echo -e "${CYAN}    # Fedora${NC}"
    echo -e "    sudo dnf install tigervnc"
    exit 1
fi

# ====================================================================
# [2/6] Vérification configuration SSH
# ====================================================================
echo -e "\n${YELLOW}[2/6] Vérification configuration SSH...${NC}"

# Check SSH config
if ! grep -q "Host $SSH_HOST" ~/.ssh/config 2>/dev/null; then
    echo -e "${RED}  [ERREUR] Configuration SSH manquante pour '$SSH_HOST'${NC}"
    echo -e "${YELLOW}  Ajoutez à ~/.ssh/config:${NC}"
    echo -e "${CYAN}"
    cat << EOF
Host $SSH_HOST
    HostName 172.234.175.48
    Port 2222
    User tunnel
    IdentityFile ~/.ssh/id_rsa
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/control-%r@%h:%p
    ControlPersist 10m
EOF
    echo -e "${NC}"
    exit 1
fi
echo -e "${GREEN}  [OK] Configuration SSH présente${NC}"

# Test SSH connection
echo -e "${GRAY}  Test de connexion SSH...${NC}"
if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" "exit" 2>/dev/null; then
    echo -e "${RED}  [ERREUR] Connexion SSH impossible${NC}"
    echo -e "${YELLOW}  Vérifications:${NC}"
    echo -e "${CYAN}    # Test connexion manuelle${NC}"
    echo -e "    ssh $SSH_HOST"
    echo -e "${CYAN}    # Vérifier relay accessible${NC}"
    echo -e "    ping -c 3 172.234.175.48"
    exit 1
fi
echo -e "${GREEN}  [OK] Connexion SSH fonctionnelle${NC}"

# ====================================================================
# [3/6] Vérification VNC server Windows
# ====================================================================
echo -e "\n${YELLOW}[3/6] Vérification du serveur VNC Windows...${NC}"

echo -e "${GRAY}  Vérification processus winvnc4...${NC}"
if ! ssh -q "$SSH_HOST" "powershell -Command \"Get-Process winvnc4 -ErrorAction SilentlyContinue\"" 2>/dev/null | grep -q "winvnc4"; then
    echo -e "${RED}  [ERREUR] VNC Server non actif sur Windows${NC}"
    echo -e "${YELLOW}  Sur Windows, exécutez:${NC}"
    echo -e "${CYAN}    Double-clic 'Start VNC Server' (bureau)${NC}"
    echo -e "    ${GRAY}ou${NC}"
    echo -e "${CYAN}    powershell C:\\HomeBridge\\scripts\\Start-VNC.ps1${NC}"
    echo -e "${YELLOW}  Attendez 10 secondes puis relancez ce script${NC}"
    exit 1
fi
echo -e "${GREEN}  [OK] VNC Server actif sur Windows${NC}"

# Check VNC port listening
echo -e "${GRAY}  Vérification port VNC ($REMOTE_VNC_PORT)...${NC}"
if ! ssh -q "$SSH_HOST" "powershell -Command \"Get-NetTCPConnection -LocalPort $REMOTE_VNC_PORT -State Listen -ErrorAction SilentlyContinue\"" 2>/dev/null | grep -q "$REMOTE_VNC_PORT"; then
    echo -e "${YELLOW}  [ATTENTION] Port VNC non en écoute${NC}"
    echo -e "${GRAY}  Le processus VNC démarre peut-être, attendez 5 secondes...${NC}"
    sleep 5
    
    # Retry check
    if ! ssh -q "$SSH_HOST" "powershell -Command \"Get-NetTCPConnection -LocalPort $REMOTE_VNC_PORT -State Listen -ErrorAction SilentlyContinue\"" 2>/dev/null | grep -q "$REMOTE_VNC_PORT"; then
        echo -e "${RED}  [ERREUR] Port VNC toujours non accessible${NC}"
        echo -e "${YELLOW}  Sur Windows, vérifiez:${NC}"
        echo -e "${CYAN}    powershell C:\\HomeBridge\\scripts\\Verify-VNC.ps1${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}  [OK] Port VNC en écoute${NC}"

# ====================================================================
# [4/6] Création tunnel SSH local
# ====================================================================
echo -e "\n${YELLOW}[4/6] Création du tunnel SSH local...${NC}"

# Check if port already forwarded
if ss -tlnp 2>/dev/null | grep -q ":$LOCAL_VNC_PORT"; then
    echo -e "${YELLOW}  [INFO] Port $LOCAL_VNC_PORT déjà utilisé${NC}"
    
    # Ask user if they want to kill existing tunnel
    echo -e "${CYAN}  Fermer le tunnel existant? (o/N)${NC}"
    read -r -n 1 -t 5 response || response="n"
    echo ""
    
    if [[ "$response" =~ ^[Oo]$ ]]; then
        echo -e "${GRAY}  Fermeture tunnel existant...${NC}"
        pkill -f "ssh.*$LOCAL_VNC_PORT:localhost:$REMOTE_VNC_PORT" || true
        sleep 2
    else
        echo -e "${GREEN}  [OK] Réutilisation du tunnel existant${NC}"
    fi
fi

# Create tunnel if not exists
if ! ss -tlnp 2>/dev/null | grep -q ":$LOCAL_VNC_PORT"; then
    echo -e "${GRAY}  Création tunnel: localhost:$LOCAL_VNC_PORT → Windows:$REMOTE_VNC_PORT${NC}"
    
    # Create SSH tunnel in background
    ssh -f -N -L "$LOCAL_VNC_PORT:localhost:$REMOTE_VNC_PORT" "$SSH_HOST" 2>/dev/null || {
        echo -e "${RED}  [ERREUR] Impossible de créer le tunnel SSH${NC}"
        echo -e "${YELLOW}  Vérifiez:${NC}"
        echo -e "${CYAN}    ssh -v $SSH_HOST${NC}"
        exit 1
    }
    
    # Wait for tunnel to be ready
    sleep 3
    
    # Verify tunnel
    if ss -tlnp 2>/dev/null | grep -q ":$LOCAL_VNC_PORT"; then
        echo -e "${GREEN}  [OK] Tunnel SSH créé${NC}"
    else
        echo -e "${RED}  [ERREUR] Tunnel SSH non établi${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}  [OK] Tunnel SSH actif${NC}"
fi

# ====================================================================
# [5/6] Choix du mode de connexion
# ====================================================================
echo -e "\n${YELLOW}[5/6] Mode de connexion VNC...${NC}"
echo ""
echo -e "${CYAN}Choisissez le mode de connexion:${NC}"
echo -e "  ${GREEN}1)${NC} Full control (contrôle complet)"
echo -e "  ${YELLOW}2)${NC} View-only (affichage seul)"
echo ""
echo -e -n "${CYAN}Votre choix [1-2] (défaut=1): ${NC}"

# Read user choice with timeout
if read -r -t 10 choice; then
    case "$choice" in
        2)
            VNC_MODE="view-only"
            VNC_ARGS="-ViewOnly"
            echo -e "${YELLOW}  Mode: View-only${NC}"
            ;;
        1|"")
            VNC_MODE="full-control"
            VNC_ARGS=""
            echo -e "${GREEN}  Mode: Full control${NC}"
            ;;
        *)
            echo -e "${YELLOW}  Choix invalide, utilisation Full control${NC}"
            VNC_MODE="full-control"
            VNC_ARGS=""
            ;;
    esac
else
    echo ""
    echo -e "${GRAY}  Timeout, utilisation Full control par défaut${NC}"
    VNC_MODE="full-control"
    VNC_ARGS=""
fi

# ====================================================================
# [6/6] Lancement client VNC
# ====================================================================
echo -e "\n${YELLOW}[6/6] Lancement du client VNC...${NC}"

echo -e "${GRAY}  Client: $VNC_CLIENT${NC}"
echo -e "${GRAY}  Destination: localhost:$LOCAL_VNC_PORT${NC}"
echo -e "${GRAY}  Mode: $VNC_MODE${NC}"
echo ""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Nettoyage...${NC}"
    
    # Kill VNC client if still running
    pkill -f "$VNC_COMMAND.*localhost:$LOCAL_VNC_PORT" 2>/dev/null || true
    
    # Optional: Close SSH tunnel (commented out to keep tunnel for reconnection)
    # pkill -f "ssh.*$LOCAL_VNC_PORT:localhost:$REMOTE_VNC_PORT" 2>/dev/null || true
    
    echo -e "${GREEN}Session VNC fermée${NC}"
}

trap cleanup EXIT INT TERM

# Launch VNC client based on detected client
case "$VNC_COMMAND" in
    vncviewer)
        # TigerVNC viewer
        echo -e "${GREEN}Connexion VNC en cours...${NC}"
        vncviewer -SecurityTypes None $VNC_ARGS "localhost:$LOCAL_VNC_PORT" &
        VNC_PID=$!
        ;;
    remmina)
        # Remmina (create temporary profile)
        REMMINA_PROFILE="/tmp/homebridge-vnc-$$.remmina"
        cat > "$REMMINA_PROFILE" << EOF
[remmina]
name=HomeBridge VNC
protocol=VNC
server=localhost:$LOCAL_VNC_PORT
username=
password=
viewonly=$([ "$VNC_MODE" = "view-only" ] && echo "1" || echo "0")
disableencryption=1
colordepth=32
quality=9
EOF
        echo -e "${GREEN}Connexion VNC en cours...${NC}"
        remmina -c "$REMMINA_PROFILE" &
        VNC_PID=$!
        rm -f "$REMMINA_PROFILE"
        ;;
esac

# Wait for VNC client
echo -e "${GRAY}Client VNC lancé (PID: $VNC_PID)${NC}"
echo -e "${CYAN}Appuyez sur Ctrl+C pour fermer la connexion${NC}"
echo ""

# Monitor VNC client process
while kill -0 $VNC_PID 2>/dev/null; do
    sleep 2
done

echo -e "${YELLOW}Client VNC fermé${NC}"

# ====================================================================
# RÉSUMÉ SESSION
# ====================================================================
echo ""
echo -e "${CYAN}========================================"
echo "SESSION VNC TERMINÉE"
echo "========================================${NC}"
echo ""
echo -e "${GRAY}Le tunnel SSH reste actif pour reconnecter rapidement.${NC}"
echo -e "${GRAY}Pour fermer le tunnel manuellement:${NC}"
echo -e "${CYAN}  pkill -f 'ssh.*$LOCAL_VNC_PORT:localhost:$REMOTE_VNC_PORT'${NC}"
echo ""

exit 0
