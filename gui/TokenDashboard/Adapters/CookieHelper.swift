import Foundation

enum CookieHelper {
    static func formatCookieHeader(credential: [String: Any]) -> String {
        guard let cookieList = credential["cookies"] as? [Any] else { return "" }
        return cookieList.compactMap { item -> String? in
            guard let dict = item as? [String: Any] else { return nil }
            let name = dict["name"] as? String
            let value = dict["value"] as? String
            guard let n = name, let v = value, !n.isEmpty else { return nil }
            return "\(n)=\(v)"
        }.joined(separator: "; ")
    }
}
