# Token Dashboard GUI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS menu bar app with ControlWidget that displays AI provider usage, replacing the CLI-only experience with a GUI.

**Architecture:** SwiftUI menu bar app (LSUIElement=true) with popover panel, 5 Swift adapters rewriting the Python ones, Keychain credential storage, and a ControlWidget extension for macOS 26+ system Control Center.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+ (Ventura), SPM dependencies: SwiftSoup, Yams, KeychainAccess

---

### Task 1: Create Xcode Project Structure

**Files:**
- Create: `gui/TokenDashboard/TokenDashboardApp.swift`
- Create: `gui/TokenDashboard/Assets.xcassets/`
- Create: `gui/TokenDashboard/Info.plist`

**Step 1: Create the Xcode project directory structure**

```bash
mkdir -p gui/TokenDashboard/{Models,Adapters,Store,Views,MenuBar,Assets.xcassets}
mkdir -p gui/TokenDashboardTests
```

**Step 2: Create Package.swift for SPM-based project**

Create `gui/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenDashboard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TokenDashboard", targets: ["TokenDashboard"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "TokenDashboard",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
            ],
            path: "TokenDashboard"
        ),
        .testTarget(
            name: "TokenDashboardTests",
            dependencies: ["TokenDashboard"],
            path: "TokenDashboardTests"
        ),
    ]
)
```

**Step 3: Create minimal app entry point**

Create `gui/TokenDashboard/TokenDashboardApp.swift`:

```swift
import SwiftUI

@main
struct TokenDashboardApp: App {
    var body: some Scene {
        MenuBarExtra("Token Dashboard", systemImage: "gauge.with.dots.needle.33percent") {
            Text("Token Dashboard")
        }
    }
}
```

**Step 4: Build and verify**

Run: `cd gui && swift build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add gui/
git commit -m "feat(gui): scaffold Swift project with SPM"
```

---

### Task 2: Implement Data Models

**Files:**
- Create: `gui/TokenDashboard/Models/ProviderId.swift`
- Create: `gui/TokenDashboard/Models/PlanKind.swift`
- Create: `gui/TokenDashboard/Models/QuotaUnit.swift`
- Create: `gui/TokenDashboard/Models/WindowKind.swift`
- Create: `gui/TokenDashboard/Models/QuotaWindow.swift`
- Create: `gui/TokenDashboard/Models/UsageSnapshot.swift`
- Test: `gui/TokenDashboardTests/ModelTests.swift`

**Step 1: Write failing tests for models**

Create `gui/TokenDashboardTests/ModelTests.swift`:

```swift
import Testing
@testable import TokenDashboard

@Suite("Models")
struct ModelTests {
    @Test("ProviderId has all expected cases")
    func providerIdCases() {
        let allCases: [ProviderId] = [.opencode, .minimax, .mimo, .xunfei, .deepseek]
        #expect(allCases.count == 5)
        #expect(ProviderId.opencode.rawValue == "opencode")
        #expect(ProviderId.deepseek.rawValue == "deepseek")
    }

    @Test("QuotaWindow computes usedPct correctly")
    func quotaWindowUsedPct() {
        let window = QuotaWindow(
            kind: .rolling5h,
            label: "5h",
            used: 75.0,
            limit: 100.0,
            remaining: 25.0,
            unit: .percent,
            usedPct: 75.0
        )
        #expect(window.usedPct == 75.0)
        #expect(window.remaining == 25.0)
    }

    @Test("UsageSnapshot primaryWindow returns most constrained")
    func primaryWindow() {
        let w1 = QuotaWindow(kind: .rolling5h, label: "5h", used: 30, limit: 100, remaining: 70, unit: .percent, usedPct: 30)
        let w2 = QuotaWindow(kind: .rollingWeek, label: "week", used: 85, limit: 100, remaining: 15, unit: .percent, usedPct: 85)
        let snap = UsageSnapshot(
            provider: .minimax,
            fetchedAt: Date(),
            planKind: .tokenPlan,
            windows: [w1, w2]
        )
        #expect(snap.primaryWindow()?.usedPct == 85.0)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd gui && swift test`
Expected: FAIL — types not defined

**Step 3: Implement ProviderId**

Create `gui/TokenDashboard/Models/ProviderId.swift`:

```swift
enum ProviderId: String, CaseIterable, Codable {
    case opencode
    case minimax
    case mimo
    case xunfei
    case deepseek
}
```

**Step 4: Implement PlanKind**

Create `gui/TokenDashboard/Models/PlanKind.swift`:

```swift
enum PlanKind: String, Codable {
    case codingPlan = "coding_plan"
    case tokenPlan = "token_plan"
    case payAsYouGo = "pay_as_you_go"
}
```

**Step 5: Implement QuotaUnit**

Create `gui/TokenDashboard/Models/QuotaUnit.swift`:

```swift
enum QuotaUnit: String, Codable {
    case credits
    case tokens
    case requests
    case usd
    case cny
    case prompts
    case percent
    case unknown
}
```

**Step 6: Implement WindowKind**

Create `gui/TokenDashboard/Models/WindowKind.swift`:

```swift
enum WindowKind: String, Codable {
    case rolling5h = "rolling_5h"
    case rollingWeek = "rolling_week"
    case rollingMonth = "rolling_month"
    case calendarMonth = "calendar_month"
    case calendarDay = "calendar_day"
    case fixedPeriod = "fixed_period"
    case balance
}
```

**Step 7: Implement QuotaWindow**

Create `gui/TokenDashboard/Models/QuotaWindow.swift`:

```swift
import Foundation

struct QuotaWindow: Codable, Identifiable {
    let id = UUID()
    var kind: WindowKind
    var label: String
    var used: Double
    var limit: Double?
    var remaining: Double?
    var unit: QuotaUnit
    var usedPct: Double?
    var resetAt: Date?
    var periodStart: Date?
    var periodEnd: Date?
    var raw: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case kind, label, used, limit, remaining, unit
        case usedPct = "used_pct"
        case resetAt = "reset_at"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case raw
    }

    init(kind: WindowKind, label: String, used: Double, limit: Double? = nil,
         remaining: Double? = nil, unit: QuotaUnit, usedPct: Double? = nil,
         resetAt: Date? = nil, periodStart: Date? = nil, periodEnd: Date? = nil,
         raw: [String: String] = [:]) {
        self.kind = kind
        self.label = label
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.unit = unit
        self.usedPct = usedPct
        self.resetAt = resetAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.raw = raw
    }
}
```

**Step 8: Implement UsageSnapshot**

Create `gui/TokenDashboard/Models/UsageSnapshot.swift`:

```swift
import Foundation

struct UsageSnapshot: Codable, Identifiable {
    let id = UUID()
    var provider: ProviderId
    var fetchedAt: Date
    var planName: String?
    var planKind: PlanKind
    var balance: Double?
    var balanceUnit: QuotaUnit?
    var windows: [QuotaWindow]
    var accountEmail: String?
    var accountName: String = "default"
    var authMode: String = ""
    var warnings: [String] = []
    var raw: [String: String] = [:]

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
        case warnings, raw
    }

    func primaryWindow() -> QuotaWindow? {
        let bounded = windows.filter { $0.limit != nil && $0.usedPct != nil }
        return bounded.max(by: { ($0.usedPct ?? 0) < ($1.usedPct ?? 0) })
    }
}
```

