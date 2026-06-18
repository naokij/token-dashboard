import XCTest
@testable import TokenDashboard

final class OpenCodeAdapterTests: XCTestCase {

    private var adapter: OpenCodeAdapter!

    override func setUp() {
        super.setUp()
        adapter = OpenCodeAdapter()
    }

    func testParseChineseHTML() {
        let html = """
        <html><body><div data-slot="usage">滚动用量20%重置于5 小时 30 分钟每周用量5%重置于1 天 14 小时每月用量3%重置于18 天 15 小时</div></body></html>
        """

        let windows = adapter.parseHTMLResponse(html)
        XCTAssertEqual(windows.count, 3)

        XCTAssertEqual(windows[0].kind, .rolling5h)
        XCTAssertEqual(windows[0].label, "5h rolling")
        XCTAssertEqual(windows[0].usedPct, 20.0)
        XCTAssertEqual(windows[0].unit, .percent)
        XCTAssertNotNil(windows[0].resetAt)

        XCTAssertEqual(windows[1].kind, .rollingWeek)
        XCTAssertEqual(windows[1].label, "Weekly")
        XCTAssertEqual(windows[1].usedPct, 5.0)
        XCTAssertNotNil(windows[1].resetAt)

        XCTAssertEqual(windows[2].kind, .rollingMonth)
        XCTAssertEqual(windows[2].label, "Monthly")
        XCTAssertEqual(windows[2].usedPct, 3.0)
        XCTAssertNotNil(windows[2].resetAt)
    }

    func testParseEnglishHTML() {
        let html = """
        <html><body><div data-slot="usage">
        <p>Rolling Usage 42% Resets in 02:55:00</p>
        <p>Weekly Usage 10% Resets in 1d 17:00:00</p>
        <p>Monthly Usage 8% Resets in 15d 00:00:00</p>
        </div></body></html>
        """

        let windows = adapter.parseHTMLResponse(html)
        XCTAssertEqual(windows.count, 3)

        XCTAssertEqual(windows[0].kind, .rolling5h)
        XCTAssertEqual(windows[0].usedPct, 42.0)
        XCTAssertNotNil(windows[0].resetAt)

        XCTAssertEqual(windows[1].kind, .rollingWeek)
        XCTAssertEqual(windows[1].usedPct, 10.0)
        XCTAssertNotNil(windows[1].resetAt)

        XCTAssertEqual(windows[2].kind, .rollingMonth)
        XCTAssertEqual(windows[2].usedPct, 8.0)
        XCTAssertNotNil(windows[2].resetAt)
    }

    func testNoUsageDivReturnsEmpty() {
        let html = "<html><body><div>No usage here</div></body></html>"
        let windows = adapter.parseHTMLResponse(html)
        XCTAssertTrue(windows.isEmpty)
    }

    func testParseResetTimeChinese() {
        XCTAssertEqual(adapter.parseResetTime("5 小时 30 分钟"), 5 * 3600 + 30 * 60)
        XCTAssertEqual(adapter.parseResetTime("1 天 14 小时"), 86400 + 14 * 3600)
        XCTAssertEqual(adapter.parseResetTime("18 天 15 小时"), 18 * 86400 + 15 * 3600)
    }

    func testParseResetTimeEnglish() {
        XCTAssertEqual(adapter.parseResetTime("02:55:00"), 2 * 3600 + 55 * 60)
        XCTAssertEqual(adapter.parseResetTime("1d 17:00:00"), 86400 + 17 * 3600)
    }

    func testParseResetTimeZero() {
        XCTAssertEqual(adapter.parseResetTime(""), 0)
    }

    func testNoAuthRaisesError() {
        let store = CredentialStore()
        XCTAssertFalse(adapter.isConfigured(store: store))
    }

    func testProviderMeta() {
        XCTAssertEqual(adapter.providerId, .opencode)
        XCTAssertEqual(adapter.displayName, "OpenCode Go")
        XCTAssertEqual(adapter.planKind, .codingPlan)
        XCTAssertEqual(adapter.supportedAuthModes(), ["cookie"])
    }
}
