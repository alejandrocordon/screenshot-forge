import SwiftUI

@main
struct ScreenshotForgeApp: App {
    @StateObject private var library = AppLibrary.previewSeed()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
