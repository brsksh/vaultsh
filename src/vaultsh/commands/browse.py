"""Browse KV paths: list, navigate, read secret; optional pick mode for path selection."""
from __future__ import annotations

from typing import Any, Optional

from vaultsh import vault_client
from vaultsh.ui import (
    error,
    has_fzf,
    info,
    pause,
    pick_from_list,
    print_section,
    select_option,
)
from vaultsh.ui import console
from vaultsh.ui import Text


def _parse_nav_root(nav_root: str) -> tuple[str, str]:
    """Return (mount_point, path). e.g. 'secret/' -> ('secret', ''), 'secret/team/' -> ('secret', 'team/')."""
    s = (nav_root or "secret/").strip().rstrip("/") + "/"
    parts = s.split("/", 1)
    mount = parts[0] or "secret"
    path = (parts[1] or "").strip("/")
    if path and not path.endswith("/"):
        path += "/"
    return mount, path


def _full_path(mount: str, path: str) -> str:
    if path:
        return f"{mount}/{path.rstrip('/')}"
    return mount + "/"


def _list_keys(client: Any, mount_point: str, path: str) -> list[str]:
    """List direct children at path (path relative to mount). Try KV v2, then v1, then raw LIST. Returns list of key names (with / for dirs)."""
    path = (path or "").strip("/")
    normalized = path + "/" if path else ""

    # 1) KV v2
    try:
        r = client.secrets.kv.v2.list_secrets(path=path, mount_point=mount_point)
        keys = (r.get("data") or {}).get("keys") or []
        return list(keys)
    except Exception:
        pass

    # 2) KV v1 (may not exist in older hvac)
    kv_v1 = getattr(client.secrets.kv, "v1", None)
    if kv_v1 is not None:
        for p in (path, normalized.rstrip("/") or "/", ""):
            try:
                r = kv_v1.list_secrets(path=p or "", mount_point=mount_point)
                keys = (r.get("data") or {}).get("keys") or []
                return list(keys)
            except Exception:
                continue

    # 3) Raw LIST (v2 then v1 style)
    adapter = getattr(client, "_adapter", None)
    if adapter is not None and hasattr(adapter, "list"):
        for api_path in (
            f"/v1/{mount_point}/metadata/{normalized}".rstrip("/"),
            f"/v1/{mount_point}/{normalized}".rstrip("/") or f"/v1/{mount_point}/",
        ):
            try:
                r = adapter.list(api_path)
                keys = (r.get("data") or {}).get("keys") or []
                return list(keys)
            except Exception:
                continue
    return []


def _can_go_up(current_path: str, root_path: str) -> bool:
    cur = (current_path or "").rstrip("/")
    root = (root_path or "").rstrip("/")
    if not cur or cur == root:
        return False
    return True


def _path_up(current_path: str, root_path: str) -> str:
    cur = (current_path or "").rstrip("/")
    root = (root_path or "").rstrip("/")
    if not cur or cur == root:
        return root + "/" if root else ""
    parts = cur.split("/")
    if len(parts) <= 1:
        return root + "/" if root else ""
    up = "/".join(parts[:-1])
    if len(up) < len(root) and root:
        return root + "/"
    return up + "/"


def _read_secret(client: Any, mount_point: str, path: str) -> Optional[dict]:
    """Path is relative to mount, no leading/trailing slash for the secret key. Try KV v2, then v1."""
    path = path.rstrip("/")
    for version in ("v2", "v1"):
        try:
            if version == "v2":
                r = client.secrets.kv.v2.read_secret_version(path=path, mount_point=mount_point)
                data = (r.get("data") or {}).get("data") or r.get("data") or {}
            else:
                r = client.secrets.kv.v1.read_secret(path=path, mount_point=mount_point)
                data = (r.get("data") or r) or {}
            return data if isinstance(data, dict) else None
        except Exception:
            continue
    return None


def run_browse(cfg: dict[str, Any], argv: Optional[list] = None, pick_mode: bool = False) -> Optional[str]:
    """Run browse loop. If pick_mode, return selected secret path or None. Otherwise return None."""
    argv = argv or []
    nav_root = (cfg.get("VAULTSH_NAV_ROOT") or "secret/").strip()
    if not nav_root.endswith("/"):
        nav_root += "/"
    mount_point, root_path = _parse_nav_root(cfg.get("VAULTSH_NAV_ROOT") or "secret/")
    current_path = root_path

    token = vault_client.get_token()
    if not token:
        error("Not logged in. Use Login from the menu first.")
        return None
    client = vault_client.ensure_client(cfg)

    while True:
        full = _full_path(mount_point, current_path)
        print_section("Browse", f"Browse: {full}")

        keys = _list_keys(client, mount_point, current_path.rstrip("/") if current_path else "")
        options: list[tuple[str, str, str]] = []
        option_keys: list[str] = []
        if _can_go_up(current_path, root_path):
            options.append(("..", "..", "Go up one level."))
            option_keys.append("..")
        for k in keys:
            if k.endswith("/"):
                options.append((k, f"Open {k}", "List contents of this path."))
                option_keys.append(k)
            else:
                options.append((k, f"Read secret {k}", "Read this secret."))
                option_keys.append(k)

        if not options:
            info("This path is empty or you have no list permission.")
            info("Check VAULTSH_NAV_ROOT and your policy's list capability.")
            select_option("Path", [("b", "Back to menu", "Return to main menu.")], fzf_header_extra="Press Enter to return.")
            return None

        choice = select_option("Path", options, fzf_header_extra="Enter: open/read. ESC: back to menu.")
        if not choice:
            return None

        if choice == "..":
            current_path = _path_up(current_path, root_path)
            continue

        # Normalize: if user chose a key that exists as folder (with /), use it
        key = choice
        if not key.endswith("/") and (key + "/") in keys:
            key = key + "/"
        full_path = current_path.rstrip("/") + "/" + key.strip("/") if current_path else key

        if key.endswith("/"):
            current_path = full_path if full_path.endswith("/") else full_path + "/"
            continue

        # Leaf secret
        if pick_mode:
            return _full_path(mount_point, full_path)

        print_section("Secret", f"Secret: {_full_path(mount_point, full_path)}")
        secret = _read_secret(client, mount_point, full_path)
        if secret is not None:
            for k, v in secret.items():
                console().print(Text(f"  {k}", style="accent") + Text(f" = {v}", style="primary"))
        else:
            error("Could not read secret.")
        console().print()
        pause()
        # Stay at same path


def run_browse_pick_path(cfg: dict[str, Any]) -> Optional[str]:
    """Browse and return selected secret path, or None on cancel."""
    return run_browse(cfg, pick_mode=True)
