import Foundation
import SwiftUI

@MainActor
final class UsageFetcher: ObservableObject {
    @Published var snapshots: [UsageSnapshot] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let registry = AdapterRegistry()
    private let credentialStore = CredentialStore()
    let sharedDefaults = SharedDefaults()
    private var timer: Timer?

    var mostConstrainedPct: Double? {
        let pcts = snapshots.compactMap { $0.primaryWindow()?.usedPct }
        return pcts.max()
    }

    func fetchAll() {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil

        Task {
            var results: [UsageSnapshot] = []
            for providerId in registry.allProviderIds {
                let adapter = registry.adapter(for: providerId)
                if !adapter.isConfigured(store: credentialStore) {
                    continue
                }
                do {
                    let snap = try await adapter.fetch(store: credentialStore)
                    results.append(snap)
                } catch let err as AuthRequiredError {
                    results.append(UsageSnapshot(
                        provider: providerId,
                        fetchedAt: Date(),
                        planKind: adapter.planKind,
                        warnings: [err.message]
                    ))
                } catch {
                    results.append(UsageSnapshot(
                        provider: providerId,
                        fetchedAt: Date(),
                        planKind: adapter.planKind,
                        warnings: ["Fetch failed: \(error.localizedDescription)"]
                    ))
                }
            }

            self.snapshots = results
            self.isLoading = false
            self.sharedDefaults.saveSnapshots(results)
        }
    }

    func startPeriodicRefresh(intervalSeconds: TimeInterval = 60) {
        stopPeriodicRefresh()
        fetchAll()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchAll()
            }
        }
    }

    func stopPeriodicRefresh() {
        timer?.invalidate()
        timer = nil
    }
}
