"""Cookie management helpers.

Provides functions for saving and formatting cookies.
Users need to manually copy cookies from their browser.
"""

from __future__ import annotations

from typing import Any

from td.config import save_credential


def save_cookie(provider_id: str, cookie_str: str, account: str = "default") -> dict[str, Any]:
    """Save a cookie string for a provider.

    Args:
        provider_id: which provider
        cookie_str: cookie string like "auth=xxx; oc_locale=zh"
        account: account name for multi-account support

    Returns:
        The saved credential dict
    """
    cookies = []
    for part in cookie_str.split(";"):
        part = part.strip()
        if "=" in part:
            name, value = part.split("=", 1)
            cookies.append({
                "name": name.strip(),
                "value": value.strip(),
            })

    cred = {"cookies": cookies}
    save_credential(provider_id, "cookie", cred, account=account)
    return cred


def format_cookie_header(cookies: list[dict[str, Any]]) -> str:
    """Turn a cookie list into a Cookie: header value."""
    return "; ".join(f"{c['name']}={c['value']}" for c in cookies if c.get("name"))
