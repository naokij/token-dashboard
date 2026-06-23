"""Adapter registry — ProviderId -> Adapter class."""

from td.adapters.base import Adapter
from td.adapters.deepseek import DeepSeekAdapter
from td.adapters.mimo import MiMoAdapter
from td.adapters.minimax import MiniMaxAdapter
from td.adapters.opencode import OpenCodeGoAdapter
from td.adapters.volcark import VolcArkAdapter
from td.adapters.xunfei import XunfeiAdapter
from td.models import ProviderId

REGISTRY: dict[ProviderId, type[Adapter]] = {
    ProviderId.OPENCODE: OpenCodeGoAdapter,
    ProviderId.MINIMAX: MiniMaxAdapter,
    ProviderId.MIMO: MiMoAdapter,
    ProviderId.XUNFEI: XunfeiAdapter,
    ProviderId.DEEPSEEK: DeepSeekAdapter,
    ProviderId.VOLCARK: VolcArkAdapter,
}


def get_adapter(provider_id: ProviderId, config, account: str = "default") -> Adapter:
    cls = REGISTRY[provider_id]
    return cls(config, account=account)
