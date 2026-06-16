"""Adapter base class and common error types."""

from __future__ import annotations

import abc
from typing import Any

from td.config import AppConfig, load_credential
from td.models import ProviderId, ProviderMeta, UsageSnapshot


class AdapterError(Exception):
    """Generic adapter failure."""


class AuthRequiredError(AdapterError):
    """Raised when the adapter needs credentials but has none."""


class Adapter(abc.ABC):
    """Base class for provider adapters.

    Lifecycle:
      1. The CLI calls `meta()` to display info about the provider.
      2. The CLI calls `is_configured()` to check if the user has logged in
         / provided an API key. If not, the user is prompted to run
         `td login <provider>` or `td add <provider>`.
      3. The CLI calls `fetch()` to get a UsageSnapshot.
    """

    id: ProviderId  # subclasses must set
    display_name: str  # subclasses must set
    home_url: str  # subclasses must set
    kind: str  # "coding_plan" | "token_plan" | "pay_as_you_go"
    api_key_format: str | None = None
    notes: str | None = None

    def __init__(self, config: AppConfig, account: str = "default"):
        self.config = config
        self.account = account

    # ---- introspection ---- #

    def meta(self) -> ProviderMeta:
        return ProviderMeta(
            id=self.id,
            display_name=self.display_name,
            kind=self.kind,
            home_url=self.home_url,
            api_key_format=self.api_key_format,
            auth_modes=self.supported_auth_modes(),
            notes=self.notes,
        )

    @abc.abstractmethod
    def supported_auth_modes(self) -> list[str]:
        """Return e.g. ['api_key'], ['cookie'], or ['api_key', 'cookie']."""

    def is_configured(self) -> bool:
        """True if the adapter has what it needs to call fetch()."""
        for mode in self.supported_auth_modes():
            if load_credential(self.id.value, mode, account=self.account) is not None:
                return True
        return False

    # ---- the main entry ---- #

    @abc.abstractmethod
    async def fetch(self) -> UsageSnapshot:
        """Fetch a current usage snapshot. Must be implemented by subclasses."""

    # ---- optional helpers ---- #

    async def probe_api(self) -> dict[str, Any] | None:
        """Make a cheap API call to validate an API key is alive and grab any
        incidental usage data. Optional — subclasses override if useful."""
        return None