**Step 9: Run tests to verify they pass**

Run: `cd gui && swift test`
Expected: All tests PASS

**Step 10: Commit**

```bash
git add gui/TokenDashboard/Models/ gui/TokenDashboardTests/ModelTests.swift
git commit -m "feat(gui): add data models mirroring Python models.py"
```

---

### Task 3: Implement Credential Store (Keychain)

**Files:**
- Create: `gui/TokenDashboard/Store/CredentialStore.swift`
- Create: `gui/TokenDashboard/Store/ConfigStore.swift`
- Test: `gui/TokenDashboardTests/CredentialStoreTests.swift`

**Step 1: Write failing test**

Create `gui/TokenDashboardTests/CredentialStoreTests.swift`:

```swift
import Testing
@testable import TokenDashboard

@Suite("CredentialStore")
struct CredentialStoreTests {
    @Test("Save and load API key credential")
    func saveAndLoadAPIKey() async throws {
        let store = CredentialStore()
        let testProvider = "test_provider_\(Int.random(in: 1000...9999))"
        let testAccount = "test_account"

        let cred: [String: String] = ["key": "sk-test-123"]
        try store.saveCredential(provider: testProvider, kind: "api_key", account: testAccount, value: cred)

        let loaded = store.loadCredential(provider: testProvider, kind: "api_key", account: testAccount)
        #expect(loaded != nil)
        #expect(loaded?["key"] == "sk-test-123")

        try store.deleteCredential(provider: testProvider, kind: "api_key", account: testAccount)
    }

    @Test("Load non-existent credential returns nil")
    func loadNonExistent() {
        let store = CredentialStore()
        let loaded = store.loadCredential(provider: "nonexistent_\(Int.random(in: 1000...9999))", kind: "api_key", account: "default")
        #expect(loaded == nil)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd gui && swift test`
Expected: FAIL — CredentialStore not defined

**Step 3: Implement CredentialStore**

Create `gui/TokenDashboard/Store/CredentialStore.swift`:

```swift
import Foundation
import KeychainAccess

final class CredentialStore {
    private let keychain: Keychain

    init(service: String = "com.token-dashboard") {
        self.keychain = Keychain(service: service)
    }

    func saveCredential(provider: String, kind: String, account: String, value: [String: Any]) throws {
        let key = "\(provider):\(account):\(kind)"
        let data = try JSONSerialization.data(withJSONObject: value)
        try keychain.set(data, key: key)
    }

    func loadCredential(provider: String, kind: String, account: String) -> [String: Any]? {
        let key = "\(provider):\(account):\(kind)"
        guard let data = try? keychain.getData(key) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    func deleteCredential(provider: String, kind: String, account: String) throws {
        let key = "\(provider):\(account):\(kind)"
        try keychain.remove(key)
    }

    func loadLegacyCredentials() -> [String: [String: [String: Any]]]? {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".token-dashboard")
        let credPath = configDir.appendingPathComponent("credentials.json")
        guard let data = try? Data(contentsOf: credPath) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Any]]]
    }

    func migrateFromLegacy() throws {
        guard let legacy = loadLegacyCredentials() else { return }
        for (provider, accounts) in legacy {
            for (account, kinds) in accounts {
                for (kind, value) in kinds {
                    if let dictValue = value as? [String: Any] {
                        try saveCredential(provider: provider, kind: kind, account: account, value: dictValue)
                    }
                }
            }
        }
    }
}
```

**Step 4: Implement ConfigStore**

Create `gui/TokenDashboard/Store/ConfigStore.swift`:

```swift
import Foundation
import Yams

final class ConfigStore: ObservableObject {
    @Published var refreshInterval: Int = 60
    @Published var warnPct: Int = 70
    @Published var criticalPct: Int = 90
    @Published var enabledProviders: Set<ProviderId> = Set(ProviderId.allCases)

    private let configDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = ProcessInfo.processInfo.environment["TD_CONFIG_DIR"]
            ?? home.appendingPathComponent(".token-dashboard").path
        self.configDir = URL(fileURLWithPath: dir)
        load()
    }

    var configPath: URL { configDir.appendingPathComponent("config.yaml") }

    func load() {
        guard FileManager.default.fileExists(atPath: configPath.path) else { return }
        guard let content = try? String(contentsOf: configPath) else { return }
        guard let yaml = try? Yams.load(yaml: content) as? [String: Any] else { return }

        if let alerts = yaml["alerts"] as? [String: Any] {
            warnPct = alerts["warn_pct"] as? Int ?? 70
            criticalPct = alerts["critical_pct"] as? Int ?? 90
        }
        if let watch = yaml["watch"] as? [String: Any] {
            refreshInterval = watch["interval_seconds"] as? Int ?? 60
        }
        if let providers = yaml["providers"] as? [String: Any] {
            var enabled = Set<ProviderId>()
            for pid in ProviderId.allCases {
                if let p = providers[pid.rawValue] as? [String: Any] {
                    if p["enabled"] as? Bool ?? true {
                        enabled.insert(pid)
                    }
                } else {
                    enabled.insert(pid)
                }
            }
            enabledProviders = enabled
        }
    }
}
```

**Step 5: Run tests**

Run: `cd gui && swift test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add gui/TokenDashboard/Store/ gui/TokenDashboardTests/CredentialStoreTests.swift
git commit -m "feat(gui): add CredentialStore (Keychain) and ConfigStore (YAML)"
```

---

### Task 4: Implement Adapter Protocol and DeepSeek Adapter

**Files:**
- Create: `gui/TokenDashboard/Adapters/AdapterProtocol.swift`
- Create: `gui/TokenDashboard/Adapters/DeepSeekAdapter.swift`
- Test: `gui/TokenDashboardTests/DeepSeekAdapterTests.swift`

**Step 1: Write failing test**

Create `gui/TokenDashboardTests/DeepSeekAdapterTests.swift`:

```swift
import Testing
@testable import TokenDashboard

@Suite("DeepSeekAdapter")
struct DeepSeekAdapterTests {
    @Test("Parse balance response with CNY")
    func parseCNYBalance() {
        let adapter = DeepSeekAdapter(account: "default")
        let json: [String: Any] = [
            "is_available": true,
            "balance_infos": [
                [
                    "currency": "CNY",
                    "total_balance": "110.00",
                    "granted_balance": "10.00",
                    "topped_up_balance": "100.00"
                ]
            ]
        ]
        let result = adapter.parseResponse(data: json)
        #expect(result.balance == 110.0)
        #expect(result.balanceUnit == .cny)
    }

    @Test("Parse balance response with USD fallback")
    func parseUSDBalance() {
        let adapter = DeepSeekAdapter(account: "default")
        let json: [String: Any] = [
            "is_available": true,
            "balance_infos": [
                [
                    "currency": "USD",
                    "total_balance": "15.50",
                    "granted_balance": "0.00",
                    "topped_up_balance": "15.50"
                ]
            ]
        ]
        let result = adapter.parseResponse(data: json)
        #expect(result.balance == 15.5)
        #expect(result.balanceUnit == .usd)
    }

    @Test("No auth raises AuthRequiredError")
    func noAuth() async {
        let adapter = DeepSeekAdapter(account: "default")
        do {
            _ = try await adapter.fetch()
            #expect(Bool(false), "Should have thrown")
        } catch is AuthRequiredError {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd gui && swift test`
