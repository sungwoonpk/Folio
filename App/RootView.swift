import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var nav = Nav()

    var body: some View {
        NavigationSplitView(
            columnVisibility: Binding(get: { nav.columns }, set: { nav.columns = $0 }),
            preferredCompactColumn: Binding(get: { nav.compactColumn }, set: { nav.compactColumn = $0 })
        ) {
            NavigationStack(path: Binding(get: { nav.path }, set: { nav.path = $0 })) {
                HomeView()
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .folder(let id): FolderScreen(folderId: id)
                        case .trash: TrashScreen()
                        }
                    }
            }
        } detail: {
            Group {
                if let id = model.selectedNoteId {
                    EditorView(noteId: id).id(id)
                } else {
                    ContentUnavailableView("No Note", systemImage: "square.and.pencil")
                }
            }
            .background(Theme.paper)
            .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(nav)
        .task {
            await model.purgeExpiredTrash()
            await model.reloadAll()
        }
    }
}
