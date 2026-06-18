import XCTest
@testable import TokenDashboard

final class DeepSeekAdapterTests: XCTestCase {

    private var adapter: DeepSeekAdapter!

    override func setUp() {
        super.setUp()
        adapter = DeepSeekAdapter()
    }

    func testParseCNYBalance() {
        let data: [String: Any] = [
            "is_available": true,
            "balance_infos": [
                [
                    "currency": "CNY",
                    "total_balance": "110.00",
                    "granted_balance": "10.00",
                    "topped_up_balance": "100.00",
                ]
            ]
        ]

        let result = adapter.parseResponse(data)
        XCTAssertEqual(result.balance, 110.0)
        XCTAssertEqual(result.balanceUnit, .cny)
    }

    func testParseUSDBalance() {
        let data: [String: Any] = [
            "is_available": true,
            "balance_infos": [
                [
                    "currency": "USD",
                    "total_balance": "50.00",
                    "granted_balance": "0.00",
                    "topped_up_balance": "50.00",
                ]
            ]
        ]

        let result = adapter.parseResponse(data)
        XCTAssertEqual(result.balance, 50.0)
        XCTAssertEqual(result.balanceUnit, .usd)
    }

    func testParseCNYPreferredOverUSD() {
        let data: [String: Any] = [
            "is_available": true,
            "balance_infos": [
                [
                    "currency": "USD",
                    "total_balance": "50.00",
                    "granted_balance": "0.00",
                    "topped_up_balance": "50.00",
                ],
                [
                    "currency": "CNY",
                    "total_balance": "110.00",
                    "granted_balance": "10.00",
                    "topped_up_balance": "100.00",
                ],
            ]
        ]

        let result = adapter.parseResponse(data)
        XCTAssertEqual(result.balance, 110.0)
        XCTAssertEqual(result.balanceUnit, .cny)
    }

    func testParseEmptyBalanceInfos() {
        let data: [String: Any] = [
            "is_available": true,
            "balance_infos": [] as [Any]
        ]

        let result = adapter.parseResponse(data)
        XCTAssertNil(result.balance)
        XCTAssertNil(result.balanceUnit)
    }

    func testNoAuthRaisesError() {
        let store = CredentialStore()
        for mode in adapter.supportedAuthModes() {
            try? store.deleteCredential(provider: adapter.providerId.rawValue, kind: mode, account: "default")
        }
        XCTAssertFalse(adapter.isConfigured(store: store))
    }

    func testProviderMeta() {
        XCTAssertEqual(adapter.providerId, .deepseek)
        XCTAssertEqual(adapter.displayName, "DeepSeek")
        XCTAssertEqual(adapter.planKind, .payAsYouGo)
        XCTAssertEqual(adapter.supportedAuthModes(), ["api_key"])
    }
}
