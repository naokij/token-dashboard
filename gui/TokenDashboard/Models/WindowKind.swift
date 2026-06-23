import Foundation

enum WindowKind: String, Codable, CaseIterable {
    case rolling5h = "rolling_5h"
    case rollingDay = "rolling_day"
    case rollingWeek = "rolling_week"
    case rollingMonth = "rolling_month"
    case calendarMonth = "calendar_month"
    case calendarDay = "calendar_day"
    case fixedPeriod = "fixed_period"
    case balance
}
