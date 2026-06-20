import Foundation

final class MiniMaxAdapter: Adapter {
    let providerId: ProviderId = .minimax
    let displayName: String = "MiniMax Token Plan"
    let homeURL: String = "https://platform.minimaxi.com/docs/token-plan/intro.md"
    let planKind: PlanKind = .tokenPlan
    let account: String

    private let apiKeyFormat: String? = "sk-..."
    private let notes: String? = "5h + weekly windows, percentage-based"

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
            throw AuthRequiredError(message: "MiniMax: please add an API key")
        }

        let result = try await fetchViaAPI(apiKey: apiKey)

        var snap = UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "MiniMax Token Plan",
            planKind: planKind,
            authMode: "api_key"
        )
        snap.windows = result.windows
        return snap
    }

    struct ParsedAPI {
        var windows: [QuotaWindow] = []
    }

    func parseAPIResponse(_ data: [String: Any]) -> ParsedAPI {
        var windows: [QuotaWindow] = []
        let modelRemains = data["model_remains"] as? [[String: Any]] ?? []

        for model in modelRemains {
            let modelName = model["model_name"] as? String ?? "unknown"

            let intervalPct = model["current_interval_remaining_percent"] as? Double ?? 100
            let endMs = model["end_time"] as? Double
            windows.append(QuotaWindow(
                kind: .rolling5h,
                label: "\(modelName) (5h)",
                used: 100.0 - intervalPct,
                limit: 100.0,
                remaining: intervalPct,
                unit: .percent,
                usedPct: 100.0 - intervalPct,
                resetAt: endMs.map { Date(timeIntervalSince1970: $0 / 1000.0) },
                raw: [:]
            ))

            let weeklyPct = model["current_weekly_remaining_percent"] as? Double ?? 100
            let weeklyEndMs = model["weekly_end_time"] as? Double
            windows.append(QuotaWindow(
                kind: .rollingWeek,
                label: "\(modelName) (week)",
                used: 100.0 - weeklyPct,
                limit: 100.0,
                remaining: weeklyPct,
                unit: .percent,
                usedPct: 100.0 - weeklyPct,
                resetAt: weeklyEndMs.map { Date(timeIntervalSince1970: $0 / 1000.0) },
                raw: [:]
            ))
        }

        return ParsedAPI(windows: windows)
    }

    private func fetchViaAPI(apiKey: String) async throws -> ParsedAPI {
        let url = URL(string: "https://www.minimaxi.com/v1/token_plan/remains")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw RuntimeError("MiniMax API request failed: \(code)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return parseAPIResponse(json)
    }
}
