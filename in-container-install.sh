#!/bin/bash
set -euo pipefail

echo "[INFO] Downloading HomePod Creator scripts..."

REPO_BASE_URL="https://raw.githubusercontent.com/scs32/homelabpodcreator/main"

# Download all required files
FILES=(
    "homelab-orchestrator.sh"
    "user-interface.sh"
    "config-builder.sh"
    "homelab.js"
    "create.sh"
    "error-handler.sh"
    "logging-utils.sh"
    "parse-service-config.sh"
    "setup-service-env.sh"
    "generate-scripts.sh"
    "generate-run-template.sh"
    "generate-diagnose-template.sh"
    "display-summary.sh"
)

echo "[FETCH] Downloading core files into: $(pwd)"
for file in "${FILES[@]}"; do
    echo "  - Downloading $file..."
    curl -fsSL "$REPO_BASE_URL/$file" -o "$file"
done

# Make all scripts executable
chmod +x *.sh

# Create symlink for backward compatibility
ln -sf homelab-orchestrator.sh homelab.sh

echo "[DONE] All scripts downloaded and ready."
echo ""
echo "To start HomePod Creator, run: ./homelab.sh"
