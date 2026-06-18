import XCTest
@testable import TokenDashboard

final class MiniMaxAdapterTests: XCTestCase {

    private var adapter: MiniMaxAdapter!

    override func setUp() {
        super.setUp()
        adapter = MiniMaxAdapter()
    }

    func testParse5hAndWeeklyWindows() {
        let data: [String: Any] = [
            "model_remains": [
                [
                    "model_name": "general",
                    "end_time": 1780729200000.0,
                    "current_interval_remaining_percent": 80.0,
                    "weekly_end_time": 1780848000000.0,
                    "current_weekly_remaining_percent": 95.0,
                ]
            ]
        ]

        let result = adapter.parseAPIResponse(data)
        XCTAssertEqual(result.windows.count, 2)

        let rolling5h = result.windows[0]
        XCTAssertEqual(rolling5h.kind, .rolling5h)
        XCTAssertEqual(rolling5h.label, "general (5h)")
        XCTAssertEqual(rolling5h.usedPct, 20.0)
        XCTAssertEqual(rolling5h.remaining, 80.0)
        XCTAssertEqual(rolling5h.limit, 100.0)
        XCTAssertEqual(rolling5h.unit, .percent)
        XCTAssertNotNil(rolling5h.resetAt)

        let weekly = result.windows[1]
        XCTAssertEqual(weekly.kind, .rollingWeek)
        XCTAssertEqual(weekly.label, "general (week)")
        XCTAssertEqual(weekly.usedPct, 5.0)
        XCTAssertEqual(weekly.remaining, 95.0)
        XCTAssertEqual(weekly.limit, 100.0)
        XCTAssertEqual(weekly.unit, .percent)
        XCTAssertNotNil(weekly.resetAt)
    }

    func testParseEmptyModelRemains() {
        let data: [String: Any] = [
            "model_remains": [] as [Any]
        ]

        let result = adapter.parseAPIResponse(data)
        XCTAssertTrue(result.windows.isEmpty)
    }

    func testNoAuthRaisesError() {
        let store = CredentialStore()
        for mode in adapter.supportedAuthModes() {
            try? store.deleteCredential(provider: adapter.providerId.rawValue, kind: mode, account: "default")
        }
        XCTAssertFalse(adapter.isConfigured(store: store))
    }

    func testProviderMeta() {
        XCTAssertEqual(adapter.providerId, .minimax)
        XCTAssertEqual(adapter.displayName, "MiniMax Token Plan")
        XCTAssertEqual(adapter.planKind, .tokenPlan)
        XCTAssertEqual(adapter.supportedAuthModes(), ["api_key"])
    }
}
