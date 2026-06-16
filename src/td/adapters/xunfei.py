"""讯飞星辰 MaaS — Coding Plan adapter.

Xunfei (iFlytek) sells a Coding Plan subscription with request-count based quotas.

Data source: GET https://maas.xfyun.cn/api/v1/gpt-finetune/coding-plan/list

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

XUNFEI_API_BASE = "https://maas.xfyun.cn/api/v1"


class XunfeiAdapter(Adapter):
    id = ProviderId.XUNFEI
    display_name = "讯飞星辰 Coding Plan"
    home_url = "https://maas.xfyun.cn/"
    kind = PlanKind.CODING_PLAN
    api_key_format = None
    notes = "Request-count based"

    def supported_auth_modes(self) -> list[str]:
        return ["cookie"]

    async def fetch(self) -> UsageSnapshot:
        snap = UsageSnapshot(
            provider=self.id,
            fetched_at=datetime.now(UTC),
            plan_name="讯飞星辰 Coding Plan",
            plan_kind=self.kind,
            windows=[],
            auth_mode="cookie",
        )

        cookie_cred = load_credential(self.id.value, "cookie", account=self.account)
        if not (cookie_cred and cookie_cred.get("cookies")):
            raise AuthRequiredError(
                "Xunfei: please run `td login xunfei -c '<cookie>'`"
            )

        cookie_header = format_cookie_header(cookie_cred["cookies"])
        headers = {
            "Cookie": cookie_header,
            "Accept": "application/json",
        }

        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(
                f"{XUNFEI_API_BASE}/gpt-finetune/coding-plan/list",
                headers=headers,
                params={"page": 1, "size": 6},
            )

            if r.status_code != 200:
                raise RuntimeError(f"API request failed: {r.status_code}")

            data = r.json()
            if data.get("code") != 0:
                raise RuntimeError(f"API error: {data.get('message')}")

            rows = data.get("data", {}).get("rows", [])
            if rows:
                plan = rows[0]
                snap.plan_name = plan.get("name", "Coding Plan")
                snap.account_email = plan.get("appId")
                snap.windows = self._parse_usage(plan)
                snap.raw["api_response"] = plan

        return snap

    def _parse_usage(self, plan: dict[str, Any]) -> list[QuotaWindow]:
        """Parse coding plan usage data.

        Response shape:
        {
            "codingPlanUsageDTO": {
                "packageLeft": 17143,
                "packageLimit": 18000,
                "packageUsage": 857,
                "rp5hLimit": 1200,
                "rp5hUsage": 0,
                "rpwLimit": 9000,
                "rpwUsage": 536
            },
            "expiresAt": "2026-06-21 10:56:21",
            "name": "专业版"
        }
        """
        windows: list[QuotaWindow] = []
        usage = plan.get("codingPlanUsageDTO", {})

        # 5h rolling window
        rp5h_limit = usage.get("rp5hLimit", 0)
        rp5h_usage = usage.get("rp5hUsage", 0)
        if rp5h_limit > 0:
            windows.append(QuotaWindow(
                kind=WindowKind.ROLLING_5H,
                label="5h rolling",
                used=float(rp5h_usage),
                limit=float(rp5h_limit),
                remaining=float(rp5h_limit - rp5h_usage),
                unit=QuotaUnit.REQUESTS,
                used_pct=(rp5h_usage / rp5h_limit * 100.0),
            ))

        # Weekly window
        rpw_limit = usage.get("rpwLimit", 0)
        rpw_usage = usage.get("rpwUsage", 0)
        if rpw_limit > 0:
            windows.append(QuotaWindow(
                kind=WindowKind.ROLLING_WEEK,
                label="Weekly",
                used=float(rpw_usage),
                limit=float(rpw_limit),
                remaining=float(rpw_limit - rpw_usage),
                unit=QuotaUnit.REQUESTS,
                used_pct=(rpw_usage / rpw_limit * 100.0),
            ))

        # Package total
        package_limit = usage.get("packageLimit", 0)
        package_usage = usage.get("packageUsage", 0)
        if package_limit > 0:
            # Parse expiry date
            expires_at = plan.get("expiresAt")
            reset_at = None
            if expires_at:
                try:
                    reset_at = datetime.strptime(
                        expires_at, "%Y-%m-%d %H:%M:%S"
                    ).replace(tzinfo=UTC)
                except Exception:
                    pass

            windows.append(QuotaWindow(
                kind=WindowKind.FIXED_PERIOD,
                label="Package Total",
                used=float(package_usage),
                limit=float(package_limit),
                remaining=float(package_limit - package_usage),
                unit=QuotaUnit.REQUESTS,
                used_pct=(package_usage / package_limit * 100.0),
                reset_at=reset_at,
            ))

        return windows
