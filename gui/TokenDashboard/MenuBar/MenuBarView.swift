import SwiftUI

struct MenuBarView: View {
    @ObservedObject var fetcher: UsageFetcher
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token Dashboard")
                    .font(.headline)
                Spacer()
                if fetcher.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            if fetcher.snapshots.isEmpty && !fetcher.isLoading {
                Text("No providers configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(fetcher.snapshots) { snapshot in
                    ProviderCardView(snapshot: snapshot)
                }
            }

            if let error = fetcher.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            HStack {
                if let lastUpdated = fetcher.sharedDefaults.lastUpdated {
                    Text("Updated \(formatTime(lastUpdated))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Not yet updated")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { fetcher.fetchAll() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")

                Button(action: { openSettings() }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .frame(width: 340)
        .padding()
        .onAppear {
            fetcher.startPeriodicRefresh()
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}
