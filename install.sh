#!/bin/bash
set -euo pipefail

echo "[INFO] Installing and launching Homepod Creator (Gen 3.5)..."

WORKDIR="$(pwd)"
REPO_BASE_URL="https://raw.githubusercontent.com/scs32/homelabpodcreator/main"

# --- Check and install podman ---
echo "[CHECK] Looking for podman..."
if ! command -v podman >/dev/null 2>&1; then
  echo "[WARN] podman not found. Attempting to install..."

  if [[ -f /etc/debian_version ]]; then
    sudo apt update
    sudo apt install -y podman
    echo "[OK] podman successfully installed."
  else
    echo "[ERROR] Unsupported OS for auto-install of podman. Please install it manually."
    exit 1
  fi
else
  echo "[OK] podman is already installed."
fi

# --- Check and install jq ---
echo "[CHECK] Looking for jq..."
if ! command -v jq >/dev/null 2>&1; then
  echo "[WARN] jq not found. Attempting to install..."

  if [[ -f /etc/debian_version ]]; then
    sudo apt update
    sudo apt install -y jq
    echo "[OK] jq successfully installed."
  else
    echo "[ERROR] Unsupported OS for auto-install of jq. Please install it manually."
    exit 1
  fi
else
  echo "[OK] jq is already installed."
fi

# --- Download all files ---
FILES=(
    "homelab.sh"                      # Main orchestrator (unchanged)
    "homelab.js"                      # Service definitions (unchanged)
    "create.sh"                       # Replacement for original create.sh
    "error-handler.sh"                # Error handling utility
    "logging-utils.sh"                # Logging utility
    "parse-service-config.sh"         # JSON parsing
    "setup-service-env.sh"            # Environment setup
    "generate-scripts.sh"             # Script generation coordinator
    "generate-run-template.sh"        # Run script generator
    "generate-diagnose-template.sh"   # Diagnose script generator
    "display-summary.sh"              # Summary display
)

echo "[FETCH] Downloading core files into: $WORKDIR"
for file in "${FILES[@]}"; do
    echo "  - Downloading $file..."
    curl -fsSL "$REPO_BASE_URL/$file" -o "$file"
done

# Make all scripts executable
chmod +x *.sh

# --- Launch homelab.sh ---
echo "[START] Running Homepod Creator..."
./homelab.sh

# --- Clean up ---
echo "[CLEAN] Removing temporary files..."
rm -f "${FILES[@]}"

echo "[DONE] Setup complete and system cleaned."
