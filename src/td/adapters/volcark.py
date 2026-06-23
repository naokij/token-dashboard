"""Volcengine Ark Agent Plan adapter.

火山方舟 Agent Plan 个人版 — 4 个 AFP 配额窗口（5h / day / week / month）。

Data source: API — POST /?Action=GetAFPUsage&Version=2024-01-01
Endpoint:    https://ark.cn-beijing.volces.com
Auth:        Volcengine SigV4 (HMAC-SHA256 with AK/SK)
Docs:        https://www.volcengine.com/docs/82379/2479849

Auth modes:
  - api_key (the credential bundle contains {access_key, secret_key})
"""

from __future__ import annotations

import hashlib
import hmac
from datetime import UTC, datetime
from typing import Any
from urllib.parse import quote

import httpx

from td.adapters.base import Adapter, AuthRequiredError
from td.config import load_credential
from td.models import (
    PlanKind,
    ProviderId,
    QuotaUnit,
    QuotaWindow,
    UsageSnapshot,
    WindowKind,
)

ARK_HOST = "open.volcengineapi.com"
ARK_REGION = "cn-beijing"
ARK_SERVICE = "ark"
ARK_VERSION = "2024-01-01"


class VolcArkAdapter(Adapter):
    id = ProviderId.VOLCARK
    display_name = "Volc Ark Agent Plan"
    home_url = "https://www.volcengine.com/docs/82379/2366393"
    kind = PlanKind.TOKEN_PLAN
    api_key_format = "AK/SK"
    notes = "AFP-based, 5h/day/week/month windows; SigV4 auth"

    def supported_auth_modes(self) -> list[str]:
        return ["api_key"]

    async def fetch(self) -> UsageSnapshot:
        cred = load_credential(self.id.value, "api_key", account=self.account)
        if not (cred and cred.get("access_key") and cred.get("secret_key")):
            raise AuthRequiredError(
                "Volc Ark: please run "
                "`td add volcark --access-key <AK> --secret-key <SK>`"
            )

        data = await self._call(cred["access_key"], cred["secret_key"])
        result = data.get("Result", {}) or {}

        snap = UsageSnapshot(
            provider=self.id,
            fetched_at=datetime.now(UTC),
            plan_name=f"Agent Plan {result.get('PlanType', '')}".strip(),
            plan_kind=self.kind,
            windows=_parse_windows(result),
            auth_mode="api_key",
        )
        snap.raw["api_response"] = data
        return snap

    async def _call(self, ak: str, sk: str) -> dict[str, Any]:
        body = "{}"
        headers, url = _sign_request(
            ak=ak,
            sk=sk,
            action="GetAFPUsage",
            version=ARK_VERSION,
            body=body,
        )
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.post(url, headers=headers, content=body)
            if r.status_code >= 400:
                # Surface the Volcengine error body, not just the HTTP status.
                try:
                    err = r.json()
                except Exception:
                    err = {"raw": r.text}
                meta = (err.get("ResponseMetadata") or {}).get("Error") or err
                code = meta.get("Code") or meta.get("CodeN") or r.status_code
                msg = meta.get("Message") or err
                raise httpx.HTTPStatusError(
                    f"Volc Ark {r.status_code} {code}: {msg}",
                    request=r.request,
                    response=r,
                )
            return r.json()


# --------------------- response parsing --------------------- #


_WINDOW_DEFS: list[tuple[str, WindowKind, str]] = [
    ("AFPFiveHour", WindowKind.ROLLING_5H, "5h"),
    ("AFPDaily", WindowKind.ROLLING_DAY, "day · vision"),
    ("AFPWeekly", WindowKind.ROLLING_WEEK, "week"),
    ("AFPMonthly", WindowKind.ROLLING_MONTH, "month"),
]


