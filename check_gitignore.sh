#!/bin/bash
# Verify that .gitignore is properly applied

echo "🔍 Checking .gitignore compliance..."

# List of files that should be ignored
IGNORED_FILES=(
    "justfile"
    "gitinit.sh"
    "reset_publish.sh"
    "article_1.md"
    "config.env"
)

FOUND_ISSUES=0

echo ""
echo "📋 Files that SHOULD be ignored:"
for file in "${IGNORED_FILES[@]}"; do
    echo "   - $file"
done

echo ""
echo "🔎 Checking if ignored files are tracked in Git..."

for file in "${IGNORED_FILES[@]}"; do
    if git ls-files --error-unmatch "$file" 2>/dev/null; then
        echo "❌ ERROR: $file is tracked in Git (should be ignored)"
        FOUND_ISSUES=1
    fi
done

if [ $FOUND_ISSUES -eq 0 ]; then
    echo "✅ All files properly ignored"
else
    echo ""
    echo "⚠️  To fix, run:"
    echo "   git rm --cached justfile gitinit.sh reset_publish.sh article_1.md"
    echo "   git commit -m 'Remove ignored files from tracking'"
    echo "   git push"
fi

echo ""
echo "📊 Current tracked files:"
git ls-files | head -20