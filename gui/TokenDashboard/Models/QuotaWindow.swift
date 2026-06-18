import Foundation

struct QuotaWindow: Codable, Identifiable {
    var id: String { "\(kind.rawValue)-\(label)" }

    var kind: WindowKind
    var label: String
    var used: Double
    var limit: Double?
    var remaining: Double?
    var unit: QuotaUnit
    var usedPct: Double?
    var resetAt: Date?
    var periodStart: Date?
    var periodEnd: Date?
    var raw: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case kind, label, used, limit, remaining, unit
        case usedPct = "used_pct"
        case resetAt = "reset_at"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case raw
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}
