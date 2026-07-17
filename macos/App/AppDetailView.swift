import SwiftUI
import SwiftData
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import ForgeCore

struct AppDetailView: View {
    @Bindable var project: AppProject
    @Environment(\.modelContext) private var context

    @State private var selectedDevices: Set<AppleDevice> = Set(AppleDevice.allCases)
    @State private var selectedGoogleDevices: Set<GooglePlayDevice> = Set(GooglePlayDevice.allCases)
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var statusText = ""
    @State private var showImporter = false
    @State private var previewImage: NSImage?
    @State private var previewSizeID = ""
    @State private var frameScreenshots = false
    @State private var showUpload = false

    private let engine = BatchEngine()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("App name", text: $project.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)

                assetsBox
                previewBox
                appleDevicesBox
                googleDevicesBox
                Toggle("Frame screenshots in a device bezel", isOn: $frameScreenshots)
                    .toggleStyle(.checkbox)
                HStack(spacing: 12) {
                    exportRow
                    Button {
                        showUpload = true
                    } label: {
                        Label("Upload to App Store Connect…", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(project.assets.isEmpty)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showUpload) {
            UploadSheet(project: project)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { add(urls) }
        }
    }

    // MARK: - Sections

    private var assetsBox: some View {
        GroupBox("Screenshots & videos") {
            VStack(alignment: .leading, spacing: 8) {
                let assets = project.sortedAssets
                if assets.isEmpty {
                    Text("Nothing added yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(assets) { asset in
                                AssetThumbnail(asset: asset)
                                    .contextMenu {
                                        Button("Remove", role: .destructive) {
                                            context.delete(asset)
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 220)
                }

                Button {
                    showImporter = true
                } label: {
                    Label("Add screenshots or videos", systemImage: "plus.rectangle.on.folder")
                }
            }
        }
    }

    /// Representative portrait screenshot size per Apple device, for the preview.
    private var previewTargets: [DeviceSize] {
        AppleSizes.screenshots.filter { !$0.isLandscape }
    }

    private var firstScreenshot: Asset? {
        project.sortedAssets.first { $0.kind == .image }
    }

    private var previewBox: some View {
        GroupBox("Crop preview") {
            VStack(alignment: .leading, spacing: 8) {
                if let previewImage {
                    Picker("Device", selection: $previewSizeID) {
                        ForEach(previewTargets) { size in
                            Text("\(size.device) — \(size.fileTag)").tag(size.id)
                        }
                    }
                    .frame(maxWidth: 340)

                    let target = previewTargets.first { $0.id == previewSizeID } ?? previewTargets.first
                    if let target {
                        CropPreview(image: previewImage, target: target.pixelSize)
                            .frame(height: 240)
                            .background(Color.black.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    Text("Add a screenshot to preview how it will be cropped.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
        }
        .task(id: firstScreenshot?.persistentModelID) { await loadPreview() }
    }

    private func loadPreview() async {
        guard let asset = firstScreenshot, let (url, started) = asset.resolvedURL() else {
            previewImage = nil
            return
        }
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        previewImage = NSImage(contentsOf: url)
        if previewSizeID.isEmpty {
            previewSizeID = previewTargets.first?.id ?? ""
        }
    }

    private var appleDevicesBox: some View {
        GroupBox("Apple devices (screenshots + app previews)") {
            HStack(spacing: 16) {
                ForEach(AppleDevice.allCases) { device in
                    Toggle(device.displayName, isOn: Binding(
                        get: { selectedDevices.contains(device) },
                        set: { isOn in
                            if isOn { selectedDevices.insert(device) }
                            else { selectedDevices.remove(device) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
                Spacer()
            }
        }
    }

    private var googleDevicesBox: some View {
        GroupBox("Google Play devices (screenshots only)") {
            HStack(spacing: 16) {
                ForEach(GooglePlayDevice.allCases) { device in
                    Toggle(device.displayName, isOn: Binding(
                        get: { selectedGoogleDevices.contains(device) },
                        set: { isOn in
                            if isOn { selectedGoogleDevices.insert(device) }
                            else { selectedGoogleDevices.remove(device) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
                Spacer()
            }
        }
    }

    private var exportRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await export() }
            } label: {
                Label("Export all sizes", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(
                isExporting
                || project.assets.isEmpty
                || (selectedDevices.isEmpty && selectedGoogleDevices.isEmpty)
            )

            if isExporting {
                ProgressView(value: progress).frame(width: 160)
            }
            if !statusText.isEmpty {
                Text(statusText).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    // MARK: - Actions

    private func add(_ urls: [URL]) {
        for url in urls {
            guard let kind = SupportedTypes.kind(of: url) else { continue }
            let fileName = url.lastPathComponent
            if project.assets.contains(where: { $0.fileName == fileName }) { continue }

            let bookmark = BookmarkStore.makeBookmark(for: url)
            let asset = Asset(fileName: fileName, kind: kind, bookmark: bookmark)
            asset.project = project
            context.insert(asset)
        }
    }

    private func export() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose output folder"
        guard panel.runModal() == .OK, let outputRoot = panel.url else { return }

        isExporting = true
        progress = 0
        statusText = "Starting…"
        defer { isExporting = false }

        // Resolve every asset's bookmark, holding any security scope for the
        // whole export, then release it.
        var resolved: [(url: URL, started: Bool)] = []
        for asset in project.sortedAssets {
            if let entry = asset.resolvedURL() { resolved.append(entry) }
        }
        defer {
            for entry in resolved where entry.started {
                entry.url.stopAccessingSecurityScopedResource()
            }
        }

        let urls = resolved.map(\.url)
        let devices = AppleDevice.allCases.filter { selectedDevices.contains($0) }
        let googleDevices = GooglePlayDevice.allCases.filter { selectedGoogleDevices.contains($0) }

        var finalOutcome = BatchOutcome()
        for await event in engine.run(
            inputs: urls,
            appleDevices: devices,
            googlePlayDevices: googleDevices,
            outputRoot: outputRoot,
            options: ExportOptions(frameScreenshots: frameScreenshots)
        ) {
            switch event {
            case .progress(let update):
                progress = update.fraction
                statusText = update.message
            case .finished(let outcome):
                finalOutcome = outcome
            }
        }

        statusText = "Done — \(finalOutcome.processed) generated, \(finalOutcome.failures.count) errors"
        NSWorkspace.shared.open(outputRoot)
    }
}

/// A thumbnail for an asset — the rendered screenshot, or an icon for a video.
/// Loads lazily so scrolling the grid doesn't resolve every bookmark up front.
struct AssetThumbnail: View {
    let asset: Asset
    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 4) {
            thumbnail
            Text(asset.fileName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 84)
        }
        .task(id: asset.persistentModelID) { await load() }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if asset.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(3)
                }
            }
        } else {
            let fallback = asset.kind == .video ? "film" : "photo"
            placeholder(loadFailed ? "exclamationmark.triangle" : fallback)
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
        }
        .frame(width: 80, height: 80)
    }

    private func load() async {
        guard image == nil else { return }
        guard let (url, started) = asset.resolvedURL() else {
            loadFailed = true
            return
        }
        let kind = asset.kind

        // Decode off the main thread so scrolling a big grid stays smooth.
        let loaded = await Task.detached(priority: .utility) { () -> NSImage? in
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            switch kind {
            case .image:
                guard let data = try? Data(contentsOf: url) else { return nil }
                return NSImage(data: data)
            case .video:
                return Self.firstFrame(of: url)
            }
        }.value

        if let loaded {
            image = loaded
        } else {
            loadFailed = true
        }
    }

    /// Extract a poster frame from a video for its thumbnail.
    private static func firstFrame(of url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
