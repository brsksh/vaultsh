"""Session check: token lookup + optional KV probe."""
from __future__ import annotations

from typing import Any

from vaultsh import vault_client
from vaultsh.ui import error, info, pause, warn
from vaultsh.ui import console
from vaultsh.ui import print_section
from vaultsh.ui import Text


def _token_lookup_ok(client: Any) -> tuple[bool, str]:
    try:
        data = client.auth.token.lookup_self()
        if not data:
            return False, ""
        d = data.get("data") or data
        expire = (d.get("expire_time") or "").replace("T", " ").split(".")[0].rstrip("Z")
        ttl = d.get("ttl", "")
        if expire:
            return True, f"Session valid until {expire}" + (f" (TTL {ttl})" if ttl else "")
        if ttl:
            return True, f"Session valid (TTL {ttl})"
        return True, "Session valid (token lookup OK)"
    except Exception:
        return False, ""


def _kv_probe_ok(client: Any, path: str, field: str) -> bool:
    try:
        secret = client.secrets.kv.v2.read_secret_version(path=path)
        if not secret or not secret.get("data"):
            return False
        data = (secret.get("data") or {}).get("data") or secret.get("data") or {}
        return field in data
    except Exception:
        return False


def run_session_check(cfg: dict[str, Any]) -> None:
    addr = cfg.get("VAULT_ADDR") or cfg.get("VAULTSH_ADDR") or "https://127.0.0.1:8200"
    token = vault_client.get_token()
    state = vault_client.token_state()

    if state == "missing":
        warn("Not logged in (no token).")
        if _offer_login(cfg):
            run_session_check(cfg)
        return

    client = vault_client.create_client(addr, token)
    ok, msg = _token_lookup_ok(client)
    if ok:
        console().print(Text(msg, style="success"))
        return

    probe_path = (cfg.get("VAULTSH_SESSION_PROBE_PATH") or "").strip()
    probe_field = (cfg.get("VAULTSH_SESSION_PROBE_FIELD") or "").strip()
    if probe_path and probe_field:
        if _kv_probe_ok(client, probe_path, probe_field):
            console().print(Text("Session valid (KV access OK; token lookup not allowed by policy).", style="success"))
            return
    else:
        warn("Session unclear: token lookup failed (no VAULTSH_SESSION_PROBE_PATH/FIELD configured).")
        return

    warn("Session unclear: token lookup and KV probe failed. Log in or check path/permissions.")
    if _offer_login(cfg):
        run_session_check(cfg)


def _offer_login(cfg: dict[str, Any]) -> bool:
    from vaultsh.ui import confirm
    warn("Token invalid or expired or permission denied. Please log in again.")
    if confirm("Log in now?", default_no=True):
        return run_login_role(cfg, cfg.get("VAULTSH_READER_ROLE", "reader")) == 0
    return False


def run_login_role(cfg: dict[str, Any], role: str) -> int:
    addr = cfg.get("VAULT_ADDR") or cfg.get("VAULTSH_ADDR") or "https://127.0.0.1:8200"
    return vault_client.login_oidc(role, addr)


def run_status(cfg: dict[str, Any]) -> None:
    import subprocess
    addr = cfg.get("VAULT_ADDR") or cfg.get("VAULTSH_ADDR") or "https://127.0.0.1:8200"
    env = {**__import__("os").environ, "VAULT_ADDR": addr}
    subprocess.run(["vault", "status"], env=env)


def run_token_lookup(cfg: dict[str, Any]) -> None:
    import subprocess
    addr = cfg.get("VAULT_ADDR") or cfg.get("VAULTSH_ADDR") or "https://127.0.0.1:8200"
    env = {**__import__("os").environ, "VAULT_ADDR": addr}
    subprocess.run(["vault", "token", "lookup"], env=env)
