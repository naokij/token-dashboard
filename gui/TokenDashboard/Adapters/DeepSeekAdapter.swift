import Foundation

final class DeepSeekAdapter: Adapter {
    let providerId: ProviderId = .deepseek
    let displayName: String = "DeepSeek"
    let homeURL: String = "https://platform.deepseek.com/"
    let planKind: PlanKind = .payAsYouGo
    let account: String

    private let apiKeyFormat: String? = "sk-..."
    private let notes: String? = "Pay-as-you-go, balance-based"

    init(account: String = "default") {
        self.account = account
    }

    func supportedAuthModes() -> [String] {
        ["api_key"]
    }

    func meta() -> ProviderMeta {
        ProviderMeta(
            id: providerId,
            displayName: displayName,
            kind: planKind,
            homeURL: homeURL,
            apiKeyFormat: apiKeyFormat,
            authModes: supportedAuthModes(),
            notes: notes
        )
    }

    func fetch(store: CredentialStore) async throws -> UsageSnapshot {
        guard let apiCred = store.loadCredential(provider: providerId.rawValue, kind: "api_key", account: account),
              let apiKey = apiCred["key"] as? String else {
            throw AuthRequiredError(message: "DeepSeek: please add an API key")
        }

        let data = try await fetchBalance(apiKey: apiKey)

        var snap = UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "DeepSeek Pay-as-you-go",
            planKind: planKind,
            authMode: "api_key"
        )
        snap.balance = data.balance
        snap.balanceUnit = data.balanceUnit
        return snap
    }

    struct ParsedBalance {
        var balance: Double?
        var balanceUnit: QuotaUnit?
    }

    func parseResponse(_ data: [String: Any]) -> ParsedBalance {
        let balanceInfos = data["balance_infos"] as? [[String: Any]] ?? []

        var balanceInfo: [String: Any]?
        for info in balanceInfos {
            if info["currency"] as? String == "CNY" {
                balanceInfo = info
                break
            }
        }
        if balanceInfo == nil, let first = balanceInfos.first {
            balanceInfo = first
        }

        var result = ParsedBalance()
        if let info = balanceInfo {
            if let total = info["total_balance"] {
                result.balance = Double("\(total)")
                let currency = info["currency"] as? String ?? "CNY"
                result.balanceUnit = currency == "CNY" ? .cny : .usd
            }
        }
        return result
    }

    private func fetchBalance(apiKey: String) async throws -> ParsedBalance {
        let url = URL(string: "https://api.deepseek.com/user/balance")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw RuntimeError("DeepSeek API request failed: \(code)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return parseResponse(json)
    }
}

extension JSONValue {
    static func from(_ value: Any) -> JSONValue {
        switch value {
        case let s as String: return .string(s)
        case let d as Double: return .double(d)
        case let i as Int: return .double(Double(i))
        case let b as Bool: return .bool(b)
        case let a as [Any]: return .array(a.map { JSONValue.from($0) })
        case let o as [String: Any]: return .object(o.mapValues { JSONValue.from($0) })
        default: return .null
        }
    }
}
