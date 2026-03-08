#!/usr/bin/env bash

# Lists direct children at the given path (must end with /). Output: one key per line.
vaultsh_nav_list() {
  local path="$1"
  local raw line
  vaultsh_set_addr
  raw="$(vault kv list -format=table "$path" 2>&1)" || return 1
  # Table format: "Keys" then "----" then one key per line
  printf '%s\n' "$raw" | tail -n +3 | while IFS= read -r line; do
    [[ -z "${line// /}" ]] && continue
    printf '%s\n' "$line"
  done
}

# Returns 0 if path is at or above nav root (can go "up").
vaultsh_nav_can_go_up() {
  local current="$1"
  local root="$2"
  [[ "$current" != "$root" ]] && [[ "${current%/}" != "${root%/}" ]]
}

# Strip last path segment; ensure result ends with / and is not below root.
vaultsh_nav_up() {
  local current="$1"
  local root="$2"
  local up
  if [[ "$current" == "$root" ]]; then
    printf '%s\n' "$current"
    return 0
  fi
  up="${current%/}"
  up="${up%/*}"
  [[ -z "$up" ]] && up="/"
  [[ "$up" != */ ]] && up+="/"
  # If we went above root (e.g. root is "secret/" and we got "/"), clamp to root
  if [[ "${#up}" -lt "${#root}" ]] && [[ "$root" != "$up" ]]; then
    printf '%s\n' "$root"
  else
    printf '%s\n' "$up"
  fi
}

# When pick_mode=1, selecting a leaf secret sets VAULTSH_PICKED_PATH and returns 0 instead of reading.
vaultsh_nav_run() {
  local pick_mode="${1:-0}"
  local current_path root list_out list_rc keys line selected full_path
  local -a options options_display
  local i idx
  root="${VAULTSH_NAV_ROOT}"
  # Ensure root ends with /
  root="${root%/}/"
  current_path="$root"
  [[ -n "${VAULTSH_PICKED_PATH:-}" ]] && unset -v VAULTSH_PICKED_PATH

  vaultsh_require_command vault || return 1
  vaultsh_set_addr

  if ! vaultsh_ensure_session; then
    return 1
  fi

  while true; do
    vaultsh_section "Browse: ${current_path}"
    set +e
    list_out="$(vaultsh_nav_list "$current_path" 2>&1)"
    list_rc=$?
    set -e
    if [[ $list_rc -ne 0 ]] || [[ "$list_out" == *"permission denied"* ]] || [[ "$list_out" == *"403"* ]]; then
      vaultsh_error "Cannot list path (permission denied or invalid path)."
      printf '%s\n' "$list_out" | head -5
      if vaultsh_offer_login "Session may have expired."; then
        continue
      fi
      return 1
    fi

    keys=()
    while IFS= read -r line; do
      [[ -z "${line// /}" ]] && continue
      keys+=("$line")
    done <<< "$list_out"

    options=()
    options_display=()
    if vaultsh_nav_can_go_up "$current_path" "$root"; then
      options+=("..")
      options_display+=("..|Go up|One level up.")
    fi
    for line in "${keys[@]}"; do
      if [[ "$line" == */ ]]; then
        options+=("$line")
        options_display+=("${line}|Open ${line%/}/|List contents of this path.")
      else
        options+=("$line")
        options_display+=("${line}|Read secret ${line}|Read this secret.")
      fi
    done

    if (( ${#options[@]} == 0 )); then
      vaultsh_info "This path is empty or you have no list permission. Use .. to go up or press Enter to exit."
      read -r -p "Press Enter to return to menu..." _
      return 0
    fi

    selected=""
    if (( HAS_FZF == 1 )); then
      local fzf_input=""
      for line in "${options_display[@]}"; do
        IFS='|' read -r key label desc <<< "$line"
        fzf_input+="${key}	${label}	${desc}"$'\n'
      done
      set +e
      selected="$(printf '%s' "$fzf_input" | fzf \
        --prompt="vaultsh browse ${current_path}> " \
        --height=~100% \
        --layout=reverse \
        --border \
        --no-sort \
        --delimiter=$'\t' \
        --with-nth=1,2 \
        --preview='printf "%s\n" {3}' \
        --preview-window='down,3,wrap,border-top' \
        --pointer='>' \
        --header='Enter: open/read. ESC: back to menu.')"
      local fzf_rc=$?
      set -e
      if (( fzf_rc != 0 )) || [[ -z "$selected" ]]; then
        return 0
      fi
      selected="${selected%%	*}"
    else
      # Classic mode: show numbered options [1], [2], ... and map input to real key
      printf '%s%s%s\n' "$COLOR_BOLD" "Path: ${current_path}" "$COLOR_RESET" >&2
      i=1
      for line in "${options_display[@]}"; do
        IFS='|' read -r key label desc <<< "$line"
        printf '  %s[%s]%s %s\n' "$COLOR_ACCENT" "$i" "$COLOR_RESET" "$label" >&2
        i=$((i + 1))
      done
      printf '%s\n' "" >&2
      read -r -p "${COLOR_PRIMARY}Choice (number or Enter to exit)${COLOR_RESET}: " selected >&2
      if [[ -z "$selected" ]]; then
        return 0
      fi
      # Map number to key: if selected is a positive integer, use options[selected-1]
      if [[ "$selected" =~ ^[0-9]+$ ]]; then
        idx=$((selected - 1))
        if (( idx >= 0 && idx < ${#options[@]} )); then
          selected="${options[$idx]}"
        fi
      fi
    fi

    if [[ "$selected" == ".." ]]; then
      current_path="$(vaultsh_nav_up "$current_path" "$root")"
      continue
    fi

    # Normalize: user may type "myapp" for folder "myapp/"
    if [[ "$selected" != */ ]] && [[ " ${options[*]} " == *" ${selected}/ "* ]]; then
      selected="${selected}/"
    fi

    full_path="${current_path}${selected}"
    if [[ "$selected" == */ ]]; then
      current_path="$full_path"
      continue
    fi

    # Leaf secret selected
    if (( pick_mode == 1 )); then
      VAULTSH_PICKED_PATH="$full_path"
      return 0
    fi

    # Read secret at full_path
    vaultsh_section "Secret: ${full_path}"
    set +e
    vault kv get "$full_path" 2>&1
    set -e
    echo
    read -r -p "Press Enter to continue browsing..." _
    # Stay at same path so user can pick another key
  done
}

# Browse and set VAULTSH_PICKED_PATH when user selects a secret; return 0 then, 1 on cancel.
vaultsh_nav_pick_path() {
  vaultsh_nav_run 1
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
