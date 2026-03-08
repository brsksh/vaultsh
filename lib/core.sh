#!/usr/bin/env bash

vaultsh_init_theme() {
  if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    COLOR_RESET=$'\033[0m'
    COLOR_BOLD=$'\033[1m'
    COLOR_DIM=$'\033[2m'
    COLOR_PANEL=$'\033[38;5;239m'
    COLOR_BORDER=$'\033[38;5;238m'
    COLOR_PRIMARY=$'\033[38;5;223m'
    COLOR_ACCENT=$'\033[38;5;215m'
    COLOR_SUCCESS=$'\033[38;5;151m'
    COLOR_WARN=$'\033[38;5;222m'
    COLOR_ERROR=$'\033[38;5;210m'
    COLOR_MUTED=$'\033[38;5;246m'
    COLOR_SECONDARY=$'\033[38;5;180m'
  else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_PANEL=""
    COLOR_BORDER=""
    COLOR_PRIMARY=""
    COLOR_ACCENT=""
    COLOR_SUCCESS=""
    COLOR_WARN=""
    COLOR_ERROR=""
    COLOR_MUTED=""
    COLOR_SECONDARY=""
  fi
}

vaultsh_load_defaults() {
  : "${VAULTSH_ADDR:=https://127.0.0.1:8200}"
  : "${VAULTSH_READER_ROLE:=reader}"
  : "${VAULTSH_OPERATOR_ROLE:=operator}"
  : "${VAULTSH_NAV_ROOT:=secret/}"
  # Session probe optional; no default path/field
  : "${VAULTSH_SESSION_PROBE_PATH:=}"
  : "${VAULTSH_SESSION_PROBE_FIELD:=}"
  # Ensure VAULT_ADDR is set for vault CLI (env overrides config)
  : "${VAULT_ADDR:=$VAULTSH_ADDR}"
}

vaultsh_load_config() {
  local script_dir="$1"
  local config_script config_home

  config_script="${script_dir}/vaultsh.conf"
  config_home="${XDG_CONFIG_HOME:-$HOME/.config}/vaultsh/config"

  # Load config files first so their values (and env) override built-in defaults
  if [[ -f "$config_script" ]]; then
    # shellcheck disable=SC1090
    source "$config_script"
  fi
  if [[ -f "$config_home" ]]; then
    # shellcheck disable=SC1090
    source "$config_home"
  fi

  vaultsh_load_defaults
  : "${VAULT_ADDR:=$VAULTSH_ADDR}"
}

vaultsh_detect_fzf() {
  if command -v fzf >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
    HAS_FZF=1
  else
    HAS_FZF=0
  fi
}

vaultsh_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

vaultsh_current_addr() {
  printf '%s\n' "${VAULT_ADDR:-$VAULTSH_ADDR}"
}

vaultsh_set_addr() {
  export VAULT_ADDR="${VAULTSH_ADDR}"
}

vaultsh_token_state() {
  if [[ -n "${VAULT_TOKEN:-}" ]]; then
    printf '%s\n' "env"
  elif [[ -f "${HOME}/.vault-token" ]]; then
    printf '%s\n' "file"
  else
    printf '%s\n' "missing"
  fi
}

# Header box width (characters)
VAULTSH_HEADER_WIDTH=72

vaultsh_print_header() {
  local token_state
  local token_badge token_color menu_badge
  local top_rule bot_rule session_color

  token_state="$(vaultsh_token_state)"

  if [[ -t 1 ]]; then
    clear
  fi

  vaultsh_refresh_header_session || true
  top_rule="$(printf '%*s' "$VAULTSH_HEADER_WIDTH" "" | tr ' ' '─')"
  bot_rule="$(printf '%*s' "$VAULTSH_HEADER_WIDTH" "" | tr ' ' '─')"

  if [[ -n "${VAULTSH_HEADER_SESSION_LINE:-}" ]]; then
    session_color="${VAULTSH_HEADER_SESSION_COLOR:-$COLOR_WARN}"
    printf '%s╭%s╮%s\n' "$COLOR_BORDER" "$top_rule" "$COLOR_RESET"
    printf '%s│%s ● %s%s%*s%s│%s\n' "$COLOR_BORDER" "$COLOR_RESET" "$session_color" "${VAULTSH_HEADER_SESSION_LINE}" "$COLOR_RESET" "$(( VAULTSH_HEADER_WIDTH - 5 - ${#VAULTSH_HEADER_SESSION_LINE} ))" "" "$COLOR_BORDER" "$COLOR_RESET"
    printf '%s╰%s╯%s\n\n' "$COLOR_BORDER" "$bot_rule" "$COLOR_RESET"
  fi

  case "$token_state" in
    env)
      token_badge="TOKEN:env"
      token_color="$COLOR_SUCCESS"
      ;;
    file)
      token_badge="TOKEN:file"
      token_color="$COLOR_ACCENT"
      ;;
    *)
      token_badge="TOKEN:missing"
      token_color="$COLOR_WARN"
      ;;
  esac

  if (( HAS_FZF == 1 )); then
    menu_badge="MENU:fzf"
  else
    menu_badge="MENU:classic"
  fi

  local addr
  addr="$(vaultsh_current_addr)"
  printf '%s╭%s╮%s\n' "$COLOR_BORDER" "$top_rule" "$COLOR_RESET"
  printf '%s│%s %s%s%s%*s%s│%s\n' "$COLOR_BORDER" "$COLOR_RESET" "$COLOR_BOLD" "$COLOR_PRIMARY" "HashiCorp Vault" "$COLOR_RESET" "$(( VAULTSH_HEADER_WIDTH - 16 ))" "" "$COLOR_BORDER" "$COLOR_RESET"
  printf '%s│%s %-12s%s %s%s%s%*s%s│%s\n' "$COLOR_BORDER" "$COLOR_RESET" "context" "$COLOR_RESET" "$token_color" "$token_badge" "$COLOR_RESET" "$(( VAULTSH_HEADER_WIDTH - 2 - 12 - 1 - ${#token_badge} ))" "" "$COLOR_BORDER" "$COLOR_RESET"
  printf '%s│%s %-12s%s %s%s%s%*s%s│%s\n' "$COLOR_BORDER" "$COLOR_RESET" "menu" "$COLOR_RESET" "$COLOR_SECONDARY" "$menu_badge" "$COLOR_RESET" "$(( VAULTSH_HEADER_WIDTH - 2 - 12 - 1 - ${#menu_badge} ))" "" "$COLOR_BORDER" "$COLOR_RESET"
  printf '%s│%s %-12s%s %s%s%s%*s%s│%s\n' "$COLOR_BORDER" "$COLOR_RESET" "nav root" "$COLOR_RESET" "$COLOR_ACCENT" "${VAULTSH_NAV_ROOT}" "$COLOR_RESET" "$(( VAULTSH_HEADER_WIDTH - 2 - 12 - 1 - ${#VAULTSH_NAV_ROOT} ))" "" "$COLOR_BORDER" "$COLOR_RESET"
  printf '%s│%s %-12s%s %s%s%s%*s%s│%s\n' "$COLOR_BORDER" "$COLOR_RESET" "address" "$COLOR_RESET" "$COLOR_BOLD" "$addr" "$COLOR_RESET" "$(( VAULTSH_HEADER_WIDTH - 2 - 12 - 1 - ${#addr} ))" "" "$COLOR_BORDER" "$COLOR_RESET"
  printf '%s╰%s╯%s\n' "$COLOR_BORDER" "$bot_rule" "$COLOR_RESET"
  printf '%s%s%s\n' "$COLOR_DIM" "  Login, browse, read/write KV secrets, inspect session, diagnose." "$COLOR_RESET"
  echo
}

