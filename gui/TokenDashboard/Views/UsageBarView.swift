import SwiftUI

struct UsageBarView: View {
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
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor)
                            .frame(width: max(0, geo.size.width * min(pct / 100.0, 1.0)), height: 10)
                    }
                }
                .frame(height: 10)

                Text(String(format: "%.1f%%", pct))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(barColor)
                    .layoutPriority(1)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 10)
                    .overlay(
                        Text("unbounded")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    )
            }
        }
    }
}
