import SwiftUI

struct SettingsView: View {
    @ObservedObject var fetcher: UsageFetcher
    @ObservedObject var config: ConfigStore

    @State private var selectedProvider: ProviderId = .opencode
    @State private var apiKey: String = ""
    @State private var cookieText: String = ""
    @State private var workspaceId: String = ""
    @State private var saveMessage: String?
    @State private var migrateMessage: String?

    private let credentialStore = CredentialStore()
    private let registry = AdapterRegistry()

    var body: some View {
        TabView {
            credentialsTab
                .tabItem { Label("Credentials", systemImage: "key") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 450, height: 350)
    }

    private var credentialsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Provider", selection: $selectedProvider) {
                ForEach(ProviderId.allCases, id: \.self) { id in
                    Text(id.rawValue.uppercased()).tag(id)
                }
            }
            .onChange(of: selectedProvider) { _ in loadExistingCredential() }

            let adapter = registry.adapter(for: selectedProvider)
            let modes = adapter.supportedAuthModes()

            if modes.contains("api_key") {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            if modes.contains("cookie") {
                TextField("Cookies JSON", text: $cookieText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                if selectedProvider == .opencode {
                    TextField("Workspace ID (optional)", text: $workspaceId)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Button("Save") {
                saveCredential()
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Divider()

            Button("Migrate from legacy credentials.json") {
                do {
                    try credentialStore.migrateFromLegacy()
                    migrateMessage = "Migration complete"
                } catch {
                    migrateMessage = "Migration failed: \(error.localizedDescription)"
                }
            }

            if let msg = migrateMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(msg.contains("failed") ? .red : .green)
            }

            Spacer()
        }
        .padding()
        .onAppear { loadExistingCredential() }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Stepper("Refresh interval: \(config.refreshInterval)s", value: $config.refreshInterval, in: 10...600, step: 10)

            Stepper("Warn threshold: \(config.warnPct)%", value: $config.warnPct, in: 10...100, step: 5)

            Stepper("Critical threshold: \(config.criticalPct)%", value: $config.criticalPct, in: 10...100, step: 5)

            Button("Apply & Refresh") {
                fetcher.stopPeriodicRefresh()
                fetcher.startPeriodicRefresh(intervalSeconds: TimeInterval(config.refreshInterval))
            }

            Spacer()
        }
        .padding()
    }

    private func loadExistingCredential() {
        let adapter = registry.adapter(for: selectedProvider)
        let modes = adapter.supportedAuthModes()

        if modes.contains("api_key"),
           let cred = credentialStore.loadCredential(provider: selectedProvider.rawValue, kind: "api_key", account: "default"),
           let key = cred["key"] as? String {
            apiKey = key
        } else {
            apiKey = ""
        }

            if modes.contains("cookie"),
               let cred = credentialStore.loadCredential(provider: selectedProvider.rawValue, kind: "cookie", account: "default") {
                if let cookies = cred["cookies"] as? [[String: Any]],
                   let data = try? JSONSerialization.data(withJSONObject: cookies, options: .prettyPrinted) {
                    cookieText = String(data: data, encoding: .utf8) ?? ""
                }
                workspaceId = cred["workspace_id"] as? String ?? ""
            } else {
            cookieText = ""
            workspaceId = ""
        }

        saveMessage = nil
    }

    private func saveCredential() {
        let adapter = registry.adapter(for: selectedProvider)
        let modes = adapter.supportedAuthModes()

        do {
            if modes.contains("api_key") && !apiKey.isEmpty {
                try credentialStore.saveCredential(
                    provider: selectedProvider.rawValue,
                    kind: "api_key",
                    account: "default",
                    value: ["key": apiKey]
                )
            }

            if modes.contains("cookie") && !cookieText.isEmpty {
                var value: [String: Any] = [:]
                if let data = cookieText.data(using: .utf8),
                   let cookies = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    value["cookies"] = cookies
                }
                if !workspaceId.isEmpty {
                    value["workspace_id"] = workspaceId
                }
                if !value.isEmpty {
                    try credentialStore.saveCredential(
                        provider: selectedProvider.rawValue,
                        kind: "cookie",
                        account: "default",
                        value: value
                    )
                }
            }

            saveMessage = "Saved"
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
        }
    }
}
