"""Configuration loading and credential storage.

Two-tier storage:
  - `config.yaml` (plaintext) holds provider enable flags, alert thresholds,
    watch interval, etc. Lives at $TD_CONFIG_DIR/config.yaml.
  - Credentials (API keys, cookies) are stored in the OS keyring when
    available, with a plaintext fallback at $TD_CONFIG_DIR/credentials.json
    (chmod 600). API keys use keyring by default.
"""

from __future__ import annotations

import json
import os
import stat
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml
from platformdirs import user_config_dir, user_data_dir

APP_NAME = "token-dashboard"
CONFIG_DIR = Path(os.environ.get("TD_CONFIG_DIR", user_config_dir(APP_NAME, appauthor=False)))
DATA_DIR = Path(os.environ.get("TD_DATA_DIR", user_data_dir(APP_NAME, appauthor=False)))
CONFIG_PATH = CONFIG_DIR / "config.yaml"
CREDENTIALS_PATH = CONFIG_DIR / "credentials.json"
CACHE_DIR = DATA_DIR / "cache"
HISTORY_DIR = DATA_DIR / "history"

DEFAULT_CONFIG: dict[str, Any] = {
    "providers": {
        "opencode": {"enabled": True, "auth": "cookie"},
        "minimax": {"enabled": True, "auth": "api_key"},
        "mimo": {"enabled": True, "auth": "cookie"},
        "xunfei": {"enabled": True, "auth": "cookie"},
        "deepseek": {"enabled": True, "auth": "api_key"},
    },
    "alerts": {
        # alert when the most-constrained window's used% exceeds this
        "warn_pct": 70,
        "critical_pct": 90,
    },
    "watch": {
        "interval_seconds": 60,
    },
    "display": {
        "currency_preference": "original",  # original | cny | usd
        "show_raw": False,
    },
}


@dataclass
class AppConfig:
    """In-memory config representation."""

    raw: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def load(cls, path: Path = CONFIG_PATH) -> AppConfig:
        if path.exists():
            data = yaml.safe_load(path.read_text()) or {}
        else:
            data = {}
        merged = _deep_merge(DEFAULT_CONFIG, data)
        return cls(raw=merged)

    def save(self, path: Path = CONFIG_PATH) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(self.raw, allow_unicode=True, sort_keys=False))

    def provider(self, provider_id: str) -> dict[str, Any]:
        return self.raw.get("providers", {}).get(provider_id, {})

    def set_provider(self, provider_id: str, **kwargs: Any) -> None:
        self.raw.setdefault("providers", {}).setdefault(provider_id, {}).update(kwargs)


def _deep_merge(base: dict, overlay: dict) -> dict:
    """Deep-merge overlay into base; overlay wins on scalars."""
    out = dict(base)
    for k, v in overlay.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


# ------------------------- credentials ------------------------- #


def save_credential(
    provider_id: str,
    kind: str,
    value: dict[str, Any],
    account: str = "default",
) -> None:
    """Save a credential bundle. kind is e.g. 'api_key', 'cookie'.

    Tries keyring first, falls back to file. Stored under
    `td:<provider>:<account>:<kind>` in keyring.
    """
    payload = json.dumps(value)
    try:
        import keyring

        keyring.set_password(f"td:{provider_id}:{account}:{kind}", "value", payload)
        return
    except Exception:
        pass

    # File fallback
    CREDENTIALS_PATH.parent.mkdir(parents=True, exist_ok=True)
    creds: dict[str, Any] = {}
    if CREDENTIALS_PATH.exists():
        try:
            creds = json.loads(CREDENTIALS_PATH.read_text())
        except Exception:
            creds = {}
    creds.setdefault(provider_id, {}).setdefault(account, {})[kind] = value
    CREDENTIALS_PATH.write_text(json.dumps(creds, indent=2, ensure_ascii=False))
    CREDENTIALS_PATH.chmod(stat.S_IRUSR | stat.S_IWUSR)


def load_credential(provider_id: str, kind: str, account: str = "default") -> dict[str, Any] | None:
    try:
        import keyring

        raw = keyring.get_password(f"td:{provider_id}:{account}:{kind}", "value")
        if raw:
            return json.loads(raw)
    except Exception:
        pass

    if not CREDENTIALS_PATH.exists():
        return None
    try:
        creds = json.loads(CREDENTIALS_PATH.read_text())
    except Exception:
        return None
    return creds.get(provider_id, {}).get(account, {}).get(kind)


def delete_credential(provider_id: str, kind: str, account: str = "default") -> None:
    try:
        import keyring

        keyring.delete_password(f"td:{provider_id}:{account}:{kind}", "value")
    except Exception:
        pass

    if CREDENTIALS_PATH.exists():
        try:
            creds = json.loads(CREDENTIALS_PATH.read_text())
        except Exception:
            return
        if (provider_id in creds
                and account in creds.get(provider_id, {})
                and kind in creds.get(provider_id, {}).get(account, {})):
            del creds[provider_id][account][kind]
            if not creds[provider_id][account]:
                del creds[provider_id][account]
            if not creds[provider_id]:
                del creds[provider_id]
            CREDENTIALS_PATH.write_text(json.dumps(creds, indent=2, ensure_ascii=False))


def list_accounts(provider_id: str) -> list[str]:
    """List all account names for a provider.

    Note: Keyring doesn't support listing, so we fall back to file storage.
    If using keyring, accounts won't be listed here.
    """
    if not CREDENTIALS_PATH.exists():
        return []
    try:
        creds = json.loads(CREDENTIALS_PATH.read_text())
    except Exception:
        return []
    return list(creds.get(provider_id, {}).keys())
