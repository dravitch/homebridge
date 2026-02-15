#!/usr/bin/env bash
# ====================================================================
# HomeBridge - Clean Git Reset & Push
# One-time use: Reset GitHub repo and push clean local state
# Philosophy: Si vis pacem, para bellum - Do it right once
# ====================================================================

set -euo pipefail

REPO_URL="${REPO_URL:-git@github.com:dravitch/homebridge.git}"
BRANCH="${BRANCH:-main}"

echo "🧹 HomeBridge - Clean Git Reset & Push"
echo "======================================"
echo ""
echo "⚠️  ATTENTION: Ce script va:"
echo "   1. Sauvegarder l'état actuel dans une branche backup"
echo "   2. Supprimer les fichiers temporaires/backup"
echo "   3. Force-push vers GitHub (écrase l'historique distant)"
echo ""
read -p "Continuer ? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "❌ Annulé"
    exit 1
fi

# ====================================================================
# PHASE 1: Sauvegarde de sécurité
# ====================================================================
echo ""
echo "[1/5] 💾 Création backup de sécurité..."

BACKUP_BRANCH="backup-$(date +%Y%m%d-%H%M%S)"
git branch "$BACKUP_BRANCH" 2>/dev/null || true
git checkout "$BACKUP_BRANCH"
git add -A
git commit -m "Backup avant clean reset" || echo "  (rien à committer)"
git checkout "$BRANCH"

echo "  ✅ Backup créé: $BACKUP_BRANCH"

# ====================================================================
# PHASE 2: Nettoyage des fichiers indésirables
# ====================================================================
echo ""
echo "[2/5] 🗑️  Nettoyage fichiers temporaires..."

# Supprimer les backups
find . -name "*.backup.*" -type f -delete
find . -name "*.tmp" -type f -delete
find . -name "*.patch" -type f -delete

# Supprimer les logs
find . -name "*.log" -type f -delete

echo "  ✅ Fichiers temporaires supprimés"

# ====================================================================
# PHASE 3: Vérifier .gitignore
# ====================================================================
echo ""
echo "[3/5] 🔍 Vérification .gitignore..."

if [[ ! -f .gitignore ]]; then
    cat > .gitignore << 'EOF'
# HomeBridge .gitignore
# Secrets & Keys
*.pem
*.key
id_rsa*
*.pub
authorized_keys

# Backups & Temp
*.backup.*
*.tmp
*.log
*.patch

# Config locale
config.env
.env

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.swp
*~
EOF
    echo "  ✅ .gitignore créé"
else
    echo "  ✅ .gitignore existe déjà"
fi

# Vérifier qu'aucune clé n'est trackée
if git ls-files | grep -E '(id_rsa|\.pem|\.key|authorized_keys)' > /dev/null 2>&1; then
    echo "  ⚠️  ATTENTION: Clés SSH détectées dans git!"
    echo ""
    echo "Fichiers à problème:"
    git ls-files | grep -E '(id_rsa|\.pem|\.key|authorized_keys)'
    echo ""
    read -p "Les supprimer du tracking git ? (yes/no): " remove_keys
    if [[ "$remove_keys" == "yes" ]]; then
        git ls-files | grep -E '(id_rsa|\.pem|\.key|authorized_keys)' | xargs git rm --cached
        echo "  ✅ Clés supprimées du tracking"
    else
        echo "  ❌ Opération annulée (clés toujours trackées)"
        exit 1
    fi
fi

# ====================================================================
# PHASE 4: Commit propre
# ====================================================================
echo ""
echo "[4/5] 📝 Création commit propre..."

git add -A

# Message de commit intelligent
COMMIT_MSG="v1.2.0: HomeBridge production-ready

- Fixed: setup-windows.ps1 parsing error
- Added: linux/diagnose-ssh-keys.sh
- Added: windows/windows-health-check.ps1
- Updated: Documentation (README, TROUBLESHOOTING)
- Cleaned: Removed temporary files and backups
- Support: Multi-machine configuration ready

Status: Tested and working on papa-windows
Next: Configure fille-windows"

git commit -m "$COMMIT_MSG" || echo "  (rien de nouveau à committer)"

echo "  ✅ Commit créé"

# ====================================================================
# PHASE 5: Push vers GitHub
# ====================================================================
echo ""
echo "[5/5] 🚀 Push vers GitHub..."
echo ""
echo "⚠️  Dernière confirmation:"
echo "   Repo: $REPO_URL"
echo "   Branch: $BRANCH"
echo "   Action: FORCE PUSH (écrase l'historique distant)"
echo ""
read -p "VRAIMENT pousser ? (YES en majuscules): " final_confirm

if [[ "$final_confirm" != "YES" ]]; then
    echo "❌ Push annulé"
    echo "   Votre backup est sur la branche: $BACKUP_BRANCH"
    exit 1
fi

# Vérifier la remote
if ! git remote get-url origin > /dev/null 2>&1; then
    echo "  ⚠️  Remote 'origin' non configurée"
    git remote add origin "$REPO_URL"
    echo "  ✅ Remote ajoutée: $REPO_URL"
fi

# Force push
echo ""
echo "  🚀 Force push en cours..."
git push --force-with-lease origin "$BRANCH"

echo ""
echo "=========================================="
echo "✅ SYNCHRONISATION TERMINÉE"
echo "=========================================="
echo ""
echo "📊 État final:"
echo "   • Backup: $BACKUP_BRANCH"
echo "   • Branch active: $BRANCH"
echo "   • Remote: $REPO_URL"
echo ""
echo "🔗 Vérifier sur GitHub:"
echo "   https://github.com/dravitch/homebridge"
echo ""
echo "💡 Pour supprimer le backup (plus tard):"
echo "   git branch -D $BACKUP_BRANCH"
echo ""
