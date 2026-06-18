import XCTest
@testable import TokenDashboard

final class CredentialStoreTests: XCTestCase {

    private var store: CredentialStore!

    override func setUp() {
        super.setUp()
        store = CredentialStore()
    }

    override func tearDown() {
        try? store.deleteCredential(provider: "test", kind: "api_key", account: "default")
        try? store.deleteCredential(provider: "test", kind: "cookie", account: "default")
        super.tearDown()
    }

    func testSaveAndLoadCredential() throws {
        let value: [String: Any] = ["key": "sk-test-123"]
        try store.saveCredential(provider: "test", kind: "api_key", account: "default", value: value)

        let loaded = store.loadCredential(provider: "test", kind: "api_key", account: "default")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?["key"] as? String, "sk-test-123")
    }

    func testLoadNonExistentReturnsNil() {
        let result = store.loadCredential(provider: "test", kind: "nonexistent", account: "default")
        XCTAssertNil(result)
    }

    func testDeleteCredential() throws {
        let value: [String: Any] = ["key": "sk-to-delete"]
        try store.saveCredential(provider: "test", kind: "api_key", account: "default", value: value)

        let loaded = store.loadCredential(provider: "test", kind: "api_key", account: "default")
        XCTAssertNotNil(loaded)

        try store.deleteCredential(provider: "test", kind: "api_key", account: "default")

        let afterDelete = store.loadCredential(provider: "test", kind: "api_key", account: "default")
        XCTAssertNil(afterDelete)
    }
}
