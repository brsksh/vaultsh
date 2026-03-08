"""Load config: defaults, then ~/.config/vaultsh/config, then vaultsh.conf, then env."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, Optional


def _parse_config_file(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1].replace('\\"', '"')
            elif value.startswith("'") and value.endswith("'"):
                value = value[1:-1]
            if value.startswith("${") and ":-" in value and value.endswith("}"):
                # Simple ${VAR:-default} → use env or default
                inner = value[2:-1]
                var_name, _, default = inner.partition(":-")
                var_name = var_name.strip()
                default = default.strip().strip('"').strip("'")
                value = os.environ.get(var_name, default)
            out[key] = value
    return out


def load_config(script_dir: Optional[Path] = None) -> Dict[str, Any]:
    defaults = {
        "VAULTSH_ADDR": "https://127.0.0.1:8200",
        "VAULTSH_READER_ROLE": "reader",
        "VAULTSH_OPERATOR_ROLE": "operator",
        "VAULTSH_NAV_ROOT": "secret/",
        "VAULTSH_SESSION_PROBE_PATH": "",
        "VAULTSH_SESSION_PROBE_FIELD": "",
    }
    cfg = dict(defaults)

    config_home = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))
    config_file_home = config_home / "vaultsh" / "config"
    for path in (config_file_home, Path(script_dir or ".") / "vaultsh.conf"):
        if path and path.exists():
            for k, v in _parse_config_file(Path(path)).items():
                if k in cfg or k.startswith("VAULTSH_") or k == "VAULT_ADDR":
                    cfg[k] = v

    cfg["VAULT_ADDR"] = cfg.get("VAULT_ADDR") or cfg["VAULTSH_ADDR"]

    for key in list(cfg):
        if key in os.environ and os.environ[key] is not None:
            cfg[key] = os.environ[key]

    cfg["VAULT_ADDR"] = cfg.get("VAULT_ADDR") or cfg["VAULTSH_ADDR"]
    return cfg
