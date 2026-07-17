import SwiftUI
import UniformTypeIdentifiers
import ForgeCore

/// App Store Connect credentials (Preferences → ⌘,). The issuer id and key id
/// are stored in `@AppStorage`; the `.p8` private key goes in the Keychain.
struct SettingsView: View {
    @AppStorage("asc.issuerID") private var issuerID = ""
    @AppStorage("asc.keyID") private var keyID = ""

    @State private var hasKey = KeychainStore.shared.exists("asc.p8")
    @State private var showImporter = false
    @State private var testing = false
    @State private var testResult = ""
    @State private var testOK = false

    private static let keyKey = "asc.p8"

    var body: some View {
        Form {
            Section("App Store Connect API key") {
                TextField("Issuer ID", text: $issuerID)
                TextField("Key ID", text: $keyID)

                HStack {
                    Button(hasKey ? "Replace .p8 key…" : "Choose .p8 key…") {
                        showImporter = true
                    }
                    if hasKey {
                        Label("key stored", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Remove", role: .destructive) {
                            KeychainStore.shared.remove(Self.keyKey)
                            hasKey = false
                        }
                    }
                }

                HStack {
                    Button("Test connection") { Task { await test() } }
                        .disabled(testing || issuerID.isEmpty || keyID.isEmpty || !hasKey)
                    if testing { ProgressView().controlSize(.small) }
                    if !testResult.isEmpty {
                        Text(testResult).foregroundStyle(testOK ? .green : .red)
                    }
                }
            }

            Text("Create a key in App Store Connect → Users and Access → Integrations → App Store Connect API. Keep the .p8 safe; it's stored in your login Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(20)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item]   // .p8 files have no dedicated UTI
        ) { result in
            if case .success(let url) = result { importKey(url) }
        }
    }

    private func importKey(_ url: URL) {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        guard let pem = try? String(contentsOf: url, encoding: .utf8) else {
            testResult = "Could not read that file"
            testOK = false
            return
        }
        hasKey = KeychainStore.shared.set(pem, for: Self.keyKey)
    }

    private func test() async {
        testing = true
        testResult = ""
        defer { testing = false }

        guard let pem = KeychainStore.shared.get(Self.keyKey) else {
            testOK = false
            testResult = "No key stored"
            return
        }
        let credentials = AppStoreConnectCredentials(
            issuerID: issuerID, keyID: keyID, privateKeyPEM: pem
        )
        do {
            let apps = try await AppStoreConnectClient(credentials: credentials).apps()
            testOK = true
            testResult = "OK — \(apps.count) app(s)"
        } catch {
            testOK = false
            testResult = error.localizedDescription
        }
    }
}
