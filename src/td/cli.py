"""Click CLI for token-dashboard."""

from __future__ import annotations

import asyncio
from datetime import datetime
from pathlib import Path

import click

from td import __version__
from td.adapters.base import AuthRequiredError
from td.adapters.registry import get_adapter
from td.config import (
    CONFIG_DIR,
    CONFIG_PATH,
    CREDENTIALS_PATH,
    AppConfig,
    delete_credential,
    save_credential,
)
from td.models import ProviderId
from td.output import console, render_status, render_watch, to_json


def _async_run(coro):
    """Run an async coroutine from sync Click handlers."""
    return asyncio.run(coro)


# ------------------------- root group ------------------------- #


@click.group()
@click.version_option(__version__, "-V", "--version")
@click.option("--config", type=click.Path(), default=None, help="Override config path")
def cli(config):
    """Token Dashboard — unified view of coding plan / token plan / API quota."""
    if config:
        from td import config as cfg_mod

        cfg_mod.CONFIG_PATH = Path(config)


# ------------------------- status ------------------------- #


@cli.command()
@click.option("--provider", "-p", multiple=True, help="Limit to specific provider id(s)")
@click.option("--account", "-a", default=None, help="Account name (default: all accounts)")
@click.option("--json", "as_json", is_flag=True, help="Emit JSON instead of a table")
@click.option("--raw", is_flag=True, help="Include raw provider data")
@click.option("--no-color", is_flag=True, help="Disable color output")
@click.option("--refresh", "-r", type=int, default=None, help="Auto-refresh interval in seconds")
def status(provider, account, as_json, raw, no_color, refresh):
    """Show current usage for all (or selected) configured providers."""
    if no_color:
        from rich.console import Console

        global console
        console = Console(no_color=True, force_terminal=False)

    cfg = AppConfig.load()
    targets = _resolve_providers(provider, cfg)

    if refresh:
        import os
        try:
            while True:
                snapshots = _async_run(_fetch_all(targets, cfg, account=account))
                os.system('clear' if os.name != 'nt' else 'cls')
                render_status(snapshots, show_raw=raw)
                import time
                time.sleep(refresh)
        except KeyboardInterrupt:
            click.echo("\nBye.")
    else:
        snapshots = _async_run(_fetch_all(targets, cfg, account=account))
        if as_json:
            click.echo(to_json(snapshots))
        else:
            render_status(snapshots, show_raw=raw)


# ------------------------- watch ------------------------- #


@cli.command()
@click.option("--provider", "-p", multiple=True)
@click.option("--interval", "-i", type=int, default=None, help="Seconds between refreshes")
@click.option("--once", is_flag=True, help="Render once and exit")
def watch(provider, interval, once):
    """Continuously refresh usage (Ctrl-C to quit)."""
    cfg = AppConfig.load()
    targets = _resolve_providers(provider, cfg)
    ivl = interval or cfg.raw.get("watch", {}).get("interval_seconds", 60)

    if once:
        snapshots = _async_run(_fetch_all(targets, cfg))
        render_watch(snapshots)
        return

    try:
        while True:
            snapshots = _async_run(_fetch_all(targets, cfg))
            render_watch(snapshots)
            import time

            time.sleep(ivl)
    except KeyboardInterrupt:
        click.echo("\nBye.")


# ------------------------- add (api_key etc) ------------------------- #


@cli.command()
@click.argument("provider_id", type=click.Choice([p.value for p in ProviderId]))
@click.option("--api-key", help="API key (for api_key auth mode)")
@click.option("--token-plan-key", help="MiMo Token Plan key (tp-...)")
@click.option("--payg-key", help="MiMo pay-as-you-go key (sk-...)")
@click.option("--access-key", help="Volcengine access key id (AK)")
@click.option("--secret-key", help="Volcengine secret access key (SK)")
@click.option("--account", "-a", default="default", help="Account name (default: 'default')")
def add(provider_id, api_key, token_plan_key, payg_key, access_key, secret_key, account):
    """Save credentials for a provider without going through the browser."""
    if not (api_key or token_plan_key or payg_key or (access_key and secret_key)):
        raise click.UsageError(
            "provide --api-key, --token-plan-key, --payg-key, "
            "or both --access-key and --secret-key"
        )

    cred: dict = {}
    if api_key:
        cred["key"] = api_key
    if token_plan_key:
        cred["token_plan_key"] = token_plan_key
    if payg_key:
        cred["payg_key"] = payg_key
    if access_key and secret_key:
        cred["access_key"] = access_key
        cred["secret_key"] = secret_key

    save_credential(provider_id, "api_key", cred, account=account)
    click.echo(f"✓ saved api_key for {provider_id} (account: {account})")


