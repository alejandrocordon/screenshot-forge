import SwiftUI
import ForgeCore

/// Uploads a project's screenshots to App Store Connect: pick app → version →
/// localization → screenshot set, and for each set we crop the project's
/// screenshots to that display size and upload them.
struct UploadSheet: View {
    let project: AppProject
    @Environment(\.dismiss) private var dismiss

    @AppStorage("asc.issuerID") private var issuerID = ""
    @AppStorage("asc.keyID") private var keyID = ""

    @State private var apps: [ASCApp] = []
    @State private var versions: [ASCVersion] = []
    @State private var localizations: [ASCLocalization] = []
    @State private var sets: [ASCScreenshotSet] = []

    @State private var appID = ""
    @State private var versionID = ""
    @State private var localizationID = ""

    @State private var status = ""
    @State private var busy = false

    private var client: AppStoreConnectClient? {
        guard !issuerID.isEmpty, !keyID.isEmpty,
              let pem = KeychainStore.shared.get("asc.p8") else { return nil }
        return AppStoreConnectClient(
            credentials: .init(issuerID: issuerID, keyID: keyID, privateKeyPEM: pem)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Upload to App Store Connect").font(.title3.bold())

            if client == nil {
                Label("Set your API key in Settings (⌘,) first.", systemImage: "key")
                    .foregroundStyle(.orange)
            } else {
                pickers
                Divider()
                setsList
            }

            if busy { ProgressView().controlSize(.small) }
            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
            HStack { Spacer(); Button("Close") { dismiss() } }
        }
        .padding(20)
        .frame(width: 540, height: 500)
        .task { await loadApps() }
    }

    // MARK: - Pickers

    private var pickers: some View {
        Group {
            Picker("App", selection: $appID) {
                Text("—").tag("")
                ForEach(apps) { Text($0.name).tag($0.id) }
            }
            .onChange(of: appID) { _, _ in
                versions = []; localizations = []; sets = []
                versionID = ""; localizationID = ""
                Task { await loadVersions() }
            }

            Picker("Version", selection: $versionID) {
                Text("—").tag("")
                ForEach(versions) { Text("\($0.versionString) (\($0.state))").tag($0.id) }
            }
            .onChange(of: versionID) { _, _ in
                localizations = []; sets = []; localizationID = ""
                Task { await loadLocalizations() }
            }

            Picker("Localization", selection: $localizationID) {
                Text("—").tag("")
                ForEach(localizations) { Text($0.locale).tag($0.id) }
            }
            .onChange(of: localizationID) { _, _ in
                sets = []
                Task { await loadSets() }
            }
        }
    }

    private var setsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sets.isEmpty {
                Text("No screenshot sets — pick a localization.").foregroundStyle(.secondary)
            }
            ForEach(sets) { set in
                HStack {
                    let size = ScreenshotDisplayType.size(for: set.displayType)
                    VStack(alignment: .leading) {
                        Text(set.displayType).font(.callout)
                        Text(size.map { $0.fileTag } ?? "unsupported size")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Upload") { Task { await upload(to: set) } }
                        .disabled(busy || size == nil)
                }
            }
        }
    }

    // MARK: - Loading

    private func loadApps() async {
        guard let client else { return }
        do { apps = try await client.apps() } catch { status = error.localizedDescription }
    }

    private func loadVersions() async {
        guard let client, !appID.isEmpty else { return }
        do { versions = try await client.versions(appID: appID) }
        catch { status = error.localizedDescription }
    }

    private func loadLocalizations() async {
        guard let client, !versionID.isEmpty else { return }
        do { localizations = try await client.localizations(versionID: versionID) }
        catch { status = error.localizedDescription }
    }

    private func loadSets() async {
        guard let client, !localizationID.isEmpty else { return }
        do { sets = try await client.screenshotSets(localizationID: localizationID) }
        catch { status = error.localizedDescription }
    }

    // MARK: - Upload

    private func upload(to set: ASCScreenshotSet) async {
        guard let client, let size = ScreenshotDisplayType.size(for: set.displayType) else { return }
        busy = true
        defer { busy = false }

        let screenshots = project.sortedAssets.filter { $0.kind == .image }
        guard !screenshots.isEmpty else { status = "No screenshots to upload."; return }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var uploaded = 0
        var failed = 0
        for asset in screenshots {
            guard let (url, started) = asset.resolvedURL() else { failed += 1; continue }
            defer { if started { url.stopAccessingSecurityScopedResource() } }

            let out = tmp.appendingPathComponent(
                "\(url.deletingPathExtension().lastPathComponent)_\(size.fileTag).png"
            )
            do {
                try ImageCropper.crop(source: url, to: size.pixelSize, output: out)
                try await client.uploadScreenshot(fileURL: out, toScreenshotSetID: set.id)
                uploaded += 1
                status = "Uploaded \(uploaded)/\(screenshots.count) to \(set.displayType)…"
            } catch {
                failed += 1
                status = "Error: \(error.localizedDescription)"
            }
        }
        status = "Done — \(uploaded) uploaded, \(failed) failed (\(set.displayType))."
    }
}
