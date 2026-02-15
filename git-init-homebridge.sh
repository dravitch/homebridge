#!/usr/bin/env bash
# ====================================================================
# HomeBridge - Git Initialization Script
# Initialize local repo and connect to GitHub
# ====================================================================

set -euo pipefail

REPO_URL="git@github.com-dravitch:dravitch/homebridge.git"
BRANCH="main"

echo "🎬 HomeBridge - Git Initialization"
echo "===================================="
echo ""

# ====================================================================
# PHASE 1: Vérifier l'état actuel
# ====================================================================
echo "[1/6] Vérification état actuel..."

if [[ -d .git ]]; then
    echo "  ⚠️  Un repo Git existe déjà"
    echo ""
    read -p "Réinitialiser complètement ? (yes/no): " reinit
    if [[ "$reinit" == "yes" ]]; then
        rm -rf .git
        echo "  ✅ Ancien repo supprimé"
    else
        echo "  ❌ Initialisation annulée"
        exit 0
    fi
else
    echo "  ✅ Pas de repo existant"
fi

# ====================================================================
# PHASE 2: Initialiser le repo local
# ====================================================================
echo ""
echo "[2/6] Initialisation repo local..."

git init
git branch -M "$BRANCH"

echo "  ✅ Repo Git initialisé (branch: $BRANCH)"

# ====================================================================
# PHASE 3: Configurer les remotes
# ====================================================================
echo ""
echo "[3/6] Configuration remote GitHub..."

# Vérifier le SSH GitHub d'abord
echo "  Test connexion GitHub..."
if ssh -T git@github.com-dravitch 2>&1 | grep -q "success\|authenticated"; then
    echo "  ✅ Connexion GitHub OK (compte dravitch)"
else
    echo "  ⚠️  Problème de connexion GitHub"
    echo "  Tester manuellement: ssh -T git@github.com-dravitch"
    echo ""
    read -p "Continuer quand même ? (y/n): " continue_anyway
    if [[ "$continue_anyway" != "y" ]]; then
        exit 1
    fi
fi

# Ajouter la remote
git remote add origin "$REPO_URL"
echo "  ✅ Remote ajoutée: $REPO_URL"

# ====================================================================
# PHASE 4: Créer/vérifier .gitignore
# ====================================================================
echo ""
echo "[4/6] Vérification .gitignore..."

if [[ ! -f .gitignore ]]; then
    echo "  ⚠️  Pas de .gitignore trouvé"
    echo "  Création d'un .gitignore de base..."
    
    cat > .gitignore << 'EOF'
# HomeBridge .gitignore
# Secrets & Keys
*.pem
*.key
id_rsa*
*.pub
authorized_keys
known_hosts

# Environment files
config.env
.env
.env.*

# Backups & Temp
*.backup.*
*.tmp
*.log
*.patch
*~

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
EOF
    
    echo "  ✅ .gitignore créé"
else
    echo "  ✅ .gitignore existe"
fi

# Vérifier qu'aucune clé n'est présente
echo "  Vérification des secrets..."
if find . -name "id_rsa*" -o -name "*.key" -o -name "*.pem" | grep -v ".git" > /dev/null 2>&1; then
    echo "  ⚠️  Fichiers secrets détectés:"
    find . -name "id_rsa*" -o -name "*.key" -o -name "*.pem" | grep -v ".git"
    echo ""
    echo "  Ces fichiers ne seront PAS ajoutés (protégés par .gitignore)"
else
    echo "  ✅ Pas de secrets détectés"
fi

# ====================================================================
# PHASE 5: Premier commit
# ====================================================================
echo ""
echo "[5/6] Création du commit initial..."

# Nettoyer les fichiers temporaires d'abord
echo "  Nettoyage fichiers temporaires..."
find . -name "*.backup.*" -type f -delete 2>/dev/null || true
find . -name "*.tmp" -type f -delete 2>/dev/null || true
find . -name "*.patch" -type f -delete 2>/dev/null || true

# Stager tous les fichiers
git add -A

# Vérifier ce qui sera commité
echo ""
echo "  Fichiers à commiter:"
git status --short | head -20
FILE_COUNT=$(git status --short | wc -l)
if [[ $FILE_COUNT -gt 20 ]]; then
    echo "  ... et $((FILE_COUNT - 20)) autres fichiers"
fi

echo ""
read -p "Continuer avec le commit initial ? (y/n): " do_commit
if [[ "$do_commit" != "y" ]]; then
    echo "  ❌ Commit annulé"
    exit 0
fi

# Créer le commit
COMMIT_MSG="Initial commit: HomeBridge v1.2

- SSH reverse tunnel (Windows → Relay → Linux)
- RDP support with wrapper for Windows HOME
- VNC support for screen sharing
- Automated setup scripts (Windows, Relay, Linux)
- Diagnostic and health check tools
- Multi-machine support (different ports)

Features:
- Secure SSH tunneling
- Key-based authentication only
- Fail2ban protection
- Cross-platform (Windows 10/11, Linux)

Status: Working on papa-windows, ready for fille-windows"

git commit -m "$COMMIT_MSG"

echo "  ✅ Commit initial créé"

# ====================================================================
# PHASE 6: Options de push
# ====================================================================
echo ""
echo "[6/6] Push vers GitHub..."
echo ""
echo "⚠️  Options:"
echo "  1. Push normal (peut échouer si repo non vide)"
echo "  2. Force push (écrase le repo distant)"
echo "  3. Ne pas pousser maintenant"
echo ""
read -p "Choix (1/2/3): " push_choice

case $push_choice in
    1)
        echo "  🚀 Push en cours..."
        if git push -u origin "$BRANCH"; then
            echo "  ✅ Push réussi"
        else
            echo "  ❌ Push échoué"
            echo ""
            echo "  Le repo distant contient peut-être déjà du contenu."
            echo "  Solutions:"
            echo "    • Réessayer avec option 2 (force push)"
            echo "    • Ou faire: git pull --rebase origin main"
        fi
        ;;
    2)
        echo "  ⚠️  Force push va ÉCRASER le repo distant"
        read -p "  Confirmer ? (YES en majuscules): " confirm_force
        if [[ "$confirm_force" == "YES" ]]; then
            echo "  🚀 Force push en cours..."
            git push --force -u origin "$BRANCH"
            echo "  ✅ Force push réussi"
        else
            echo "  ❌ Force push annulé"
        fi
        ;;
    3)
        echo "  ℹ️  Push annulé"
        echo "  Pour pousser plus tard: git push -u origin $BRANCH"
        ;;
    *)
        echo "  ❌ Choix invalide"
        ;;
esac

# ====================================================================
# RÉSUMÉ
# ====================================================================
echo ""
echo "=========================================="
echo "✅ INITIALISATION TERMINÉE"
echo "=========================================="
echo ""
echo "📊 État du repo:"
echo "   • Branch: $(git branch --show-current)"
echo "   • Commits: $(git rev-list --count HEAD)"
echo "   • Remote: $(git remote get-url origin)"
echo ""
echo "🔗 Repo GitHub:"
echo "   https://github.com/dravitch/homebridge"
echo ""
echo "💡 Commandes utiles:"
echo "   • just sync          # Commit + push quotidien"
echo "   • just status        # Voir l'état"
echo "   • just check         # Vérifier secrets"
echo ""
