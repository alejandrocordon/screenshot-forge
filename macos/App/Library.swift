import Foundation
import ForgeCore

/// One managed app with its screenshots and preview videos.
///
/// For the MVP this is an in-memory model. The natural next step is to make it
/// a SwiftData `@Model` so a library of apps persists between launches (and to
/// store security-scoped bookmarks for the imported files).
final class AppProject: Identifiable, ObservableObject {
    let id = UUID()
    @Published var name: String
    @Published var screenshots: [URL]
    @Published var videos: [URL]

    init(name: String, screenshots: [URL] = [], videos: [URL] = []) {
        self.name = name
        self.screenshots = screenshots
        self.videos = videos
    }

    var allAssets: [URL] { screenshots + videos }
}

/// The library of apps shown in the sidebar.
final class AppLibrary: ObservableObject {
    @Published var projects: [AppProject]
    @Published var selection: AppProject.ID?

    init(projects: [AppProject] = []) {
        self.projects = projects
        self.selection = projects.first?.id
    }

    var selectedProject: AppProject? {
        projects.first { $0.id == selection }
    }

    func addProject(named name: String = "New App") {
        let project = AppProject(name: name)
        projects.append(project)
        selection = project.id
    }

    func removeSelected() {
        guard let id = selection else { return }
        projects.removeAll { $0.id == id }
        selection = projects.first?.id
    }

    /// Seed with one empty app so the first launch isn't a blank window.
    static func previewSeed() -> AppLibrary {
        AppLibrary(projects: [AppProject(name: "My App")])
    }
}
