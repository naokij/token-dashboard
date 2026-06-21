import Foundation

struct UsageSnapshot: Codable, Identifiable {
    var id: String { "\(provider.rawValue)-\(fetchedAt.timeIntervalSince1970)" }

    var provider: ProviderId
    var fetchedAt: Date
    var planName: String?
    var planKind: PlanKind
    var balance: Double?
    var balanceUnit: QuotaUnit?
    var windows: [QuotaWindow]
    var accountEmail: String?
    var accountName: String
    var authMode: String
    var planExpiresAt: Date?
    var warnings: [String]
    var raw: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case provider
        case fetchedAt = "fetched_at"
        case planName = "plan_name"
        case planKind = "plan_kind"
        case balance
        case balanceUnit = "balance_unit"
        case windows
        case accountEmail = "account_email"
        case accountName = "account_name"
        case authMode = "auth_mode"
        case planExpiresAt = "plan_expires_at"
        case warnings
        case raw
    }

    init(
        provider: ProviderId,
        fetchedAt: Date,
        planName: String? = nil,
        planKind: PlanKind,
        balance: Double? = nil,
        balanceUnit: QuotaUnit? = nil,
        windows: [QuotaWindow] = [],
        accountEmail: String? = nil,
        accountName: String = "default",
        authMode: String = "",
        planExpiresAt: Date? = nil,
        warnings: [String] = [],
        raw: [String: JSONValue] = [:]
    ) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.planName = planName
        self.planKind = planKind
        self.balance = balance
        self.balanceUnit = balanceUnit
        self.windows = windows
        self.accountEmail = accountEmail
        self.accountName = accountName
        self.authMode = authMode
        self.planExpiresAt = planExpiresAt
        self.warnings = warnings
        self.raw = raw
    }

    func primaryWindow() -> QuotaWindow? {
        let bounded = windows.filter { $0.limit != nil && $0.usedPct != nil }
        guard !bounded.isEmpty else { return nil }
        return bounded.max(by: { ($0.usedPct ?? 0) < ($1.usedPct ?? 0) })
    }
}
