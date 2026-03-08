"""Main menu and quick-open palette."""
from __future__ import annotations

import time
from typing import Any

from vaultsh import vault_client
from vaultsh.ui import (
    clear_screen,
    console,
    has_fzf,
    pause,
    print_header,
    print_panel,
    print_kv,
    select_option,
    show_guidance,
    warn,
)
from vaultsh.commands import session, browse, read_write, diagnostics

_SESSION_CACHE: tuple[float, str, str] = (0, "", "warn")
SESSION_CACHE_TTL = 30


def invalidate_session_cache() -> None:
    """Force next menu draw to re-check session (e.g. after login)."""
    global _SESSION_CACHE
    _SESSION_CACHE = (0, "", "warn")


def _get_session_line(cfg: dict[str, Any]) -> tuple[str, str]:
    """Return (session_line, style_name). Cached for SESSION_CACHE_TTL seconds."""
    global _SESSION_CACHE
    now = time.time()
    if _SESSION_CACHE[0] > 0 and (now - _SESSION_CACHE[0]) < SESSION_CACHE_TTL and _SESSION_CACHE[1]:
        return _SESSION_CACHE[1], _SESSION_CACHE[2]
    state = vault_client.token_state()
    if state == "missing":
        _SESSION_CACHE = (now, "Session: not logged in", "warn")
        return _SESSION_CACHE[1], _SESSION_CACHE[2]
    client = vault_client.ensure_client(cfg)
    try:
        data = client.auth.token.lookup_self()
        d = (data.get("data") or data) or {}
        expire = (d.get("expire_time") or "").replace("T", " ").split(".")[0].rstrip("Z")
        if expire:
            _SESSION_CACHE = (now, f"Session: active (until {expire})", "success")
        else:
            _SESSION_CACHE = (now, "Session: active", "success")
        return _SESSION_CACHE[1], _SESSION_CACHE[2]
    except Exception:
        pass
    probe_path = (cfg.get("VAULTSH_SESSION_PROBE_PATH") or "").strip()
    probe_field = (cfg.get("VAULTSH_SESSION_PROBE_FIELD") or "").strip()
    if probe_path and probe_field:
        try:
            from vaultsh.commands.diagnostics import _kv_probe
            mount = probe_path.split("/")[0] if "/" in probe_path else "secret"
            rc, _ = _kv_probe(client, probe_path, probe_field, mount)
            if rc == 0:
                _SESSION_CACHE = (now, "Session: active (KV)", "success")
                return _SESSION_CACHE[1], _SESSION_CACHE[2]
        except Exception:
            pass
    _SESSION_CACHE = (now, "Session: expired or no access", "warn")
    return _SESSION_CACHE[1], _SESSION_CACHE[2]


def _recommended_one(state: str) -> str:
    if state == "missing":
        return "1. Open Login and start an OIDC reader session."
    if state in ("file", "env"):
        return "1. Browse KV or read a secret, or inspect token details."
    return "1. Start with Login to establish a clean Vault session."


def _recommended_two(state: str) -> str:
    if state == "missing":
        return "2. Run diagnostics if you expect a token but reads still fail."
    if state in ("file", "env"):
        return "2. Use diagnostics before changing policies or secret paths."
    return "2. Review quick commands if you prefer the raw CLI path."


def run_main_menu(cfg: dict[str, Any]) -> None:
    while True:
        clear_screen()
        session_line, session_style = _get_session_line(cfg)
        state = vault_client.token_state()
        token_badge = f"TOKEN:{state}" if state != "missing" else "TOKEN:missing"
        token_style = "success" if state == "env" else ("accent" if state == "file" else "warn")
        menu_badge = "MENU:fzf" if has_fzf() else "MENU:classic"
        nav_root = cfg.get("VAULTSH_NAV_ROOT") or "secret/"
        addr = cfg.get("VAULT_ADDR") or cfg.get("VAULTSH_ADDR") or "https://127.0.0.1:8200"

        print_header(session_line, session_style, token_badge, token_style, menu_badge, nav_root, addr)
        print_panel("session", "Login, then browse, read or write secrets at any KV path.",
                    "Use diagnostics when auth succeeds but CLI reads fail.")
        print_panel("recommended next", _recommended_one(state), _recommended_two(state))
        console().print()

        choice = select_option(
            "Main menu",
            [
                ("p", "Quick open palette", "Jump straight to common actions by intent."),
                ("1", "Login and identity", "Open an OIDC session as reader or operator."),
                ("2", "Token and status checks", "Inspect connection, current token, and Vault health."),
                ("3", "Browse / Navigate", "Navigate KV paths and read secrets."),
                ("4", "Read secret", "Enter path and optional field to read a secret."),
                ("5", "Write or update secret", "Perform controlled writes with preview and confirmation."),
                ("6", "Run diagnostics", "Bundle the common checks for 403s, missing tokens, and wrong paths."),
                ("7", "Show quick commands", "Print the equivalent manual CLI commands."),
                ("q", "Quit", "Leave the interactive shell."),
            ],
        )
        if not choice:
            break
        if choice.lower() == "q":
            break
        if choice == "p":
            _handle_palette(cfg)
            continue
        if choice == "1":
            _handle_login_menu(cfg)
            continue
        if choice == "2":
            _handle_status_menu(cfg)
            continue
        if choice == "3":
            browse.run_browse(cfg, pick_mode=False)
            pause()
            continue
        if choice == "4":
            read_write.run_read_interactive(cfg)
            continue
        if choice == "5":
            read_write.run_write_interactive(cfg)
            continue
        if choice == "6":
            diagnostics.run_diagnostics(cfg)
            pause()
            continue
        if choice == "7":
            _handle_help(cfg)
            continue
        warn(f"Unknown menu choice: {choice}")
        pause()


