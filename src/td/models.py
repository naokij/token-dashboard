"""Data models for token-dashboard.

Provider-agnostic view of coding plan / token plan / pay-as-you-go usage.

The core concept is a *quota window* — a bounded time interval during which
a provider tracks some kind of usage budget. Most coding plans (OpenCode Go,
MiMo Token Plan, MiniMax Token Plan) have multiple overlapping windows
(5-hour rolling, weekly, monthly). Pay-as-you-go has only one running total.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class ProviderId(str, Enum):
    """Built-in provider identifiers."""

    OPENCODE = "opencode"
    MINIMAX = "minimax"
    MIMO = "mimo"
    XUNFEI = "xunfei"
    DEEPSEEK = "deepseek"


class PlanKind(str, Enum):
    """How a provider bills the user."""

    CODING_PLAN = "coding_plan"  # Fixed monthly subscription, request/credit-based
    TOKEN_PLAN = "token_plan"  # Fixed monthly subscription, token-credits-based
    PAY_AS_YOU_GO = "pay_as_you_go"  # Continuous, balance-based


class QuotaUnit(str, Enum):
    """The unit in which a quota is measured.

    We normalize display as much as possible, but the source unit is preserved
    so adapters don't lose information.
    """

    CREDITS = "credits"  # Provider-specific credit points (e.g. MiMo 1 credit = 1 token-equiv)
    TOKENS = "tokens"
    REQUESTS = "requests"
    USD = "usd"  # For OpenCode Go (which charges in $)
    CNY = "cny"  # For Chinese providers' balance
    PROMPTS = "prompts"  # Some providers count prompts, not requests
    PERCENT = "percent"  # Percentage-based (e.g. MiniMax Token Plan)
    UNKNOWN = "unknown"


class WindowKind(str, Enum):
    """The shape of a quota window."""

    ROLLING_5H = "rolling_5h"
    ROLLING_WEEK = "rolling_week"
    ROLLING_MONTH = "rolling_month"
    CALENDAR_MONTH = "calendar_month"
    CALENDAR_DAY = "calendar_day"
    FIXED_PERIOD = "fixed_period"  # A subscription period start->end
    BALANCE = "balance"  # Pay-as-you-go running balance (no reset)


class QuotaWindow(BaseModel):
    """A single bounded usage window.

    `used`, `limit`, and `remaining` are all in `unit`. When `limit` is None,
    the window is unbounded (e.g. a pay-as-you-go balance might have a limit
    if a top-up cap is set, or None if not).
    """

    kind: WindowKind
    label: str  # Human label, e.g. "5-hour rolling", "May 2026"
    used: float
    limit: float | None = None  # None = unbounded
    remaining: float | None = None
    unit: QuotaUnit
    used_pct: float | None = None  # 0..100, derived; None if unbounded
    reset_at: datetime | None = None  # When this window's limit resets
    period_start: datetime | None = None
    period_end: datetime | None = None
    raw: dict[str, Any] = Field(default_factory=dict)  # Original provider data


class ProviderMeta(BaseModel):
    """Static metadata for a provider — what plans it offers, pricing, etc."""

    id: ProviderId
    display_name: str
    kind: PlanKind
    home_url: str
    api_key_format: str | None = None  # Hint, e.g. "sk-..." or "tp-..."
    auth_modes: list[str] = []  # "api_key" | "cookie" | "login_flow"
    notes: str | None = None


class UsageSnapshot(BaseModel):
    """A point-in-time snapshot of one provider's usage."""

    provider: ProviderId
    fetched_at: datetime
    plan_name: str | None = None  # e.g. "Plus", "Max", "Lite"
    plan_kind: PlanKind
    balance: float | None = None  # For pay-as-you-go only
    balance_unit: QuotaUnit | None = None
    windows: list[QuotaWindow] = []
    account_email: str | None = None  # If known via cookie
    account_name: str = "default"  # Account name for multi-account support
    auth_mode: str = ""  # How the data was obtained: "api" / "cookie" / "manual"
    plan_expires_at: datetime | None = None  # When the current plan period ends
    warnings: list[str] = []  # Adapter-side messages, e.g. "cookie expired, please re-login"
    raw: dict[str, Any] = Field(default_factory=dict)

    def primary_window(self) -> QuotaWindow | None:
        """Return the most-constrained (most-used %) window, or None."""
        bounded = [w for w in self.windows if w.limit is not None and w.used_pct is not None]
        if not bounded:
            return None
        return max(bounded, key=lambda w: w.used_pct or 0)
