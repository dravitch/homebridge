#!/usr/bin/env bash
# ====================================================================
# HomeBridge - Simple Git Sync
# Daily workflow: commit + push avec vérifications
# Philosophy: In armis jus ac pax - Peace through automation
# ====================================================================

set -euo pipefail

BRANCH="${BRANCH:-main}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

print_ok() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠️${NC}  $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# ====================================================================
# PHASE 1: Vérifications pré-sync
# ====================================================================
print_step "HomeBridge Git Sync"
echo ""

# Vérifier qu'on est dans le bon repo
if [[ ! -d .git ]]; then
    print_error "Pas un repo git. Lancer depuis la racine de homebridge/"
    exit 1
fi

# Vérifier la branche
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
    print_warn "Branche actuelle: $CURRENT_BRANCH (attendu: $BRANCH)"
    read -p "Changer vers $BRANCH ? (y/n): " switch
    if [[ "$switch" == "y" ]]; then
        git checkout "$BRANCH"
    else
        print_error "Sync annulé"
        exit 1
    fi
fi

# ====================================================================
# PHASE 2: Vérifier les secrets
# ====================================================================
print_step "Vérification secrets..."

SECRETS_FOUND=0

# Chercher des clés dans les fichiers modifiés/nouveaux
while IFS= read -r file; do
    if [[ -f "$file" ]]; then
        if grep -qE "(BEGIN.*PRIVATE KEY|ssh-rsa.*PRIVATE|password.*=|token.*=)" "$file" 2>/dev/null; then
            print_error "Secret détecté dans: $file"
            SECRETS_FOUND=1
        fi
    fi
done < <(git diff --name-only HEAD)

if [[ $SECRETS_FOUND -eq 1 ]]; then
    print_error "Secrets détectés! Nettoyez avant de continuer."
    exit 1
fi

print_ok "Pas de secrets détectés"

# ====================================================================
# PHASE 3: Status et modifications
# ====================================================================
print_step "Status du repo..."

# Récupérer le status
STATUS=$(git status --porcelain)

if [[ -z "$STATUS" ]]; then
    print_ok "Rien à committer"
    
    # Vérifier si on est à jour avec remote
    git fetch origin "$BRANCH" --quiet
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
    
    if [[ "$LOCAL" == "$REMOTE" ]]; then
        print_ok "Déjà synchronisé avec GitHub"
        exit 0
    else
        print_warn "Des commits locaux existent"
        read -p "Pousser vers GitHub ? (y/n): " push_only
        if [[ "$push_only" == "y" ]]; then
            git push origin "$BRANCH"
            print_ok "Push réussi"
            exit 0
        else
            exit 0
        fi
    fi
fi

# Afficher les modifications
echo ""
echo "Fichiers modifiés/nouveaux:"
git status --short | sed 's/^/  /'

# ====================================================================
# PHASE 4: Commit intelligent
# ====================================================================
echo ""
print_step "Création du commit..."

# Demander le message de commit
echo ""
read -p "Message de commit (vide = auto): " USER_MSG

if [[ -z "$USER_MSG" ]]; then
    # Auto-générer un message basé sur les fichiers modifiés
    MODIFIED=$(git diff --name-only --cached --diff-filter=M | wc -l)
    ADDED=$(git diff --name-only --cached --diff-filter=A | wc -l)
    DELETED=$(git diff --name-only --cached --diff-filter=D | wc -l)
    
    COMMIT_MSG="Update HomeBridge"
    [[ $ADDED -gt 0 ]] && COMMIT_MSG="$COMMIT_MSG: +$ADDED files"
    [[ $MODIFIED -gt 0 ]] && COMMIT_MSG="$COMMIT_MSG, ~$MODIFIED modified"
    [[ $DELETED -gt 0 ]] && COMMIT_MSG="$COMMIT_MSG, -$DELETED deleted"
    
    echo "Message auto: $COMMIT_MSG"
else
    COMMIT_MSG="$USER_MSG"
fi

# Stager tous les changements
git add -A

# Créer le commit
if git commit -m "$COMMIT_MSG"; then
    print_ok "Commit créé"
else
    print_error "Échec du commit"
    exit 1
fi

# ====================================================================
# PHASE 5: Push vers GitHub
# ====================================================================
echo ""
print_step "Push vers GitHub..."

if git push origin "$BRANCH"; then
    print_ok "Synchronisation réussie"
    
    echo ""
    echo "=========================================="
    echo "✅ SYNC TERMINÉ"
    echo "=========================================="
    echo ""
    echo "📊 Derniers commits:"
    git log --oneline -3 | sed 's/^/  /'
    echo ""
    echo "🔗 Voir sur GitHub:"
    echo "   https://github.com/dravitch/homebridge"
    echo ""
else
    print_error "Échec du push"
    echo ""
    echo "💡 Solutions possibles:"
    echo "   • Vérifier la connexion internet"
    echo "   • Vérifier les droits SSH: ssh -T git@github.com"
    echo "   • Pull avant push: git pull --rebase origin $BRANCH"
    exit 1
fi
