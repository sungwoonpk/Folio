import NoteCore
import SwiftUI

struct TrashView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEmpty = false

    var body: some View {
        List {
            if !model.trash.folders.isEmpty {
                Section("Folders") {
                    ForEach(model.trash.folders) { folder in
                        Label(folder.name, systemImage: "folder")
                            .swipeActions(edge: .leading) {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    Task { await model.restoreFolder(folder.id) }
                                }
                                .tint(Theme.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await model.purgeFolder(folder.id) }
                                }
                            }
                    }
                }
            }
            if !model.trash.notes.isEmpty {
                Section("Notes") {
                    ForEach(model.trash.notes) { note in
                        NoteRow(note: note)
                            .swipeActions(edge: .leading) {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    Task { await model.restoreNote(note.id) }
                                }
                                .tint(Theme.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await model.purgeNote(note.id) }
                                }
                            }
                    }
                }
            }
        }
        .overlay {
            if model.trash.folders.isEmpty && model.trash.notes.isEmpty {
                ContentUnavailableView("Trash is Empty", systemImage: "trash")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Empty", role: .destructive) { confirmEmpty = true }
                    .disabled(model.trash.folders.isEmpty && model.trash.notes.isEmpty)
            }
        }
        .confirmationDialog("Delete everything in Trash?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { Task { await model.emptyTrash() } }
        }
    }
}