def _parse_windows(result: dict[str, Any]) -> list[QuotaWindow]:
    windows: list[QuotaWindow] = []
    for key, kind, label in _WINDOW_DEFS:
        w = result.get(key)
        if not isinstance(w, dict):
            continue
        quota = w.get("Quota")
        used = w.get("Used")
        if quota is None or used is None:
            continue
        quota = float(quota)
        used = float(used)
        remaining = max(0.0, quota - used)
        used_pct = (used / quota * 100.0) if quota > 0 else None
        windows.append(
            QuotaWindow(
                kind=kind,
                label=f"AFP ({label})",
                used=used,
                limit=quota,
                remaining=remaining,
                unit=QuotaUnit.CREDITS,
                used_pct=used_pct,
                reset_at=_ms_to_dt(w.get("ResetTime")),
                period_start=_ms_to_dt(w.get("SubscribeTime")),
                period_end=_ms_to_dt(w.get("ResetTime")),
                raw=w,
            )
        )
    return windows


def _ms_to_dt(ms: Any) -> datetime | None:
    if ms is None:
        return None
    try:
        return datetime.fromtimestamp(int(ms) / 1000, tz=UTC)
    except (TypeError, ValueError):
        return None


# --------------------- Volcengine SigV4 --------------------- #


def _norm_query(params: dict[str, str]) -> str:
    """Alphabetically sorted, URL-encoded query string (Volcengine format)."""
    parts = []
    for key in sorted(params.keys()):
        val = params[key]
        if isinstance(val, list):
            for v in val:
                parts.append(f"{quote(key, safe='-_.~')}={quote(v, safe='-_.~')}")
        else:
            parts.append(f"{quote(key, safe='-_.~')}={quote(val, safe='-_.~')}")
    return "&".join(parts).replace("+", "%20")


def _sign_request(
    *,
    ak: str,
    sk: str,
    action: str,
    version: str,
    body: str,
    host: str = ARK_HOST,
    region: str = ARK_REGION,
    service: str = ARK_SERVICE,
) -> tuple[dict[str, str], str]:
    """Build signed headers + URL for a Volcengine top-level API POST.

    Follows the official volcengine-python-sdk signing pattern exactly.
    """
    now = datetime.now(UTC)
    x_date = now.strftime("%Y%m%dT%H%M%SZ")
    short_x_date = x_date[:8]

    x_content_sha256 = hashlib.sha256(body.encode("utf-8")).hexdigest()

    query = {"Action": action, "Version": version}
    canonical_query = _norm_query(query)

    content_type = "application/json"
    signed_headers_list = ["content-type", "host", "x-content-sha256", "x-date"]
    signed_headers_str = ";".join(signed_headers_list)

    canonical_request = "\n".join(
        [
            "POST",
            "/",
            canonical_query,
            f"content-type:{content_type}",
            f"host:{host}",
            f"x-content-sha256:{x_content_sha256}",
            f"x-date:{x_date}",
            "",
            signed_headers_str,
            x_content_sha256,
        ]
    )

    hashed_canonical_request = hashlib.sha256(canonical_request.encode("utf-8")).hexdigest()
    credential_scope = f"{short_x_date}/{region}/{service}/request"

    string_to_sign = "\n".join(
        ["HMAC-SHA256", x_date, credential_scope, hashed_canonical_request]
    )

    k_date = hmac.new(sk.encode("utf-8"), short_x_date.encode("utf-8"), hashlib.sha256).digest()
    k_region = hmac.new(k_date, region.encode("utf-8"), hashlib.sha256).digest()
    k_service = hmac.new(k_region, service.encode("utf-8"), hashlib.sha256).digest()
    k_signing = hmac.new(k_service, b"request", hashlib.sha256).digest()
    signature = hmac.new(k_signing, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    authorization = (
        f"HMAC-SHA256 Credential={ak}/{credential_scope}, "
        f"SignedHeaders={signed_headers_str}, Signature={signature}"
    )

    headers = {
        "Host": host,
        "Content-Type": content_type,
        "X-Date": x_date,
        "X-Content-Sha256": x_content_sha256,
        "Authorization": authorization,
    }
    url = f"https://{host}/?{canonical_query}"
    return headers, url
