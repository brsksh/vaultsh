"""Interactive or non-interactive setup: write ~/.config/vaultsh/config with VAULTSH_* values."""
from __future__ import annotations

import os
import sys
from pathlib import Path


def main() -> None:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))
    config_dir = config_home / "vaultsh"
    config_file = config_dir / "config"
    config_dir.mkdir(parents=True, exist_ok=True)

    non_interactive = "--non-interactive" in sys.argv or os.environ.get("VAULTSH_NON_INTERACTIVE") == "1"
    if non_interactive:
        addr = os.environ.get("VAULTSH_ADDR", "https://127.0.0.1:8200")
        reader = os.environ.get("VAULTSH_READER_ROLE", "reader")
        operator = os.environ.get("VAULTSH_OPERATOR_ROLE", "operator")
        nav_root = os.environ.get("VAULTSH_NAV_ROOT", "secret/")
        probe_path = os.environ.get("VAULTSH_SESSION_PROBE_PATH", "")
        probe_field = os.environ.get("VAULTSH_SESSION_PROBE_FIELD", "")
    else:
        print("vaultsh configuration")
        print("---------------------")
        addr = input(f"VAULTSH_ADDR [{os.environ.get('VAULTSH_ADDR', 'https://127.0.0.1:8200')}]: ").strip() or os.environ.get("VAULTSH_ADDR", "https://127.0.0.1:8200")
        reader = input(f"VAULTSH_READER_ROLE [{os.environ.get('VAULTSH_READER_ROLE', 'reader')}]: ").strip() or os.environ.get("VAULTSH_READER_ROLE", "reader")
        operator = input(f"VAULTSH_OPERATOR_ROLE [{os.environ.get('VAULTSH_OPERATOR_ROLE', 'operator')}]: ").strip() or os.environ.get("VAULTSH_OPERATOR_ROLE", "operator")
        nav_root = input(f"VAULTSH_NAV_ROOT [{os.environ.get('VAULTSH_NAV_ROOT', 'secret/')}]: ").strip() or os.environ.get("VAULTSH_NAV_ROOT", "secret/")
        probe_path = input("VAULTSH_SESSION_PROBE_PATH (optional; Enter to skip): ").strip()
        probe_field = input("VAULTSH_SESSION_PROBE_FIELD (optional): ").strip() if probe_path else ""

    lines = [
        f'VAULTSH_ADDR="{addr}"',
        f'VAULTSH_READER_ROLE="{reader}"',
        f'VAULTSH_OPERATOR_ROLE="{operator}"',
        f'VAULTSH_NAV_ROOT="{nav_root}"',
    ]
    if probe_path:
        lines.append(f'VAULTSH_SESSION_PROBE_PATH="{probe_path}"')
        if probe_field:
            lines.append(f'VAULTSH_SESSION_PROBE_FIELD="{probe_field}"')
    config_file.write_text("\n".join(lines) + "\n")
    print(f"Wrote {config_file}")


if __name__ == "__main__":
    main()
