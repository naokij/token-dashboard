import Foundation
import CryptoKit

final class CredentialStore: @unchecked Sendable {
    private let directory: URL
    private var cache: [String: [String: Any]] = [:]
    private let cacheLock = NSLock()

    init(directory: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.directory = directory ?? home.appendingPathComponent(".token-dashboard/credentials")
    }

    private func makeKey(provider: String, kind: String, account: String) -> String {
        "\(provider):\(account):\(kind)"
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
    }

    func saveCredential(provider: String, kind: String, account: String, value: [String: Any]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = makeKey(provider: provider, kind: kind, account: account)
        let data = try JSONSerialization.data(withJSONObject: value)
        try data.write(to: fileURL(for: key), options: .atomic)
        cacheLock.lock()
        cache[key] = value
        cacheLock.unlock()
    }

    func loadCredential(provider: String, kind: String, account: String) -> [String: Any]? {
        let key = makeKey(provider: provider, kind: kind, account: account)
        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let value {
            cacheLock.lock()
            cache[key] = value
            cacheLock.unlock()
        }
        return value
    }

    func deleteCredential(provider: String, kind: String, account: String) throws {
        let key = makeKey(provider: provider, kind: kind, account: account)
        cacheLock.lock()
        cache.removeValue(forKey: key)
        cacheLock.unlock()
        let url = fileURL(for: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
