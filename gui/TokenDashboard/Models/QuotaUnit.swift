import Foundation

enum QuotaUnit: String, Codable, CaseIterable {
    case credits
    case tokens
    case requests
    case usd
    case cny
    case prompts
    case percent
    case unknown
}
