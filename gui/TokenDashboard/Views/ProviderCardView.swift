import SwiftUI

struct ProviderCardView: View {
    let snapshot: UsageSnapshot

    private var displayName: String {
        snapshot.provider.rawValue.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(displayName)
                    .font(.headline)
                Spacer()
                if let planName = snapshot.planName {
                    Text(planName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let expiresAt = snapshot.planExpiresAt {
                    Text("Exp: \(formatDate(expiresAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if snapshot.windows.isEmpty && snapshot.balance == nil {
                if snapshot.warnings.isEmpty {
                    Text("No data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(snapshot.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            } else {
                ForEach(snapshot.windows) { window in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(window.label)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)

                            UsageBarView(usedPct: window.usedPct)
                        }

                        if let resetAt = window.resetAt {
                            Text("Resets in \(formatRemaining(resetAt))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.leading, 84)
                        }
                    }
                }

                if let balance = snapshot.balance, let unit = snapshot.balanceUnit {
                    HStack(spacing: 4) {
                        Text("balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text(String(format: "%.2f %@", balance, unit.rawValue))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }

            ForEach(snapshot.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatRemaining(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "soon" }
        let totalHours = Int(interval / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd HH:mm"
        return fmt.string(from: date)
    }
}