def _handle_palette(cfg: dict[str, Any]) -> None:
    show_guidance("quick open", "Jump straight to common actions by intent.", "Pick a task instead of walking the whole menu tree.")
    choice = select_option(
        "Quick open",
        [
            ("1", "Login as reader", "Open an OIDC reader session immediately."),
            ("2", "Login as operator", "Open an OIDC operator session immediately."),
            ("3", "Browse KV", "Navigate through Vault KV paths and read secrets."),
            ("4", "Read secret", "Prompt for path and optional field, then read."),
            ("5", "Run diagnostics", "Bundle the common health, token, and secret checks."),
            ("6", "Session check", "Show whether you are still logged in or need to log in."),
            ("7", "Open write flow", "Go directly to the write/update menu."),
            ("8", "Quick commands", "Show the equivalent manual CLI commands."),
            ("b", "Back", "Return to the main menu."),
        ],
    )
    if not choice or choice == "b":
        return
    if choice == "1":
        session.run_login_role(cfg, cfg.get("VAULTSH_READER_ROLE", "reader"))
        invalidate_session_cache()
        pause()
        return
    if choice == "2":
        session.run_login_role(cfg, cfg.get("VAULTSH_OPERATOR_ROLE", "operator"))
        invalidate_session_cache()
        pause()
        return
    if choice == "3":
        browse.run_browse(cfg, pick_mode=False)
        pause()
        return
    if choice == "4":
        read_write.run_read_interactive(cfg)
        return
    if choice == "5":
        diagnostics.run_diagnostics(cfg)
        pause()
        return
    if choice == "6":
        session.run_session_check(cfg)
        pause()
        return
    if choice == "7":
        read_write.run_write_interactive(cfg)
        return
    if choice == "8":
        _handle_help(cfg)
        return


def _handle_login_menu(cfg: dict[str, Any]) -> None:
    reader = cfg.get("VAULTSH_READER_ROLE", "reader")
    operator = cfg.get("VAULTSH_OPERATOR_ROLE", "operator")
    show_guidance("login", "Reader is for normal daily access. Operator is for controlled writes and maintenance.",
                  "The browser flow should open automatically once you pick a role.")
    choice = select_option(
        "Login menu",
        [
            ("1", f"OIDC login as {reader}", "Read-only everyday session for secret access and checks."),
            ("2", f"OIDC login as {operator}", "Privileged session for updates, rotations, and maintenance."),
            ("b", "Back", "Return to the main menu without opening a browser flow."),
        ],
    )
    if not choice or choice == "b":
        return
    if choice == "1":
        session.run_login_role(cfg, reader)
        invalidate_session_cache()
    elif choice == "2":
        session.run_login_role(cfg, operator)
        invalidate_session_cache()
    pause()


def _handle_status_menu(cfg: dict[str, Any]) -> None:
    show_guidance("status", "Use this when you want confidence about the current session before touching secrets.",
                  "Session check shows at a glance whether you are still logged in or need to log in.")
    choice = select_option(
        "Status and token",
        [
            ("1", "Session check", "Show whether the session is valid or you need to log in."),
            ("2", "vault status", "Check connectivity, seal state, and core server health."),
            ("3", "vault token lookup", "Inspect the current token, policies, and expiry."),
            ("4", "Run both", "A quick read on connection plus identity state."),
            ("b", "Back", "Return to the main menu."),
        ],
    )
    if not choice or choice == "b":
        return
    if choice == "1":
        session.run_session_check(cfg)
    elif choice == "2":
        session.run_status(cfg)
    elif choice == "3":
        session.run_token_lookup(cfg)
    elif choice == "4":
        session.run_status(cfg)
        console().print()
        session.run_token_lookup(cfg)
    pause()


def _handle_help(cfg: dict[str, Any]) -> None:
    print_panel("config",
                f"address       {cfg.get('VAULTSH_ADDR', '')}",
                f"reader        {cfg.get('VAULTSH_READER_ROLE', '')}",
                f"operator      {cfg.get('VAULTSH_OPERATOR_ROLE', '')}",
                f"nav root      {cfg.get('VAULTSH_NAV_ROOT', '')}")
    probe = cfg.get("VAULTSH_SESSION_PROBE_PATH") or ""
    if probe:
        console().print(Text("session probe ", style="muted") + Text(f"{probe}:{cfg.get('VAULTSH_SESSION_PROBE_FIELD', '')}", style="bold"))
    from vaultsh.ui import console
    console().print(Text("─" * 72, style="panel"))
    console().print()
    console().print("Quick Commands")
    console().print("--------------")
    addr = cfg.get("VAULTSH_ADDR", "")
    reader = cfg.get("VAULTSH_READER_ROLE", "reader")
    console().print(f'export VAULT_ADDR="{addr}"')
    console().print(f'vault login -method=oidc role="{reader}"')
    console().print("vault kv get <path>                    # full secret")
    console().print("vault kv get -field=<field> <path>      # single field")
    pause()
