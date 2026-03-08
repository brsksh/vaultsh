"""Read and write KV secrets (path, optional field)."""
from __future__ import annotations

from typing import Any, Optional

from vaultsh import vault_client
from vaultsh.ui import (
    confirm,
    error,
    info,
    pause,
    pick_from_list,
    print_preview,
    prompt,
    prompt_secret,
    show_guidance,
    warn,
)
from vaultsh.ui import console
from vaultsh.ui import Text


def _read_secret(client: Any, path: str, mount_point: str = "secret") -> Optional[dict]:
    """path: full path like 'secret/myapp/config'. Returns data dict or None."""
    try:
        # path relative to mount
        rel = path
        if path.startswith(mount_point + "/"):
            rel = path[len(mount_point) + 1 :]
        r = client.secrets.kv.v2.read_secret_version(path=rel.rstrip("/"), mount_point=mount_point)
        return (r.get("data") or {}).get("data") or r.get("data") or {}
    except Exception:
        return None


def _mount_and_path(full_path: str) -> tuple[str, str]:
    parts = full_path.strip().split("/", 1)
    mount = parts[0] or "secret"
    path = (parts[1] or "").strip("/")
    return mount, path


def run_read(cfg: dict[str, Any], argv: list[str]) -> None:
    """CLI: vaultsh read --path X [--field Y]. Also used from menu with interactive path/field."""
    path = ""
    field = ""
    i = 0
    while i < len(argv):
        if argv[i] in ("--path", "-p") and i + 1 < len(argv):
            path = argv[i + 1]
            i += 2
            continue
        if argv[i] in ("--field", "-f") and i + 1 < len(argv):
            field = argv[i + 1]
            i += 2
            continue
        i += 1

    if not path:
        error("read subcommand requires --path (or -p). Example: vaultsh read -p secret/myapp/config")
        return

    token = vault_client.get_token()
    if not token:
        error("Not logged in. Use Login from the menu first.")
        return
    client = vault_client.ensure_client(cfg)
    mount, rel_path = _mount_and_path(path)
    data = _read_secret(client, path, mount)
    if data is None:
        error("Could not read secret at path.")
        return
    if field:
        if field not in data:
            error(f"Field '{field}' not found in secret.")
            return
        console().print(data[field])
    else:
        for k, v in data.items():
            console().print(Text(f"{k}", style="accent") + Text(f" = {v}", style="primary"))


def run_read_interactive(cfg: dict[str, Any]) -> None:
    """Menu flow: prompt path (or browse), optional field (or pick), then read."""
    show_guidance(
        "read",
        "Enter a secret path and optionally a field name (leave field empty for full secret).",
        "",
    )
    token = vault_client.get_token()
    if not token:
        warn("Not logged in.")
        if not confirm("Log in now?", default_no=True):
            pause()
            return
        from vaultsh.commands.session import run_login_role
        run_login_role(cfg, cfg.get("VAULTSH_READER_ROLE", "reader"))
        pause()
        return run_read_interactive(cfg)

    path = prompt("Secret path (Enter to browse)", "")
    if not path:
        from vaultsh.commands.browse import run_browse_pick_path
        path = run_browse_pick_path(cfg)
        if not path:
            return
    field = prompt("Optional field (Enter for full secret)", "")
    if path and not field:
        client = vault_client.ensure_client(cfg)
        mount, _ = _mount_and_path(path)
        data = _read_secret(client, path, mount)
        if data and len(data) > 1:
            choices = ["(full secret)"] + list(data.keys())
            picked = pick_from_list("Field (choose or ESC for full secret)", choices)
            if picked == "(full secret)":
                field = ""
            elif picked:
                field = picked
    run_read(cfg, ["--path", path, "--field", field] if field else ["--path", path])
    pause()


def run_write_interactive(cfg: dict[str, Any]) -> None:
    """Menu flow: path (or browse), field (or pick/new), value, preview, confirm, put."""
    show_guidance(
        "write",
        "Writes are previewed first and stay intentionally explicit.",
        "Use operator access before attempting updates or rotations.",
    )
    token = vault_client.get_token()
    if not token:
        warn("Not logged in.")
        if not confirm("Log in now?", default_no=True):
            pause()
            return
        from vaultsh.commands.session import run_login_role
        run_login_role(cfg, cfg.get("VAULTSH_OPERATOR_ROLE", "operator"))
        pause()
        return run_write_interactive(cfg)

    path = prompt("Secret path (Enter to browse)", "")
    if not path:
        from vaultsh.commands.browse import run_browse_pick_path
        path = run_browse_pick_path(cfg)
        if not path:
            return
    field = prompt("Field name (Enter to browse)", "")
    if path and not field:
        client = vault_client.ensure_client(cfg)
        mount, _ = _mount_and_path(path)
        data = _read_secret(client, path, mount)
        if data:
            choices = list(data.keys()) + ["(type new field)"]
            picked = pick_from_list("Field (choose or ESC to type name)", choices)
            if picked == "(type new field)":
                field = prompt("Field name", "")
            elif picked:
                field = picked
    if not path or not field:
        warn("Path and field are required. Skipping write.")
        pause()
        return
    value = prompt_secret("Field value (hidden)")
    print_preview("write secret", f"vault kv put {path} {field}=***")
    if not confirm("Execute this write", default_no=True):
        pause()
        return
    client = vault_client.ensure_client(cfg)
    mount, rel_path = _mount_and_path(path)
    try:
        # read current secret and merge, or create new
        current = _read_secret(client, path, mount)
        if current is None:
            current = {}
        else:
            current = dict(current)
        current[field] = value
        client.secrets.kv.v2.create_or_update_secret(path=rel_path, secret=current, mount_point=mount)
        info("Write succeeded.")
    except Exception:
        error("Write failed.")
    pause()