Expected: FAIL

**Step 3: Implement AdapterProtocol**

Create `gui/TokenDashboard/Adapters/AdapterProtocol.swift`:

```swift
import Foundation

struct AuthRequiredError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ProviderMeta {
    let id: ProviderId
    let displayName: String
    let kind: PlanKind
    let homeURL: String
    let apiKeyFormat: String?
    let authModes: [String]
    let notes: String?
}

protocol Adapter {
    var providerId: ProviderId { get }
    var displayName: String { get }
    var homeURL: String { get }
    var planKind: PlanKind { get }
    var account: String { get }

    func supportedAuthModes() -> [String]
    func meta() -> ProviderMeta
    func isConfigured(store: CredentialStore) -> Bool
    func fetch(store: CredentialStore) async throws -> UsageSnapshot
}

extension Adapter {
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

    func isConfigured(store: CredentialStore) -> Bool {
        for mode in supportedAuthModes() {
            if store.loadCredential(provider: providerId.rawValue, kind: mode, account: account) != nil {
                return true
            }
        }
        return false
    }
}
```

**Step 4: Implement DeepSeekAdapter**

Create `gui/TokenDashboard/Adapters/DeepSeekAdapter.swift`:

```swift
import Foundation

final class DeepSeekAdapter: Adapter {
    let providerId: ProviderId = .deepseek
    let displayName = "DeepSeek"
    let homeURL = "https://platform.deepseek.com/"
    let planKind: PlanKind = .payAsYouGo
    let account: String

    private let apiBase = "https://api.deepseek.com"

    init(account: String = "default") {
        self.account = account
    }

    func supportedAuthModes() -> [String] { ["api_key"] }

    func fetch(store: CredentialStore) async throws -> UsageSnapshot {
        guard let cred = store.loadCredential(provider: providerId.rawValue, kind: "api_key", account: account),
              let key = cred["key"] as? String else {
            throw AuthRequiredError(message: "DeepSeek: please add your API key in Settings")
        }

        var snap = UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "DeepSeek Pay-as-you-go",
            planKind: planKind,
            windows: [],
            authMode: "api_key"
        )

        let result = try await fetchBalance(apiKey: key)
        snap.balance = result.balance
        snap.balanceUnit = result.balanceUnit
        return snap
    }

    private func fetchBalance(apiKey: String) async throws -> (balance: Double?, balanceUnit: QuotaUnit?) {
        var request = URLRequest(url: URL(string: "\(apiBase)/user/balance")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw RuntimeError("DeepSeek API request failed")
        }
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return parseBalanceResult(parseResponse(data: json))
    }

    struct ParsedResult {
        var balance: Double?
        var balanceUnit: QuotaUnit?
        var raw: [String: Any] = [:]
    }

    func parseResponse(data: [String: Any]) -> ParsedResult {
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

        var balance: Double?
        var balanceUnit: QuotaUnit?

        if let info = balanceInfo {
            if let total = info["total_balance"] as? String {
                balance = Double(total)
                let currency = info["currency"] as? String ?? "CNY"
                balanceUnit = currency == "CNY" ? .cny : .usd
            }
        }

        return ParsedResult(balance: balance, balanceUnit: balanceUnit, raw: data)
    }

    private func parseBalanceResult(_ result: ParsedResult) -> (Double?, QuotaUnit?) {
        (result.balance, result.balanceUnit)
    }
}

struct RuntimeError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
```

**Step 5: Run tests**

Run: `cd gui && swift test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add gui/TokenDashboard/Adapters/ gui/TokenDashboardTests/DeepSeekAdapterTests.swift
git commit -m "feat(gui): add Adapter protocol and DeepSeek adapter"
```

---

### Task 5: Implement MiniMax Adapter

**Files:**
- Create: `gui/TokenDashboard/Adapters/MiniMaxAdapter.swift`
- Test: `gui/TokenDashboardTests/MiniMaxAdapterTests.swift`

**Step 1: Write failing test**

Create `gui/TokenDashboardTests/MiniMaxAdapterTests.swift`:

```swift
import Testing
@testable import TokenDashboard

@Suite("MiniMaxAdapter")
struct MiniMaxAdapterTests {
    @Test("Parse API response with 5h and weekly windows")
    func parseAPIResponse() {
        let adapter = MiniMaxAdapter(account: "default")
        let json: [String: Any] = [
            "model_remains": [
                [
                    "model_name": "general",
                    "end_time": 1780729200000,
                    "current_interval_remaining_percent": 80,
                    "weekly_end_time": 1780848000000,
                    "current_weekly_remaining_percent": 95,
                ]
            ]
        ]
        let result = adapter.parseAPIResponse(data: json)
        #expect(result.windows.count == 2)
        #expect(result.windows[0].kind == .rolling5h)
        #expect(result.windows[0].usedPct == 20.0)
        #expect(result.windows[1].kind == .rollingWeek)
        #expect(result.windows[1].usedPct == 5.0)
    }

    @Test("No auth raises AuthRequiredError")
    func noAuth() async {
        let adapter = MiniMaxAdapter(account: "default")
        let store = CredentialStore()
        do {
            _ = try await adapter.fetch(store: store)
            #expect(Bool(false), "Should have thrown")
        } catch is AuthRequiredError {
            #expect(Bool(true))
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd gui && swift test`
Expected: FAIL

**Step 3: Implement MiniMaxAdapter**

Create `gui/TokenDashboard/Adapters/MiniMaxAdapter.swift`:

```swift
import Foundation

final class MiniMaxAdapter: Adapter {
    let providerId: ProviderId = .minimax
    let displayName = "MiniMax Token Plan"
    let homeURL = "https://platform.minimaxi.com/docs/token-plan/intro.md"
    let planKind: PlanKind = .tokenPlan
    let account: String

    private let apiBase = "https://www.minimaxi.com"

    init(account: String = "default") {
        self.account = account
    }

    func supportedAuthModes() -> [String] { ["api_key"] }

    func fetch(store: CredentialStore) async throws -> UsageSnapshot {
        guard let cred = store.loadCredential(provider: providerId.rawValue, kind: "api_key", account: account),
              let key = cred["key"] as? String else {
            throw AuthRequiredError(message: "MiniMax: please add your API key in Settings")
        }

        var request = URLRequest(url: URL(string: "\(apiBase)/v1/token_plan/remains")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw RuntimeError("MiniMax API request failed")
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let result = parseAPIResponse(data: json)

        return UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "MiniMax Token Plan",
            planKind: planKind,
            windows: result.windows,
            authMode: "api_key"
        )
    }

    struct ParsedResult {
        var windows: [QuotaWindow]
        var raw: [String: Any]
    }

    func parseAPIResponse(data: [String: Any]) -> ParsedResult {
        var windows: [QuotaWindow] = []
        let models = data["model_remains"] as? [[String: Any]] ?? []

        for model in models {
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
                resetAt: endMs.map { Date(timeIntervalSince1970: $0 / 1000) }
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
                resetAt: weeklyEndMs.map { Date(timeIntervalSince1970: $0 / 1000) }
            ))
        }

        return ParsedResult(windows: windows, raw: data)
    }
}
```

