"""MiniMax Token Plan adapter.

MiniMax is a Chinese provider. Token Plan uses a "credit" budget shared across
text/image/speech/music models, with rolling 5h and weekly windows.

Data source: API — call /v1/token_plan/remains with the API key.

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
    QuotaWindow,
    UsageSnapshot,
    WindowKind,
)

MINIMAX_API_BASE = "https://www.minimaxi.com"


class MiniMaxAdapter(Adapter):
    id = ProviderId.MINIMAX
    display_name = "MiniMax Token Plan"
    home_url = "https://platform.minimaxi.com/docs/token-plan/intro.md"
    kind = PlanKind.TOKEN_PLAN
    api_key_format = "sk-..."
    notes = "5h + weekly windows, percentage-based"

    def supported_auth_modes(self) -> list[str]:
        return ["api_key"]

    async def fetch(self) -> UsageSnapshot:
        snap = UsageSnapshot(
            provider=self.id,
            fetched_at=datetime.now(UTC),
            plan_name="MiniMax Token Plan",
            plan_kind=self.kind,
            windows=[],
            auth_mode="api_key",
        )

        api_cred = load_credential(self.id.value, "api_key", account=self.account)
        if not (api_cred and "key" in api_cred):
            raise AuthRequiredError(
                "MiniMax: please run `td add minimax --api-key <key>`"
            )

        data = await self._fetch_via_api(api_cred["key"])
        snap.windows = data.get("windows", [])
        snap.raw["api_response"] = data.get("raw", {})

        return snap

    async def _fetch_via_api(self, api_key: str) -> dict[str, Any]:
        """Query /v1/token_plan/remains with API key."""
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(
                f"{MINIMAX_API_BASE}/v1/token_plan/remains",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
            )
            r.raise_for_status()
            return self._parse_api_response(r.json())

    def _parse_api_response(self, data: dict[str, Any]) -> dict[str, Any]:
        """Parse the /v1/token_plan/remains response.

        Response shape:
        {
            "model_remains": [
                {
                    "model_name": "general",
                    "end_time": 1780729200000,         # 5h window end (ms)
                    "current_interval_remaining_percent": 98,
                    "weekly_end_time": 1780848000000,
                    "current_weekly_remaining_percent": 100,
                    ...
                }
            ]
        }
        """
        windows: list[QuotaWindow] = []

        for model in data.get("model_remains", []):
            model_name = model.get("model_name", "unknown")

            # 5h rolling window
            interval_pct = model.get("current_interval_remaining_percent", 100)
            end_ms = model.get("end_time")
            windows.append(
                QuotaWindow(
                    kind=WindowKind.ROLLING_5H,
                    label=f"{model_name} (5h)",
                    used=100.0 - interval_pct,
                    limit=100.0,
                    remaining=float(interval_pct),
                    unit=QuotaUnit.PERCENT,
                    used_pct=100.0 - interval_pct,
                    reset_at=datetime.fromtimestamp(end_ms / 1000, tz=UTC) if end_ms else None,
                    raw=model,
                )
            )

            # Weekly window
            weekly_pct = model.get("current_weekly_remaining_percent", 100)
            weekly_end_ms = model.get("weekly_end_time")
            windows.append(
                QuotaWindow(
                    kind=WindowKind.ROLLING_WEEK,
                    label=f"{model_name} (week)",
                    used=100.0 - weekly_pct,
                    limit=100.0,
                    remaining=float(weekly_pct),
                    unit=QuotaUnit.PERCENT,
                    used_pct=100.0 - weekly_pct,
                    reset_at=datetime.fromtimestamp(
                        weekly_end_ms / 1000, tz=UTC
                    ) if weekly_end_ms else None,
                    raw=model,
                )
            )

        return {"windows": windows, "raw": data}
