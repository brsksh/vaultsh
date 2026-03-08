#!/usr/bin/env bash

# Lists direct children at the given path (must end with /). Output: one key per line.
vaultsh_nav_list() {
  local path="$1"
  local raw line rc jq_out
  vaultsh_set_addr
  if command -v jq >/dev/null 2>&1; then
    raw="$(vault kv list -format=json "$path" 2>&1)"
    rc=$?
    if (( rc != 0 )); then
      printf '%s\n' "$raw"
      return "$rc"
    fi
    jq_out="$(printf '%s\n' "$raw" | jq -r '(.data.keys // .) | .[]?' 2>/dev/null)"
    if [[ -z "$jq_out" ]]; then
      case "$raw" in
        *error*|*permission*|*403*|*denied*) printf '%s\n' "$raw"; return 1 ;;
      esac
    fi
    printf '%s\n' "$jq_out"
  else
    raw="$(vault kv list -format=table "$path" 2>&1)"
    rc=$?
    if (( rc != 0 )); then
      printf '%s\n' "$raw"
      return "$rc"
    fi
    printf '%s\n' "$raw" | tail -n +3 | while IFS= read -r line; do
      [[ -z "${line// /}" ]] && continue
      printf '%s\n' "$line"
    done
  fi
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
  local current_path root list_out list_rc keys line selected full_path list_raw
  local -a options options_display
  local i idx list_tmp
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

  if [[ -z "${VAULT_TOKEN:-}" ]] && [[ -f "${HOME}/.vault-token" ]]; then
    VAULT_TOKEN="$(cat "${HOME}/.vault-token")"
    export VAULT_TOKEN
  fi

  list_tmp="$(mktemp)"
  trap 'rm -f "${list_tmp}"' RETURN

  while true; do
    vaultsh_section "Browse" "Browse: ${current_path}"
    set +e
    if command -v jq >/dev/null 2>&1; then
      vault kv list -format=json "$current_path" > "${list_tmp}" 2>&1
    else
      vault kv list -format=table "$current_path" > "${list_tmp}" 2>&1
    fi
    list_rc=$?
    set -e
    list_raw="$(cat "${list_tmp}")"
    if [[ $list_rc -ne 0 ]] || [[ "$list_raw" == *"permission denied"* ]] || [[ "$list_raw" == *"403"* ]]; then
      vaultsh_error "Cannot list path (permission denied or invalid path)."
      if [[ -n "${list_raw//[[:space:]]/}" ]]; then
        printf '%s\n' "$list_raw" | head -10
      else
        printf '%s\n' "(vault list failed with no output — check VAULT_ADDR and token)"
      fi
      vaultsh_info "Check VAULTSH_NAV_ROOT (currently: ${VAULTSH_NAV_ROOT}) or policy list permission. Press Enter to return to menu."
      read -r -p "Press Enter to return to menu..." _
      return 0
    fi

    if command -v jq >/dev/null 2>&1; then
      list_out="$(jq -r '(.data.keys // .) | .[]?' "${list_tmp}" 2>/dev/null)"
    else
      list_out="$(tail -n +3 "${list_tmp}" | while IFS= read -r line; do [[ -z "${line// /}" ]] && continue; printf '%s\n' "$line"; done)"
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
    vaultsh_section "Secret" "Secret: ${full_path}"
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

