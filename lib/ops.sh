#!/usr/bin/env bash

vaultsh_login_role() {
  local role="$1"
  vaultsh_require_command vault || return 1
  vaultsh_set_addr
  vault login -method=oidc "role=${role}"
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

# Single-line session status: "Session valid until ..." or clear message for missing/expired/denied.
vaultsh_session_check() {
  local json_raw lookup_rc expire_time ttl line
  local probe_path probe_field kv_err kv_rc

  vaultsh_require_command vault || return 1
  vaultsh_set_addr

  probe_path="${VAULTSH_SESSION_PROBE_PATH:-}"
  probe_field="${VAULTSH_SESSION_PROBE_FIELD:-}"

  if [[ "$(vaultsh_token_state)" == "missing" ]]; then
    printf '%sNot logged in (no token). Run login first.%s\n' "$COLOR_WARN" "$COLOR_RESET"
    return 1
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