**Step 4: Run tests**

Run: `cd gui && swift test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add gui/TokenDashboard/Adapters/MiniMaxAdapter.swift gui/TokenDashboardTests/MiniMaxAdapterTests.swift
git commit -m "feat(gui): add MiniMax adapter"
```

---

### Task 6: Implement MiMo Adapter

**Files:**
- Create: `gui/TokenDashboard/Adapters/MiMoAdapter.swift`
- Test: `gui/TokenDashboardTests/MiMoAdapterTests.swift`

**Step 1: Write failing test**

Create `gui/TokenDashboardTests/MiMoAdapterTests.swift`:

```swift
import Testing
@testable import TokenDashboard

@Suite("MiMoAdapter")
struct MiMoAdapterTests {
    @Test("Parse token plan usage")
    func parseTokenPlan() {
        let adapter = MiMoAdapter(account: "default")
        let data: [String: Any] = [
            "monthUsage": [
                "percent": 0.03,
                "items": [[
                    "name": "month_total_token",
                    "used": 100000,
                    "limit": 4100000000,
                    "percent": 0.03
                ]]
            ],
            "usage": [
                "percent": 0.03,
                "items": [[
                    "name": "plan_total_token",
                    "used": 100000,
                    "limit": 4100000000,
                    "percent": 0.03
                ]]
            ]
        ]
        let windows = adapter.parseTokenPlan(data: data)
        #expect(windows.count == 2)
        #expect(windows[0].kind == .calendarMonth)
        #expect(windows[1].kind == .rollingMonth)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd gui && swift test`
Expected: FAIL

**Step 3: Implement MiMoAdapter**

Create `gui/TokenDashboard/Adapters/MiMoAdapter.swift`:

```swift
import Foundation

final class MiMoAdapter: Adapter {
    let providerId: ProviderId = .mimo
    let displayName = "Xiaomi MiMo"
    let homeURL = "https://platform.xiaomimimo.com/"
    let planKind: PlanKind = .tokenPlan
    let account: String

    private let apiBase = "https://platform.xiaomimimo.com/api/v1"

    init(account: String = "default") {
        self.account = account
    }

    func supportedAuthModes() -> [String] { ["cookie"] }

    func fetch(store: CredentialStore) async throws -> UsageSnapshot {
        guard let cred = store.loadCredential(provider: providerId.rawValue, kind: "cookie", account: account),
              let cookies = cred["cookies"] as? [[String: String]] else {
            throw AuthRequiredError(message: "MiMo: please add your cookie in Settings")
        }

        let cookieHeader = formatCookieHeader(cookies: cookies)
        var headers = [
            "Cookie": cookieHeader,
            "Accept": "application/json",
            "x-timezone": "Asia/Shanghai",
        ]

        var snap = UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "MiMo",
            planKind: planKind,
            windows: [],
            authMode: "cookie"
        )

        // Fetch balance
        do {
            let balanceData = try await apiGet(path: "/balance", headers: headers)
            if let data = balanceData["data"] as? [String: Any] {
                snap.balance = data["balance"] as? Double
                snap.balanceUnit = .cny
            }
        } catch {
            snap.warnings.append("Balance fetch failed: \(error.localizedDescription)")
        }

        // Fetch token plan
        do {
            let planData = try await apiGet(path: "/tokenPlan/usage", headers: headers)
            if let data = planData["data"] as? [String: Any] {
                snap.windows = parseTokenPlan(data: data)
            }
        } catch {
            snap.warnings.append("Token plan fetch failed: \(error.localizedDescription)")
        }

        return snap
    }

    private func apiGet(path: String, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(apiBase)\(path)")!)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw RuntimeError("MiMo API request failed")
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func parseTokenPlan(data: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []

        if let monthUsage = data["monthUsage"] as? [String: Any],
           let items = monthUsage["items"] as? [[String: Any]] {
            for item in items {
                if item["name"] as? String == "month_total_token" {
                    let used = item["used"] as? Double ?? 0
                    let limit = item["limit"] as? Double ?? 0
                    let usedPct = limit > 0 ? used / limit * 100.0 : 0
                    windows.append(QuotaWindow(
                        kind: .calendarMonth,
                        label: "Monthly",
                        used: used,
                        limit: limit,
                        remaining: limit - used,
                        unit: .credits,
                        usedPct: usedPct
                    ))
                }
            }
        }

        if let usage = data["usage"] as? [String: Any],
           let items = usage["items"] as? [[String: Any]] {
            for item in items {
                if item["name"] as? String == "plan_total_token" {
                    let used = item["used"] as? Double ?? 0
                    let limit = item["limit"] as? Double ?? 0
                    let usedPct = limit > 0 ? used / limit * 100.0 : 0
                    windows.append(QuotaWindow(
                        kind: .rollingMonth,
                        label: "Plan Total",
                        used: used,
                        limit: limit,
                        remaining: limit - used,
                        unit: .credits,
                        usedPct: usedPct
                    ))
                }
            }
        }

        return windows
    }

    private func formatCookieHeader(cookies: [[String: String]]) -> String {
        cookies.compactMap { c in
            guard let name = c["name"], let value = c["value"] else { return nil }
            return "\(name)=\(value)"
        }.joined(separator: "; ")
    }
}
```

**Step 4: Run tests**

Run: `cd gui && swift test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add gui/TokenDashboard/Adapters/MiMoAdapter.swift gui/TokenDashboardTests/MiMoAdapterTests.swift
git commit -m "feat(gui): add MiMo adapter"
```

---

### Task 7: Implement Xunfei Adapter

**Files:**
- Create: `gui/TokenDashboard/Adapters/XunfeiAdapter.swift`
- Test: `gui/TokenDashboardTests/XunfeiAdapterTests.swift`

**Step 1: Write failing test**

Create `gui/TokenDashboardTests/XunfeiAdapterTests.swift`:

```swift
import Testing
@testable import TokenDashboard

@Suite("XunfeiAdapter")
struct XunfeiAdapterTests {
    @Test("Parse coding plan usage")
    func parseUsage() {
        let adapter = XunfeiAdapter(account: "default")
        let plan: [String: Any] = [
            "codingPlanUsageDTO": [
                "packageLeft": 17143,
                "packageLimit": 18000,
                "packageUsage": 857,
                "rp5hLimit": 1200,
                "rp5hUsage": 0,
                "rpwLimit": 9000,
                "rpwUsage": 536,
            ],
            "expiresAt": "2026-06-21 10:56:21",
            "name": "专业版",
        ]
        let windows = adapter.parseUsage(plan: plan)
        #expect(windows.count == 3)
        #expect(windows[0].kind == .rolling5h)
        #expect(windows[0].used == 0)
        #expect(windows[1].kind == .rollingWeek)
        #expect(windows[1].used == 536)
        #expect(windows[2].kind == .fixedPeriod)
        #expect(windows[2].used == 857)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd gui && swift test`
