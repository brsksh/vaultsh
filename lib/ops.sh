#!/usr/bin/env bash

vaultsh_login_role() {
  local role="$1" errfile rc
  vaultsh_require_command vault || return 1
  vaultsh_set_addr
  errfile="$(mktemp)" || { vault login -method=oidc "role=${role}"; return $?; }
  trap 'rm -f "$errfile"' RETURN
  vault login -method=oidc "role=${role}" 2>&1 | tee "$errfile"
  rc=${PIPESTATUS[0]}
  if (( rc != 0 )); then
    if grep -q "connection refused\|dial tcp" "$errfile" 2>/dev/null; then
      printf '%sVault server not reachable at %s. Check that the server is running; to use another server set VAULTSH_ADDR in ~/.config/vaultsh/config (or vaultsh.conf next to the script).%s\n' \
        "$COLOR_WARN" "${VAULTSH_ADDR:-$VAULT_ADDR}" "$COLOR_RESET"
    fi
    return "$rc"
  fi
}

# Offer to log in (Reader role). Returns 0 if user logged in successfully, 1 otherwise.
vaultsh_offer_login() {
  local reason="${1:-Session missing or expired.}"
  printf '%s%s%s\n' "$COLOR_WARN" "$reason" "$COLOR_RESET"
  if vaultsh_confirm "Log in now?" "N"; then
    vaultsh_login_role "${VAULTSH_READER_ROLE}"
    local rc=$?
    (( rc == 0 )) && unset -v VAULTSH_HEADER_SESSION_TS VAULTSH_HEADER_SESSION_LINE VAULTSH_HEADER_SESSION_COLOR 2>/dev/null || true
    return "$rc"
  fi
  return 1
}

# If no token, offer login. Return 0 if we have a session (or user logged in), 1 if not.
vaultsh_ensure_session() {
  if [[ "$(vaultsh_token_state)" != "missing" ]]; then
    return 0
  fi
  vaultsh_offer_login "Not logged in."
}

vaultsh_show_status() {
  vaultsh_require_command vault || return 1
  vaultsh_set_addr
  vault status
}

vaultsh_show_token_lookup() {
  vaultsh_require_command vault || return 1
  vaultsh_set_addr
  vault token lookup
}

# Cache TTL in seconds for header session line
: "${VAULTSH_HEADER_SESSION_CACHE_TTL:=30}"

