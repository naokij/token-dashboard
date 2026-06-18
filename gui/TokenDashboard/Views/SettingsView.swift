import SwiftUI

struct SettingsView: View {
    @ObservedObject var fetcher: UsageFetcher
    @ObservedObject var config: ConfigStore

    @State private var selectedProvider: ProviderId = .opencode
    @State private var apiKey: String = ""
    @State private var cookieText: String = ""
    @State private var workspaceId: String = ""
    @State private var saveMessage: String?

    private let credentialStore = CredentialStore()
    private let registry = AdapterRegistry()

    var body: some View {
        TabView {
            credentialsTab
                .tabItem { Label("Credentials", systemImage: "key") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 500, height: 400)
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
                SecureField("API Key (e.g. sk-...)", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            if modes.contains("cookie") {
                TextField("Cookie (name=value; ...  or  paste cURL)", text: $cookieText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                if selectedProvider == .opencode {
                    TextField("Workspace ID (optional)", text: $workspaceId)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Paste from browser: F12 → Network → Copy as cURL, or just the Cookie header value")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Button("Save") {
                saveCredential()
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(msg.hasPrefix("Error") ? .red : .green)
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
            if let cookies = cred["cookies"] as? [[String: Any]] {
                cookieText = cookies.compactMap { c in
                    guard let name = c["name"] as? String, let value = c["value"] as? String else { return nil }
                    return "\(name)=\(value)"
                }.joined(separator: "; ")
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
                let cookies = parseCookieInput(cookieText)
                if cookies.isEmpty {
                    saveMessage = "Error: no valid cookies found in input"
                    return
                }
                var value: [String: Any] = ["cookies": cookies]
                if !workspaceId.isEmpty {
                    value["workspace_id"] = workspaceId
                }
                try credentialStore.saveCredential(
                    provider: selectedProvider.rawValue,
                    kind: "cookie",
                    account: "default",
                    value: value
                )
            }

            saveMessage = "Saved!"
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func parseCookieInput(_ input: String) -> [[String: String]] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // cURL format: extract -b '...' or --cookie '...'
        if trimmed.contains("curl") || trimmed.contains("-b ") || trimmed.contains("--cookie ") {
            return parseCurlCookie(trimmed)
        }

        // "Cookie: name=value; name2=value2" header format
        var cookieStr = trimmed
        if cookieStr.hasPrefix("Cookie:") {
            cookieStr = String(cookieStr.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }

        // Plain "name=value; name2=value2" format
        return parsePlainCookie(cookieStr)
    }

    private func parseCurlCookie(_ input: String) -> [[String: String]] {
        var cookies: [[String: String]] = []

        // Match -b '...' or --cookie '...' (with single or double quotes)
        let patterns = [
            #"-b\s+'([^']+)'"#,
            #"-b\s+\"([^\"]+)\""#,
            #"--cookie\s+'([^']+)'"#,
            #"--cookie\s+\"([^\"]+)\""#,
            #"-b\s+([^\s]+)"#,
            #"--cookie\s+([^\s]+)"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: input) {
                let cookieStr = String(input[range])
                cookies = parsePlainCookie(cookieStr)
                if !cookies.isEmpty { return cookies }
            }
        }

        return cookies
    }

    private func parsePlainCookie(_ input: String) -> [[String: String]] {
        var cookies: [[String: String]] = []
        for part in input.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                cookies.append(["name": name, "value": value])
            }
        }
        return cookies
    }
}