Expected: FAIL

**Step 3: Implement XunfeiAdapter**

Create `gui/TokenDashboard/Adapters/XunfeiAdapter.swift`:

```swift
import Foundation

final class XunfeiAdapter: Adapter {
    let providerId: ProviderId = .xunfei
    let displayName = "讯飞星辰 Coding Plan"
    let homeURL = "https://maas.xfyun.cn/"
    let planKind: PlanKind = .codingPlan
    let account: String

    private let apiBase = "https://maas.xfyun.cn/api/v1"

    init(account: String = "default") {
        self.account = account
    }

    func supportedAuthModes() -> [String] { ["cookie"] }

    func fetch(store: CredentialStore) async throws -> UsageSnapshot {
        guard let cred = store.loadCredential(provider: providerId.rawValue, kind: "cookie", account: account),
              let cookies = cred["cookies"] as? [[String: String]] else {
            throw AuthRequiredError(message: "讯飞: please add your cookie in Settings")
        }

        let cookieHeader = cookies.compactMap { c in
            guard let name = c["name"], let value = c["value"] else { return nil }
            return "\(name)=\(value)"
        }.joined(separator: "; ")

        var request = URLRequest(url: URL(string: "\(apiBase)/gpt-finetune/coding-plan/list?page=1&size=6")!)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            throw RuntimeError("Xunfei API request failed")
        }
        guard httpResp.statusCode == 200 else {
            throw RuntimeError("Xunfei API returned \(httpResp.statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard json["code"] as? Int == 0 else {
            throw RuntimeError("Xunfei API error: \(json["message"] ?? "unknown")")
        }

        var snap = UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planKind: planKind,
            windows: [],
            authMode: "cookie"
        )

        if let dataObj = json["data"] as? [String: Any],
           let rows = dataObj["rows"] as? [[String: Any]],
           let plan = rows.first {
            snap.planName = plan["name"] as? String ?? "Coding Plan"
            snap.accountEmail = plan["appId"] as? String
            snap.windows = parseUsage(plan: plan)
        }

        return snap
    }

    func parseUsage(plan: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        guard let usage = plan["codingPlanUsageDTO"] as? [String: Any] else { return windows }

        let rp5hLimit = usage["rp5hLimit"] as? Double ?? 0
        let rp5hUsage = usage["rp5hUsage"] as? Double ?? 0
        if rp5hLimit > 0 {
            windows.append(QuotaWindow(
                kind: .rolling5h,
                label: "5h rolling",
                used: rp5hUsage,
                limit: rp5hLimit,
                remaining: rp5hLimit - rp5hUsage,
                unit: .requests,
                usedPct: rp5hUsage / rp5hLimit * 100.0
            ))
        }

        let rpwLimit = usage["rpwLimit"] as? Double ?? 0
        let rpwUsage = usage["rpwUsage"] as? Double ?? 0
        if rpwLimit > 0 {
            windows.append(QuotaWindow(
                kind: .rollingWeek,
                label: "Weekly",
                used: rpwUsage,
                limit: rpwLimit,
                remaining: rpwLimit - rpwUsage,
                unit: .requests,
                usedPct: rpwUsage / rpwLimit * 100.0
            ))
        }

        let packageLimit = usage["packageLimit"] as? Double ?? 0
        let packageUsage = usage["packageUsage"] as? Double ?? 0
        if packageLimit > 0 {
            var resetAt: Date?
            if let expiresStr = plan["expiresAt"] as? String {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
                fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
                resetAt = fmt.date(from: expiresStr)
            }
            windows.append(QuotaWindow(
                kind: .fixedPeriod,
                label: "Package Total",
                used: packageUsage,
                limit: packageLimit,
                remaining: packageLimit - packageUsage,
                unit: .requests,
                usedPct: packageUsage / packageLimit * 100.0,
                resetAt: resetAt
            ))
        }

        return windows
    }
}
```

**Step 4: Run tests**

Run: `cd gui && swift test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add gui/TokenDashboard/Adapters/XunfeiAdapter.swift gui/TokenDashboardTests/XunfeiAdapterTests.swift
git commit -m "feat(gui): add Xunfei adapter"
```

---

### Task 8: Implement OpenCode Adapter

**Files:**
- Create: `gui/TokenDashboard/Adapters/OpenCodeAdapter.swift`
- Test: `gui/TokenDashboardTests/OpenCodeAdapterTests.swift`

**Step 1: Write failing test**

Create `gui/TokenDashboardTests/OpenCodeAdapterTests.swift`:

```swift
import Testing
@testable import TokenDashboard

@Suite("OpenCodeAdapter")
struct OpenCodeAdapterTests {
    @Test("Parse Chinese HTML response")
    func parseChineseHTML() {
        let adapter = OpenCodeAdapter(account: "default")
        let html = """
        <html><body><div data-slot="usage">
        滚动用量75%重置于2小时30分钟每周用量45%重置于1天14小时每月用量30%重置于18天15小时
        </div></body></html>
        """
        let windows = adapter.parseHTMLResponse(html: html)
        #expect(windows.count == 3)
        #expect(windows[0].kind == .rolling5h)
        #expect(windows[0].usedPct == 75.0)
        #expect(windows[1].kind == .rollingWeek)
        #expect(windows[1].usedPct == 45.0)
        #expect(windows[2].kind == .rollingMonth)
        #expect(windows[2].usedPct == 30.0)
    }

    @Test("Parse English HTML response")
    func parseEnglishHTML() {
        let adapter = OpenCodeAdapter(account: "default")
        let html = """
        <html><body><div data-slot="usage">
        Rolling Usage 60% Resets in 02:55:00Weekly Usage 35% Resets in 1d 17:00:00Monthly Usage 20% Resets in 18d 05:00:00
        </div></body></html>
        """
        let windows = adapter.parseHTMLResponse(html: html)
        #expect(windows.count == 3)
        #expect(windows[0].usedPct == 60.0)
    }

    @Test("No usage div returns empty windows")
    func noUsageDiv() {
        let adapter = OpenCodeAdapter(account: "default")
        let html = "<html><body><p>No data</p></body></html>"
        let windows = adapter.parseHTMLResponse(html: html)
        #expect(windows.isEmpty)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd gui && swift test`
Expected: FAIL

**Step 3: Implement OpenCodeAdapter**

Create `gui/TokenDashboard/Adapters/OpenCodeAdapter.swift`:

