import Foundation

final class XunfeiAdapter: Adapter {
    let providerId: ProviderId = .xunfei
    let displayName: String = "讯飞星辰 Coding Plan"
    let homeURL: String = "https://maas.xfyun.cn/"
    let planKind: PlanKind = .codingPlan
    let account: String

    private let notes: String? = "Request-count based"

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
            throw AuthRequiredError(message: "Xunfei: please add cookie credentials")
        }
        let cookies = cookieCred["cookies"] as? [[String: Any]] ?? []
        guard !cookies.isEmpty else {
            throw AuthRequiredError(message: "Xunfei: no cookies found, please re-add your cookie")
        }

        let cookieHeader = CookieHelper.formatCookieHeader(credential: cookieCred)

        var components = URLComponents(string: "https://maas.xfyun.cn/api/v1/gpt-finetune/coding-plan/list")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "size", value: "6"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw RuntimeError("Xunfei API request failed: \(code)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if json["code"] as? Int != 0 {
            throw RuntimeError("Xunfei API error: \(json["message"] ?? "unknown")")
        }

        var snap = UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "讯飞星辰 Coding Plan",
            planKind: planKind,
            authMode: "cookie"
        )

        if let rows = (json["data"] as? [String: Any])?["rows"] as? [[String: Any]],
           let plan = rows.first {
            snap.planName = plan["name"] as? String ?? "Coding Plan"
            snap.accountEmail = plan["appId"] as? String
            snap.windows = parseUsage(plan)
            snap.raw = plan.mapValues { JSONValue.from($0) }
        }

        return snap
    }

    func parseUsage(_ plan: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        let usage = plan["codingPlanUsageDTO"] as? [String: Any] ?? [:]

        let rp5hLimit = usage["rp5hLimit"] as? Double ?? Double("\(usage["rp5hLimit"] ?? 0)") ?? 0
        let rp5hUsage = usage["rp5hUsage"] as? Double ?? Double("\(usage["rp5hUsage"] ?? 0)") ?? 0
        if rp5hLimit > 0 {
            windows.append(QuotaWindow(
                kind: .rolling5h,
                label: "5h rolling",
                used: rp5hUsage,
                limit: rp5hLimit,
                remaining: rp5hLimit - rp5hUsage,
                unit: .requests,
                usedPct: rp5hUsage / rp5hLimit * 100.0,
                raw: usage.mapValues { JSONValue.from($0) }
            ))
        }

        let rpwLimit = usage["rpwLimit"] as? Double ?? Double("\(usage["rpwLimit"] ?? 0)") ?? 0
        let rpwUsage = usage["rpwUsage"] as? Double ?? Double("\(usage["rpwUsage"] ?? 0)") ?? 0
        if rpwLimit > 0 {
            windows.append(QuotaWindow(
                kind: .rollingWeek,
                label: "Weekly",
                used: rpwUsage,
                limit: rpwLimit,
                remaining: rpwLimit - rpwUsage,
                unit: .requests,
                usedPct: rpwUsage / rpwLimit * 100.0,
                raw: usage.mapValues { JSONValue.from($0) }
            ))
        }

        let packageLimit = usage["packageLimit"] as? Double ?? Double("\(usage["packageLimit"] ?? 0)") ?? 0
        let packageUsage = usage["packageUsage"] as? Double ?? Double("\(usage["packageUsage"] ?? 0)") ?? 0
        if packageLimit > 0 {
            var resetAt: Date?
            if let expiresAt = plan["expiresAt"] as? String {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
                resetAt = formatter.date(from: expiresAt)
            }
            windows.append(QuotaWindow(
                kind: .fixedPeriod,
                label: "Package Total",
                used: packageUsage,
                limit: packageLimit,
                remaining: packageLimit - packageUsage,
                unit: .requests,
                usedPct: packageUsage / packageLimit * 100.0,
                resetAt: resetAt,
                raw: usage.mapValues { JSONValue.from($0) }
            ))
        }

        return windows
    }
}
