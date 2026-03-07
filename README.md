# vaultsh

A standalone, reusable CLI wrapper around the HashiCorp Vault CLI for interactive use. It makes Vault administration easier for operators and readers working from the terminal.

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

- **OIDC login** with configurable roles (e.g. reader, operator).
- **Session check** — see if you're logged in; handles token lookup 403 with a configurable KV read fallback; clear messages for missing/expired token and permission denied.
- **Read/write KV secrets** — specify path and optional field each time (no fixed default secret).
- **Browse / Navigate** — walk KV paths, open "folders" (prefixes), and read secrets.
- **Optional vault status and token lookup**.
- **Diagnostics** — connectivity, token, and a sample secret read.
- **Config file** (shell script) for Vault address, roles, optional session-probe path, and nav root; no hardcoded project references.
- **Optional fzf** for menus; falls back to simple prompts.

---

## Requirements

- **Bash** (4.x or 5.x; for `[[ ]]`, arrays, etc.). On macOS the system Bash may be older; install a newer Bash (e.g. via Homebrew) if needed.
- [HashiCorp Vault CLI](https://developer.hashicorp.com/vault/docs/install) installed and on your `PATH`
- Optional: [fzf](https://github.com/junegunn/fzf) for interactive menus
- Optional: [jq](https://jqlang.github.io/jq/) for browsing secret fields when reading or writing (Enter at the field prompt)

---

## Installation

### One-line install (recommended)

Run the installer script, which will clone the repository, run the setup, and optionally create a symlink into a directory on your `PATH`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/brsksh/vaultsh/main/install_vaultsh.sh)
```

### Manual install

Clone vaultsh into a directory of your choice and make the script executable:

```bash
git clone https://github.com/brsksh/vaultsh.git ~/.local/share/vaultsh
chmod +x ~/.local/share/vaultsh/vaultsh
```

Create a config file (recommended) by copying the example and editing it, or run the setup script from the repo:

```bash
cd ~/.local/share/vaultsh
cp config.example vaultsh.conf
# edit vaultsh.conf, or run:
./setup_vaultsh.sh
```

To run vaultsh from anywhere, symlink it into a directory on your `PATH` (e.g. `~/.local/bin`):

```bash
mkdir -p ~/.local/bin
ln -sf ~/.local/share/vaultsh/vaultsh ~/.local/bin/vaultsh
```

---

## Updating

- **If you installed via the one-line installer:** run the install script again; it will `git pull` if the target directory is already a clone. To update without re-running setup (e.g. to keep your existing config), use `--no-setup` or `VAULTSH_SKIP_SETUP=1`:  
  `bash install_vaultsh.sh --no-setup` or `VAULTSH_SKIP_SETUP=1 bash install_vaultsh.sh`
- **If you cloned the repo yourself:** run `git pull` in the vaultsh directory.
- **If vaultsh is a symlink** to your clone, run `git pull` in that clone to update.

---

## Usage

1. After installation, run the interactive setup to configure vaultsh (if you haven't already):

   ```bash
   ./setup_vaultsh.sh
   ```

2. Start vaultsh:

   ```bash
   vaultsh
   ```
   (or `./vaultsh` from the repo directory)

3. Use the main menu: log in (OIDC reader or operator), browse KV paths, read or write secrets, run a session check, or run diagnostics.

4. **Session check** shows whether you're still logged in. If token lookup returns permission denied, you can optionally set `VAULTSH_SESSION_PROBE_PATH` and `VAULTSH_SESSION_PROBE_FIELD` so vaultsh tries a KV read and reports clearly (e.g. "Session valid (KV access OK)" or "Token invalid or expired"). Use **Run diagnostics** for connectivity and token lookup (and an optional KV read if probe is configured).

You can also run single actions without the menu: `vaultsh session-check`, `vaultsh read --path <path> [--field <field>]`, `vaultsh browse`. See `vaultsh --help` for details.

---

## Security

vaultsh does not store secrets; it forwards them to the Vault CLI. Do not pass sensitive values through insecure channels. The **Write** action sends the value to `vault kv put`; be aware that command-line arguments may appear in process lists and that terminal history can capture input unless disabled.

---

## Configuration

Configuration is stored in `${XDG_CONFIG_HOME:-$HOME/.config}/vaultsh/config`. Create or update it by running:

```bash
./setup_vaultsh.sh
```

The script prompts for:

- `VAULTSH_ADDR` (Vault server URL)
- `VAULTSH_READER_ROLE` and `VAULTSH_OPERATOR_ROLE` (OIDC roles)
- `VAULTSH_NAV_ROOT` (start path for Browse; must end with `/`)
- Optionally `VAULTSH_SESSION_PROBE_PATH` and `VAULTSH_SESSION_PROBE_FIELD` (for session check when token lookup returns 403; Enter to skip)

For non-interactive setup (e.g. in dotfiles):

```bash
VAULTSH_ADDR="https://vault.example.com" \
VAULTSH_READER_ROLE="reader" \
VAULTSH_OPERATOR_ROLE="operator" \
VAULTSH_NAV_ROOT="secret/" \
./setup_vaultsh.sh --non-interactive
```

Config is loaded in this order (later overrides earlier):

1. Built-in defaults
2. `vaultsh.conf` in the same directory as the `vaultsh` script (if present)
3. `~/.config/vaultsh/config` (if present)
4. Environment variables (override everything)

| Variable | Purpose | Default |
|----------|---------|---------|
| `VAULTSH_ADDR` | Vault server address (sets `VAULT_ADDR` for the vault CLI) | `https://127.0.0.1:8200` |
| `VAULTSH_READER_ROLE` | OIDC role for read-only use | `reader` |
| `VAULTSH_OPERATOR_ROLE` | OIDC role for writes/maintenance | `operator` |
| `VAULTSH_NAV_ROOT` | Start path for Browse / Navigate (must end with `/`). Use the full path to your KV mount, e.g. `secret/` or `kv/` depending on how the engine is mounted. | `secret/` |
| `VAULTSH_SESSION_PROBE_PATH` | Optional path used by session check when token lookup returns 403 (KV fallback) | (empty) |
| `VAULTSH_SESSION_PROBE_FIELD` | Optional field for that probe | (empty) |

### CLI appearance

Colored output is enabled by default when the terminal is a TTY. Disable with `export NO_COLOR=1` (or `VAULTSH_NO_COLOR=1` if the tool is extended to respect it).

---

## Debugging

vaultsh does not write a separate log file. To troubleshoot:

- Run `vaultsh` in a terminal and read any error messages.
- Use the **Run diagnostics** menu option to see environment, `vault status`, token lookup, and (if configured) a KV probe read.
- Manually run `vault status` and `vault token lookup` with the same `VAULT_ADDR` (and token) to verify connectivity and token validity.

---

## License

[MIT](LICENSE)
