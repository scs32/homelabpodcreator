#!/bin/bash
set -euo pipefail

echo "📦 Installing and launching Homepod Creator (Gen 3)..."

WORKDIR="$(pwd)"
REPO_BASE_URL="https://raw.githubusercontent.com/scs32/homelabpodcreator/main"

# --- Check and install podman ---
echo "🔍 Checking for podman..."
if ! command -v podman >/dev/null 2>&1; then
  echo "⚠️  podman not found. Attempting to install..."

  if [[ -f /etc/debian_version ]]; then
    sudo apt update
    sudo apt install -y podman
    echo "✅ podman successfully installed."
  else
    echo "❌ Unsupported OS for auto-install of podman. Please install it manually."
    exit 1
  fi
else
  echo "✅ podman is already installed."
fi

# --- Check and install jq ---
echo "🔍 Checking for jq..."
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️  jq not found. Attempting to install..."

  if [[ -f /etc/debian_version ]]; then
    sudo apt update
    sudo apt install -y jq
    echo "✅ jq successfully installed."
  else
    echo "❌ Unsupported OS for auto-install of jq. Please install it manually."
    exit 1
  fi
else
  echo "✅ jq is already installed."
fi

# --- Download homelab files ---
echo "⬇️  Fetching core files into: $WORKDIR"
curl -fsSL "$REPO_BASE_URL/homelab.sh" -o homelab.sh
curl -fsSL "$REPO_BASE_URL/create.sh"  -o create.sh
curl -fsSL "$REPO_BASE_URL/homelab.js" -o homelab.js

chmod +x homelab.sh

# --- Launch homelab.sh ---
echo "🚀 Launching Homepod Creator..."
./homelab.sh

# --- Clean up ---
echo "🧹 Cleaning up temporary files..."
rm -f homelab.sh create.sh homelab.js

echo "✅ Done! Setup complete and system cleaned."
