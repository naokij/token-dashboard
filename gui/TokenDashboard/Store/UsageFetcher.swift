import Foundation
import SwiftUI

@MainActor
final class UsageFetcher: ObservableObject {
    @Published var snapshots: [UsageSnapshot] = []
    @Published var isLoading = false
    @Published var lastError: String?

    let registry = AdapterRegistry()
    let credentialStore = CredentialStore()
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
            await withTaskGroup(of: UsageSnapshot?.self) { group in
                for providerId in registry.allProviderIds {
                    let adapter = registry.adapter(for: providerId)
                    if !adapter.isConfigured(store: credentialStore) {
                        continue
                    }
                    group.addTask {
                        do {
                            return try await adapter.fetch(store: self.credentialStore)
                        } catch let err as AuthRequiredError {
                            return UsageSnapshot(
                                provider: providerId,
                                fetchedAt: Date(),
                                planKind: adapter.planKind,
                                warnings: [err.message]
                            )
                        } catch {
                            return UsageSnapshot(
                                provider: providerId,
                                fetchedAt: Date(),
                                planKind: adapter.planKind,
                                warnings: ["Fetch failed: \(error.localizedDescription)"]
                            )
                        }
                    }
                }
                for await snapshot in group {
                    if let snap = snapshot {
                        results.append(snap)
                    }
                }
            }

            let hasChanges = self.snapshots.count != results.count || !zip(self.snapshots, results).allSatisfy { old, new in
                old.provider == new.provider &&
                old.primaryWindow()?.usedPct == new.primaryWindow()?.usedPct &&
                old.balance == new.balance &&
                old.warnings == new.warnings
            }
            if hasChanges {
                self.snapshots = results
            }
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