# Refresh VAULTSH_HEADER_SESSION_LINE and VAULTSH_HEADER_SESSION_COLOR for header (with cache).
# Call from vaultsh_print_header. Invalidates cache after VAULTSH_HEADER_SESSION_CACHE_TTL seconds.
vaultsh_refresh_header_session() {
  local now ts json_raw lookup_rc expire_time ttl line probe_path probe_field
  now=$(date +%s 2>/dev/null) || now=0
  ts="${VAULTSH_HEADER_SESSION_TS:-0}"
  if (( ts > 0 && (now - ts) < VAULTSH_HEADER_SESSION_CACHE_TTL )) && [[ -n "${VAULTSH_HEADER_SESSION_LINE:-}" ]]; then
    return 0
  fi

  VAULTSH_HEADER_SESSION_LINE=""
  VAULTSH_HEADER_SESSION_COLOR="${COLOR_WARN}"

  if [[ "$(vaultsh_token_state)" == "missing" ]]; then
    VAULTSH_HEADER_SESSION_LINE="Session: nicht eingeloggt"
    VAULTSH_HEADER_SESSION_TS=$now
    return 0
  fi

  if ! vaultsh_require_command vault 2>/dev/null; then
    VAULTSH_HEADER_SESSION_LINE="Session: ? (vault nicht gefunden)"
    VAULTSH_HEADER_SESSION_TS=$now
    return 0
  fi
  vaultsh_set_addr

  set +e
  json_raw="$(vault token lookup -format=json 2>&1)"
  lookup_rc=$?
  set -e

  if (( lookup_rc == 0 )); then
    line="$(printf '%s\n' "$json_raw" | tr -d '\n' | tr -s ' \t' ' ')"
    expire_time=""
    ttl=""
    if [[ "$line" =~ \"expire_time\":\"([^\"]+)\" ]]; then
      expire_time="${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ \"ttl\":\"([^\"]+)\" ]]; then
      ttl="${BASH_REMATCH[1]}"
    fi
    if [[ -n "$expire_time" ]]; then
      expire_time="${expire_time/T/ }"
      expire_time="${expire_time%%.*}"
      expire_time="${expire_time%%Z}"
      VAULTSH_HEADER_SESSION_LINE="Session: aktiv (bis ${expire_time})"
    else
      VAULTSH_HEADER_SESSION_LINE="Session: aktiv"
    fi
    VAULTSH_HEADER_SESSION_COLOR="${COLOR_SUCCESS}"
    VAULTSH_HEADER_SESSION_TS=$now
    return 0
  fi

  probe_path="${VAULTSH_SESSION_PROBE_PATH:-}"
  probe_field="${VAULTSH_SESSION_PROBE_FIELD:-}"
  if [[ -n "$probe_path" && -n "$probe_field" ]]; then
    if vault kv get "-field=${probe_field}" "${probe_path}" >/dev/null 2>&1; then
      VAULTSH_HEADER_SESSION_LINE="Session: aktiv (KV)"
      VAULTSH_HEADER_SESSION_COLOR="${COLOR_SUCCESS}"
      VAULTSH_HEADER_SESSION_TS=$now
      return 0
    fi
  fi

  VAULTSH_HEADER_SESSION_LINE="Session: abgelaufen oder kein Zugriff"
  VAULTSH_HEADER_SESSION_TS=$now
  return 0
}

# Single-line session status: "Session valid until ..." or clear message for missing/expired/denied.
vaultsh_session_check() {
  local json_raw lookup_rc expire_time ttl line
  local probe_path probe_field kv_err kv_rc

  vaultsh_require_command vault || return 1
  vaultsh_set_addr

  probe_path="${VAULTSH_SESSION_PROBE_PATH:-}"
  probe_field="${VAULTSH_SESSION_PROBE_FIELD:-}"

  if [[ "$(vaultsh_token_state)" == "missing" ]]; then
    vaultsh_offer_login "Not logged in (no token)."
    return $?
  fi

  set +e
  json_raw="$(vault token lookup -format=json 2>&1)"
  lookup_rc=$?
  set -e

  if (( lookup_rc != 0 )); then
    # Token lookup can return permission denied when policy allows only KV access.
    # If a probe path is configured and the KV read succeeds, treat session as valid.
    if [[ -z "$probe_path" || -z "$probe_field" ]]; then
      printf '%sSession unclear: token lookup failed (no VAULTSH_SESSION_PROBE_PATH/FIELD configured).%s\n' \
        "$COLOR_WARN" "$COLOR_RESET"
      return 1
    fi
    if vault kv get "-field=${probe_field}" "${probe_path}" >/dev/null 2>&1; then
      kv_rc=0
    else
      kv_rc=1
    fi
    if (( kv_rc == 0 )); then
      printf '%sSession valid (KV access OK; token lookup not allowed by policy).%s\n' \
        "$COLOR_SUCCESS" "$COLOR_RESET"
      return 0
    fi
    kv_err="$(vault kv get "-field=${probe_field}" "${probe_path}" 2>&1)" || true
    if [[ -n "${kv_err:-}" ]]; then
      printf '%sReason: %s%s\n' "$COLOR_MUTED" "${kv_err//$'\n'/ }" "$COLOR_RESET"
      if [[ "$kv_err" == *"invalid token"* ]] || [[ "$kv_err" == *"expired"* ]]; then
        printf '%sToken invalid or expired. Please log in again.%s\n' \
          "$COLOR_WARN" "$COLOR_RESET"
      elif [[ "$kv_err" == *"permission denied"* ]] || [[ "$kv_err" == *"403"* ]]; then
        printf '%sPermission denied for path %s. Log in or check role and policy.%s\n' \
          "$COLOR_WARN" "$probe_path" "$COLOR_RESET"
      else
        printf '%sSession unclear: token lookup and KV probe failed. Log in or check path/permissions (probe: %s).%s\n' \
          "$COLOR_WARN" "$probe_path" "$COLOR_RESET"
      fi
    else
      printf '%sSession unclear: token lookup and KV probe failed. Log in or check path/permissions (probe: %s).%s\n' \
        "$COLOR_WARN" "$probe_path" "$COLOR_RESET"
    fi
    return 1
  fi

  line="$(printf '%s\n' "$json_raw" | tr -d '\n' | tr -s ' \t' ' ')"
  expire_time=""
  ttl=""
  if [[ "$line" =~ \"expire_time\":\"([^\"]+)\" ]]; then
    expire_time="${BASH_REMATCH[1]}"
  fi
  if [[ "$line" =~ \"ttl\":\"([^\"]+)\" ]]; then
    ttl="${BASH_REMATCH[1]}"
  fi

  if [[ -n "$expire_time" ]]; then
    expire_display="${expire_time/T/ }"
    expire_display="${expire_display%%.*}"
    expire_display="${expire_display%%Z}"
    printf '%sSession valid until %s%s' "$COLOR_SUCCESS" "$expire_display" "$COLOR_RESET"
    if [[ -n "$ttl" ]]; then
      printf ' %s(TTL %s)%s' "$COLOR_MUTED" "$ttl" "$COLOR_RESET"
    fi
    printf '\n'
    return 0
  fi

  if [[ -n "$ttl" ]]; then
    printf '%sSession valid (TTL %s)%s\n' "$COLOR_SUCCESS" "$ttl" "$COLOR_RESET"
    return 0
  fi

  printf '%sSession valid (token lookup OK; expiry not parsed).%s\n' \
    "$COLOR_SUCCESS" "$COLOR_RESET"
  return 0
}

# Output secret field names at path (one per line). Requires jq. Return 0 on success.
vaultsh_secret_fields() {
  local path="$1" json
  vaultsh_require_command vault || return 1
  vaultsh_set_addr
  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  json="$(vault kv get -format=json "$path" 2>/dev/null)" || return 1
  printf '%s\n' "$json" | jq -r '(.data.data // .data) | keys[]?' 2>/dev/null
}

# Let user pick a field at path; set VAULTSH_PICKED_FIELD and return 0, or return 1. mode=read|write.
vaultsh_pick_field() {
  local path="$1" mode="${2:-read}" fields line
  [[ -z "$path" ]] && return 1
  VAULTSH_PICKED_FIELD=""
  fields="$(vaultsh_secret_fields "$path" 2>/dev/null)" || return 1
  [[ -z "$fields" ]] && return 1
  if [[ "$mode" == "read" ]]; then
    (printf '%s\n' "(full secret)"; printf '%s\n' "$fields") | vaultsh_pick_from_list "Field (choose or ESC for full secret)"
  else
    (printf '%s\n' "$fields"; printf '%s\n' "(type new field)") | vaultsh_pick_from_list "Field (choose or ESC to type name)"
  fi
  [[ -z "${VAULTSH_PICKED_CHOICE:-}" ]] && return 1
  if [[ "$VAULTSH_PICKED_CHOICE" == "(full secret)" ]]; then
    VAULTSH_PICKED_FIELD=""
  elif [[ "$VAULTSH_PICKED_CHOICE" == "(type new field)" ]]; then
    VAULTSH_PICKED_FIELD="(type new field)"
  else
    VAULTSH_PICKED_FIELD="$VAULTSH_PICKED_CHOICE"
  fi
  unset -v VAULTSH_PICKED_CHOICE
  return 0
}

vaultsh_read_secret() {
  local path="$1"
  local field="${2:-}"
  vaultsh_require_command vault || return 1
  vaultsh_set_addr

  if [[ -n "$field" ]]; then
    vault kv get "-field=${field}" "$path"
  else
    vault kv get "$path"
  fi
}

vaultsh_write_secret_value() {
  local path="$1"
  local field="$2"
  local value="$3"
  vaultsh_require_command vault || return 1
  vaultsh_set_addr
  vault kv put "$path" "${field}=${value}"
}

vaultsh_write_secret_from_file() {
  local path="$1"
  local field="$2"
  local input_file="$3"
  local value=""

  if [[ ! -f "$input_file" ]]; then
    vaultsh_error "Local file not found: ${input_file}"
    return 1
  fi

  value="$(tr -d '\n' < "$input_file")"
  vaultsh_write_secret_value "$path" "$field" "$value"
}

vaultsh_print_quick_commands() {
  cat <<EOF
Quick Commands
--------------
export VAULT_ADDR="${VAULTSH_ADDR}"
vault login -method=oidc role="${VAULTSH_READER_ROLE}"
vault kv get <path>                    # full secret
vault kv get -field=<field> <path>      # single field
EOF
}

vaultsh_run_diagnostics() {
  local current_addr token_state
  local status_output status_rc lookup_output lookup_rc secret_output secret_rc

  vaultsh_require_command vault || return 1
  vaultsh_set_addr

  current_addr="$(vaultsh_current_addr)"
  token_state="$(vaultsh_token_state)"

  vaultsh_section "Environment"
  echo "VAULT_ADDR: ${current_addr}"
  echo "Token source: ${token_state}"
  if [[ -n "${VAULTSH_SESSION_PROBE_PATH:-}" ]]; then
    echo "Session probe path: ${VAULTSH_SESSION_PROBE_PATH}"
    echo "Session probe field: ${VAULTSH_SESSION_PROBE_FIELD:-}"
  else
    echo "Session probe: not set (optional)"
  fi

  vaultsh_section "vault status"
  set +e
  status_output="$(vault status 2>&1)"
  status_rc=$?
  set -e
  printf '%s\n' "$status_output"

  vaultsh_section "vault token lookup"
  set +e
  lookup_output="$(vault token lookup 2>&1)"
  lookup_rc=$?
  set -e
  printf '%s\n' "$lookup_output"

  secret_rc=0
  if [[ -n "${VAULTSH_SESSION_PROBE_PATH:-}" && -n "${VAULTSH_SESSION_PROBE_FIELD:-}" ]]; then
    vaultsh_section "KV read (session probe path/field)"
    set +e
    secret_output="$(vault kv get "-field=${VAULTSH_SESSION_PROBE_FIELD}" "${VAULTSH_SESSION_PROBE_PATH}" 2>&1)"
    secret_rc=$?
    set -e
    printf '%s\n' "$secret_output"
  else
    secret_output=""
    vaultsh_section "KV read"
    echo "(Optional: set VAULTSH_SESSION_PROBE_PATH and VAULTSH_SESSION_PROBE_FIELD to test a KV read here.)"
  fi

  vaultsh_section "Diagnosis"
  if (( status_rc != 0 )) && [[ "$status_output" == *"127.0.0.1:8200"* ]]; then
    echo "- VAULT_ADDR may be wrong for remote Vault. Set VAULTSH_ADDR or VAULT_ADDR."
  fi
  if [[ "$token_state" == "missing" ]]; then
    echo "- No Vault token detected. Run OIDC login first."
  fi
  if (( lookup_rc != 0 )) && [[ "$lookup_output" == *"permission denied"* ]]; then
    echo "- Token exists but lacks token lookup permission. Set VAULTSH_SESSION_PROBE_PATH for session-check fallback."
  fi
  if [[ -n "${secret_output:-}" ]]; then
    if (( secret_rc != 0 )) && [[ "$secret_output" == *"403"* ]]; then
      echo "- Secret access returned 403. Check role, policy, or secret path."
    fi
    if (( secret_rc != 0 )) && [[ "$secret_output" == *"No value found"* ]]; then
      echo "- Path may exist but the expected field or secret does not exist yet."
    fi
  fi
  if (( status_rc == 0 && lookup_rc == 0 )); then
    if [[ -n "${VAULTSH_SESSION_PROBE_PATH:-}" ]] && (( secret_rc == 0 )); then
      echo "- Vault connectivity, token lookup, and KV probe read look healthy."
    else
      echo "- Vault connectivity and token lookup look healthy."
    fi
  fi
}
