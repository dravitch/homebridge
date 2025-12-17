#!/usr/bin/env bash
# ====================================================================
# SETUP RELAY VNC - HomeBridge v1.1
# Ajoute support VNC au relay existant (suppose setup-relay.sh exécuté)
# Usage: sudo ./setup-relay-vnc.sh
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
TUNNEL_USER="tunnel"
VNC_PORT=15900
HOMEBRIDGE_LOG_DIR="/var/log/homebridge"
MONITOR_SCRIPT="/usr/local/bin/check-vnc-tunnel.sh"

echo -e "${CYAN}"
echo "========================================"
echo "SETUP RELAY VNC - HomeBridge v1.1"
echo "Ajoute support VNC au relay existant"
echo "========================================"
echo -e "${NC}"

# ====================================================================
# VÉRIFICATION PRÉREQUIS
# ====================================================================
echo -e "\n${YELLOW}[1/5] Vérification des prérequis...${NC}"

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}  [ERREUR] Ce script doit être exécuté en tant que root${NC}"
   echo -e "${YELLOW}  Utilisez: sudo ./setup-relay-vnc.sh${NC}"
   exit 1
fi
echo -e "${GREEN}  [OK] Privilèges root${NC}"

# Check tunnel user exists
if ! id "$TUNNEL_USER" &>/dev/null; then
    echo -e "${RED}  [ERREUR] Utilisateur '$TUNNEL_USER' n'existe pas${NC}"
    echo -e "${YELLOW}  Exécutez d'abord: ./setup-relay.sh${NC}"
    exit 1
fi
echo -e "${GREEN}  [OK] Utilisateur tunnel existe${NC}"

# Check SSH configured
if [[ ! -d "/home/$TUNNEL_USER/.ssh" ]]; then
    echo -e "${RED}  [ERREUR] SSH non configuré pour l'utilisateur tunnel${NC}"
    echo -e "${YELLOW}  Exécutez d'abord: ./setup-relay.sh${NC}"
    exit 1
fi
echo -e "${GREEN}  [OK] SSH configuré${NC}"

# ====================================================================
# CONFIGURATION SSH VNC
# ====================================================================
echo -e "\n${YELLOW}[2/5] Configuration SSH pour VNC...${NC}"

AUTHORIZED_KEYS="/home/$TUNNEL_USER/.ssh/authorized_keys"

echo -e "${CYAN}Collez la clé publique SSH Windows VNC (affichée par setup-windows-vnc.ps1):${NC}"
echo -e "${GRAY}Format attendu: ssh-rsa AAAAB3NzaC1yc2EA... windows-homebridge-tunnel${NC}"
echo -e "${GRAY}Appuyez sur Entrée deux fois pour terminer${NC}"
echo ""

# Read public key (multi-line support)
VNC_PUBLIC_KEY=""
while IFS= read -r line; do
    [[ -z "$line" ]] && break
    VNC_PUBLIC_KEY+="$line"
done

# Validate key format
if [[ ! "$VNC_PUBLIC_KEY" =~ ^ssh-(rsa|ed25519) ]]; then
    echo -e "${RED}  [ERREUR] Format de clé invalide${NC}"
    echo -e "${YELLOW}  La clé doit commencer par 'ssh-rsa' ou 'ssh-ed25519'${NC}"
    exit 1
fi

# Check if key already exists
if grep -Fq "$VNC_PUBLIC_KEY" "$AUTHORIZED_KEYS" 2>/dev/null; then
    echo -e "${YELLOW}  [INFO] Clé déjà présente dans authorized_keys${NC}"
else
    echo "$VNC_PUBLIC_KEY" >> "$AUTHORIZED_KEYS"
    echo -e "${GREEN}  [OK] Clé ajoutée à authorized_keys${NC}"
fi

# Fix permissions
chown "$TUNNEL_USER:$TUNNEL_USER" "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"
echo -e "${GREEN}  [OK] Permissions configurées (600)${NC}"

# ====================================================================
# CONFIGURATION FIREWALL (si UFW actif)
# ====================================================================
echo -e "\n${YELLOW}[3/5] Configuration firewall...${NC}"

if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo -e "${GRAY}  UFW détecté, vérification règles...${NC}"
    
    # VNC tunnel port already allowed by SSH rules (port 2222)
    # No additional rules needed as tunnel uses existing SSH connection
    echo -e "${GREEN}  [OK] Aucune règle firewall supplémentaire requise${NC}"
    echo -e "${GRAY}  Le tunnel VNC utilise la connexion SSH existante (port 2222)${NC}"
else
    echo -e "${GRAY}  [INFO] UFW non actif, aucune règle à configurer${NC}"
fi

# ====================================================================
# SCRIPT MONITORING VNC
# ====================================================================
echo -e "\n${YELLOW}[4/5] Installation du script de monitoring...${NC}"

