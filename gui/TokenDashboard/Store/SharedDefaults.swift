import Foundation

final class SharedDefaults {
    static let appGroupIdentifier = "group.com.token-dashboard"
    private let defaults: UserDefaults?
    private var lastSavedData: Data?

    init() {
        self.defaults = UserDefaults(suiteName: SharedDefaults.appGroupIdentifier)
    }

    func saveSnapshots(_ snapshots: [UsageSnapshot]) {
        guard let defaults = defaults else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshots) else { return }
        if data == lastSavedData { return }
        lastSavedData = data
        defaults.set(data, forKey: "snapshots")
        defaults.set(Date(), forKey: "lastUpdated")
    }

    func loadSnapshots() -> [UsageSnapshot]? {
        guard let defaults = defaults,
              let data = defaults.data(forKey: "snapshots") else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode([UsageSnapshot].self, from: data)
    }

    var lastUpdated: Date? {
        defaults?.object(forKey: "lastUpdated") as? Date
    }
}
