#!/usr/bin/env bash
# ====================================================================
# Script RDP pour connexion à Windows via tunnel SSH
# Utilise SSH multiplexing pour éviter les authentifications multiples
# ====================================================================

set -e

# Configuration
WINDOWS_HOST="targetpc-windows"
WINDOWS_USER="tunnel-admin"
LOCAL_RDP_PORT=13389
REMOTE_RDP_PORT=3389
WINDOWS_PASSWORD=""  # Sera demandé interactivement
# Et avant xfreerdp (après ligne 127) :
if [ -z "$WINDOWS_PASSWORD" ]; then
    read -s -p "Mot de passe Windows: " WINDOWS_PASSWORD
    echo ""
    echo ""
fi

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonction de nettoyage
cleanup() {
    echo -e "\n${YELLOW}🧹 Fermeture du tunnel RDP...${NC}"
    # Fermer uniquement le tunnel RDP, pas la connexion master
    pkill -f "ssh.*-L ${LOCAL_RDP_PORT}:127.0.0.1:${REMOTE_RDP_PORT}" 2>/dev/null || true
}

trap cleanup EXIT

echo -e "${BLUE}🖥️  Connexion RDP vers $WINDOWS_HOST...${NC}"
echo ""

# ====================================================================
# 1. Vérifier la connexion SSH de base
# ====================================================================
echo -e "${YELLOW}[1/5]${NC} Vérification de la connexion SSH..."

# Vérifier si une connexion master existe déjà
if ssh -O check "$WINDOWS_HOST" 2>/dev/null; then
    echo -e "${GREEN}  ✅ Connexion SSH master active${NC}"
else
    # Établir une connexion master en arrière-plan
    echo -e "${YELLOW}  📡 Établissement de la connexion master...${NC}"
    ssh -fN -M "$WINDOWS_HOST" 2>/dev/null || {
        echo -e "${RED}  ❌ Impossible d'établir la connexion SSH${NC}"
        echo "  Vérifier :"
        echo "    • Le tunnel reverse Windows est actif"
        echo "    • ssh $WINDOWS_HOST fonctionne"
        exit 1
    }
    sleep 2
    echo -e "${GREEN}  ✅ Connexion SSH établie${NC}"
fi

# ====================================================================
# 2. Vérifier que le tunnel reverse est actif
# ====================================================================
echo -e "${YELLOW}[2/5]${NC} Vérification du tunnel reverse..."

if ssh "$WINDOWS_HOST" "exit" 2>/dev/null; then
    echo -e "${GREEN}  ✅ Tunnel reverse actif${NC}"
else
    echo -e "${RED}  ❌ Tunnel reverse inactif${NC}"
    exit 1
fi

# ====================================================================
# 3. Vérifier que RDP écoute sur Windows
# ====================================================================
echo -e "${YELLOW}[3/5]${NC} Vérification du service RDP..."

RDP_STATUS=$(ssh "$WINDOWS_HOST" 'powershell.exe -Command "Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty State"' 2>/dev/null | tr -d '\r\n' || echo "")

if [ -n "$RDP_STATUS" ]; then
    echo -e "${GREEN}  ✅ RDP actif sur le port 3389${NC}"
else
    echo -e "${RED}  ❌ RDP n'écoute pas${NC}"
    echo "  Sur Windows, exécuter :"
    echo "    Get-Service TermService"
    echo "    netstat -an | findstr 3389"
    exit 1
fi

# ====================================================================
# 4. Créer le tunnel RDP
# ====================================================================
echo -e "${YELLOW}[4/5]${NC} Création du tunnel RDP..."

# Nettoyer les anciens tunnels
pkill -f "ssh.*-L ${LOCAL_RDP_PORT}" 2>/dev/null || true
sleep 1

# Créer le tunnel en utilisant la connexion master existante
ssh -f -N -L ${LOCAL_RDP_PORT}:127.0.0.1:${REMOTE_RDP_PORT} "$WINDOWS_HOST" 2>/dev/null || {
    echo -e "${RED}  ❌ Échec de création du tunnel${NC}"
    exit 1
}

# Attendre que le port soit ouvert
for i in {1..5}; do
    if ss -tlnp 2>/dev/null | grep -q ":${LOCAL_RDP_PORT}"; then
        break
    fi
    sleep 1
done

if ss -tlnp 2>/dev/null | grep -q ":${LOCAL_RDP_PORT}"; then
    echo -e "${GREEN}  ✅ Tunnel établi sur localhost:${LOCAL_RDP_PORT}${NC}"
else
    echo -e "${RED}  ❌ Le port ${LOCAL_RDP_PORT} n'écoute pas${NC}"
    exit 1
fi

# ====================================================================
# 5. Lancer le client RDP
# ====================================================================
echo -e "${YELLOW}[5/5]${NC} Lancement de xfreerdp..."
echo ""
echo -e "${BLUE}════════════════════════════════════${NC}"
echo -e "${GREEN}Utilisateur: $WINDOWS_USER${NC}"
echo -e "${BLUE}════════════════════════════════════${NC}"

# Demander le mot de passe de manière sécurisée
read -s -p "Mot de passe Windows: " WINDOWS_PASSWORD
echo ""
echo ""

# Lancer xfreerdp
xfreerdp \
    /v:127.0.0.1:${LOCAL_RDP_PORT} \
    /u:"${WINDOWS_USER}" \
    /p:"${WINDOWS_PASSWORD}" \
    /cert:ignore \
    /size:1920x1080 \
    /dynamic-resolution \
    /compression \
    /network:auto \
    /gfx:AVC444 \
    +clipboard \
    /audio-mode:0 \
    /video \
    /ipv4 \
    2>/dev/null

# Note : Le cleanup sera automatiquement appelé à la sortie
# La connexion master SSH restera active pendant 10 minutes (ControlPersist)