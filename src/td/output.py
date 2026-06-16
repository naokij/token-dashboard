"""Rich-based output formatting for `td status` and `td watch`."""

from __future__ import annotations

import json
from datetime import datetime

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from td.models import QuotaUnit, QuotaWindow, UsageSnapshot

console = Console()


def _fmt_num(n: float | None, unit: QuotaUnit) -> str:
    if n is None:
        return "-"
    if unit in (QuotaUnit.USD, QuotaUnit.CNY):
        return f"{n:.2f}"
    if unit == QuotaUnit.PERCENT:
        return f"{n:.1f}%"
    if unit == QuotaUnit.TOKENS:
        if n >= 1_000_000_000:
            return f"{n / 1_000_000_000:.2f}B"
        if n >= 1_000_000:
            return f"{n / 1_000_000:.2f}M"
        if n >= 1_000:
            return f"{n / 1_000:.2f}K"
        return f"{n:.0f}"
    if unit in (QuotaUnit.CREDITS, QuotaUnit.REQUESTS, QuotaUnit.PROMPTS):
        if n >= 1_000_000_000:
            return f"{n / 1_000_000_000:.2f}B"
        if n >= 1_000_000:
            return f"{n / 1_000_000:.2f}M"
        if n >= 1_000:
            return f"{n / 1_000:.1f}K"
        return f"{n:.0f}"
    return f"{n:.2f}"


def _window_bar(window: QuotaWindow, width: int = 30) -> Text:
    """Build a text-based progress bar for a single window."""
    if window.limit is None or window.used_pct is None:
        return Text("  (unbounded)", style="dim")
    pct = max(0.0, min(100.0, window.used_pct))
    filled = int(round(pct / 100 * width))
    empty = width - filled
    if pct >= 90:
        style = "bold red"
    elif pct >= 70:
        style = "bold yellow"
    else:
        style = "bold green"
    bar = Text()
    bar.append("█" * filled, style=style)
    bar.append("░" * empty, style="dim")
    bar.append(f" {pct:5.1f}%", style=style)
    return bar


def render_status(snapshots: list[UsageSnapshot], show_raw: bool = False) -> None:
    """Render a unified status table for all providers."""
    if not snapshots:
        console.print("[yellow]No snapshots to display.[/yellow]")
        return

    table = Table(
        title="Token Dashboard",
        title_style="bold",
        show_header=True,
        header_style="bold cyan",
        expand=True,
    )
    table.add_column("Provider", style="bold", no_wrap=True)
    table.add_column("Plan", style="dim")
    table.add_column("Account", style="dim")
    table.add_column("Window", no_wrap=True)
    table.add_column("Usage", justify="right", no_wrap=True)
    table.add_column("Bar", no_wrap=False)
    table.add_column("Resets", style="dim")

    for snap in snapshots:
        provider_label = f"{snap.provider.value}"
        account_label = (
            snap.account_name
            if snap.account_name != "default"
            else (snap.account_email or "-")
        )
        if not snap.windows and snap.balance is None:
            # No data — show a placeholder row
            warning_text = snap.warnings[0] if snap.warnings else ""
            is_login_required = "please run" in warning_text.lower()
            table.add_row(
                provider_label,
                snap.plan_name or "-",
                account_label,
                "[dim]no data[/dim]",
                "[dim]-[/dim]",
                "[red]login required[/red]" if is_login_required else "[dim]-[/dim]",
                "[dim]-[/dim]",
            )
            continue

        # Render a row per window, repeating provider/plan/account cells
        first = True
        rows_added = 0
        for w in snap.windows:
            reset = w.reset_at.strftime("%Y-%m-%d %H:%M") if w.reset_at else "-"
            usage_str = f"{_fmt_num(w.used, w.unit)} / {_fmt_num(w.limit, w.unit)} {w.unit.value}"
            table.add_row(
                provider_label if first else "",
                snap.plan_name or "-" if first else "",
                account_label if first else "",
                w.label,
                usage_str,
                _window_bar(w),
                reset,
            )
            first = False
            rows_added += 1

        # Show balance if available (pay-as-you-go)
        if snap.balance is not None:
            unit_str = f" {snap.balance_unit.value}" if snap.balance_unit else ""
            table.add_row(
                provider_label if rows_added == 0 else "",
                snap.plan_name or "-" if rows_added == 0 else "",
                account_label if rows_added == 0 else "",
                "balance",
                f"{_fmt_num(snap.balance, snap.balance_unit or QuotaUnit.UNKNOWN)}{unit_str}",
                Text("(running)", style="dim"),
                "-",
            )
            rows_added += 1

        if rows_added == 0:
            table.add_row(
                provider_label,
                snap.plan_name or "-",
                snap.account_email or "-",
                "[dim]no data[/dim]",
                "[dim]-[/dim]",
                "[dim]-[/dim]",
                "[dim]-[/dim]",
            )

    console.print(table)

    # Warnings
    warnings = [w for s in snapshots for w in s.warnings]
    if warnings:
        console.print()
        console.print(Panel(
            "\n".join(f"• {w}" for w in warnings),
            title="[yellow]Warnings[/yellow]",
            border_style="yellow",
        ))

    if show_raw:
        console.print()
        console.print("[dim]Raw data:[/dim]")
        for snap in snapshots:
            console.print(f"[dim]{snap.provider.value}:[/dim]")
            console.print_json(json.dumps(snap.raw, default=str, ensure_ascii=False))


def render_watch(snapshots: list[UsageSnapshot]) -> None:
    """Compact single-line view for `td watch`."""
    parts = []
    for snap in snapshots:
        account_suffix = (
            f"[{snap.account_name}]"
            if snap.account_name != "default"
            else ""
        )
        win = snap.primary_window()
        if win:
            used = _fmt_num(win.used, win.unit)
            limit = _fmt_num(win.limit, win.unit)
            pct = f"{win.used_pct:.0f}%" if win.used_pct is not None else "-"
            part = (
                f"{snap.provider.value}{account_suffix}: "
                f"{used}/{limit} {win.unit.value} ({pct})"
            )
            # Add balance if available
            if snap.balance is not None:
                unit = snap.balance_unit.value if snap.balance_unit else ""
                part += (
                    f" + "
                    f"{_fmt_num(snap.balance, snap.balance_unit or QuotaUnit.UNKNOWN)}"
                    f" {unit}"
                )
            parts.append(part)
        elif snap.balance is not None:
            unit = snap.balance_unit.value if snap.balance_unit else ""
            parts.append(
                f"{snap.provider.value}{account_suffix}: "
                f"{_fmt_num(snap.balance, snap.balance_unit or QuotaUnit.UNKNOWN)} {unit}"
            )
        else:
            parts.append(f"{snap.provider.value}{account_suffix}: no data")
    line = "  ".join(parts)
    ts = datetime.now().strftime("%H:%M:%S")
    console.print(f"[dim]{ts}[/dim]  {line}", highlight=False)


def to_json(snapshots: list[UsageSnapshot]) -> str:
    return json.dumps(
        [s.model_dump(mode="json") for s in snapshots],
        ensure_ascii=False,
        indent=2,
    )