vaultsh_section() {
  echo
  printf '%s[%s]%s %s%s%s\n' \
    "$COLOR_ACCENT" "$COLOR_PRIMARY" "$COLOR_RESET" "$COLOR_BOLD" "$1" "$COLOR_RESET"
}

vaultsh_info() {
  printf '%sINFO%s %s\n' "$COLOR_PRIMARY" "$COLOR_RESET" "$*"
}

vaultsh_warn() {
  printf '%sWARN%s %s\n' "$COLOR_WARN" "$COLOR_RESET" "$*" >&2
}

vaultsh_error() {
  printf '%sERROR%s %s\n' "$COLOR_ERROR" "$COLOR_RESET" "$*" >&2
}

vaultsh_require_command() {
  local command_name="$1"
  if ! vaultsh_command_exists "$command_name"; then
    vaultsh_error "Required command not found: ${command_name}"
    return 1
  fi
}

vaultsh_print_panel() {
  local title="$1" line
  local panel_rule
  shift
  : "${VAULTSH_HEADER_WIDTH:=72}"
  panel_rule="$(printf '%*s' "$VAULTSH_HEADER_WIDTH" "" | tr ' ' '─')"
  printf '%s╭%s╮%s\n' "$COLOR_BORDER" "$panel_rule" "$COLOR_RESET"
  printf '%s│%s ▎ %s[%s%s%s]%s%*s%s│%s\n' "$COLOR_BORDER" "$COLOR_RESET" "$COLOR_ACCENT" "$COLOR_PANEL" "$title" "$COLOR_RESET" "$COLOR_RESET" "$(( VAULTSH_HEADER_WIDTH - 2 - 5 - ${#title} ))" "" "$COLOR_BORDER" "$COLOR_RESET"
  while (($#)); do
    line="$1"
    if [[ "$line" =~ ^([0-9]+\.)([[:space:]].*)$ ]]; then
      printf '%s│%s   %s%s%s%s%s%s%*s%s│%s\n' "$COLOR_BORDER" "$COLOR_RESET" "$COLOR_ACCENT" "${BASH_REMATCH[1]}" "$COLOR_RESET" "$COLOR_MUTED" "${BASH_REMATCH[2]}" "$COLOR_RESET" "$(( VAULTSH_HEADER_WIDTH - 2 - 3 - ${#BASH_REMATCH[1]} - ${#BASH_REMATCH[2]} ))" "" "$COLOR_BORDER" "$COLOR_RESET"
    else
      printf '%s│%s   %s%s%s%*s%s│%s\n' "$COLOR_BORDER" "$COLOR_RESET" "$COLOR_MUTED" "$line" "$COLOR_RESET" "$(( VAULTSH_HEADER_WIDTH - 2 - 3 - ${#line} ))" "" "$COLOR_BORDER" "$COLOR_RESET"
    fi
    shift
  done
  printf '%s╰%s╯%s\n' "$COLOR_BORDER" "$panel_rule" "$COLOR_RESET"
}

vaultsh_print_kv() {
  local label="$1"
  local value="$2"
  printf '%s%-12s%s %s%s%s\n' \
    "$COLOR_MUTED" "$label" "$COLOR_RESET" "$COLOR_BOLD" "$value" "$COLOR_RESET"
}
