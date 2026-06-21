"""Xiaomi MiMo adapter.

MiMo offers two billing modes:
  - Token Plan subscription: monthly credits quota
  - Pay-as-you-go: continuous balance deduction

Data sources:
  - Token Plan: GET /api/v1/tokenPlan/usage
  - Pay-as-you-go: GET /api/v1/balance

Auth modes:
  - cookie (required)
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import httpx

from td.adapters.base import Adapter, AuthRequiredError
from td.config import load_credential
from td.cookies import format_cookie_header
from td.models import (
    PlanKind,
    ProviderId,
    QuotaUnit,
    QuotaWindow,
    UsageSnapshot,
    WindowKind,
)

MIMO_API_BASE = "https://platform.xiaomimimo.com/api/v1"


class MiMoAdapter(Adapter):
    id = ProviderId.MIMO
    display_name = "Xiaomi MiMo"
    home_url = "https://platform.xiaomimimo.com/"
    kind = PlanKind.TOKEN_PLAN
    api_key_format = None
    notes = "Token Plan + Pay-as-you-go"

    def supported_auth_modes(self) -> list[str]:
        return ["cookie"]

    async def fetch(self) -> UsageSnapshot:
        snap = UsageSnapshot(
            provider=self.id,
            fetched_at=datetime.now(UTC),
            plan_name="MiMo",
            plan_kind=self.kind,
            windows=[],
            auth_mode="cookie",
        )

        cookie_cred = load_credential(self.id.value, "cookie", account=self.account)
        if not (cookie_cred and cookie_cred.get("cookies")):
            raise AuthRequiredError(
                "MiMo: please run `td login mimo -c '<cookie>'`"
            )

        cookie_header = format_cookie_header(cookie_cred["cookies"])
        headers = {
            "Cookie": cookie_header,
            "Accept": "application/json",
            "x-timezone": "Asia/Shanghai",
        }

        async with httpx.AsyncClient(timeout=15) as client:
            # Fetch token plan detail (plan name + expiry)
            try:
                r = await client.get(
                    f"{MIMO_API_BASE}/tokenPlan/detail",
                    headers=headers,
                )
                if r.status_code == 200:
                    data = r.json()
                    if data.get("code") == 0:
                        detail_data = data.get("data", {})
                        if plan_name := detail_data.get("planName"):
                            snap.plan_name = plan_name
                        if period_end := detail_data.get("currentPeriodEnd"):
                            snap.plan_expires_at = datetime.strptime(
                                period_end, "%Y-%m-%d %H:%M:%S"
                            ).replace(tzinfo=UTC)
            except Exception as e:
                snap.warnings.append(f"Plan detail fetch failed: {e}")

            # Fetch balance (pay-as-you-go)
            try:
                r = await client.get(
                    f"{MIMO_API_BASE}/balance",
                    headers=headers,
                )
                if r.status_code == 200:
                    data = r.json()
                    if data.get("code") == 0:
                        balance_data = data.get("data", {})
                        balance = float(balance_data.get("balance", 0))
                        snap.balance = balance
                        snap.balance_unit = QuotaUnit.CNY
            except Exception as e:
                snap.warnings.append(f"Balance fetch failed: {e}")

            # Fetch token plan usage
            try:
                r = await client.get(
                    f"{MIMO_API_BASE}/tokenPlan/usage",
                    headers=headers,
                )
                if r.status_code == 200:
                    data = r.json()
                    if data.get("code") == 0:
                        windows = self._parse_token_plan(data.get("data", {}))
                        snap.windows = windows
            except Exception as e:
                snap.warnings.append(f"Token plan fetch failed: {e}")

        # Set reset_at on calendar_month window from plan_expires_at
        if snap.plan_expires_at:
            for w in snap.windows:
                if w.kind == WindowKind.CALENDAR_MONTH and w.reset_at is None:
                    w.reset_at = snap.plan_expires_at

        return snap

    def _parse_token_plan(self, data: dict[str, Any]) -> list[QuotaWindow]:
        """Parse token plan usage data.

        Response shape:
        {
            "monthUsage": {
                "percent": 0.03,
                "items": [{
                    "name": "month_total_token",
                    "used": 100000,
                    "limit": 4100000000,
                    "percent": 0.03
                }]
            },
            "usage": {
                "percent": 0.03,
                "items": [{
                    "name": "plan_total_token",
                    "used": 100000,
                    "limit": 4100000000,
                    "percent": 0.03
                }]
            }
        }
        """
        windows: list[QuotaWindow] = []

        # Monthly usage
        month_usage = data.get("monthUsage", {})
        month_items = month_usage.get("items", [])
        for item in month_items:
            if item.get("name") == "month_total_token":
                used = item.get("used", 0)
                limit = item.get("limit", 0)
                # Calculate used_pct from used/limit
                used_pct = (used / limit * 100.0) if limit else 0
                windows.append(QuotaWindow(
                    kind=WindowKind.CALENDAR_MONTH,
                    label="Monthly",
                    used=used,
                    limit=limit,
                    remaining=limit - used if limit else None,
                    unit=QuotaUnit.CREDITS,
                    used_pct=used_pct,
                ))

        # Overall usage (rolling)
        usage = data.get("usage", {})
        usage_items = usage.get("items", [])
        for item in usage_items:
            if item.get("name") == "plan_total_token":
                used = item.get("used", 0)
                limit = item.get("limit", 0)
                # Calculate used_pct from used/limit
                used_pct = (used / limit * 100.0) if limit else 0
                windows.append(QuotaWindow(
                    kind=WindowKind.ROLLING_MONTH,
                    label="Plan Total",
                    used=used,
                    limit=limit,
                    remaining=limit - used if limit else None,
                    unit=QuotaUnit.CREDITS,
                    used_pct=used_pct,
                ))

        return windows