# Create log directory
mkdir -p "$HOMEBRIDGE_LOG_DIR"
chown "$TUNNEL_USER:$TUNNEL_USER" "$HOMEBRIDGE_LOG_DIR"
chmod 755 "$HOMEBRIDGE_LOG_DIR"

# Create monitoring script
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/usr/bin/env bash
# ====================================================================
# CHECK VNC TUNNEL - HomeBridge v1.1
# Vérifie l'état du tunnel VNC reverse
# ====================================================================

VNC_PORT=15900
LOG_FILE="/var/log/homebridge/vnc-tunnel.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if VNC tunnel port is listening
if ss -tlnp 2>/dev/null | grep -q ":$VNC_PORT"; then
    log "✅ VNC tunnel actif (port $VNC_PORT)"
    
    # Get connection info
    CONN_INFO=$(ss -tlnp 2>/dev/null | grep ":$VNC_PORT")
    log "   Détails: $CONN_INFO"
    
    exit 0
else
    log "❌ VNC tunnel inactif (port $VNC_PORT non en écoute)"
    log "   Vérifiez la connexion Windows → Relay"
    exit 1
fi
EOF

chmod +x "$MONITOR_SCRIPT"
echo -e "${GREEN}  [OK] Script de monitoring créé: $MONITOR_SCRIPT${NC}"

# ====================================================================
# TEST CONNEXION
# ====================================================================
echo -e "\n${YELLOW}[5/5] Test de la configuration...${NC}"

echo -e "${GRAY}  Attente du tunnel Windows (10 secondes)...${NC}"
sleep 10

# Check if VNC port is listening
if ss -tlnp 2>/dev/null | grep -q ":$VNC_PORT"; then
    echo -e "${GREEN}  [OK] Port $VNC_PORT en écoute${NC}"
    echo -e "${GREEN}  [OK] Tunnel VNC actif${NC}"
    
    # Show connection details
    CONN_INFO=$(ss -tlnp 2>/dev/null | grep ":$VNC_PORT" | head -n1)
    echo -e "${GRAY}  Détails: $CONN_INFO${NC}"
else
    echo -e "${YELLOW}  [INFO] Port $VNC_PORT pas encore en écoute${NC}"
    echo -e "${GRAY}  Ceci est normal si le tunnel Windows n'est pas encore établi${NC}"
    echo -e "${GRAY}  Après démarrage du tunnel Windows, vérifiez avec:${NC}"
    echo -e "${CYAN}    sudo ss -tlnp | grep $VNC_PORT${NC}"
fi

# ====================================================================
# RÉSUMÉ FINAL
# ====================================================================
echo -e "\n${CYAN}"
echo "========================================"
echo "CONFIGURATION RELAY VNC TERMINÉE"
echo "========================================"
echo -e "${NC}"

echo -e "\n${YELLOW}COMPOSANTS INSTALLÉS:${NC}"
echo -e "${GREEN}  ✅ Clé SSH VNC autorisée${NC}"
echo -e "${GREEN}  ✅ Script de monitoring${NC}"
echo -e "${GREEN}  ✅ Logs configurés${NC}"

echo -e "\n${YELLOW}PORT VNC:${NC}"
echo -e "${CYAN}  Relay tunnel: $VNC_PORT${NC}"

echo -e "\n${YELLOW}VÉRIFICATIONS:${NC}"
echo -e "${CYAN}  # Vérifier tunnel actif${NC}"
echo -e "  sudo ss -tlnp | grep $VNC_PORT"
echo ""
echo -e "${CYAN}  # Exécuter monitoring${NC}"
echo -e "  sudo $MONITOR_SCRIPT"
echo ""
echo -e "${CYAN}  # Voir logs tunnel${NC}"
echo -e "  sudo tail -f $HOMEBRIDGE_LOG_DIR/vnc-tunnel.log"

echo -e "\n${YELLOW}PROCHAINES ÉTAPES:${NC}"
echo -e "  1. Sur Windows: Double-clic 'Start VNC Server' (bureau)"
echo -e "  2. Attendre 10 secondes"
echo -e "  3. Sur Linux client: ./vnc.sh"

echo -e "\n${YELLOW}TROUBLESHOOTING:${NC}"
echo -e "  Si le tunnel n'apparaît pas:"
echo -e "  ${CYAN}# Sur relay${NC}"
echo -e "  sudo ss -tlnp | grep $VNC_PORT"
echo -e "  sudo tail -n 50 /var/log/auth.log | grep tunnel"
echo ""
echo -e "  ${CYAN}# Sur Windows${NC}"
echo -e "  Get-ScheduledTask -TaskName 'SSH-Reverse-Tunnel-VNC' | Select State"
echo -e "  Get-Content C:\\HomeBridge\\logs\\vnc-tunnel.log -Tail 20"

echo -e "\n${CYAN}=======================================${NC}\n"

exit 0