# ------------------------- login (cookie flow) ------------------------- #


@cli.command()
@click.argument("provider_id", type=click.Choice([p.value for p in ProviderId]))
@click.option("--cookie", "-c", help="Cookie string from browser")
@click.option("--account", "-a", default="default", help="Account name (default: 'default')")
def login(provider_id, cookie, account):
    """Save cookie for a provider.

    How to get cookie:

    \b
    1. Open browser, login to the provider website
    2. Press F12 to open DevTools
    3. Go to Network tab, refresh the page
    4. Right-click any request -> Copy -> Copy as cURL
    5. Extract cookie from the -b '...' part

    \b
    Provider websites:
    - OpenCode: https://opencode.ai/auth
    - MiMo: https://platform.xiaomimimo.com
    - 讯飞: https://maas.xfyun.cn
    """
    from td.cookies import save_cookie

    if not cookie:
        click.echo("Usage: td login <provider> -c '<cookie>'")
        click.echo()
        click.echo("How to get cookie:")
        click.echo("  1. Open browser, login to the provider website")
        click.echo("  2. Press F12 to open DevTools")
        click.echo("  3. Go to Network tab, refresh the page")
        click.echo("  4. Right-click any request -> Copy -> Copy as cURL")
        click.echo("  5. Extract cookie from the -b '...' part")
        click.echo()
        click.echo("Provider websites:")
        click.echo("  OpenCode: https://opencode.ai/auth")
        click.echo("  MiMo: https://platform.xiaomimimo.com")
        click.echo("  讯飞: https://maas.xfyun.cn")
        click.echo()
        click.echo("Example:")
        click.echo(f"  td login {provider_id} -c 'auth=xxx; ...'")
        return

    cred = save_cookie(provider_id, cookie, account=account)
    n = len(cred.get("cookies", []))
    click.echo(f"✓ saved {n} cookies for {provider_id} (account: {account})")


# ------------------------- list ------------------------- #


@cli.command("list")
@click.option("--accounts", is_flag=True, help="Show accounts for each provider")
def list_cmd(accounts):
    """List all providers and their configuration status."""
    from td.config import list_accounts
    cfg = AppConfig.load()
    from rich.table import Table

    if accounts:
        table = Table(title="Providers & Accounts", header_style="bold cyan")
        table.add_column("Provider", style="bold")
        table.add_column("Account", style="bold")
        table.add_column("Type")
        table.add_column("Auth Modes")

        for pid in ProviderId:
            account_list = list_accounts(pid.value)
            if not account_list:
                account_list = ["(none)"]
            for i, acct in enumerate(account_list):
                adapter = get_adapter(pid, cfg, account=acct if acct != "(none)" else "default")
                meta = adapter.meta()
                table.add_row(
                    pid.value if i == 0 else "",
                    acct,
                    meta.kind.value if i == 0 else "",
                    ", ".join(meta.auth_modes) if i == 0 else "",
                )
    else:
        table = Table(title="Providers", header_style="bold cyan")
        table.add_column("ID", style="bold")
        table.add_column("Name")
        table.add_column("Type")
        table.add_column("Accounts")
        table.add_column("Auth Modes")

        for pid in ProviderId:
            adapter = get_adapter(pid, cfg)
            meta = adapter.meta()
            account_list = list_accounts(pid.value)
            acct_count = len(account_list) if account_list else 0
            table.add_row(
                pid.value,
                meta.display_name,
                meta.kind.value,
                str(acct_count),
                ", ".join(meta.auth_modes),
            )

    console.print(table)


