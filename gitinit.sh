#!/bin/sh
# Vérification multi-compte GitHub + GPG

echo "👉 Remote configuré :"
git remote -v

echo "\n👉 Test connexion SSH (alias dravitch) :"
ssh -T git@github.com-dravitch 2>&1 | grep "Hi"

echo "\n👉 Détail clé utilisée :"
ssh -vT git@github.com-dravitch 2>&1 | grep "Offering public key"

echo "\n👉 Clés chargées dans l'agent :"
ssh-add -l

echo "\n👉 Vérification clé GPG configurée pour ce projet :"
SIGNKEY=$(git config user.signingkey)
if [ -n "$SIGNKEY" ]; then
    echo "Clé configurée dans Git : $SIGNKEY"
    echo "\n👉 Détails de la clé GPG :"
    gpg --list-secret-keys --keyid-format LONG "$SIGNKEY"
else
    echo "⚠️ Aucune clé GPG configurée dans ce projet (git config user.signingkey)"
fi

echo "\n👉 Vérification de la signature du dernier commit :"
git log -1 --show-signature
