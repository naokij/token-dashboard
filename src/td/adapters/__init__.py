"""Adapter package.

Each provider has an adapter module exporting a class implementing
`td.adapters.base.Adapter`. The CLI looks up adapters by `ProviderId` value.
"""

from td.adapters.base import Adapter, AdapterError, AuthRequiredError

__all__ = ["Adapter", "AdapterError", "AuthRequiredError"]
