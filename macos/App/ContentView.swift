import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: AppLibrary

    var body: some View {
        NavigationSplitView {
            List(selection: $library.selection) {
                ForEach(library.projects) { project in
                    Label(project.name, systemImage: "app.dashed")
                        .tag(project.id)
                }
            }
            .navigationTitle("Apps")
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        library.addProject()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add app")

                    Button {
                        library.removeSelected()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(library.selection == nil)
                    .help("Remove selected app")
                }
            }
        } detail: {
            if let project = library.selectedProject {
                // Re-create the detail view when the selection changes so its
                // @State (device toggles, progress) resets per app.
                AppDetailView(project: project)
                    .id(project.id)
            } else {
                ContentUnavailableView(
                    "No app selected",
                    systemImage: "app.dashed",
                    description: Text("Add an app to manage its screenshots and videos.")
                )
            }
        }
    }
}
