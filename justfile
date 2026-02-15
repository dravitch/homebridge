# ====================================================================
# HomeBridge Justfile
# Workflow automation compatible avec Universal Workflow 2026
# ====================================================================

# Default recipe (affiche l'aide)
default:
    @just --list

# ====================================================================
# GIT SYNC - Compatible avec workflow universel
# ====================================================================

# Sync rapide : commit + push (usage quotidien)
sync MESSAGE="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{MESSAGE}}" ]; then
        ./git-sync.sh
    else
        git add -A
        git commit -m "{{MESSAGE}}"
        git push origin main
        echo "✅ Sync terminé avec message: {{MESSAGE}}"
    fi

# Alias pour compatibilité workflow universel
git-sync MESSAGE="": (sync MESSAGE)

# Reset propre + force push (usage unique ou recovery)
reset:
    @echo "⚠️  ATTENTION: Reset complet et force push"
    @echo "Continuer ? (Ctrl+C pour annuler)"
    @read -p "Press Enter to continue..."
    ./git-clean-and-push.sh

# ====================================================================
# VÉRIFICATIONS - Sécurité avant commit
# ====================================================================

# Vérifier qu'aucune clé SSH n'est trackée
check:
    @echo "🔍 Vérification gitignore et secrets..."
    @./check_gitignore.sh
    @echo "✅ Vérification terminée"

# Check avant sync (automatique)
check-before-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔍 Pré-vérification..."
    
    # Vérifier les secrets dans les fichiers modifiés
    if git diff --name-only HEAD | xargs grep -lE "(BEGIN.*PRIVATE KEY|ssh-rsa.*PRIVATE)" 2>/dev/null; then
        echo "❌ ERREUR: Secrets détectés dans les modifications!"
        exit 1
    fi
    
    echo "✅ Pré-vérification OK"

# Sync avec vérification automatique
safe-sync MESSAGE="": check-before-sync (sync MESSAGE)

# ====================================================================
# DIAGNOSTIC - Debug et troubleshooting
# ====================================================================

# Status git détaillé
status:
    @echo "📊 Status HomeBridge"
    @echo "===================="
    @echo ""
    @echo "Branch:"
    @git branch --show-current
    @echo ""
    @echo "Derniers commits:"
    @git log --oneline -5
    @echo ""
    @echo "Fichiers modifiés:"
    @git status --short
    @echo ""
    @echo "Remote:"
    @git remote -v

# Tester les connexions SSH
test-ssh:
    @echo "🔐 Test SSH Keys"
    @echo "================"
    @echo ""
    @echo "[1/3] GitHub (dravitch)..."
    @ssh -T git@github.com-dravitch 2>&1 | grep -i "success\|authenticated" || echo "❌ Échec"
    @echo ""
    @echo "[2/3] Relay server..."
    @ssh -o ConnectTimeout=5 relay "echo '✅ Relay OK'" || echo "❌ Relay échec"
    @echo ""
    @echo "[3/3] Papa-windows..."
    @ssh -o ConnectTimeout=5 papa-windows "echo '✅ Windows OK'" || echo "⚠️  Windows non accessible (normal si pas de clé configurée)"

# Diagnostic SSH complet (si script existe)
diagnose-ssh:
    @if [ -f "3-linux/diagnose-ssh-keys.sh" ]; then \
        ./3-linux/diagnose-ssh-keys.sh; \
    else \
        echo "❌ Script diagnose-ssh-keys.sh introuvable"; \
    fi

# ====================================================================
# MAINTENANCE - Nettoyage et organisation
# ====================================================================

# Nettoyer les fichiers temporaires (sans toucher à git)
clean:
    @echo "🧹 Nettoyage fichiers temporaires..."
    @find . -name "*.backup.*" -type f -delete 2>/dev/null || true
    @find . -name "*.tmp" -type f -delete 2>/dev/null || true
    @find . -name "*.log" -type f -delete 2>/dev/null || true
    @find . -name "*.patch" -type f -delete 2>/dev/null || true
    @echo "✅ Nettoyage terminé"

# Nettoyer + sync
clean-sync MESSAGE="": clean (sync MESSAGE)

# ====================================================================
# DOCUMENTATION - Aide et guides
# ====================================================================

# Afficher le workflow recommandé
workflow:
    @echo "📖 Workflow HomeBridge"
    @echo "======================"
    @echo ""
    @echo "🔄 USAGE QUOTIDIEN:"
    @echo "  just sync                    # Commit + push auto"
    @echo "  just sync 'message'          # Commit + push avec message"
    @echo "  just safe-sync               # Sync avec vérifications"
    @echo ""
    @echo "🔍 DIAGNOSTIC:"
    @echo "  just status                  # Status git détaillé"
    @echo "  just test-ssh                # Tester connexions SSH"
    @echo "  just diagnose-ssh            # Diagnostic SSH complet"
    @echo ""
    @echo "🧹 MAINTENANCE:"
    @echo "  just clean                   # Nettoyer fichiers temp"
    @echo "  just check                   # Vérifier secrets"
    @echo "  just reset                   # Reset complet (⚠️ force push)"
    @echo ""
    @echo "💡 EXEMPLES:"
    @echo "  just sync 'Fix setup-windows.ps1 parsing error'"
    @echo "  just clean-sync 'Update docs'"
    @echo "  just safe-sync"
    @echo ""

# Afficher les commandes disponibles (alias de default)
help: default

# ====================================================================
# WINDOWS SPECIFIC - Scripts PowerShell
# ====================================================================

# Health check Windows (si connecté)
health-check-windows:
    @if ssh papa-windows "Test-Path 'windows-health-check.ps1'" 2>/dev/null; then \
        ssh papa-windows "powershell.exe -File windows-health-check.ps1"; \
    else \
        echo "⚠️  Windows non accessible ou script manquant"; \
    fi

# ====================================================================
# ALIASES - Compatibilité et raccourcis
# ====================================================================

# Aliases courts
s MESSAGE="": (sync MESSAGE)
c: check
st: status
cl: clean

# Aliases workflow universel (pour future migration)
commit MESSAGE="": (sync MESSAGE)
push: sync
pull:
    @git pull --rebase origin main

# ====================================================================
# FUTURE - Vers workflow universel complet
# ====================================================================

# Placeholder pour future intégration git_sync.py
# Décommenter quand prêt à migrer vers workflow complet
# sync-v4:
#     python3 git_sync_v4_ultra_robust.py

# Placeholder pour tests automatisés
# test:
#     @echo "🧪 Tests HomeBridge (à implémenter)"
