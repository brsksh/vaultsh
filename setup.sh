#!/usr/bin/env bash
# Simple setup for vaultsh (Python). Run from repo root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "vaultsh setup"
echo "-------------"

# Python 3.9+
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 not found. Install Python 3.9 or later."
  exit 1
fi
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "Python: $(python3 --version)"

if ! command -v vault &>/dev/null; then
  echo "WARNING: 'vault' CLI not on PATH. Install it for OIDC login and status checks."
fi

# venv
if [[ ! -d .venv ]]; then
  echo "Creating .venv..."
  python3 -m venv .venv
fi
# upgrade pip so editable install works with pyproject.toml
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -e .

echo "Installed."

# optional symlink
BIN_DIR="${HOME}/.local/bin"
if [[ -d "$BIN_DIR" ]] || mkdir -p "$BIN_DIR" 2>/dev/null; then
  ln -sf "$(pwd)/.venv/bin/vaultsh" "$BIN_DIR/vaultsh"
  ln -sf "$(pwd)/.venv/bin/vaultsh-setup" "$BIN_DIR/vaultsh-setup" 2>/dev/null || true
  echo "Linked: $BIN_DIR/vaultsh (and vaultsh-setup)"
else
  echo "Run with: .venv/bin/vaultsh  (or add .venv/bin to PATH)"
fi

# config
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/vaultsh"
CONFIG_FILE="$CONFIG_DIR/config"
if [[ ! -f "$CONFIG_FILE" ]]; then
  mkdir -p "$CONFIG_DIR"
  cp config.example "$CONFIG_FILE"
  echo "Config: $CONFIG_FILE (created from config.example — edit as needed)"
else
  echo "Config: $CONFIG_FILE (already exists)"
fi

# ensure ~/.vault-token has restrictive permissions if it exists (created by vault login)
VAULT_TOKEN_FILE="${HOME}/.vault-token"
if [[ -f "$VAULT_TOKEN_FILE" ]]; then
  if chmod 600 "$VAULT_TOKEN_FILE" 2>/dev/null; then
    echo "Permissions set: ~/.vault-token (600)"
  fi
fi

echo ""
echo "Done. Run: vaultsh   (or .venv/bin/vaultsh)"
