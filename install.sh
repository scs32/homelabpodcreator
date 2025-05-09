#!/bin/bash
set -euo pipefail

echo "📦 Installing Homepod Creator (Gen 3)..."

INSTALL_DIR="$HOME/homepod-create"
BIN_DIR="$HOME/.local/bin"
REPO_BASE_URL="https://raw.githubusercontent.com/scs32/homelabpodcreator/main"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# Download the three core files
echo "⬇️  Fetching latest scripts..."
curl -fsSL "$REPO_BASE_URL/homelab.sh" -o "$INSTALL_DIR/homelab.sh"
curl -fsSL "$REPO_BASE_URL/create.sh"  -o "$INSTALL_DIR/create.sh"
curl -fsSL "$REPO_BASE_URL/homelab.js" -o "$INSTALL_DIR/homelab.js"

chmod +x "$INSTALL_DIR/homelab.sh"

# Create symlink to ~/.local/bin/homepod
ln -sf "$INSTALL_DIR/homelab.sh" "$BIN_DIR/homepod"

# Add ~/.local/bin to PATH if not already present
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  export PATH="$HOME/.local/bin:$PATH"
  echo "🛠 Added ~/.local/bin to PATH (reload your shell if needed)"
fi

echo "✅ Installation complete!"
echo "👉 Run with: homepod"
