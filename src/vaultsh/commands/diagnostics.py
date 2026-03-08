"""Diagnostics: status, token lookup, optional KV probe, diagnosis text."""
from __future__ import annotations

import os
import subprocess
from typing import Any

from vaultsh import vault_client
from vaultsh.ui import print_section


def _kv_probe(client: Any, path: str, field: str, mount_point: str = "secret") -> tuple[int, str]:
    try:
        if path.startswith(mount_point + "/"):
            path = path[len(mount_point) + 1 :]
        r = client.secrets.kv.v2.read_secret_version(path=path.rstrip("/"), mount_point=mount_point)
        data = (r.get("data") or {}).get("data") or r.get("data") or {}
        val = data.get(field, "")
        return 0, str(val)
    except Exception as e:
        return 1, str(e)


def run_diagnostics(cfg: dict[str, Any]) -> None:
    addr = cfg.get("VAULT_ADDR") or cfg.get("VAULTSH_ADDR") or "https://127.0.0.1:8200"
    state = vault_client.token_state()
    probe_path = (cfg.get("VAULTSH_SESSION_PROBE_PATH") or "").strip()
    probe_field = (cfg.get("VAULTSH_SESSION_PROBE_FIELD") or "").strip()

    print_section("Environment")
    print(f"VAULT_ADDR: {addr}")
    print(f"Token source: {state}")
    if probe_path:
        print(f"Session probe path: {probe_path}")
        print(f"Session probe field: {probe_field or ''}")
    else:
        print("Session probe: not set (optional)")

    print_section("vault status")
    env = os.environ.copy()
    env["VAULT_ADDR"] = addr
    r = subprocess.run(["vault", "status"], env=env, capture_output=True, text=True)
    status_rc = r.returncode
    print(r.stdout or "")
    if r.stderr:
        print(r.stderr, end="")

    print_section("vault token lookup")
    r2 = subprocess.run(["vault", "token", "lookup"], env=env, capture_output=True, text=True)
    lookup_rc = r2.returncode
    print(r2.stdout or "")
    if r2.stderr:
        print(r2.stderr, end="")

    secret_rc = 0
    secret_output = ""
    if probe_path and probe_field:
        print_section("KV read (session probe path/field)")
        token = vault_client.get_token()
        if token:
            client = vault_client.create_client(addr, token)
            mount = probe_path.split("/")[0] if "/" in probe_path else "secret"
            secret_rc, secret_output = _kv_probe(client, probe_path, probe_field, mount)
            print(secret_output)
        else:
            secret_output = "(no token)"
            secret_rc = 1
    else:
        print_section("KV read")
        print("(Optional: set VAULTSH_SESSION_PROBE_PATH and VAULTSH_SESSION_PROBE_FIELD to test a KV read here.)")

    print_section("Diagnosis")
    if status_rc != 0 and "127.0.0.1:8200" in (addr or ""):
        print("- VAULT_ADDR may be wrong for remote Vault. Set VAULTSH_ADDR or VAULT_ADDR.")
    if state == "missing":
        print("- No Vault token detected. Run OIDC login first.")
    if lookup_rc != 0 and "permission denied" in (r2.stderr or r2.stdout or ""):
        print("- Token exists but lacks token lookup permission. Set VAULTSH_SESSION_PROBE_PATH for session-check fallback.")
    if secret_output:
        if secret_rc != 0 and "403" in secret_output:
            print("- Secret access returned 403. Check role, policy, or secret path.")
        if secret_rc != 0 and "No value found" in secret_output:
            print("- Path may exist but the expected field or secret does not exist yet.")
    if status_rc == 0 and lookup_rc == 0:
        if probe_path and secret_rc == 0:
            print("- Vault connectivity, token lookup, and KV probe read look healthy.")
        else:
            print("- Vault connectivity and token lookup look healthy.")
