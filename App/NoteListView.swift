import NoteCore
import SwiftUI

struct NoteListView: View {
    @Environment(AppModel.self) private var model
    @State private var moving: Note?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.sidebar == .trash {
                TrashView()
            } else {
                list
            }
        }
        .navigationTitle(model.title)
        .searchable(text: $model.query, prompt: "Search")
        .task(id: model.query) {
            // Debounce typing.
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            await model.reloadNotes()
        }
        .toolbar {
            if model.sidebar != .trash {
                ToolbarItem(placement: .bottomBar) {
                    Button("New Note", systemImage: "square.and.pencil") {
                        Task { await model.createNote() }
                    }
                }
            }
        }
        .sheet(item: $moving) { note in
            MovePicker(title: "Move", current: note.folderId) { target in
                Task { await model.moveNote(note.id, to: target) }
            }
        }
    }

    private var list: some View {
        @Bindable var model = model
        return List(selection: $model.selectedNoteId) {
            ForEach(model.notes) { note in
                NoteRow(note: note)
                    .tag(note.id)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await model.trashNote(note.id) }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") {
                            Task { await model.togglePin(note) }
                        }
                        .tint(Theme.accent)
                    }
                    .contextMenu {
                        Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") {
                            Task { await model.togglePin(note) }
                        }
                        Button("Move", systemImage: "folder") { moving = note }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            Task { await model.duplicateNote(note.id) }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await model.trashNote(note.id) }
                        }
                    }
            }
        }
        .overlay {
            if model.notes.isEmpty {
                if model.query.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "note.text")
                } else {
                    ContentUnavailableView.search(text: model.query)
                }
            }
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if note.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.accent)
                }
                Text(note.title.isEmpty ? "New Note" : note.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(note.updatedAt, format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
                Text(note.snippet.isEmpty ? "No additional text" : note.snippet)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
