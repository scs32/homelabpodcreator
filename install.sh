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
    "homelab.sh"
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

echo "[FETCH] Downloading core files into: $WORKDIR"
for file in "${FILES[@]}"; do
    echo "  - Downloading $file..."
    curl -fsSL "$REPO_BASE_URL/$file" -o "$file"
done

# Make all scripts executable
chmod +x *.sh

# Create a cleanup script that will be run automatically when homelab.sh completes
cat > cleanup.sh << 'EOF_CLEANUP'
#!/bin/bash
# Auto-cleanup script for temporary files

FILES=(
    "homelab.sh"
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
    "cleanup.sh"
)

echo ""
echo "[CLEAN] Removing temporary files..."
for file in "${FILES[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        echo "  - Removed $file"
    fi
done
echo "[DONE] Cleanup complete."
EOF_CLEANUP

chmod +x cleanup.sh

# Check if we're running interactively
if [[ -t 0 ]]; then
    # Running interactively, launch homelab.sh directly
    echo "[START] Running Homepod Creator..."
    ./homelab.sh
    ./cleanup.sh
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
    echo "  rm -f ${FILES[*]} cleanup.sh"
    echo ""
    echo "[DONE] Download complete. Ready for interactive mode."
fi
