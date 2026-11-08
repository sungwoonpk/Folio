import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.trashDays) private var trashDays = 30
    @State private var columns: NavigationSplitViewVisibility = .automatic
    // On iPhone, open on the note list instead of the folder list.
    @State private var compactColumn: NavigationSplitViewColumn = .content

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            SidebarView()
        } content: {
            NoteListView()
        } detail: {
            if model.sidebar == .trash {
                ContentUnavailableView("Trash", systemImage: "trash")
            } else if let id = model.selectedNoteId {
                EditorView(noteId: id).id(id)
            } else {
                ContentUnavailableView("No Note", systemImage: "square.and.pencil")
            }
        }
        .navigationSplitViewStyle(.balanced)
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
