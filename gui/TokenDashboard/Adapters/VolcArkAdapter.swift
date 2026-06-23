import Foundation
import CryptoKit

/// Volcengine Ark Agent Plan adapter — GetAFPUsage via Volcengine SigV4.
/// Docs: https://www.volcengine.com/docs/82379/2479849
final class VolcArkAdapter: Adapter {
    let providerId: ProviderId = .volcark
    let displayName: String = "Volc Ark Agent Plan"
    let homeURL: String = "https://www.volcengine.com/docs/82379/2366393"
    let planKind: PlanKind = .tokenPlan
    let account: String

    private let apiKeyFormat: String? = "AK/SK"
    private let notes: String? = "AFP-based, 5h/day(vision)/week/month windows; SigV4 auth"

    private let host = "open.volcengineapi.com"
    private let region = "cn-beijing"
    private let service = "ark"
    private let version = "2024-01-01"

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
        guard let cred = store.loadCredential(provider: providerId.rawValue, kind: "api_key", account: account),
              let ak = cred["access_key"] as? String, !ak.isEmpty,
              let sk = cred["secret_key"] as? String, !sk.isEmpty else {
            throw AuthRequiredError(message: "Volc Ark: please add Access Key and Secret Key")
        }

        let json = try await callGetAFPUsage(ak: ak, sk: sk)
        let result = json["Result"] as? [String: Any] ?? [:]
        let planType = result["PlanType"] as? String ?? ""

        var snap = UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: planType.isEmpty ? "Agent Plan" : "Agent Plan \(planType)",
            planKind: planKind,
            authMode: "api_key"
        )
        snap.windows = parseWindows(result)
        return snap
    }

    // MARK: - Response parsing

    private struct WindowDef {
        let key: String
        let kind: WindowKind
        let label: String
    }

    private let windowDefs: [WindowDef] = [
        WindowDef(key: "AFPFiveHour", kind: .rolling5h, label: "AFP (5h)"),
        WindowDef(key: "AFPDaily", kind: .rollingDay, label: "AFP (day · vision)"),
        WindowDef(key: "AFPWeekly", kind: .rollingWeek, label: "AFP (week)"),
        WindowDef(key: "AFPMonthly", kind: .rollingMonth, label: "AFP (month)"),
    ]

    func parseWindows(_ result: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        for def in windowDefs {
            guard let w = result[def.key] as? [String: Any] else { continue }
            guard let quotaVal = (w["Quota"] as? NSNumber)?.doubleValue,
                  let usedVal = (w["Used"] as? NSNumber)?.doubleValue else { continue }
            let remaining = max(0.0, quotaVal - usedVal)
            let usedPct: Double? = quotaVal > 0 ? usedVal / quotaVal * 100.0 : nil
            let resetAt: Date? = (w["ResetTime"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue / 1000.0)
            }
            windows.append(QuotaWindow(
                kind: def.kind,
                label: def.label,
                used: usedVal,
                limit: quotaVal,
                remaining: remaining,
                unit: .credits,
                usedPct: usedPct,
                resetAt: resetAt,
                raw: [:]
            ))
        }
        return windows
    }

    // MARK: - HTTP

    private func callGetAFPUsage(ak: String, sk: String) async throws -> [String: Any] {
        let body = "{}"
        let signed = signRequest(ak: ak, sk: sk, action: "GetAFPUsage", body: body)

        guard let url = URL(string: signed.url) else {
            throw RuntimeError("Volc Ark: bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in signed.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RuntimeError("Volc Ark: invalid response")
        }
        if httpResponse.statusCode >= 400 {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            // Try to extract Volcengine error code/message
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let meta = json["ResponseMetadata"] as? [String: Any],
                   let err = meta["Error"] as? [String: Any] {
                    let code = err["Code"] as? String ?? "\(httpResponse.statusCode)"
                    let msg = err["Message"] as? String ?? bodyText
                    throw RuntimeError("Volc Ark \(httpResponse.statusCode) \(code): \(msg)")
                }
                if let err = json["error"] as? [String: Any] {
                    let code = err["code"] as? String ?? "\(httpResponse.statusCode)"
                    let msg = err["message"] as? String ?? bodyText
                    throw RuntimeError("Volc Ark \(httpResponse.statusCode) \(code): \(msg)")
                }
            }
            throw RuntimeError("Volc Ark \(httpResponse.statusCode): \(bodyText)")
        }

        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Volcengine SigV4 signing

    func signRequest(ak: String, sk: String, action: String, body: String) -> (headers: [String: String], url: String) {
        let now = Date()
        let xDate = formatXDate(now)
        let shortDate = String(xDate.prefix(8))

        let bodyData = body.data(using: .utf8) ?? Data()
        let xContentSha256 = sha256Hex(bodyData)

        let query = ["Action": action, "Version": version]
        let canonicalQuery = normQuery(query)

        let contentType = "application/json"
        let signedHeadersList = ["content-type", "host", "x-content-sha256", "x-date"]
        let signedHeaders = signedHeadersList.joined(separator: ";")

        let canonicalRequest = [
            "POST",
            "/",
            canonicalQuery,
            "content-type:\(contentType)",
            "host:\(host)",
            "x-content-sha256:\(xContentSha256)",
            "x-date:\(xDate)",
            "",
            signedHeaders,
            xContentSha256,
        ].joined(separator: "\n")

        let hashedCanonical = sha256Hex(Data(canonicalRequest.utf8))
        let credentialScope = "\(shortDate)/\(region)/\(service)/request"
        let stringToSign = [
            "HMAC-SHA256",
            xDate,
            credentialScope,
            hashedCanonical,
        ].joined(separator: "\n")

        let kDate = hmacSHA256(key: Data(sk.utf8), data: Data(shortDate.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("request".utf8))
        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }.joined()

        let authorization = "HMAC-SHA256 Credential=\(ak)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        let headers: [String: String] = [
            "Host": host,
            "Content-Type": contentType,
            "X-Date": xDate,
            "X-Content-Sha256": xContentSha256,
            "Authorization": authorization,
        ]
        let url = "https://\(host)/?\(canonicalQuery)"
        return (headers: headers, url: url)
    }

    // MARK: - signing helpers

    private func formatXDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symKey)
        return Data(mac)
    }

    private func normQuery(_ params: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        var parts: [String] = []
        for key in params.keys.sorted() {
            let value = params[key] ?? ""
            let ek = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let ev = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            parts.append("\(ek)=\(ev)")
        }
        return parts.joined(separator: "&").replacingOccurrences(of: "+", with: "%20")
    }
}