```swift
import Foundation
import SwiftSoup

final class OpenCodeAdapter: Adapter {
    let providerId: ProviderId = .opencode
    let displayName = "OpenCode Go"
    let homeURL = "https://opencode.ai/docs/go/"
    let planKind: PlanKind = .codingPlan
    let account: String

    init(account: String = "default") {
        self.account = account
    }

    func supportedAuthModes() -> [String] { ["cookie"] }

    func fetch(store: CredentialStore) async throws -> UsageSnapshot {
        guard let cred = store.loadCredential(provider: providerId.rawValue, kind: "cookie", account: account),
              let cookies = cred["cookies"] as? [[String: String]] else {
            throw AuthRequiredError(message: "OpenCode Go: please add your cookie in Settings")
        }

        let cookieHeader = cookies.compactMap { c in
            guard let name = c["name"], let value = c["value"] else { return nil }
            return "\(name)=\(value)"
        }.joined(separator: "; ")

        let clientHeaders = [
            "Cookie": cookieHeader,
            "Accept": "text/html",
            "User-Agent": "Mozilla/5.0 Chrome/120.0.0.0",
        ]

        // Find workspace ID
        var workspaceId = cred["workspace_id"] as? String
        if workspaceId == nil {
            var req = URLRequest(url: URL(string: "https://opencode.ai/workspace/usage")!)
            req.httpMethod = "GET"
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue("text/html", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            if let html = String(data: data, encoding: .utf8) {
                if let match = html.range(of: #"wrk_[a-zA-Z0-9]+"#, options: .regularExpression) {
                    workspaceId = String(html[match])
                }
            }
        }

        guard let wsId = workspaceId else {
            throw RuntimeError("Could not find workspace ID")
        }

        var request = URLRequest(url: URL(string: "https://opencode.ai/workspace/\(wsId)/go")!)
        request.httpMethod = "GET"
        for (key, value) in clientHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw RuntimeError("OpenCode page fetch failed")
        }

        let html = String(data: data, encoding: .utf8) ?? ""
        let windows = parseHTMLResponse(html: html)

        return UsageSnapshot(
            provider: providerId,
            fetchedAt: Date(),
            planName: "OpenCode Go",
            planKind: planKind,
            windows: windows,
            authMode: "cookie"
        )
    }

    func parseHTMLResponse(html: String) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        let now = Date()

        guard let doc = try? SwiftSoup.parse(html) else { return windows }
        guard let usageDiv = try? doc.select("div[data-slot=usage]").first() else { return windows }
        guard let usageText = try? usageDiv.text() else { return windows }

        let patterns: [(String, WindowKind, String)] = [
            ("滚动用量(\\d+)%重置于(.*?)(?=每周用量|每月用量|$)", .rolling5h, "5h rolling"),
            ("每周用量(\\d+)%重置于(.*?)(?=每月用量|$)", .rollingWeek, "Weekly"),
            ("每月用量(\\d+)%重置于(.*?)$", .rollingMonth, "Monthly"),
            ("Rolling\\s+Usage\\s+(\\d+)%\\s+Resets?\\s+in\\s+(.*?)(?=Weekly|Monthly|$)", .rolling5h, "5h rolling"),
            ("Weekly\\s+Usage\\s+(\\d+)%\\s+Resets?\\s+in\\s+(.*?)(?=Monthly|$)", .rollingWeek, "Weekly"),
            ("Monthly\\s+Usage\\s+(\\d+)%\\s+Resets?\\s+in\\s+(.*?)$", .rollingMonth, "Monthly"),
        ]

        for (pattern, kind, label) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            let range = NSRange(usageText.startIndex..., in: usageText)
            guard let match = regex.firstMatch(in: usageText, range: range) else { continue }

            let pctRange = Range(match.range(at: 1), in: usageText)!
            let pctStr = String(usageText[pctRange])
            guard let usedPct = Double(pctStr) else { continue }

            let resetRange = Range(match.range(at: 2), in: usageText)!
            let resetStr = String(usageText[resetRange])
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
                resetAt: resetAt
            ))
        }

        return windows
    }

    private func parseResetTime(_ timeStr: String) -> Int {
        var totalSeconds = 0

        // Chinese
        if let m = timeStr.range(of: #"(\d+)\s*天"#, options: .regularExpression),
           let n = Int(timeStr[m].filter { $0.isNumber }) {
            totalSeconds += n * 86400
        }
        if let m = timeStr.range(of: #"(\d+)\s*小时"#, options: .regularExpression),
           let n = Int(timeStr[m].filter { $0.isNumber }) {
            totalSeconds += n * 3600
        }
        if let m = timeStr.range(of: #"(\d+)\s*分钟"#, options: .regularExpression),
           let n = Int(timeStr[m].filter { $0.isNumber }) {
            totalSeconds += n * 60
        }

        // English
        if totalSeconds == 0 {
            if let m = timeStr.range(of: #"(\d+)d"#, options: .regularExpression),
               let n = Int(timeStr[m].filter { $0.isNumber }) {
                totalSeconds += n * 86400
            }
            if let m = timeStr.range(of: #"(\d+):(\d+):(\d+)"#, options: .regularExpression) {
                let parts = timeStr[m].split(separator: ":").compactMap { Int($0) }
                if parts.count == 3 {
                    totalSeconds += parts[0] * 3600 + parts[1] * 60 + parts[2]
                }
            }
        }

        return totalSeconds
    }
}
```

**Step 4: Run tests**

Run: `cd gui && swift test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add gui/TokenDashboard/Adapters/OpenCodeAdapter.swift gui/TokenDashboardTests/OpenCodeAdapterTests.swift
git commit -m "feat(gui): add OpenCode adapter with HTML parsing"
```

---

### Task 9: Implement Adapter Registry and SharedDefaults

**Files:**
- Create: `gui/TokenDashboard/Adapters/AdapterRegistry.swift`
- Create: `gui/TokenDashboard/Store/SharedDefaults.swift`
- Test: `gui/TokenDashboardTests/AdapterRegistryTests.swift`

**Step 1: Write failing test**

Create `gui/TokenDashboardTests/AdapterRegistryTests.swift`:

```swift
import Testing
@testable import TokenDashboard

@Suite("AdapterRegistry")
struct AdapterRegistryTests {
    @Test("All 5 providers are registered")
    func allProvidersRegistered() {
        let registry = AdapterRegistry()
        #expect(registry.allProviderIds.count == 5)
    }

    @Test("Get adapter by provider ID")
    func getAdapter() {
        let registry = AdapterRegistry()
        let adapter = registry.adapter(for: .deepseek, account: "default")
        #expect(adapter.providerId == .deepseek)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd gui && swift test`
Expected: FAIL

**Step 3: Implement AdapterRegistry**

Create `gui/TokenDashboard/Adapters/AdapterRegistry.swift`:

```swift
final class AdapterRegistry {
    func adapter(for providerId: ProviderId, account: String = "default") -> Adapter {
        switch providerId {
        case .opencode: return OpenCodeAdapter(account: account)
        case .minimax: return MiniMaxAdapter(account: account)
        case .mimo: return MiMoAdapter(account: account)
        case .xunfei: return XunfeiAdapter(account: account)
        case .deepseek: return DeepSeekAdapter(account: account)
        }
    }

    var allProviderIds: [ProviderId] { ProviderId.allCases }
}
```

**Step 4: Implement SharedDefaults**

Create `gui/TokenDashboard/Store/SharedDefaults.swift`:

```swift
import Foundation

final class SharedDefaults {
    static let appGroupIdentifier = "group.com.token-dashboard"

    private let defaults: UserDefaults?

    init() {
        self.defaults = UserDefaults(suiteName: SharedDefaults.appGroupIdentifier)
    }

    func saveSnapshots(_ snapshots: [UsageSnapshot]) {
        guard let defaults = defaults else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }
        defaults.set(data, forKey: "snapshots")
        defaults.set(Date(), forKey: "lastUpdated")
    }

    func loadSnapshots() -> [UsageSnapshot]? {
        guard let defaults = defaults,
              let data = defaults.data(forKey: "snapshots") else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([UsageSnapshot].self, from: data)
    }

    var lastUpdated: Date? {
        defaults?.object(forKey: "lastUpdated") as? Date
    }
}
```