# ------------------------- export ------------------------- #


@cli.command()
@click.argument("path", type=click.Path())
def export(path):
    """Export a JSON snapshot to a file."""
    cfg = AppConfig.load()
    targets = _resolve_providers((), cfg)
    snapshots = _async_run(_fetch_all(targets, cfg))
    Path(path).write_text(to_json(snapshots))
    click.echo(f"✓ exported to {path}")


# ------------------------- config (show / edit) ------------------------- #


@cli.command("config")
@click.option("--show", is_flag=True, help="Show current config + resolved paths")
@click.option("--path", "show_path", is_flag=True, help="Print config file path")
def config_cmd(show, show_path):
    """Show config / paths."""
    if show_path:
        click.echo(str(CONFIG_PATH))
        return
    if show:
        click.echo(f"Config file: {CONFIG_PATH}")
        click.echo(f"Data dir:    {CONFIG_DIR}")
        click.echo(f"Credentials: {CREDENTIALS_PATH}")
        if CONFIG_PATH.exists():
            click.echo("\n--- config.yaml ---")
            click.echo(CONFIG_PATH.read_text())
        else:
            click.echo("(no config.yaml yet — defaults are in use)")


# ------------------------- reset ------------------------- #


@cli.command()
@click.argument("provider_id", type=click.Choice([p.value for p in ProviderId]))
@click.option("--yes", "-y", is_flag=True, help="Skip confirmation")
@click.option("--account", "-a", default=None, help="Account name (default: all accounts)")
def reset(provider_id, yes, account):
    """Forget all credentials for a provider."""
    if account:
        if not yes:
            click.confirm(f"Delete credentials for {provider_id} account '{account}'?", abort=True)
        for mode in ("api_key", "cookie"):
            delete_credential(provider_id, mode, account=account)
        click.echo(f"✓ cleared credentials for {provider_id} (account: {account})")
    else:
        if not yes:
            click.confirm(f"Delete ALL credentials for {provider_id}?", abort=True)
        from td.config import list_accounts
        accounts = list_accounts(provider_id)
        for acct in accounts:
            for mode in ("api_key", "cookie"):
                delete_credential(provider_id, mode, account=acct)
        click.echo(f"✓ cleared all credentials for {provider_id}")


# ------------------------- helpers ------------------------- #


def _resolve_providers(filter_ids: tuple[str, ...], cfg: AppConfig) -> list[ProviderId]:
    if not filter_ids:
        return [pid for pid in ProviderId if cfg.provider(pid.value).get("enabled", True)]
    return [ProviderId(p) for p in filter_ids]


async def _fetch_all(targets: list[ProviderId], cfg: AppConfig, account: str = None) -> list:
    from td.config import list_accounts
    from td.models import UsageSnapshot

    snapshots: list = []
    for pid in targets:
        if account:
            # Fetch specific account
            accounts_to_fetch = [account]
        else:
            # Fetch all accounts for this provider
            accounts_to_fetch = list_accounts(pid.value)
            if not accounts_to_fetch:
                accounts_to_fetch = ["default"]

        for acct in accounts_to_fetch:
            adapter = get_adapter(pid, cfg, account=acct)
            try:
                snap = await adapter.fetch()
                snap.account_name = acct
            except AuthRequiredError as e:
                snap = UsageSnapshot(
                    provider=pid,
                    fetched_at=datetime.now(),
                    plan_name=adapter.meta().display_name,
                    plan_kind=adapter.meta().kind,
                    windows=[],
                    auth_mode="",
                    warnings=[str(e)],
                    account_name=acct,
                )
            except Exception as e:
                snap = UsageSnapshot(
                    provider=pid,
                    fetched_at=datetime.now(),
                    plan_name=adapter.meta().display_name,
                    plan_kind=adapter.meta().kind,
                    windows=[],
                    auth_mode="",
                    warnings=[f"fetch failed: {e}"],
                    account_name=acct,
                )
            snapshots.append(snap)
    return snapshots


if __name__ == "__main__":
    cli()
