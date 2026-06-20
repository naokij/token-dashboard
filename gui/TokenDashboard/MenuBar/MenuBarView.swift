import SwiftUI

private enum Formatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

struct MenuBarView: View {
    @ObservedObject var fetcher: UsageFetcher
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Token Dashboard")
                    .font(.headline)
                Spacer()
                LoadingIndicator(isLoading: fetcher.isLoading)
            }

            if fetcher.snapshots.isEmpty && !fetcher.isLoading {
                Text("No providers configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                SnapshotListView(snapshots: fetcher.snapshots)
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

                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .help("Quit")
            }
        }
        .frame(width: 340)
        .padding()
        .onAppear {
            fetcher.startPeriodicRefresh()
        }
    }

    private func formatTime(_ date: Date) -> String {
        Formatters.relative.localizedString(for: date, relativeTo: Date())
    }

    private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}

private struct LoadingIndicator: View {
    let isLoading: Bool

    var body: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(0.6)
        }
    }
}

private struct SnapshotListView: View {
    let snapshots: [UsageSnapshot]

    var body: some View {
        ForEach(snapshots) { snapshot in
            ProviderCardView(snapshot: snapshot)
        }
    }
}
