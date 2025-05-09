#!/bin/bash
set -euo pipefail

echo "📦 Installing Homepod Creator (Gen 3)..."

INSTALL_DIR="$(pwd)"
BIN_DIR="$HOME/.local/bin"
REPO_BASE_URL="https://raw.githubusercontent.com/scs32/homelabpodcreator/main"

mkdir -p "$BIN_DIR"

# Download the core files into current working directory
echo "⬇️  Fetching latest scripts into $INSTALL_DIR..."
curl -fsSL "$REPO_BASE_URL/homelab.sh" -o "$INSTALL_DIR/homelab.sh"
curl -fsSL "$REPO_BASE_URL/create.sh"  -o "$INSTALL_DIR/create.sh"
curl -fsSL "$REPO_BASE_URL/homelab.js" -o "$INSTALL_DIR/homelab.js"

chmod +x "$INSTALL_DIR/homelab.sh"

# Link 'homepod' command to this local version
ln -sf "$INSTALL_DIR/homelab.sh" "$BIN_DIR/homepod"

# Ensure ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  export PATH="$HOME/.local/bin:$PATH"
  echo "🛠 Added ~/.local/bin to PATH (reload your shell if needed)"
fi

echo "✅ Installation complete!"
echo "👉 Run with: homepod"
