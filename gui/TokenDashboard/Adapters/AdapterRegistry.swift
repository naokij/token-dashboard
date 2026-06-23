import Foundation

final class AdapterRegistry {
    func adapter(for providerId: ProviderId, account: String = "default") -> Adapter {
        switch providerId {
        case .opencode: return OpenCodeAdapter(account: account)
        case .minimax: return MiniMaxAdapter(account: account)
        case .mimo: return MiMoAdapter(account: account)
        case .xunfei: return XunfeiAdapter(account: account)
        case .deepseek: return DeepSeekAdapter(account: account)
        case .volcark: return VolcArkAdapter(account: account)
        }
    }

    var allProviderIds: [ProviderId] { ProviderId.allCases }
}
