#!/usr/bin/env bash
# ====================================================================
# HomeBridge - RDP Connection to fille-windows
# Opens RDP session via SSH tunnel
# ====================================================================

set -euo pipefail

# Configuration
WINDOWS_HOST="fille-windows"
LOCAL_RDP_PORT=13390  # Different from papa (13389)
REMOTE_RDP_PORT=3389
WINDOWS_USER="${WINDOWS_USER:-tunnel}"

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🖥️  Connexion RDP vers fille-windows..."
echo ""

# ====================================================================
# 1. Vérifier connexion SSH
# ====================================================================
echo "[1/5] Vérification de la connexion SSH..."
if timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes "$WINDOWS_HOST" exit 2>/dev/null; then
    echo -e "  ${GREEN}✅ SSH OK${NC}"
else
    echo -e "  ${RED}❌ Connexion SSH impossible${NC}"
    echo "  Vérifier :"
    echo "    • Le tunnel reverse Windows est actif"
    echo "    • ssh fille-windows fonctionne"
    exit 1
fi

# ====================================================================
# 2. Vérifier que RDP est actif sur Windows
# ====================================================================
echo ""
echo "[2/5] Vérification du service RDP..."
RDP_CHECK=$(ssh "$WINDOWS_HOST" "powershell.exe -Command \"(Get-Service TermService).Status\"" 2>/dev/null || echo "Error")

if [[ "$RDP_CHECK" == *"Running"* ]]; then
    echo -e "  ${GREEN}✅ RDP actif sur Windows${NC}"
else
    echo -e "  ${YELLOW}⚠️  RDP status: $RDP_CHECK${NC}"
    echo "  Sur Windows, vérifier :"
    echo "    Get-Service TermService"
    echo "    Get-NetTCPConnection -LocalPort 3389"
fi

# ====================================================================
# 3. Fermer tunnel existant si présent
# ====================================================================
echo ""
echo "[3/5] Nettoyage des tunnels existants..."
# Chercher les processus ssh avec le port local
if pgrep -f "ssh.*$LOCAL_RDP_PORT:localhost:$REMOTE_RDP_PORT" > /dev/null; then
    pkill -f "ssh.*$LOCAL_RDP_PORT:localhost:$REMOTE_RDP_PORT"
    sleep 1
    echo -e "  ${GREEN}✅ Ancien tunnel fermé${NC}"
else
    echo "  ℹ️  Pas de tunnel existant"
fi

# ====================================================================
# 4. Créer le tunnel SSH
# ====================================================================
echo ""
echo "[4/5] Création du tunnel RDP..."
echo "  Local: 127.0.0.1:$LOCAL_RDP_PORT → Remote: $REMOTE_RDP_PORT"

# Créer le tunnel en arrière-plan
ssh -f -N -L "$LOCAL_RDP_PORT:localhost:$REMOTE_RDP_PORT" "$WINDOWS_HOST"

# Attendre que le tunnel soit prêt
sleep 2

# Vérifier que le port local écoute
if ss -tlnp 2>/dev/null | grep -q ":$LOCAL_RDP_PORT"; then
    echo -e "  ${GREEN}✅ Tunnel créé${NC}"
else
    echo -e "  ${RED}❌ Tunnel création échouée${NC}"
    exit 1
fi

# ====================================================================
# 5. Lancer xfreerdp
# ====================================================================
echo ""
echo "[5/5] Lancement de xfreerdp..."
echo ""

# Vérifier que xfreerdp est installé
if ! command -v xfreerdp &> /dev/null; then
    echo -e "${RED}❌ xfreerdp n'est pas installé${NC}"
    echo "Installer avec: nix-env -iA nixpkgs.freerdp"
    
    # Fermer le tunnel
    pkill -f "ssh.*$LOCAL_RDP_PORT:localhost:$REMOTE_RDP_PORT"
    exit 1
fi

# Paramètres RDP optimisés
xfreerdp \
    /v:127.0.0.1:$LOCAL_RDP_PORT \
    /u:"$WINDOWS_USER" \
    /cert:ignore \
    /dynamic-resolution \
    /audio-mode:0 \
    /clipboard \
    /drive:home,"$HOME" \
    +compression \
    /network:auto \
    /gfx:AVC444 \
    /smart-sizing \
    2>/dev/null || {
        echo ""
        echo -e "${YELLOW}⚠️  xfreerdp s'est fermé${NC}"
    }

# ====================================================================
# Nettoyage à la fermeture
# ====================================================================
echo ""
echo "🧹 Fermeture du tunnel RDP..."
pkill -f "ssh.*$LOCAL_RDP_PORT:localhost:$REMOTE_RDP_PORT" 2>/dev/null || true

echo -e "${GREEN}✅ Terminé${NC}"
