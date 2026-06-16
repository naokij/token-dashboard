"""DeepSeek adapter.

DeepSeek is a pay-as-you-go API service. No subscription plans, just
balance-based billing. Users can query their balance via the API.

Data source: API — call /user/balance with the API key.

Auth modes:
  - api_key (required)
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import httpx

from td.adapters.base import Adapter, AuthRequiredError
from td.config import load_credential
from td.models import (
    PlanKind,
    ProviderId,
    QuotaUnit,
    UsageSnapshot,
)

DEEPSEEK_API_BASE = "https://api.deepseek.com"


class DeepSeekAdapter(Adapter):
    id = ProviderId.DEEPSEEK
    display_name = "DeepSeek"
    home_url = "https://platform.deepseek.com/"
    kind = PlanKind.PAY_AS_YOU_GO
    api_key_format = "sk-..."
    notes = "Pay-as-you-go, balance-based"

    def supported_auth_modes(self) -> list[str]:
        return ["api_key"]

    async def fetch(self) -> UsageSnapshot:
        snap = UsageSnapshot(
            provider=self.id,
            fetched_at=datetime.now(UTC),
            plan_name="DeepSeek Pay-as-you-go",
            plan_kind=self.kind,
            windows=[],
            auth_mode="api_key",
        )

        api_cred = load_credential(self.id.value, "api_key", account=self.account)
        if not (api_cred and "key" in api_cred):
            raise AuthRequiredError(
                "DeepSeek: please run `td add deepseek --api-key <key>`"
            )

        data = await self._fetch_balance(api_cred["key"])
        snap.balance = data.get("balance")
        snap.balance_unit = data.get("balance_unit")
        snap.raw["api_response"] = data.get("raw", {})

        return snap

    async def _fetch_balance(self, api_key: str) -> dict[str, Any]:
        """Query /user/balance with API key."""
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(
                f"{DEEPSEEK_API_BASE}/user/balance",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Accept": "application/json",
                },
            )
            r.raise_for_status()
            return self._parse_response(r.json())

    def _parse_response(self, data: dict[str, Any]) -> dict[str, Any]:
        """Parse the /user/balance response.

        Response shape:
        {
            "is_available": true,
            "balance_infos": [
                {
                    "currency": "CNY",
                    "total_balance": "110.00",
                    "granted_balance": "10.00",
                    "topped_up_balance": "100.00"
                }
            ]
        }
        """
        balance_infos = data.get("balance_infos", [])

        # Find CNY balance first, fallback to USD
        balance_info = None
        for info in balance_infos:
            if info.get("currency") == "CNY":
                balance_info = info
                break
        if not balance_info and balance_infos:
            balance_info = balance_infos[0]

        balance = None
        balance_unit = None

        if balance_info:
            total = balance_info.get("total_balance")
            if total is not None:
                balance = float(total)
                currency = balance_info.get("currency", "CNY")
                balance_unit = QuotaUnit.CNY if currency == "CNY" else QuotaUnit.USD

        return {
            "balance": balance,
            "balance_unit": balance_unit,
            "raw": data,
        }
