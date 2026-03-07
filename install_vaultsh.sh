#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${VAULTSH_REPO_URL:-https://github.com/brsksh/vaultsh.git}"
INSTALL_DIR="${VAULTSH_INSTALL_DIR:-$HOME/.local/share/vaultsh}"
BIN_DIR="${VAULTSH_BIN_DIR:-$HOME/.local/bin}"

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  COLOR_INFO="\033[36m"
  COLOR_WARN="\033[33m"
  COLOR_ERROR="\033[31m"
  COLOR_RESET="\033[0m"
else
  COLOR_INFO=""
  COLOR_WARN=""
  COLOR_ERROR=""
  COLOR_RESET=""
fi

info() {
  echo -e "${COLOR_INFO}INFO:${COLOR_RESET} $*"
}

warn() {
  echo -e "${COLOR_WARN}WARNING:${COLOR_RESET} $*"
}

error() {
  echo -e "${COLOR_ERROR}ERROR:${COLOR_RESET} $*"
}

SKIP_SETUP=0
if [[ -n "${VAULTSH_SKIP_SETUP:-}" ]]; then
  SKIP_SETUP=1
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-setup)
      SKIP_SETUP=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

info "Installing vaultsh"

if ! command -v git >/dev/null 2>&1; then
  error "git is required but not installed."
  exit 1
fi

mkdir -p "$(dirname "$INSTALL_DIR")"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Existing vaultsh clone found at $INSTALL_DIR"
  info "Updating repository (git pull --ff-only)"
  if ! git -C "$INSTALL_DIR" pull --ff-only; then
    warn "git pull failed, continuing with existing clone"
  fi
else
  info "Cloning vaultsh into $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

info "Making scripts executable"
chmod +x "$INSTALL_DIR/vaultsh" "$INSTALL_DIR/setup_vaultsh.sh" 2>/dev/null || true

if [[ $SKIP_SETUP -eq 1 ]]; then
  info "Skipping setup (VAULTSH_SKIP_SETUP / --no-setup). Run setup_vaultsh.sh manually if needed."
else
  info "Running setup_vaultsh.sh"
  (
    cd "$INSTALL_DIR"
    ./setup_vaultsh.sh
  )
fi

echo
read -r -p "Create symlink $BIN_DIR/vaultsh -> $INSTALL_DIR/vaultsh? [y/N]: " answer
case "$answer" in
  [Yy]*)
    mkdir -p "$BIN_DIR"
    if ln -sf "$INSTALL_DIR/vaultsh" "$BIN_DIR/vaultsh"; then
      info "Symlink created. Ensure $BIN_DIR is in your PATH."
      info "Then run: vaultsh"
    else
      warn "Failed to create symlink."
    fi
    ;;
  *)
    info "Skipped symlink. Run vaultsh from the install directory: $INSTALL_DIR/vaultsh"
    ;;
esac

info "Installation finished."
