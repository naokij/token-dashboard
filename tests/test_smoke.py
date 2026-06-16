"""Smoke tests for models and adapter registry."""

from datetime import datetime, timezone

from td.adapters.registry import REGISTRY
from td.models import (
    PlanKind,
    ProviderId,
    QuotaUnit,
    QuotaWindow,
    UsageSnapshot,
    WindowKind,
)


def test_provider_ids_have_adapters():
    for pid in ProviderId:
        assert pid in REGISTRY


def test_quota_window_pct():
    w = QuotaWindow(
        kind=WindowKind.ROLLING_5H,
        label="5h",
        used=50,
        limit=100,
        remaining=50,
        unit=QuotaUnit.CREDITS,
        used_pct=50.0,
    )
    assert w.used_pct == 50.0


def test_snapshot_primary_window_picks_most_constrained():
    snap = UsageSnapshot(
        provider=ProviderId.OPENCODE,
        fetched_at=datetime.now(timezone.utc),
        plan_name="Go",
        plan_kind=PlanKind.CODING_PLAN,
        windows=[
            QuotaWindow(
                kind=WindowKind.ROLLING_5H,
                label="5h",
                used=2, limit=12, remaining=10,
                unit=QuotaUnit.USD, used_pct=16.6,
            ),
            QuotaWindow(
                kind=WindowKind.ROLLING_MONTH,
                label="month",
                used=50, limit=60, remaining=10,
                unit=QuotaUnit.USD, used_pct=83.3,
            ),
        ],
    )
    primary = snap.primary_window()
    assert primary is not None
    assert primary.kind == WindowKind.ROLLING_MONTH
