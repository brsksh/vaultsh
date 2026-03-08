"""Vault client via hvac. Token from env or ~/.vault-token; addr from config. OIDC via vault CLI subprocess."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any, Optional

import hvac


def login_oidc(role: str, addr: str) -> int:
    """Run vault login -method=oidc role=<role>. Returns exit code. Sets VAULT_ADDR for subprocess."""
    env = os.environ.copy()
    env["VAULT_ADDR"] = addr
    try:
        r = subprocess.run(
            ["vault", "login", "-method=oidc", f"role={role}"],
            env=env,
        )
        return r.returncode
    except FileNotFoundError:
        return 127


def get_token() -> Optional[str]:
    token = os.environ.get("VAULT_TOKEN")
    if token:
        return token
    path = Path.home() / ".vault-token"
    if path.exists():
        return path.read_text().strip() or None
    return None


def token_state() -> str:
    if os.environ.get("VAULT_TOKEN"):
        return "env"
    if (Path.home() / ".vault-token").exists():
        return "file"
    return "missing"


def create_client(url: str, token: Optional[str] = None) -> hvac.Client:
    client = hvac.Client(url=url.rstrip("/"), token=token)
    return client


def ensure_client(cfg: dict[str, Any]) -> hvac.Client:
    url = cfg.get("VAULT_ADDR") or cfg.get("VAULTSH_ADDR") or "https://127.0.0.1:8200"
    token = get_token()
    return create_client(url, token)
