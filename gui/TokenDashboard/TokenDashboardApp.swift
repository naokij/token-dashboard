import SwiftUI

@main
struct TokenDashboardApp: App {
    @StateObject private var fetcher = UsageFetcher()
    @StateObject private var config = ConfigStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(fetcher: fetcher)
        } label: {
            if let pct = fetcher.mostConstrainedPct {
                let clamped = max(0, min(100, pct))
                Text(String(format: "%.0f%%", clamped))
            } else {
                Image(systemName: "gauge.with.dots.needle.33percent")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Token Dashboard Settings", id: "settings") {
            SettingsView(fetcher: fetcher, config: config)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
