import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import ForgeCore

struct AppDetailView: View {
    @Bindable var project: AppProject
    @Environment(\.modelContext) private var context

    @State private var selectedDevices: Set<AppleDevice> = Set(AppleDevice.allCases)
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var statusText = ""
    @State private var showImporter = false

    private let engine = BatchEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("App name", text: $project.name)
                .textFieldStyle(.roundedBorder)
                .font(.title2)

            assetsBox
            devicesBox
            exportRow

            Spacer()
        }
        .padding(20)
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

    private var devicesBox: some View {
        GroupBox("Apple devices") {
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

    private var exportRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await export() }
            } label: {
                Label("Export all Apple sizes", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isExporting || project.assets.isEmpty || selectedDevices.isEmpty)

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

        let outcome = await engine.run(
            inputs: urls,
            devices: devices,
            outputRoot: outputRoot
        ) { update in
            Task { @MainActor in
                progress = update.fraction
                statusText = update.message
            }
        }

        statusText = "Done — \(outcome.processed) generated, \(outcome.failures.count) errors"
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
        if asset.kind == .video {
            placeholder("film")
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholder(loadFailed ? "exclamationmark.triangle" : "photo")
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
        guard asset.kind == .image, image == nil else { return }
        guard let (url, started) = asset.resolvedURL() else {
            loadFailed = true
            return
        }
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        if let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            loadFailed = true
        }
    }
}
