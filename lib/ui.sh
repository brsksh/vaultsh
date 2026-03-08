#!/usr/bin/env bash

vaultsh_pause() {
  echo
  read -r -p "Press Enter to continue..." _
}

vaultsh_confirm() {
  local prompt="$1"
  local default_answer="${2:-N}"
  local reply=""

  if [[ "$default_answer" == "Y" ]]; then
    read -r -p "${COLOR_ACCENT}${prompt}${COLOR_RESET} [Y/n]: " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]
  else
    read -r -p "${COLOR_ACCENT}${prompt}${COLOR_RESET} [y/N]: " reply
    [[ "$reply" =~ ^[Yy]$ ]]
  fi
}

vaultsh_prompt() {
  local prompt="$1"
  local default_value="${2:-}"
  local reply=""

  if [[ -n "$default_value" ]]; then
    read -r -p "${COLOR_PRIMARY}${prompt}${COLOR_RESET} [${default_value}]: " reply
    printf '%s\n' "${reply:-$default_value}"
  else
    read -r -p "${COLOR_PRIMARY}${prompt}${COLOR_RESET}: " reply
    printf '%s\n' "$reply"
  fi
}

vaultsh_prompt_secret() {
  local prompt="$1"
  local reply=""

  read -r -s -p "${COLOR_PRIMARY}${prompt}${COLOR_RESET}: " reply
  echo
  printf '%s\n' "$reply"
}

vaultsh_prompt_multiline() {
  local prompt="$1"
  local terminator="${2:-EOF}"
  local line=""
  local result=""

  printf '%s[%s%s%s]%s\n' "$COLOR_PANEL" "$COLOR_BOLD" "$prompt" "$COLOR_PANEL" "$COLOR_RESET" >&2
  printf '  %sPaste your content below. Finish with a single line containing %s.%s\n' \
    "$COLOR_MUTED" "$terminator" "$COLOR_RESET" >&2

  while IFS= read -r line; do
    if [[ "$line" == "$terminator" ]]; then
      break
    fi
    result+="${line}"$'\n'
  done

  printf '%s' "$result"
}

vaultsh_select_option() {
  local prompt="$1"
  shift
  local options=("$@")
  local selected=""
  local display_input=""
  local option key label description

  if (( ${#options[@]} == 0 )); then
    return 1
  fi

  if (( HAS_FZF == 1 )); then
    for option in "${options[@]}"; do
      IFS='|' read -r key label description <<< "$option"
      display_input+="${key}. ${label}"$'\t'"${description}"$'\n'
    done

    local fzf_header="Move with arrows. Enter confirms. ESC goes back. Preview explains the action."
    if [[ -n "${VAULTSH_HEADER_SESSION_LINE:-}" ]]; then
      fzf_header="${VAULTSH_HEADER_SESSION_LINE}"$'\n'"${fzf_header}"
    fi

    set +e
    selected="$(printf '%s' "$display_input" | fzf \
      --prompt="vaultsh > ${prompt}: " \
      --height=~100% \
      --layout=reverse \
      --border \
      --no-sort \
      --delimiter=$'\t' \
      --with-nth=1 \
      --preview='printf "%s\n" {2}' \
      --preview-window='down,4,wrap,border-top' \
      --pointer='>' \
      --marker='+' \
      --color='border:8,separator:8,label:11,query:15,prompt:11,header:8,pointer:10,marker:10,fg:15,bg:-1,hl:11,info:8,preview-border:8,preview-label:10' \
      --header="$fzf_header")"
    local fzf_rc=$?
    set -e

    if (( fzf_rc != 0 )) || [[ -z "$selected" ]]; then
      return 1
    fi

    printf '%s\n' "${selected%%.*}"
    return 0
  fi

  printf '%s%s%s\n' "$COLOR_BOLD" "$prompt" "$COLOR_RESET" >&2
  for option in "${options[@]}"; do
    IFS='|' read -r key label description <<< "$option"
    printf '  %s[%s]%s %s%s%s\n' "$COLOR_ACCENT" "$key" "$COLOR_RESET" "$COLOR_PRIMARY" "$label" "$COLOR_RESET" >&2
    if [[ -n "$description" ]]; then
      printf '      %s%s%s\n' "$COLOR_MUTED" "$description" "$COLOR_RESET" >&2
    fi
  done
  printf '%sChoose one option and press Enter.%s\n\n' "$COLOR_MUTED" "$COLOR_RESET" >&2

  read -r -p "${COLOR_PRIMARY}Selection${COLOR_RESET}: " selected >&2
  [[ -n "$selected" ]] || return 1
  printf '%s\n' "$selected"
}

vaultsh_print_preview() {
  local label="$1"
  shift
  echo
  printf '%s[%spreview%s]%s %s%s%s\n' "$COLOR_PANEL" "$COLOR_ACCENT" "$COLOR_PANEL" "$COLOR_RESET" "$COLOR_PRIMARY" "$label" "$COLOR_RESET"
  printf '  %q' "$@"
  echo
  printf '%s-------------------------------------------------------------------------------%s\n' "$COLOR_PANEL" "$COLOR_RESET"
}

vaultsh_show_guidance() {
  local title="$1"
  local line_one="$2"
  local line_two="${3:-}"

  printf '%s[%s%s%s]%s\n' "$COLOR_PANEL" "$COLOR_BOLD" "$title" "$COLOR_PANEL" "$COLOR_RESET"
  printf '  %s%s%s\n' "$COLOR_MUTED" "$line_one" "$COLOR_RESET"
  if [[ -n "$line_two" ]]; then
    printf '  %s%s%s\n' "$COLOR_MUTED" "$line_two" "$COLOR_RESET"
  fi
  printf '%s-------------------------------------------------------------------------------%s\n' "$COLOR_PANEL" "$COLOR_RESET"
  echo
}