**Step 5: Run tests**

Run: `cd gui && swift test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add gui/TokenDashboard/Adapters/AdapterRegistry.swift gui/TokenDashboard/Store/SharedDefaults.swift gui/TokenDashboardTests/AdapterRegistryTests.swift
git commit -m "feat(gui): add adapter registry and SharedDefaults"
```

---

### Task 10: Implement UsageFetcher (Data Layer)

**Files:**
- Create: `gui/TokenDashboard/Store/UsageFetcher.swift`

**Step 1: Implement UsageFetcher**

Create `gui/TokenDashboard/Store/UsageFetcher.swift`:

```swift
import Foundation

@MainActor
final class UsageFetcher: ObservableObject {
    @Published var snapshots: [UsageSnapshot] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let registry = AdapterRegistry()
    private let credentialStore = CredentialStore()
    private let sharedDefaults = SharedDefaults()
    private var timer: Timer?

    func fetchAll() async {
        isLoading = true
        lastError = nil

        var results: [UsageSnapshot] = []
        for pid in ProviderId.allCases {
            let adapter = registry.adapter(for: pid, account: "default")
            do {
                let snap = try await adapter.fetch(store: credentialStore)
                results.append(snap)
            } catch let error as AuthRequiredError {
                results.append(UsageSnapshot(
                    provider: pid,
                    fetchedAt: Date(),
                    planKind: adapter.planKind,
                    warnings: [error.message]
                ))
            } catch {
                results.append(UsageSnapshot(
                    provider: pid,
                    fetchedAt: Date(),
                    planKind: adapter.planKind,
                    warnings: ["fetch failed: \(error.localizedDescription)"]
                ))
            }
        }

        snapshots = results
        sharedDefaults.saveSnapshots(results)
        isLoading = false
    }

    func startPeriodicRefresh(intervalSeconds: Int = 60) {
        stopPeriodicRefresh()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAll()
            }
        }
        Task { await fetchAll() }
    }

    func stopPeriodicRefresh() {
        timer?.invalidate()
        timer = nil
    }

    var mostConstrainedPct: Double? {
        let allPcts = snapshots.compactMap { $0.primaryWindow()?.usedPct }
        return allPcts.max()
    }
}
```

**Step 2: Commit**

```bash
git add gui/TokenDashboard/Store/UsageFetcher.swift
git commit -m "feat(gui): add UsageFetcher with periodic refresh"
```

---

### Task 11: Build UI — UsageBarView and ProviderCardView

**Files:**
- Create: `gui/TokenDashboard/Views/UsageBarView.swift`
- Create: `gui/TokenDashboard/Views/ProviderCardView.swift`

**Step 1: Implement UsageBarView**

Create `gui/TokenDashboard/Views/UsageBarView.swift`:

```swift
import SwiftUI

struct UsageBarView: View {
    let usedPct: Double?
    let width: CGFloat = 200

    var body: some View {
        if let pct = usedPct {
            let clamped = max(0, min(100, pct))
            let color: Color = {
                if clamped >= 90 { return .red }
                if clamped >= 70 { return .yellow }
                return .green
            }()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(clamped / 100), height: 8)
                }
            }
            .frame(height: 8)
            .overlay(alignment: .trailing) {
                Text(String(format: "%.1f%%", clamped))
                    .font(.caption2)
                    .foregroundColor(color)
                    .padding(.leading, 4)
            }
        } else {
            Text("unbounded")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
```

**Step 2: Implement ProviderCardView**

Create `gui/TokenDashboard/Views/ProviderCardView.swift`:

