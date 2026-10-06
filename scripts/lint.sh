#!/usr/bin/env bash
# Runs linters and syntax checks across Python, QML, and formatted assets.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "==> Checking Python code with Ruff..."
ruff check .
ruff format --check .

echo "==> Verifying QML files syntax & formatting..."
for f in qs/*.qml; do
    qmlformat "$f" > /dev/null
done

if [ -f "$REPO_DIR/node_modules/.bin/prettier" ]; then
    echo "==> Checking code format with Prettier..."
    npx prettier --check "**/*.{json,md,yml,yaml}" --ignore-path .prettierignore
fi

echo "==> All lint checks passed successfully!"
