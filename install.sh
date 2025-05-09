#!/bin/bash
set -euo pipefail

echo "📦 Installing and launching Homepod Creator (Gen 3)..."

WORKDIR="$(pwd)"
REPO_BASE_URL="https://raw.githubusercontent.com/scs32/homelabpodcreator/main"

# Download required files to current directory
echo "⬇️  Fetching files into: $WORKDIR"
curl -fsSL "$REPO_BASE_URL/homelab.sh" -o homelab.sh
curl -fsSL "$REPO_BASE_URL/create.sh"  -o create.sh
curl -fsSL "$REPO_BASE_URL/homelab.js" -o homelab.js

chmod +x homelab.sh

# Run the main script
echo "🚀 Launching Homepod Creator..."
./homelab.sh

# If it finishes successfully, clean up
echo "🧹 Cleaning up temporary files..."
rm -f homelab.sh create.sh homelab.js

echo "✅ Done! System is clean. Scripts and pod files were generated where needed."