```swift
import SwiftUI

struct ProviderCardView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.provider.rawValue.uppercased())
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if let planName = snapshot.planName {
                    Text(planName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if snapshot.windows.isEmpty && snapshot.balance == nil {
                if let warning = snapshot.warnings.first {
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("No data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(snapshot.windows) { window in
                    HStack {
                        Text(window.label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        UsageBarView(usedPct: window.usedPct)
                    }
                    if let resetAt = window.resetAt {
                        Text("Resets \(resetAt, style: .timer)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 80)
                    }
                }

                if let balance = snapshot.balance, let unit = snapshot.balanceUnit {
                    HStack {
                        Text("balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text(String(format: "%.2f %@", balance, unit.rawValue))
                            .font(.caption)
                    }
                }
            }

            ForEach(snapshot.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

**Step 3: Commit**

```bash
git add gui/TokenDashboard/Views/
git commit -m "feat(gui): add UsageBarView and ProviderCardView"
```

---

### Task 12: Build UI — MenuBar and Popover

**Files:**
- Create: `gui/TokenDashboard/MenuBar/MenuBarView.swift`
- Modify: `gui/TokenDashboard/TokenDashboardApp.swift`

**Step 1: Implement MenuBarView**

Create `gui/TokenDashboard/MenuBar/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var fetcher: UsageFetcher
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token Dashboard")
                .font(.headline)
                .padding(.bottom, 4)

            if fetcher.isLoading && fetcher.snapshots.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(fetcher.snapshots) { snap in
                    ProviderCardView(snapshot: snap)
                }
            }

            Divider()

            HStack {
                if let lastUpdated = fetcher.snapshots.first?.fetchedAt {
                    Text("Updated \(lastUpdated, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    Task { await fetcher.fetchAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}
```

**Step 2: Update app entry point**

Replace `gui/TokenDashboard/TokenDashboardApp.swift`:

```swift
import SwiftUI

@main
struct TokenDashboardApp: App {
    @StateObject private var fetcher = UsageFetcher()
    @StateObject private var config = ConfigStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(fetcher: fetcher)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(fetcher: fetcher, config: config)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if let pct = fetcher.mostConstrainedPct {
            let clamped = max(0, min(100, pct))
            Text(String(format: "%.0f%%", clamped))
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }

    init() {
        let fetcher = UsageFetcher()
        _fetcher = StateObject(wrappedValue: fetcher)
        let config = ConfigStore()
        _config = StateObject(wrappedValue: config)
    }
}
```

**Step 3: Commit**

```bash
git add gui/TokenDashboard/MenuBar/ gui/TokenDashboard/TokenDashboardApp.swift
git commit -m "feat(gui): add menu bar popover with provider cards"
```

---

### Task 13: Build UI — Settings Window

**Files:**
- Create: `gui/TokenDashboard/Views/SettingsView.swift`

**Step 1: Implement SettingsView**

Create `gui/TokenDashboard/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var fetcher: UsageFetcher
    @ObservedObject var config: ConfigStore
    private let credentialStore = CredentialStore()

    var body: some View {
        TabView {
            CredentialsTab(credentialStore: credentialStore)
                .tabItem { Label("Credentials", systemImage: "key") }

            GeneralTab(config: config, fetcher: fetcher)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 500, height: 400)
    }
}

struct CredentialsTab: View {
    let credentialStore: CredentialStore
    @State private var selectedProvider: ProviderId = .deepseek
    @State private var apiKeyInput = ""
    @State private var cookieInput = ""
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Provider", selection: $selectedProvider) {
                ForEach(ProviderId.allCases, id: \.self) { pid in
                    Text(pid.rawValue).tag(pid)
                }
            }

            let adapter = AdapterRegistry().adapter(for: selectedProvider)
            let authModes = adapter.supportedAuthModes()

            if authModes.contains("api_key") {
                SecureField("API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                Button("Save API Key") {
                    saveAPIKey()
                }
            }

            if authModes.contains("cookie") {
                TextField("Cookie (e.g. auth=xxx; ...)", text: $cookieInput)
                    .textFieldStyle(.roundedBorder)
                Button("Save Cookie") {
                    saveCookie()
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Spacer()

            Divider()
            Button("Migrate from CLI credentials.json") {
                migrateLegacy()
            }
        }
        .padding()
    }

    private func saveAPIKey() {
        let cred: [String: Any] = ["key": apiKeyInput]
        do {
            try credentialStore.saveCredential(provider: selectedProvider.rawValue, kind: "api_key", account: "default", value: cred)
            statusMessage = "Saved!"
            apiKeyInput = ""
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func saveCookie() {
        var cookies: [[String: String]] = []
        for part in cookieInput.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let eq = trimmed.firstIndex(of: "=") {
                let name = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                cookies.append(["name": name, "value": value])
            }
        }
        let cred: [String: Any] = ["cookies": cookies]
        do {
            try credentialStore.saveCredential(provider: selectedProvider.rawValue, kind: "cookie", account: "default", value: cred)
            statusMessage = "Saved \(cookies.count) cookies!"
            cookieInput = ""
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func migrateLegacy() {
        do {
            try credentialStore.migrateFromLegacy()
            statusMessage = "Migration complete!"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}

struct GeneralTab: View {
    @ObservedObject var config: ConfigStore
    @ObservedObject var fetcher: UsageFetcher

    var body: some View {
        Form {
            Stepper("Refresh interval: \(config.refreshInterval)s", value: $config.refreshInterval, in: 10...300, step: 10)
            Stepper("Warn threshold: \(config.warnPct)%", value: $config.warnPct, in: 10...100, step: 5)
            Stepper("Critical threshold: \(config.criticalPct)%", value: $config.criticalPct, in: 10...100, step: 5)

            Button("Apply & Restart Refresh") {
                fetcher.stopPeriodicRefresh()
                fetcher.startPeriodicRefresh(intervalSeconds: config.refreshInterval)
            }
        }
        .padding()
    }
}
```

**Step 2: Commit**

```bash
git add gui/TokenDashboard/Views/SettingsView.swift
git commit -m "feat(gui): add Settings window with credential and general tabs"
```

---

### Task 14: Wire Up App Lifecycle and Build

**Files:**
- Modify: `gui/TokenDashboard/TokenDashboardApp.swift` (add onAppear)

**Step 1: Update app to start fetching on launch**

Add `.onAppear` to the `MenuBarView`:

In `gui/TokenDashboard/MenuBar/MenuBarView.swift`, add to the VStack:

```swift
.onAppear {
    fetcher.startPeriodicRefresh(intervalSeconds: 60)
}
```

**Step 2: Build and run**

Run: `cd gui && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add gui/
git commit -m "feat(gui): wire up app lifecycle with periodic refresh"
```

---

### Task 15: Implement ControlWidget Extension (macOS 26+)

**Files:**
- Create: `gui/TokenDashboardControlWidget/ControlWidgetEntry.swift`
- Create: `gui/TokenDashboardControlWidget/TokenDashboardControlWidget.swift`

> Note: This requires macOS 26 SDK and Xcode 26+. The ControlWidget target needs to be added as a separate target in the Xcode project. For SPM, this would be a separate package or manual configuration.

**Step 1: Create ControlWidget entry**

Create `gui/TokenDashboardControlWidget/ControlWidgetEntry.swift`:

```swift
import WidgetKit
import SwiftUI

struct TokenDashboardEntry: TimelineEntry {
    let date: Date
    let providerName: String
    let usedPct: Double
}

struct TokenDashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> TokenDashboardEntry {
        TokenDashboardEntry(date: Date(), providerName: "—", usedPct: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenDashboardEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenDashboardEntry>) -> Completion) {
        let entry = loadEntry()
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300)))
        completion(timeline)
    }

    private func loadEntry() -> TokenDashboardEntry {
        guard let defaults = UserDefaults(suiteName: "group.com.token-dashboard"),
              let data = defaults.data(forKey: "snapshots") else {
            return TokenDashboardEntry(date: Date(), providerName: "—", usedPct: 0)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshots = try? decoder.decode([UsageSnapshot].self, from: data) else {
            return TokenDashboardEntry(date: Date(), providerName: "—", usedPct: 0)
        }

        let mostConstrained = snapshots.compactMap { snap -> (String, Double)? in
            guard let w = snap.primaryWindow(), let pct = w.usedPct else { return nil }
            return (snap.provider.rawValue, pct)
        }.max(by: { $0.1 < $1.1 })

        if let mc = mostConstrained {
            return TokenDashboardEntry(date: Date(), providerName: mc.0, usedPct: mc.1)
        }
        return TokenDashboardEntry(date: Date(), providerName: "—", usedPct: 0)
    }
}
```

**Step 2: Create ControlWidget**

Create `gui/TokenDashboardControlWidget/TokenDashboardControlWidget.swift`:

```swift
import SwiftUI
import WidgetKit

@available(macOS 26, *)
struct TokenDashboardControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.token-dashboard.usage") {
            ControlWidgetToggle("Token Usage") {
                TokenDashboardControlView()
            } action: { _ in
            }
        }
    }
}

@available(macOS 26, *)
struct TokenDashboardControlView: View {
    let entry: TokenDashboardEntry

    var body: some View {
        VStack(spacing: 4) {
            Text(entry.providerName.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
            Text(String(format: "%.0f%%", entry.usedPct))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(colorForPct(entry.usedPct))
            ProgressView(value: entry.usedPct, total: 100)
                .tint(colorForPct(entry.usedPct))
        }
    }

    private func colorForPct(_ pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 70 { return .yellow }
        return .green
    }
}
```

**Step 3: Commit**

```bash
git add gui/TokenDashboardControlWidget/
git commit -m "feat(gui): add ControlWidget extension for macOS 26+ Control Center"
```

---

### Task 16: Final Integration Test and Cleanup

**Files:**
- Modify: various files for any compilation fixes

**Step 1: Full build**

Run: `cd gui && swift build`
Expected: Build succeeds with no warnings

**Step 2: Run all tests**

Run: `cd gui && swift test`
Expected: All tests pass

**Step 3: Lint with swift-format (if available)**

Run: `cd gui && swift-format lint --recursive TokenDashboard/`
Expected: No formatting issues

**Step 4: Final commit**

```bash
git add gui/
git commit -m "feat(gui): complete macOS GUI app with menu bar, adapters, and ControlWidget"
```
