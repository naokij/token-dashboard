import XCTest
@testable import TokenDashboard

final class MiMoAdapterTests: XCTestCase {

    private var adapter: MiMoAdapter!

    override func setUp() {
        super.setUp()
        adapter = MiMoAdapter()
    }

    func testParseTokenPlanWithMonthAndPlanWindows() {
        let data: [String: Any] = [
            "monthUsage": [
                "percent": 0.03,
                "items": [
                    [
                        "name": "month_total_token",
                        "used": 100000,
                        "limit": 4100000000,
                        "percent": 0.03,
                    ]
                ]
            ],
            "usage": [
                "percent": 0.03,
                "items": [
                    [
                        "name": "plan_total_token",
                        "used": 100000,
                        "limit": 4100000000,
                        "percent": 0.03,
                    ]
                ]
            ]
        ]

        let windows = adapter.parseTokenPlan(data)
        XCTAssertEqual(windows.count, 2)

        let monthly = windows[0]
        XCTAssertEqual(monthly.kind, .calendarMonth)
        XCTAssertEqual(monthly.label, "Monthly")
        XCTAssertEqual(monthly.used, 100000.0)
        XCTAssertEqual(monthly.limit, 4100000000.0)
        XCTAssertEqual(monthly.unit, .credits)
        XCTAssertNotNil(monthly.usedPct)
        XCTAssertLessThan(monthly.usedPct!, 1.0)

        let planTotal = windows[1]
        XCTAssertEqual(planTotal.kind, .rollingMonth)
        XCTAssertEqual(planTotal.label, "Plan Total")
        XCTAssertEqual(planTotal.used, 100000.0)
        XCTAssertEqual(planTotal.limit, 4100000000.0)
        XCTAssertEqual(planTotal.unit, .credits)
    }

    func testParseEmptyTokenPlan() {
        let data: [String: Any] = [:]
        let windows = adapter.parseTokenPlan(data)
        XCTAssertTrue(windows.isEmpty)
    }

    func testParseOnlyMonthUsage() {
        let data: [String: Any] = [
            "monthUsage": [
                "items": [
                    [
                        "name": "month_total_token",
                        "used": 50000,
                        "limit": 1000000,
                    ]
                ]
            ]
        ]

        let windows = adapter.parseTokenPlan(data)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .calendarMonth)
    }

    func testNoAuthRaisesError() {
        let store = CredentialStore()
        XCTAssertFalse(adapter.isConfigured(store: store))
    }

    func testProviderMeta() {
        XCTAssertEqual(adapter.providerId, .mimo)
        XCTAssertEqual(adapter.displayName, "Xiaomi MiMo")
        XCTAssertEqual(adapter.planKind, .tokenPlan)
        XCTAssertEqual(adapter.supportedAuthModes(), ["cookie"])
    }
}
