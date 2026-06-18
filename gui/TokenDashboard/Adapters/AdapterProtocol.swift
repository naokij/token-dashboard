import Foundation

struct AuthRequiredError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct RuntimeError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
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
