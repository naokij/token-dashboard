import Foundation

enum PlanKind: String, Codable, CaseIterable {
    case codingPlan = "coding_plan"
    case tokenPlan = "token_plan"
    case payAsYouGo = "pay_as_you_go"
}
