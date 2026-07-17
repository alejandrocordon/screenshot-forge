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
    @State private var caption = ""
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
                    .disabled(!caption.isEmpty)
                TextField("Caption (optional marketing title)", text: $caption)
                    .textFieldStyle(.roundedBorder)
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

    /// First screenshot, or a video if there are no screenshots.
    private var previewAsset: Asset? {
        project.sortedAssets.first { $0.kind == .image }
            ?? project.sortedAssets.first { $0.kind == .video }
    }

    /// Portrait sizes for the previewed asset (screenshot vs app-preview video).
    private var previewTargets: [DeviceSize] {
        guard let asset = previewAsset else { return [] }
        let table = asset.kind == .image ? AppleSizes.screenshots : AppleSizes.videos
        return table.filter { !$0.isLandscape }
    }

    /// Re-render the preview whenever the asset, size, or output options change.
    private var previewKey: String {
        let id = previewAsset?.persistentModelID.hashValue ?? 0
        return "\(id)|\(previewSizeID)|\(frameScreenshots)|\(caption)"
    }

    private var previewBox: some View {
        GroupBox("Preview (what you'll export)") {
            VStack(alignment: .leading, spacing: 8) {
                if !previewTargets.isEmpty {
                    Picker("Device", selection: Binding(
                        get: {
                            previewTargets.contains { $0.id == previewSizeID }
                                ? previewSizeID
                                : (previewTargets.first?.id ?? "")
                        },
                        set: { previewSizeID = $0 }
                    )) {
                        ForEach(previewTargets) { size in
                            Text("\(size.device) — \(size.fileTag)").tag(size.id)
                        }
                    }
                    .frame(maxWidth: 340)
                }
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Add a screenshot or video to preview the output.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
        }
        .task(id: previewKey) { await loadPreview() }
    }

    private func loadPreview() async {
        guard let asset = previewAsset else { previewImage = nil; return }
        if !previewTargets.contains(where: { $0.id == previewSizeID }) {
            previewSizeID = previewTargets.first?.id ?? ""
        }
        guard let target = previewTargets.first(where: { $0.id == previewSizeID }),
              let (url, started) = asset.resolvedURL() else { previewImage = nil; return }

        let options = ExportOptions(
            frameScreenshots: frameScreenshots,
            caption: caption.isEmpty ? nil : caption
        )
        let kind = asset.kind
        let size = target.pixelSize
        previewImage = await Task.detached(priority: .userInitiated) {
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            return Self.renderPreview(url: url, kind: kind, target: size, options: options)
        }.value
    }

    /// Render the real output (crop / bezel / caption; video → first frame) to
    /// an NSImage via a temp PNG.
    private static func renderPreview(
        url: URL, kind: AssetKind, target: PixelSize, options: ExportOptions
    ) -> NSImage? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // A URL to a still image to feed the renderers.
        var sourceURL = url
        if kind == .video {
            guard let frame = AssetThumbnail.firstFrame(of: url),
                  let framePNG = writePNG(frame, into: tmp) else { return nil }
            sourceURL = framePNG
        }

        let out = tmp.appendingPathComponent("out.png")
        do {
            if kind == .image, let caption = options.caption, !caption.isEmpty {
                try CaptionRenderer.render(source: sourceURL, to: target,
                                           caption: caption, style: options.captionStyle, output: out)
            } else if kind == .image, options.frameScreenshots {
                try BezelRenderer.renderFramed(source: sourceURL, to: target,
                                               style: options.frameStyle, output: out)
            } else {
                try ImageCropper.crop(source: sourceURL, to: target, output: out)
            }
        } catch {
            return nil
        }
        return NSImage(contentsOf: out)
    }

    private static func writePNG(_ image: NSImage, into dir: URL) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = dir.appendingPathComponent("frame.png")
        return (try? data.write(to: url)) != nil ? url : nil
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
            VStack(alignment: .leading, spacing: 6) {
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
                if !project.assets.contains(where: { $0.kind == .image }) {
                    Text("Add a screenshot (PNG/JPG) to get Android output — Google Play doesn't take videos, so a video alone produces none.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            options: ExportOptions(
                frameScreenshots: frameScreenshots,
                caption: caption.isEmpty ? nil : caption
            )
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

    /// Extract a poster frame from a video (thumbnail + preview).
    static func firstFrame(of url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
