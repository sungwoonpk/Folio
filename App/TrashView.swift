import NoteCore
import SwiftUI

/// List only. The header, select and empty buttons live in NoteListView.
struct TrashView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if !model.trash.folders.isEmpty {
                Section {
                    ForEach(model.trash.folders) { folder in
                        HStack(spacing: 10) {
                            if model.selectingNotes {
                                SelectMark(picked: model.pickedNotes.contains(folder.id))
                            }
                            Label(folder.name, systemImage: "folder")
                                .font(Theme.serifBody)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if model.selectingNotes { model.toggleNote(folder.id) } }
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
                } header: {
                    Text("FOLDERS").font(Theme.meta)
                }
            }
            if !model.trash.notes.isEmpty {
                Section {
                    ForEach(model.trash.notes) { note in
                        HStack(spacing: 10) {
                            if model.selectingNotes {
                                SelectMark(picked: model.pickedNotes.contains(note.id))
                            }
                            NoteRow(note: note)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if model.selectingNotes { model.toggleNote(note.id) } }
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
                } header: {
                    Text("NOTES").font(Theme.meta)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.trash.folders.isEmpty && model.trash.notes.isEmpty {
                ContentUnavailableView("Trash is Empty", systemImage: "trash")
            }
        }
    }
}
