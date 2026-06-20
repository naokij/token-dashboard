import Foundation

final class MiMoAdapter: Adapter {
    let providerId: ProviderId = .mimo
    let displayName: String = "Xiaomi MiMo"
    let homeURL: String = "https://platform.xiaomimimo.com/"
    let planKind: PlanKind = .tokenPlan
    let account: String

    private let notes: String? = "Token Plan + Pay-as-you-go"

    init(account: String = "default") {
        self.account = account
    }

    func supportedAuthModes() -> [String] {
        ["cookie"]
    }

    func meta() -> ProviderMeta {
        ProviderMeta(
            id: providerId,
            displayName: displayName,
            kind: planKind,
            homeURL: homeURL,
            apiKeyFormat: nil,
            authModes: supportedAuthModes(),
            notes: notes
        )
    }

    func fetch(store: CredentialStore) async throws -> UsageSnapshot {
        guard let cookieCred = store.loadCredential(provider: providerId.rawValue, kind: "cookie", account: account) else {
            throw AuthRequiredError(message: "MiMo: please add cookie credentials")
        }
        let cookies = cookieCred["cookies"] as? [[String: Any]] ?? []
        guard !cookies.isEmpty else {
            throw AuthRequiredError(message: "MiMo: no cookies found, please re-add your cookie")
        }

        let cookieHeader = CookieHelper.formatCookieHeader(credential: cookieCred)
        let headers: [String: String] = [
            "Cookie": cookieHeader,
            "Accept": "application/json",
            "x-timezone": "Asia/Shanghai",
        ]

        var snap = UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "MiMo",
            planKind: planKind,
            authMode: "cookie"
        )

        do {
            let balanceData = try await fetchBalance(headers: headers)
            if balanceData["code"] as? Int == 0,
               let data = balanceData["data"] as? [String: Any] {
                snap.balance = data["balance"] as? Double ?? Double("\(data["balance"] ?? 0)")
                snap.balanceUnit = .cny
            }
        } catch {
            snap.warnings.append("Balance fetch failed: \(error.localizedDescription)")
        }

        do {
            let planData = try await fetchTokenPlan(headers: headers)
            if planData["code"] as? Int == 0,
               let data = planData["data"] as? [String: Any] {
                snap.windows = parseTokenPlan(data)
            }
        } catch {
            snap.warnings.append("Token plan fetch failed: \(error.localizedDescription)")
        }

        return snap
    }

    func parseTokenPlan(_ data: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        if let monthUsage = data["monthUsage"] as? [String: Any],
           let monthItems = monthUsage["items"] as? [[String: Any]] {
            for item in monthItems {
                if item["name"] as? String == "month_total_token" {
                    let used = item["used"] as? Double ?? Double("\(item["used"] ?? 0)") ?? 0
                    let limit = item["limit"] as? Double ?? Double("\(item["limit"] ?? 0)") ?? 0
                    let usedPct = limit > 0 ? (used / limit * 100.0) : 0
                    windows.append(QuotaWindow(
                        kind: .calendarMonth,
                        label: "Monthly",
                        used: used,
                        limit: limit,
                        remaining: limit > 0 ? limit - used : nil,
                        unit: .credits,
                        usedPct: usedPct,
                        raw: [:]
                    ))
                }
            }
        }

        if let usage = data["usage"] as? [String: Any],
           let usageItems = usage["items"] as? [[String: Any]] {
            for item in usageItems {
                if item["name"] as? String == "plan_total_token" {
                    let used = item["used"] as? Double ?? Double("\(item["used"] ?? 0)") ?? 0
                    let limit = item["limit"] as? Double ?? Double("\(item["limit"] ?? 0)") ?? 0
                    let usedPct = limit > 0 ? (used / limit * 100.0) : 0
                    windows.append(QuotaWindow(
                        kind: .rollingMonth,
                        label: "Plan Total",
                        used: used,
                        limit: limit,
                        remaining: limit > 0 ? limit - used : nil,
                        unit: .credits,
                        usedPct: usedPct,
                        raw: [:]
                    ))
                }
            }
        }

        return windows
    }

    private func fetchBalance(headers: [String: String]) async throws -> [String: Any] {
        let url = URL(string: "https://platform.xiaomimimo.com/api/v1/balance")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func fetchTokenPlan(headers: [String: String]) async throws -> [String: Any] {
        let url = URL(string: "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
