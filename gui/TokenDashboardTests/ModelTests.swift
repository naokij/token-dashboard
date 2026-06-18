import XCTest
@testable import TokenDashboard

final class ModelTests: XCTestCase {

    // MARK: - ProviderId

    func testProviderIdAllCases() {
        let expected: [(ProviderId, String)] = [
            (.opencode, "opencode"),
            (.minimax, "minimax"),
            (.mimo, "mimo"),
            (.xunfei, "xunfei"),
            (.deepseek, "deepseek"),
        ]
        XCTAssertEqual(ProviderId.allCases.count, 5)
        for (value, raw) in expected {
            XCTAssertEqual(value.rawValue, raw)
        }
    }

    // MARK: - QuotaWindow usedPct

    func testQuotaWindowUsedPctDecoding() throws {
        let json = """
        {
            "kind": "rolling_5h",
            "label": "5-hour rolling",
            "used": 42.5,
            "limit": 100,
            "remaining": 57.5,
            "unit": "credits",
            "used_pct": 42.5,
            "reset_at": 795000000.0,
            "raw": {}
        }
        """
        let data = json.data(using: .utf8)!
        let window = try JSONDecoder().decode(QuotaWindow.self, from: data)
        XCTAssertEqual(window.usedPct, 42.5)
        XCTAssertEqual(window.kind, .rolling5h)
        XCTAssertEqual(window.used, 42.5)
        XCTAssertEqual(window.limit, 100)
        XCTAssertEqual(window.remaining, 57.5)
        XCTAssertEqual(window.unit, .credits)
    }

    func testQuotaWindowUsedPctEncoding() throws {
        let window = QuotaWindow(
            kind: .rolling5h,
            label: "5h",
            used: 50,
            limit: 100,
            remaining: 50,
            unit: .credits,
            usedPct: 50.0,
            raw: [:]
        )
        let data = try JSONEncoder().encode(window)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["used_pct"] as? Double, 50.0)
        XCTAssertNil(dict["usedPct"])
    }

    // MARK: - UsageSnapshot.primaryWindow()

    func testPrimaryWindowReturnsHighestUsedPct() {
        let snapshot = UsageSnapshot(
            provider: .opencode,
            fetchedAt: Date(),
            planKind: .codingPlan,
            windows: [
                QuotaWindow(kind: .rolling5h, label: "5h", used: 30, limit: 100, unit: .credits, usedPct: 30, raw: [:]),
                QuotaWindow(kind: .rollingMonth, label: "month", used: 80, limit: 100, unit: .credits, usedPct: 80, raw: [:]),
                QuotaWindow(kind: .rollingWeek, label: "week", used: 50, limit: 100, unit: .credits, usedPct: 50, raw: [:]),
            ]
        )
        XCTAssertEqual(snapshot.primaryWindow()?.kind, .rollingMonth)
        XCTAssertEqual(snapshot.primaryWindow()?.usedPct, 80)
    }

    func testPrimaryWindowIgnoresUnbounded() {
        let snapshot = UsageSnapshot(
            provider: .deepseek,
            fetchedAt: Date(),
            planKind: .payAsYouGo,
            windows: [
                QuotaWindow(kind: .balance, label: "balance", used: 5.0, limit: nil, unit: .cny, usedPct: nil, raw: [:]),
                QuotaWindow(kind: .rolling5h, label: "5h", used: 10, limit: 50, unit: .tokens, usedPct: 20, raw: [:]),
            ]
        )
        XCTAssertEqual(snapshot.primaryWindow()?.kind, .rolling5h)
    }

    func testPrimaryWindowReturnsNilWhenNoBounded() {
        let snapshot = UsageSnapshot(
            provider: .deepseek,
            fetchedAt: Date(),
            planKind: .payAsYouGo,
            windows: [
                QuotaWindow(kind: .balance, label: "balance", used: 5.0, limit: nil, unit: .cny, raw: [:]),
            ]
        )
        XCTAssertNil(snapshot.primaryWindow())
    }

    // MARK: - UsageSnapshot CodingKeys

    func testUsageSnapshotSnakeCaseEncoding() throws {
        let snapshot = UsageSnapshot(
            provider: .minimax,
            fetchedAt: Date(timeIntervalSince1970: 1718700000),
            planName: "Plus",
            planKind: .tokenPlan,
            balance: 10.5,
            balanceUnit: .cny,
            accountEmail: "test@example.com",
            accountName: "default",
            authMode: "api",
            warnings: [],
            raw: [:]
        )
        let data = try JSONEncoder().encode(snapshot)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(dict["fetched_at"])
        XCTAssertNotNil(dict["plan_name"])
        XCTAssertNotNil(dict["plan_kind"])
        XCTAssertNotNil(dict["balance_unit"])
        XCTAssertNotNil(dict["account_email"])
        XCTAssertNotNil(dict["account_name"])
        XCTAssertNotNil(dict["auth_mode"])
        XCTAssertNil(dict["fetchedAt"])
        XCTAssertNil(dict["planName"])
        XCTAssertNil(dict["planKind"])
    }

    // MARK: - Round-trip JSON compatibility

    func testUsageSnapshotRoundTrip() throws {
        let json = """
        {
            "provider": "opencode",
            "fetched_at": 795000000.0,
            "plan_name": "Go",
            "plan_kind": "coding_plan",
            "balance": null,
            "balance_unit": null,
            "windows": [
                {
                    "kind": "rolling_5h",
                    "label": "5-hour rolling",
                    "used": 42.0,
                    "limit": 100.0,
                    "remaining": 58.0,
                    "unit": "credits",
                    "used_pct": 42.0,
                    "reset_at": 795018000.0,
                    "period_start": null,
                    "period_end": null,
                    "raw": {}
                }
            ],
            "account_email": "user@example.com",
            "account_name": "default",
            "auth_mode": "api",
            "warnings": [],
            "raw": {}
        }
        """
        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(snapshot.provider, .opencode)
        XCTAssertEqual(snapshot.planName, "Go")
        XCTAssertEqual(snapshot.planKind, .codingPlan)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPct, 42.0)
        XCTAssertEqual(snapshot.primaryWindow()?.usedPct, 42.0)
    }
}
