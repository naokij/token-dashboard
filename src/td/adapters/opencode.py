"""OpenCode Go adapter.

OpenCode Go is a fixed-monthly subscription billed in USD with three
overlapping rolling windows: 5h, weekly, monthly. Limits are defined in
$ value; actual request counts vary per model.

Data source: Cookie scrape — the user logs into https://opencode.ai/auth
and we read the workspace usage panel.

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

OPENCODE_BASE = "https://opencode.ai"


class OpenCodeGoAdapter(Adapter):
    id = ProviderId.OPENCODE
    display_name = "OpenCode Go"
    home_url = "https://opencode.ai/docs/go/"
    kind = PlanKind.CODING_PLAN
    api_key_format = None
    notes = "Cookie auth only; rolling 5h/week/month limits in USD"

    def supported_auth_modes(self) -> list[str]:
        return ["cookie"]

    async def fetch(self) -> UsageSnapshot:
        snap = UsageSnapshot(
            provider=self.id,
            fetched_at=datetime.now(UTC),
            plan_name="OpenCode Go",
            plan_kind=self.kind,
            windows=[],
            auth_mode="cookie",
        )

        cookie_cred = load_credential(self.id.value, "cookie", account=self.account)
        if not (cookie_cred and cookie_cred.get("cookies")):
            raise AuthRequiredError(
                "OpenCode Go: please run `td login opencode` to set cookie auth"
            )

        windows = await self._fetch_usage_via_cookie(cookie_cred)
        snap.windows = windows

        return snap

    async def _fetch_usage_via_cookie(self, cred: dict[str, Any]) -> list[QuotaWindow]:
        """Read usage from the OpenCode Go console using a captured cookie."""
        import re


        cookies = cred.get("cookies", [])
        cookie_header = format_cookie_header(cookies)

        async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
            # Try to find workspace ID from various sources
            workspace_id = cred.get("workspace_id")

            if not workspace_id:
                # Try to get from the workspace usage page
                r = await client.get(
                    "https://opencode.ai/workspace/usage",
                    headers={"Cookie": cookie_header, "Accept": "text/html"},
                )
                if r.status_code == 200:
                    match = re.search(r'wrk_[a-zA-Z0-9]+', r.text)
                    if match:
                        workspace_id = match.group(0)

            if not workspace_id:
                raise RuntimeError(
                    "Could not find workspace ID. "
                    "Please run: td login opencode --workspace-id <your-workspace-id>"
                )

            # Fetch the usage page
            url = f"https://opencode.ai/workspace/{workspace_id}/go"
            r = await client.get(
                url,
                headers={
                    "Cookie": cookie_header,
                    "Accept": "text/html",
                    "User-Agent": "Mozilla/5.0 Chrome/120.0.0.0",
                },
            )

            if r.status_code != 200:
                raise RuntimeError(f"Failed to fetch usage page: {r.status_code}")

            return self._parse_html_response(r.text)

    def _parse_html_response(self, html: str) -> list[QuotaWindow]:
        """Parse the HTML response from OpenCode Go usage page."""
        import re
        from datetime import timedelta

        from bs4 import BeautifulSoup

        windows: list[QuotaWindow] = []
        now = datetime.now(UTC)

        soup = BeautifulSoup(html, "html.parser")
        usage_div = soup.find("div", attrs={"data-slot": "usage"})
        if not usage_div:
            return windows

        usage_text = usage_div.get_text(strip=True)

        # Pattern for Chinese: 滚动用量XX%重置于X小时X分钟
        # Pattern for English: Rolling Usage XX% Resets in HH:MM:SS
        patterns = [
            # Chinese
            (r'滚动用量(\d+%)重置于(.*?)(?=每周用量|每月用量|$)',
             WindowKind.ROLLING_5H, "5h rolling"),
            (r'每周用量(\d+%)重置于(.*?)(?=每月用量|$)',
             WindowKind.ROLLING_WEEK, "Weekly"),
            (r'每月用量(\d+%)重置于(.*?)$',
             WindowKind.ROLLING_MONTH, "Monthly"),
            # English
            (r'Rolling\s+Usage\s+(\d+)%\s+Resets?\s+in\s+(.*?)(?=Weekly|Monthly|$)',
             WindowKind.ROLLING_5H, "5h rolling"),
            (r'Weekly\s+Usage\s+(\d+)%\s+Resets?\s+in\s+(.*?)(?=Monthly|$)',
             WindowKind.ROLLING_WEEK, "Weekly"),
            (r'Monthly\s+Usage\s+(\d+)%\s+Resets?\s+in\s+(.*?)$',
             WindowKind.ROLLING_MONTH, "Monthly"),
        ]

        for pattern, kind, label in patterns:
            match = re.search(pattern, usage_text, re.IGNORECASE | re.DOTALL)
            if match:
                pct_str = match.group(1).replace("%", "")
                used_pct = float(pct_str)
                reset_time = match.group(2).strip()
                reset_sec = self._parse_reset_time(reset_time)
                reset_at = now + timedelta(seconds=reset_sec) if reset_sec else None

                windows.append(QuotaWindow(
                    kind=kind,
                    label=label,
                    used=used_pct,
                    limit=100.0,
                    remaining=100.0 - used_pct,
                    unit=QuotaUnit.PERCENT,
                    used_pct=used_pct,
                    reset_at=reset_at,
                ))

        return windows

    def _parse_reset_time(self, time_str: str) -> int:
        """Parse reset time string to seconds.

        Supports:
        - Chinese: "5 小时 0 分钟", "1 天 14 小时", "18 天 15 小时"
        - English: "02:55:00", "1d 17:00:00"
        """
        import re

        total_seconds = 0

        # Chinese patterns
        days_match = re.search(r'(\d+)\s*天', time_str)
        if days_match:
            total_seconds += int(days_match.group(1)) * 86400

        hours_match = re.search(r'(\d+)\s*小时', time_str)
        if hours_match:
            total_seconds += int(hours_match.group(1)) * 3600

        minutes_match = re.search(r'(\d+)\s*分钟', time_str)
        if minutes_match:
            total_seconds += int(minutes_match.group(1)) * 60

        # English patterns
        if total_seconds == 0:
            days_match = re.search(r'(\d+)d', time_str)
            if days_match:
                total_seconds += int(days_match.group(1)) * 86400

            time_match = re.search(r'(\d+):(\d+):(\d+)', time_str)
            if time_match:
                hours, minutes, seconds = map(int, time_match.groups())
                total_seconds += hours * 3600 + minutes * 60 + seconds

        return total_seconds
