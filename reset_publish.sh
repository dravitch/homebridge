#!/bin/bash
# Reset Git history and publish clean repo under dravitch/homebridge
# SIMPLE VERSION: Just works.

set -e

REPO_URL="git@github.com-dravitch:dravitch/homebridge.git"
GPG_KEY="56E068ECDDD83C8C"

echo "👉 Cleaning old Git history..."
rm -rf .git

echo "👉 Initializing fresh repository..."
git init
git branch -M main

echo "👉 Setting identity..."
git config user.name "dravitch"
git config user.email "dravitch@hotmail.fr"
git config commit.gpgsign true
git config user.signingkey "$GPG_KEY"

echo "👉 Verifying GPG key..."
gpg --list-secret-keys --keyid-format LONG "$GPG_KEY" 2>/dev/null || echo "⚠️ GPG key not found"

echo "👉 Adding files..."
git add .

echo "👉 Creating initial commit..."
git commit -S -m "Initial commit: HomeBridge v1.0 - Own Your Remote Access"

echo "👉 Setting remote..."
git remote add origin "$REPO_URL"

echo "👉 Force pushing..."
git push -u origin main --force

echo "✅ Done. Check GitHub to verify ignored files are not present."