import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AppProject.createdAt) private var projects: [AppProject]
    @State private var selection: AppProject?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(projects) { project in
                    Label(project.name, systemImage: "app.dashed")
                        .tag(project)
                }
            }
            .navigationTitle("Apps")
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItemGroup {
                    Button(action: addProject) {
                        Image(systemName: "plus")
                    }
                    .help("Add app")

                    Button(action: removeSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    .help("Remove selected app")
                }
            }
        } detail: {
            if let selection {
                AppDetailView(project: selection)
                    .id(selection.persistentModelID)
            } else {
                ContentUnavailableView(
                    "No app selected",
                    systemImage: "app.dashed",
                    description: Text("Add an app to manage its screenshots and videos.")
                )
            }
        }
    }

    private func addProject() {
        let project = AppProject(name: "New App")
        context.insert(project)
        selection = project
    }

    private func removeSelected() {
        guard let selection else { return }
        context.delete(selection)
        self.selection = nil
    }
}
