"""CLI entry: vaultsh [--help] [session-check|read|browse] [options]; no subcommand → main menu."""
import shutil
import sys
from pathlib import Path

from . import config as config_module
from .ui import error


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] in ("--help", "-h"):
        print("""Usage: vaultsh [--help] [session-check|read|browse] [options]

HashiCorp Vault CLI assistant for interactive use.

Subcommands (optional; without one, the interactive menu starts):
  session-check    Show whether you are logged in (token state or KV probe).
  read             Read a secret; use --path and optionally --field.
  browse           Start the KV path browser.

Options for read:
  --path, -p PATH  Secret path (required).
  --field, -f NAME Secret field (optional; omit for full secret).

  - OIDC login (configurable reader/operator roles)
  - Session check and token/status inspection
  - Browse KV paths and read secrets
  - Read/write KV secrets (path and field chosen each time)
  - Diagnostics for connectivity and token issues

Not intended for automation or CI; use the vault CLI directly there.""")
        return

    script_dir = Path(__file__).resolve().parent.parent.parent
    cfg = config_module.load_config(script_dir)

    if not shutil.which("vault"):
        error("Required command not found: vault")
        sys.exit(1)

    sub = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
    if sub == "session-check":
        from .commands.session import run_session_check
        run_session_check(cfg)
        return
    if sub == "read":
        from .commands.read_write import run_read
        path = ""
        field = ""
        i = 0
        argv = sys.argv[2:]  # after "read"
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
            sys.exit(1)
        run_read(cfg, ["--path", path] + (["--field", field] if field else []))
        return
    if sub == "browse":
        from .commands.browse import run_browse
        run_browse(cfg, sys.argv[2:], pick_mode=False)
        return

    # Interactive main menu
    from .menus import run_main_menu
    run_main_menu(cfg)


if __name__ == "__main__":
    main()
