import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ForgeCore

struct AppDetailView: View {
    @ObservedObject var project: AppProject

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
                if project.allAssets.isEmpty {
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
                            ForEach(project.allAssets, id: \.self) { url in
                                AssetThumbnail(url: url)
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
            .disabled(isExporting || project.allAssets.isEmpty || selectedDevices.isEmpty)

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
            switch SupportedTypes.kind(of: url) {
            case .image:
                if !project.screenshots.contains(url) { project.screenshots.append(url) }
            case .video:
                if !project.videos.contains(url) { project.videos.append(url) }
            case .none:
                break
            }
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

        let devices = AppleDevice.allCases.filter { selectedDevices.contains($0) }
        let outcome = await engine.run(
            inputs: project.allAssets,
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

/// A small thumbnail for a screenshot (rendered) or a video (icon placeholder).
struct AssetThumbnail: View {
    let url: URL

    var body: some View {
        VStack(spacing: 4) {
            thumbnail
            Text(url.lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 84)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        switch SupportedTypes.kind(of: url) {
        case .image:
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                placeholder("photo")
            }
        case .video:
            placeholder("film")
        case .none:
            placeholder("questionmark")
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
        }
        .frame(width: 80, height: 80)
    }
}
