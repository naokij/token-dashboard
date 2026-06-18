import XCTest
@testable import TokenDashboard

final class XunfeiAdapterTests: XCTestCase {

    private var adapter: XunfeiAdapter!

    override func setUp() {
        super.setUp()
        adapter = XunfeiAdapter()
    }

    func testParseUsageWith3Windows() {
        let plan: [String: Any] = [
            "name": "专业版",
            "appId": "test-app-id",
            "codingPlanUsageDTO": [
                "rp5hLimit": 1200,
                "rp5hUsage": 0,
                "rpwLimit": 9000,
                "rpwUsage": 536,
                "packageLimit": 18000,
                "packageUsage": 857,
            ],
            "expiresAt": "2026-06-21 10:56:21",
        ]

        let windows = adapter.parseUsage(plan)
        XCTAssertEqual(windows.count, 3)

        let rolling5h = windows[0]
        XCTAssertEqual(rolling5h.kind, .rolling5h)
        XCTAssertEqual(rolling5h.label, "5h rolling")
        XCTAssertEqual(rolling5h.used, 0.0)
        XCTAssertEqual(rolling5h.limit, 1200.0)
        XCTAssertEqual(rolling5h.unit, .requests)
        XCTAssertEqual(rolling5h.usedPct, 0.0)

        let weekly = windows[1]
        XCTAssertEqual(weekly.kind, .rollingWeek)
        XCTAssertEqual(weekly.label, "Weekly")
        XCTAssertEqual(weekly.used, 536.0)
        XCTAssertEqual(weekly.limit, 9000.0)
        XCTAssertEqual(weekly.unit, .requests)
        XCTAssertGreaterThan(weekly.usedPct!, 0)

        let package = windows[2]
        XCTAssertEqual(package.kind, .fixedPeriod)
        XCTAssertEqual(package.label, "Package Total")
        XCTAssertEqual(package.used, 857.0)
        XCTAssertEqual(package.limit, 18000.0)
        XCTAssertEqual(package.unit, .requests)
        XCTAssertNotNil(package.resetAt)
    }

    func testParseUsageWithZeroLimits() {
        let plan: [String: Any] = [
            "codingPlanUsageDTO": [
                "rp5hLimit": 0,
                "rp5hUsage": 0,
                "rpwLimit": 0,
                "rpwUsage": 0,
                "packageLimit": 0,
                "packageUsage": 0,
            ]
        ]

        let windows = adapter.parseUsage(plan)
        XCTAssertTrue(windows.isEmpty)
    }

    func testParseExpiryDate() {
        let plan: [String: Any] = [
            "codingPlanUsageDTO": [
                "rp5hLimit": 100,
                "rp5hUsage": 10,
                "rpwLimit": 0,
                "rpwUsage": 0,
                "packageLimit": 1000,
                "packageUsage": 100,
            ],
            "expiresAt": "2026-06-21 10:56:21",
        ]

        let windows = adapter.parseUsage(plan)
        XCTAssertEqual(windows.count, 2)
        let package = windows[1]
        XCTAssertEqual(package.kind, .fixedPeriod)
        XCTAssertNotNil(package.resetAt)
    }

    func testProviderMeta() {
        XCTAssertEqual(adapter.providerId, .xunfei)
        XCTAssertEqual(adapter.displayName, "讯飞星辰 Coding Plan")
        XCTAssertEqual(adapter.planKind, .codingPlan)
        XCTAssertEqual(adapter.supportedAuthModes(), ["cookie"])
    }
}
