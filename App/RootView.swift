import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.trashDays) private var trashDays = 30
    @State private var nav = Nav()

    var body: some View {
        NavigationSplitView(
            columnVisibility: Binding(get: { nav.columns }, set: { nav.columns = $0 }),
            preferredCompactColumn: Binding(get: { nav.compactColumn }, set: { nav.compactColumn = $0 })
        ) {
            SidebarView()
        } content: {
            NoteListView()
        } detail: {
            Group {
                if model.sidebar == .trash {
                    ContentUnavailableView("Trash", systemImage: "trash")
                } else if let id = model.selectedNoteId {
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
            await model.reloadAll()
            await model.purgeExpiredTrash(days: trashDays)
        }
        .onChange(of: model.sidebar) {
            model.selectedNoteId = nil
            model.query = ""
            Task { await model.reloadNotes() }
        }
    }
}
