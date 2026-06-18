import Foundation
import KeychainAccess

final class CredentialStore {
    static let serviceName = "com.token-dashboard"

    private let keychain: Keychain

    init(keychain: Keychain = Keychain(service: CredentialStore.serviceName)) {
        self.keychain = keychain
    }

    private func makeKey(provider: String, kind: String, account: String) -> String {
        "\(provider):\(account):\(kind)"
    }

    func saveCredential(provider: String, kind: String, account: String, value: [String: Any]) throws {
        let key = makeKey(provider: provider, kind: kind, account: account)
        let data = try JSONSerialization.data(withJSONObject: value)
        keychain[key] = data.base64EncodedString()
    }

    func loadCredential(provider: String, kind: String, account: String) -> [String: Any]? {
        let key = makeKey(provider: provider, kind: kind, account: account)
        guard let encoded = keychain[key] else { return nil }
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func deleteCredential(provider: String, kind: String, account: String) throws {
        let key = makeKey(provider: provider, kind: kind, account: account)
        try keychain.remove(key)
    }

    func loadLegacyCredentials() -> [String: [String: [String: [String: Any]]]]? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".token-dashboard/credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: [String: [String: [String: Any]]]]
    }

    func migrateFromLegacy() throws {
        guard let legacy = loadLegacyCredentials() else { return }
        for (provider, accounts) in legacy {
            for (account, kinds) in accounts {
                for (kind, value) in kinds {
                    try saveCredential(provider: provider, kind: kind, account: account, value: value)
                }
            }
        }
    }
}
