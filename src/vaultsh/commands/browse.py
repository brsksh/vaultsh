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


def _get_kv_mounts(client: Any) -> list[str]:
    """Return list of KV secrets engine mount names (e.g. ['kv', 'secret']). Requires sys/mounts read."""
    try:
        data = client.sys.list_mounted_secrets_engines()
        mounts = (data.get("data") or data) or {}
        out = []
        for path, info in mounts.items():
            if not isinstance(info, dict):
                continue
            mount_type = (info.get("type") or "").strip().lower()
            if mount_type in ("kv", "kv-v2"):
                name = (path or "").rstrip("/")
                if name:
                    out.append(name)
        return sorted(out)
    except Exception:
        return []


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
    """Run browse loop. Without VAULTSH_NAV_ROOT: show KV mounts first, then browse. With: start in that mount."""
    argv = argv or []
    token = vault_client.get_token()
    if not token:
        error("Not logged in. Use Login from the menu first.")
        return None
    client = vault_client.ensure_client(cfg)

    nav_root_cfg = (cfg.get("VAULTSH_NAV_ROOT") or "").strip()
    if nav_root_cfg:
        mount_point: Optional[str]
        mount_point, root_path = _parse_nav_root(nav_root_cfg)
        current_path = root_path
    else:
        mount_point = None
        root_path = ""
        current_path = ""

    while True:
        # Mount selection (no fixed nav root)
        if mount_point is None:
            mounts = _get_kv_mounts(client)
            if not mounts:
                error("No KV secrets engines found (or no sys/mounts permission).")
                info("Ensure your token can read sys/mounts, or set VAULTSH_NAV_ROOT to a mount (e.g. kv/).")
                select_option("Path", [("b", "Back to menu", "Return to main menu.")], fzf_header_extra="Press Enter to return.")
                return None
            options = [(m, f"{m}/", f"Browse KV mount {m}/") for m in mounts]
            options.append(("b", "Back to menu", "Return to main menu."))
            choice = select_option("KV mount", options, fzf_header_extra="Select a mount to browse.")
            if not choice or choice == "b":
                return None
            mount_point = choice
            current_path = ""
            root_path = ""
            continue

        full = _full_path(mount_point, current_path)
        print_section("Browse", f"Browse: {full}")

        keys = _list_keys(client, mount_point, current_path.rstrip("/") if current_path else "")
        options_list: list[tuple[str, str, str]] = []
        if current_path:
            options_list.append(("..", "..", "Go up one level."))
        else:
            options_list.append(("..", "..", "Back to mount list."))
        for k in keys:
            if k.endswith("/"):
                options_list.append((k, f"Open {k}", "List contents of this path."))
            else:
                options_list.append((k, f"Read secret {k}", "Read this secret."))

        if not keys:
            info("This path is empty or you have no list permission.")
            choice = select_option(
                "Path",
                [("..", "Back to mount list", "Choose another KV mount."), ("b", "Back to menu", "Return to main menu.")],
                fzf_header_extra="Press Enter to return.",
            )
            if not choice or choice == "b":
                return None
            if choice == "..":
                mount_point = None
            continue

        choice = select_option("Path", options_list, fzf_header_extra="Enter: open/read. ESC: back.")
        if not choice:
            return None

        if choice == "..":
            if current_path:
                current_path = _path_up(current_path, root_path)
            else:
                mount_point = None
            continue

        key = choice
        if not key.endswith("/") and (key + "/") in keys:
            key = key + "/"
        full_path = current_path.rstrip("/") + "/" + key.strip("/") if current_path else key

        if key.endswith("/"):
            current_path = full_path if full_path.endswith("/") else full_path + "/"
            continue

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


def run_browse_pick_path(cfg: dict[str, Any]) -> Optional[str]:
    """Browse and return selected secret path, or None on cancel."""
    return run_browse(cfg, pick_mode=True)
