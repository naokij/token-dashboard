import SwiftUI

struct UsageBarView: View {
    private static let barWidth: CGFloat = 170

    let usedPct: Double?

    private var barColor: Color {
        guard let pct = usedPct else { return .gray }
        if pct < 70 { return .green }
        if pct < 90 { return .yellow }
        return .red
    }

    var body: some View {
        HStack(spacing: 6) {
            if let pct = usedPct {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: Self.barWidth, height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: Self.barWidth * min(pct / 100.0, 1.0), height: 10)
                }

                Text(String(format: "%.1f%%", pct))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(barColor)
                    .layoutPriority(1)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: Self.barWidth, height: 10)
                    .overlay(
                        Text("unbounded")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    )
            }
        }
    }
}
