# vaultsh

A standalone, reusable CLI wrapper around HashiCorp Vault for interactive use. It makes Vault administration easier for operators and readers working from the terminal.

**Not intended for automation or CI** — use the `vault` CLI directly there.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Updating](#updating)
- [Usage](#usage)
- [Security](#security)
- [Configuration](#configuration)
- [Debugging](#debugging)
- [License](#license)

---

## Features

- **OIDC login** with configurable roles (e.g. reader, operator) via the Vault CLI (browser flow).
- **Session check** — see if you're logged in; handles token lookup 403 with a configurable KV read fallback; clear messages for missing/expired token and permission denied.
- **Read/write KV secrets** — specify path and optional field each time (no fixed default secret). Vault API via **hvac** (no subprocess for read/write).
- **Browse / Navigate** — walk KV paths, open "folders" (prefixes), and read secrets.
- **Optional vault status and token lookup** (subprocess).
- **Diagnostics** — connectivity, token, and a sample secret read.
- **Config file** (Key=Value) for Vault address, roles, optional session-probe path, and nav root; same format as before (`~/.config/vaultsh/config` or `vaultsh.conf` next to the app).
- **Menus** — arrow keys to move, Enter to select, ESC to go back; 1–9 or letter as shortcut (no external tools).

---

## Requirements

- **Python 3.9+**
- [HashiCorp Vault CLI](https://developer.hashicorp.com/vault/docs/install) on your `PATH` (used for OIDC login and for `vault status` / `vault token lookup` in the menu)

---

## Installation

### Quick setup (from source)

```bash
git clone https://github.com/brsksh/vaultsh.git ~/.local/share/vaultsh
cd ~/.local/share/vaultsh
./setup.sh
```

The script creates a venv, installs the package, links `vaultsh` and `vaultsh-setup` into `~/.local/bin` (if that directory exists), and creates `~/.config/vaultsh/config` from the example if missing. Edit the config as needed, then run `vaultsh`.

### From source (manual)

```bash
git clone https://github.com/brsksh/vaultsh.git ~/.local/share/vaultsh
cd ~/.local/share/vaultsh
python3 -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -e .
ln -sf "$(pwd)/.venv/bin/vaultsh" ~/.local/bin/vaultsh
cp config.example ~/.config/vaultsh/config   # then edit
```

If your `pip` does not support editable install from `pyproject.toml` alone, run `./setup.sh` (it upgrades pip) or:

```bash
.venv/bin/pip install hvac rich
# Run with: PYTHONPATH=src .venv/bin/python -m vaultsh
# Or: .venv/bin/pip install .
```

---

## Updating

- **If you installed from PyPI:** `pip install -U vaultsh`
- **If you cloned the repo:** run `git pull` in the vaultsh directory, then `pip install -e .` (or re-create the venv) if needed.

---

## Usage

1. Configure vaultsh (see [Configuration](#configuration)) if you haven’t already.

2. Start vaultsh:

   ```bash
   vaultsh
   ```
   (or `python -m vaultsh` from the repo with `PYTHONPATH=src`)

3. Use the main menu: log in (OIDC reader or operator), browse KV paths, read or write secrets, run a session check, or run diagnostics.

4. **Session check** shows whether you’re still logged in. If token lookup returns permission denied, you can set `VAULTSH_SESSION_PROBE_PATH` and `VAULTSH_SESSION_PROBE_FIELD` so vaultsh tries a KV read and reports clearly. Use **Run diagnostics** for connectivity, token lookup, and an optional KV read.

You can also run single actions without the menu:

- `vaultsh session-check`
- `vaultsh read --path <path> [--field <field>]` (or `-p` / `-f`)
- `vaultsh browse`

See `vaultsh --help` for details.

---

## Security

vaultsh does not store secrets; it forwards them to the Vault API (hvac) or the Vault CLI (OIDC login, status, token lookup). The **Write** action sends the value via the Vault API; be aware that terminal history can capture path/field input unless disabled.

- **Token file:** If you use `~/.vault-token` (written by `vault login`), ensure restrictive permissions, e.g. `chmod 600 ~/.vault-token`, so other users cannot read it.

---

## Configuration

Configuration is loaded from (later overrides earlier):

1. Built-in defaults  
2. `~/.config/vaultsh/config` (if present)  
3. `vaultsh.conf` in the project root when run from source, or next to the installed package (if present)  
4. Environment variables (override everything)

You can run the setup helper (after installation) to create or overwrite `~/.config/vaultsh/config`:

```bash
vaultsh-setup
# or: python -m vaultsh.setup_config
# Non-interactive (use env vars): VAULTSH_ADDR=... VAULTSH_READER_ROLE=... vaultsh-setup --non-interactive
```

Or create/edit the file manually as Key=Value, e.g.:

```bash
VAULTSH_ADDR="https://vault.example.com"
VAULTSH_READER_ROLE="reader"
VAULTSH_OPERATOR_ROLE="operator"
# VAULTSH_NAV_ROOT="kv/"   # optional; leave unset to list all KV mounts in Browse
# Optional: for session check when token lookup returns 403
# VAULTSH_SESSION_PROBE_PATH="secret/probe"
# VAULTSH_SESSION_PROBE_FIELD="ok"
```

| Variable | Purpose | Default |
|----------|---------|---------|
| `VAULTSH_ADDR` | Vault server address (sets `VAULT_ADDR` for the vault CLI) | `https://127.0.0.1:8200` |
| `VAULTSH_READER_ROLE` | OIDC role for read-only use | `reader` |
| `VAULTSH_OPERATOR_ROLE` | OIDC role for writes/maintenance | `operator` |
| `VAULTSH_NAV_ROOT` | Optional. If set, Browse starts in this mount (e.g. `kv/`, `secret/`). If empty, Browse lists all KV mounts. | (empty = show all) |
| `VAULTSH_SESSION_PROBE_PATH` | Optional path for session check KV fallback | (empty) |
| `VAULTSH_SESSION_PROBE_FIELD` | Optional field for that probe | (empty) |

### Browse: mount list vs fixed start

- **Option A — Show all KV mounts (default)**  
  Leave `VAULTSH_NAV_ROOT` unset. When you choose **Browse**, vaultsh lists all KV secrets engines (e.g. `kv/`, `secret/`) and you pick one.  
  **Policy:** Your token needs read access to `sys/mounts` so vaultsh can discover mounts. Add to the role’s policy (e.g. reader/operator):

  ```hcl
  path "sys/mounts" {
    capabilities = ["read"]
  }
  ```

- **Option B — Start in one mount**  
  Set `VAULTSH_NAV_ROOT="kv/"` (or `secret/`, etc.). Browse opens directly in that mount; no mount list and **no** `sys/mounts` permission needed.  
  **Policy:** Only the usual KV permissions (list/read on that mount); no `sys` policy required.

If you see *"No KV secrets engines found (or no sys/mounts permission)"*, either add the `sys/mounts` block above to your policy or use Option B and set `VAULTSH_NAV_ROOT` to your mount (e.g. `kv/`).

Colored output is enabled when the terminal is a TTY. Disable with `export NO_COLOR=1`.

---

## Debugging

- Run `vaultsh` in a terminal and read any error messages.
- Use the **Run diagnostics** menu option to see environment, `vault status`, token lookup, and (if configured) a KV probe read.
- Manually run `vault status` and `vault token lookup` with the same `VAULT_ADDR` (and token) to verify connectivity and token validity.

---

## License

[MIT](LICENSE)
 