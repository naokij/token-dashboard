import XCTest
@testable import TokenDashboard

final class VolcArkAdapterTests: XCTestCase {

    private var adapter: VolcArkAdapter!

    override func setUp() {
        super.setUp()
        adapter = VolcArkAdapter()
    }

    func testParse4Windows() {
        let data: [String: Any] = [
            "PlanType": "medium",
            "AFPFiveHour": [
                "Quota": 10000,
                "Used": 1072.2356,
                "SubscribeTime": 1782182294000,
                "ResetTime": 1782200294000,
            ],
            "AFPDaily": [
                "Quota": 50000,
                "Used": 0,
                "SubscribeTime": 1781712000000,
                "ResetTime": 1781798400000,
            ],
            "AFPWeekly": [
                "Quota": 35000,
                "Used": 1072.2356,
                "SubscribeTime": 1782057600000,
                "ResetTime": 1782662400000,
            ],
            "AFPMonthly": [
                "Quota": 100000,
                "Used": 1072.2356,
                "SubscribeTime": 1777939200000,
                "ResetTime": 1780531200000,
            ],
        ]

        let windows = adapter.parseWindows(data)
        XCTAssertEqual(windows.count, 4)

        // 5h
        XCTAssertEqual(windows[0].kind, .rolling5h)
        XCTAssertEqual(windows[0].label, "AFP (5h)")
        XCTAssertEqual(windows[0].used, 1072.2356)
        XCTAssertEqual(windows[0].limit, 10000)
        XCTAssertEqual(windows[0].unit, .credits)
        XCTAssertEqual(windows[0].usedPct ?? 0, 10.722356, accuracy: 0.001)
        XCTAssertNotNil(windows[0].resetAt)

        // day · vision
        XCTAssertEqual(windows[1].kind, .rollingDay)
        XCTAssertEqual(windows[1].label, "AFP (day · vision)")
        XCTAssertEqual(windows[1].used, 0)
        XCTAssertEqual(windows[1].limit, 50000)
        XCTAssertEqual(windows[1].usedPct ?? -1, 0)

        // week
        XCTAssertEqual(windows[2].kind, .rollingWeek)
        XCTAssertEqual(windows[2].unit, .credits)

        // month
        XCTAssertEqual(windows[3].kind, .rollingMonth)
    }

    func testParseEmptyWindows() {
        let windows = adapter.parseWindows([:])
        XCTAssertTrue(windows.isEmpty)
    }

    func testParsePartialWindows() {
        let data: [String: Any] = [
            "PlanType": "small",
            "AFPFiveHour": [
                "Quota": 5000,
                "Used": 100,
                "SubscribeTime": 1782182294000,
                "ResetTime": 1782200294000,
            ],
        ]
        let windows = adapter.parseWindows(data)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .rolling5h)
    }

    func testProviderMeta() {
        XCTAssertEqual(adapter.providerId, .volcark)
        XCTAssertEqual(adapter.displayName, "Volc Ark Agent Plan")
        XCTAssertEqual(adapter.planKind, .tokenPlan)
        XCTAssertEqual(adapter.supportedAuthModes(), ["api_key"])
    }

    func testSignRequestProducedValidOutput() {
        let result = adapter.signRequest(
            ak: "AKTEST",
            sk: "SKTEST",
            action: "GetAFPUsage",
            body: "{}"
        )
        XCTAssertFalse(result.headers.isEmpty)
        XCTAssertTrue(result.url.contains("open.volcengineapi.com"))
        XCTAssertTrue(result.url.contains("Action=GetAFPUsage"))
        XCTAssertNotNil(result.headers["Authorization"])
        XCTAssertNotNil(result.headers["X-Date"])
        XCTAssertNotNil(result.headers["X-Content-Sha256"])
        // Verify Authorization format
        let auth = result.headers["Authorization"]!
        XCTAssertTrue(auth.hasPrefix("HMAC-SHA256 Credential="))
        XCTAssertTrue(auth.contains("SignedHeaders=content-type;host;x-content-sha256;x-date"))
        XCTAssertTrue(auth.contains("Signature="))
    }
}