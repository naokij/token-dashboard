import Foundation
import Yams
import Combine

final class ConfigStore: ObservableObject {
    @Published var refreshInterval: Int = 60
    @Published var warnPct: Int = 70
    @Published var criticalPct: Int = 90
    @Published var enabledProviders: Set<ProviderId> = Set(ProviderId.allCases)

    private var configDir: String {
        if let env = ProcessInfo.processInfo.environment["TD_CONFIG_DIR"] {
            return env
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.token-dashboard"
    }

    private var configPath: String {
        "\(configDir)/config.yaml"
    }

    func load() {
        let url = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8),
              let yaml = try? Yams.load(yaml: string) as? [String: Any] else {
            return
        }

        if let val = yaml["refresh_interval"] as? Int {
            refreshInterval = val
        }
        if let val = yaml["warn_pct"] as? Int {
            warnPct = val
        }
        if let val = yaml["critical_pct"] as? Int {
            criticalPct = val
        }
        if let arr = yaml["enabled_providers"] as? [String] {
            let ids = arr.compactMap { ProviderId(rawValue: $0) }
            if !ids.isEmpty {
                enabledProviders = Set(ids)
            }
        }
    }
}
