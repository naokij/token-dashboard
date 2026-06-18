import Foundation
import CryptoKit

final class CredentialStore {
    private let directory: URL

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
    }

    func loadCredential(provider: String, kind: String, account: String) -> [String: Any]? {
        let key = makeKey(provider: provider, kind: kind, account: account)
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func deleteCredential(provider: String, kind: String, account: String) throws {
        let key = makeKey(provider: provider, kind: kind, account: account)
        let url = fileURL(for: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
