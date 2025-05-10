#!/bin/bash
set -euo pipefail

echo "[INFO] Installing and launching Homepod Creator (Gen 4.0)..."

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
    # Main orchestrator (replaces old homelab.sh)
    "homelab-orchestrator.sh"
    
    # User interface components
    "user-interface.sh"
    "config-builder.sh"
    
    # Service database
    "homelab.js"
    
    # Deployment components
    "create.sh"
    "error-handler.sh"
    "logging-utils.sh"
    "parse-service-config.sh"
    "setup-service-env.sh"
    "generate-scripts.sh"
    "generate-run-template.sh"
    "generate-diagnose-template.sh"
    "display-summary.sh"
    
    # Cleanup script
    "cleanup.sh"
)

echo "[FETCH] Downloading core files into: $WORKDIR"
for file in "${FILES[@]}"; do
    echo "  - Downloading $file..."
    curl -fsSL "$REPO_BASE_URL/$file" -o "$file"
done

# Make all scripts executable
chmod +x *.sh

# Create an alias for backward compatibility
if [[ ! -f "homelab.sh" ]]; then
    ln -s homelab-orchestrator.sh homelab.sh
fi

# Check if we're running interactively
if [[ -t 0 ]]; then
    # Running interactively, launch homelab.sh directly
    echo "[START] Running Homepod Creator..."
    ./homelab.sh
else
    # Not running interactively (piped), save scripts and provide instructions
    echo "[NOTICE] Interactive mode required for configuration."
    echo ""
    echo "Files downloaded to: $WORKDIR"
    echo ""
    echo "To continue, run:"
    echo "  ./homelab.sh"
    echo ""
    echo "When finished, clean up with:"
    echo "  ./cleanup.sh"
    echo ""
    echo "Or manually:"
    printf "  rm -f "
    printf '%s ' "${FILES[@]}"
    echo "homelab.sh"
    echo ""
    echo "[DONE] Download complete. Ready for interactive mode."
fi
