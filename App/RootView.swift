import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var nav = Nav()

    var body: some View {
        NavigationSplitView(
            columnVisibility: Binding(get: { nav.columns }, set: { nav.columns = $0 }),
            preferredCompactColumn: Binding(get: { nav.compactColumn }, set: { nav.compactColumn = $0 })
        ) {
            NavigationStack {
                HomeView()
                    .navigationDestination(
                        isPresented: Binding(get: { nav.showTrash }, set: { nav.showTrash = $0 })
                    ) {
                        TrashScreen()
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
        .task { await model.reloadAll() }
    }
}
