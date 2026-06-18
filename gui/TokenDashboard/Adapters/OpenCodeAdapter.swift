import Foundation
import SwiftSoup

final class OpenCodeAdapter: Adapter {
    let providerId: ProviderId = .opencode
    let displayName: String = "OpenCode Go"
    let homeURL: String = "https://opencode.ai/docs/go/"
    let planKind: PlanKind = .codingPlan
    let account: String

    private let session: URLSession

    init(account: String = "default") {
        self.account = account
        let config = URLSessionConfiguration.default
        let delegate = CookiePreservingRedirectDelegate()
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
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
            notes: nil
        )
    }

    func fetch(store: CredentialStore) async throws -> UsageSnapshot {
        guard let cookieCred = store.loadCredential(provider: providerId.rawValue, kind: "cookie", account: account) else {
            throw AuthRequiredError(message: "OpenCode Go: please add cookie credentials")
        }

        let cookies = cookieCred["cookies"] as? [Any] ?? []
        guard !cookies.isEmpty else {
            throw AuthRequiredError(message: "OpenCode Go: no cookies found, please re-add your cookie")
        }

        let cookieHeader = CookieHelper.formatCookieHeader(credential: cookieCred)

        var warnings: [String] = []
        var windows: [QuotaWindow] = []

        var workspaceId = cookieCred["workspace_id"] as? String

        if workspaceId == nil {
            workspaceId = await findWorkspaceId(cookieHeader: cookieHeader)
        }

        if let wsId = workspaceId {
            let goUrl = URL(string: "https://opencode.ai/workspace/\(wsId)/go")!
            var goRequest = URLRequest(url: goUrl)
            goRequest.httpMethod = "GET"
            goRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            goRequest.setValue("text/html", forHTTPHeaderField: "Accept")
            goRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

            let (goData, goResponse) = try await session.data(for: goRequest)
            let goStatus = (goResponse as? HTTPURLResponse)?.statusCode ?? -1

            if goStatus == 200 {
                let goHtml = String(data: goData, encoding: .utf8) ?? ""
                windows = parseHTMLResponse(goHtml)
                if windows.isEmpty {
                    if goHtml.contains("sign-in") || goHtml.contains("login") || goHtml.contains("Sign in") {
                        warnings.append("Cookie expired, please re-add your OpenCode cookie")
                    } else {
                        warnings.append("Usage data not found on page, structure may have changed")
                    }
                }
            } else {
                warnings.append("Failed to fetch usage page (status \(goStatus))")
            }
        } else {
            warnings.append("Could not find workspace ID. Try adding workspace_id in cookie settings")
        }

        return UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "OpenCode Go",
            planKind: planKind,
            windows: windows,
            authMode: "cookie",
            warnings: warnings
        )
    }

    private func makeRequest(url: String, cookieHeader: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func findWorkspaceId(cookieHeader: String) async -> String? {
        let urls = [
            "https://opencode.ai/workspace/usage",
            "https://opencode.ai/auth",
        ]

        for urlStr in urls {
            let request = makeRequest(url: urlStr, cookieHeader: cookieHeader)
            guard let (data, response) = try? await session.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                continue
            }

            if let regex = try? NSRegularExpression(pattern: "wrk_[a-zA-Z0-9]+"),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
                return (html as NSString).substring(with: match.range)
            }
        }

        return nil
    }

    func parseHTMLResponse(_ html: String) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        let now = Date()

        guard let doc = try? SwiftSoup.parse(html) else { return windows }

        let usageDiv = try? doc.select("div[data-slot=usage]").first()
        if let usageDiv = usageDiv {
            let items = try? usageDiv.select("div[data-slot=usage-item]")
            if let items = items, !items.isEmpty {
                for item in items {
                    guard let labelEl = try? item.select("span[data-slot=usage-label]").first(),
                          let valueEl = try? item.select("span[data-slot=usage-value]").first(),
                          let resetEl = try? item.select("span[data-slot=reset-time]").first() else {
                        continue
                    }

                    let label = (try? labelEl.text()) ?? ""
                    let valueText = (try? valueEl.text()) ?? ""
                    let resetText = (try? resetEl.text()) ?? ""

                    guard let usedPct = extractPercentage(valueText) else { continue }

                    let kind: WindowKind
                    let windowLabel: String
                    if label.contains("滚动") || label.lowercased().contains("rolling") {
                        kind = .rolling5h
                        windowLabel = "5h rolling"
                    } else if label.contains("每周") || label.lowercased().contains("weekly") {
                        kind = .rollingWeek
                        windowLabel = "Weekly"
                    } else if label.contains("每月") || label.lowercased().contains("monthly") {
                        kind = .rollingMonth
                        windowLabel = "Monthly"
                    } else {
                        continue
                    }

                    let resetSec = parseResetTime(resetText)
                    let resetAt = resetSec > 0 ? now.addingTimeInterval(TimeInterval(resetSec)) : nil

                    windows.append(QuotaWindow(
                        kind: kind,
                        label: windowLabel,
                        used: usedPct,
                        limit: 100.0,
                        remaining: 100.0 - usedPct,
                        unit: .percent,
                        usedPct: usedPct,
                        resetAt: resetAt,
                        raw: [:]
                    ))
                }

                if !windows.isEmpty { return windows }
            }
        }

        return parseFromHydrationData(html)
    }

    private func extractPercentage(_ text: String) -> Double? {
        let digits = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return Double(digits)
    }

    private func parseFromHydrationData(_ html: String) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        let now = Date()

        let pattern = #"rollingUsage:\{[^}]*status:"ok",resetInSec:(\d+),usagePercent:(\d+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges >= 3 else {
            return windows
        }

        let rollingSec = Int((html as NSString).substring(with: match.range(at: 1))) ?? 0
        let rollingPct = Double((html as NSString).substring(with: match.range(at: 2))) ?? 0
        windows.append(QuotaWindow(kind: .rolling5h, label: "5h rolling", used: rollingPct, limit: 100.0, remaining: 100.0 - rollingPct, unit: .percent, usedPct: rollingPct, resetAt: now.addingTimeInterval(TimeInterval(rollingSec)), raw: [:]))

        let weeklyPattern = #"weeklyUsage:\{[^}]*status:"ok",resetInSec:(\d+),usagePercent:(\d+)\}"#
        if let wRegex = try? NSRegularExpression(pattern: weeklyPattern),
           let wMatch = wRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           wMatch.numberOfRanges >= 3 {
            let sec = Int((html as NSString).substring(with: wMatch.range(at: 1))) ?? 0
            let pct = Double((html as NSString).substring(with: wMatch.range(at: 2))) ?? 0
            windows.append(QuotaWindow(kind: .rollingWeek, label: "Weekly", used: pct, limit: 100.0, remaining: 100.0 - pct, unit: .percent, usedPct: pct, resetAt: now.addingTimeInterval(TimeInterval(sec)), raw: [:]))
        }

        let monthlyPattern = #"monthlyUsage:\{[^}]*status:"ok",resetInSec:(\d+),usagePercent:(\d+)\}"#
        if let mRegex = try? NSRegularExpression(pattern: monthlyPattern),
           let mMatch = mRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           mMatch.numberOfRanges >= 3 {
            let sec = Int((html as NSString).substring(with: mMatch.range(at: 1))) ?? 0
            let pct = Double((html as NSString).substring(with: mMatch.range(at: 2))) ?? 0
            windows.append(QuotaWindow(kind: .rollingMonth, label: "Monthly", used: pct, limit: 100.0, remaining: 100.0 - pct, unit: .percent, usedPct: pct, resetAt: now.addingTimeInterval(TimeInterval(sec)), raw: [:]))
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
}

private final class CookiePreservingRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var newRequest = request
        if let originalHeaders = task.originalRequest?.allHTTPHeaderFields {
            for (key, value) in originalHeaders {
                if newRequest.value(forHTTPHeaderField: key) == nil {
                    newRequest.setValue(value, forHTTPHeaderField: key)
                }
            }
        }
        completionHandler(newRequest)
    }
}
