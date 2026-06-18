import Foundation
import SwiftSoup

final class OpenCodeAdapter: Adapter {
    let providerId: ProviderId = .opencode
    let displayName: String = "OpenCode Go"
    let homeURL: String = "https://opencode.ai/docs/go/"
    let planKind: PlanKind = .codingPlan
    let account: String

    private let notes: String? = "Cookie auth only; rolling 5h/week/month limits in USD"

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
        guard let cookieCred = store.loadCredential(provider: providerId.rawValue, kind: "cookie", account: account),
              let cookies = cookieCred["cookies"] as? [[String: Any]], !cookies.isEmpty else {
            throw AuthRequiredError(message: "OpenCode Go: please add cookie credentials")
        }

        let cookieHeader = formatCookieHeader(cookies)
        let windows = try await fetchUsageViaCookie(cookieCred: cookieCred, cookieHeader: cookieHeader)

        var snap = UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "OpenCode Go",
            planKind: planKind,
            authMode: "cookie"
        )
        snap.windows = windows
        return snap
    }

    func parseHTMLResponse(_ html: String) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        let now = Date()

        guard let doc = try? SwiftSoup.parse(html),
              let usageDiv = try? doc.select("div[data-slot=usage]").first(),
              let usageText = try? usageDiv.text() else {
            return windows
        }

        let patterns: [(String, WindowKind, String)] = [
            ("滚动用量(\\d+)%重置于(.*?)(?=每周用量|每月用量|$)", .rolling5h, "5h rolling"),
            ("每周用量(\\d+)%重置于(.*?)(?=每月用量|$)", .rollingWeek, "Weekly"),
            ("每月用量(\\d+)%重置于(.*?)$", .rollingMonth, "Monthly"),
            ("Rolling\\s+Usage\\s+(\\d+)%\\s+Resets?\\s+in\\s+(.*?)(?=Weekly|Monthly|$)", .rolling5h, "5h rolling"),
            ("Weekly\\s+Usage\\s+(\\d+)%\\s+Resets?\\s+in\\s+(.*?)(?=Monthly|$)", .rollingWeek, "Weekly"),
            ("Monthly\\s+Usage\\s+(\\d+)%\\s+Resets?\\s+in\\s+(.*?)$", .rollingMonth, "Monthly"),
        ]

        for (pattern, kind, label) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: usageText, range: NSRange(usageText.startIndex..., in: usageText)),
                  match.numberOfRanges >= 3 else {
                continue
            }

            let pctRange = Range(match.range(at: 1), in: usageText)!
            let resetRange = Range(match.range(at: 2), in: usageText)!
            let pctStr = String(usageText[pctRange])
            let resetStr = String(usageText[resetRange]).trimmingCharacters(in: .whitespaces)

            guard let usedPct = Double(pctStr) else { continue }
            let resetSec = parseResetTime(resetStr)
            let resetAt = resetSec > 0 ? now.addingTimeInterval(TimeInterval(resetSec)) : nil

            windows.append(QuotaWindow(
                kind: kind,
                label: label,
                used: usedPct,
                limit: 100.0,
                remaining: 100.0 - usedPct,
                unit: .percent,
                usedPct: usedPct,
                resetAt: resetAt,
                raw: [:]
            ))
        }

        return windows
    }

    func parseResetTime(_ timeStr: String) -> Int {
        var totalSeconds = 0

        if let match = timeStr.range(of: #"(\d+)\s*天"#, options: .regularExpression) {
            let numStr = timeStr[match].replacingOccurrences(of: "天", with: "").trimmingCharacters(in: .whitespaces)
            if let d = Int(numStr) { totalSeconds += d * 86400 }
        }

        if let match = timeStr.range(of: #"(\d+)\s*小时"#, options: .regularExpression) {
            let numStr = timeStr[match].replacingOccurrences(of: "小时", with: "").trimmingCharacters(in: .whitespaces)
            if let h = Int(numStr) { totalSeconds += h * 3600 }
        }

        if let match = timeStr.range(of: #"(\d+)\s*分钟"#, options: .regularExpression) {
            let numStr = timeStr[match].replacingOccurrences(of: "分钟", with: "").trimmingCharacters(in: .whitespaces)
            if let m = Int(numStr) { totalSeconds += m * 60 }
        }

        if totalSeconds == 0 {
            if let match = timeStr.range(of: #"(\d+)d"#, options: .regularExpression) {
                let numStr = String(timeStr[match]).replacingOccurrences(of: "d", with: "")
                if let d = Int(numStr) { totalSeconds += d * 86400 }
            }

            if let regex = try? NSRegularExpression(pattern: #"(\d+):(\d+):(\d+)"#),
               let match = regex.firstMatch(in: timeStr, range: NSRange(timeStr.startIndex..., in: timeStr)),
               match.numberOfRanges >= 4 {
                let h = Int((timeStr as NSString).substring(with: match.range(at: 1))) ?? 0
                let m = Int((timeStr as NSString).substring(with: match.range(at: 2))) ?? 0
                let s = Int((timeStr as NSString).substring(with: match.range(at: 3))) ?? 0
                totalSeconds += h * 3600 + m * 60 + s
            }
        }

        return totalSeconds
    }

    private func fetchUsageViaCookie(cookieCred: [String: Any], cookieHeader: String) async throws -> [QuotaWindow] {
        var workspaceId = cookieCred["workspace_id"] as? String

        if workspaceId == nil {
            let url = URL(string: "https://opencode.ai/workspace/usage")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue("text/html", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let html = String(data: data, encoding: .utf8) {
                if let regex = try? NSRegularExpression(pattern: "wrk_[a-zA-Z0-9]+"),
                   let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
                    workspaceId = (html as NSString).substring(with: match.range)
                }
            }
        }

        guard let wsId = workspaceId else {
            throw RuntimeError("Could not find workspace ID. Please set workspace_id in credentials.")
        }

        let url = URL(string: "https://opencode.ai/workspace/\(wsId)/go")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 Chrome/120.0.0.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw RuntimeError("Failed to fetch usage page: \(code)")
        }

        let html = String(data: data, encoding: .utf8) ?? ""
        return parseHTMLResponse(html)
    }

    private func formatCookieHeader(_ cookies: [[String: Any]]) -> String {
        cookies.compactMap { c -> String? in
            guard let name = c["name"] as? String, let value = c["value"] as? String else { return nil }
            return "\(name)=\(value)"
        }.joined(separator: "; ")
    }
}
