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

# Read options from stdin (one per line), show picker; set VAULTSH_PICKED_CHOICE and return 0, or return 1 on cancel.
# First argument is the prompt/header string.
vaultsh_pick_from_list() {
  local header="${1:-Choose}"
  local -a options
  local line selected i idx
  VAULTSH_PICKED_CHOICE=""
  options=()
  while IFS= read -r line; do
    [[ -z "${line// /}" ]] && continue
    options+=("$line")
  done
  (( ${#options[@]} == 0 )) && return 1
  if (( HAS_FZF == 1 )); then
    set +e
    selected="$(printf '%s\n' "${options[@]}" | fzf --prompt="${header}> " --height=~50% --layout=reverse --border --no-sort --header="$header")"
    set -e
    [[ -z "$selected" ]] && return 1
  else
    printf '%s%s%s\n' "$COLOR_BOLD" "$header" "$COLOR_RESET" >&2
    i=1
    for line in "${options[@]}"; do
      printf '  %s[%s]%s %s\n' "$COLOR_ACCENT" "$i" "$COLOR_RESET" "$line" >&2
      i=$((i + 1))
    done
    printf '\n' >&2
    read -r -p "${COLOR_PRIMARY}Choice (number or Enter to cancel)${COLOR_RESET}: " selected >&2
    [[ -z "$selected" ]] && return 1
    if [[ "$selected" =~ ^[0-9]+$ ]]; then
      idx=$((selected - 1))
      if (( idx >= 0 && idx < ${#options[@]} )); then
        selected="${options[$idx]}"
      fi
    fi
  fi
  VAULTSH_PICKED_CHOICE="$selected"
  return 0
}
