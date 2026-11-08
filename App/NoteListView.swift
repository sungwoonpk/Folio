import NoteCore
import SwiftUI

struct NoteListView: View {
    @Environment(AppModel.self) private var model
    @Environment(Nav.self) private var nav
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var moving: Note?
    @State private var movingPicked = false
    @State private var confirmEmpty = false
    @State private var confirmPurge = false

    private var isTrash: Bool { model.sidebar == .trash }
    private var nothingPicked: Bool { model.pickedNotes.isEmpty }
    private var trashIsEmpty: Bool { model.trash.folders.isEmpty && model.trash.notes.isEmpty }

    private var headerTitle: String {
        guard model.selectingNotes else { return model.title }
        return nothingPicked ? "Select" : "\(model.pickedNotes.count) Selected"
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Header(title: headerTitle, leading: leading) { actions }
            if !isTrash { SearchField(text: $model.query) }

            if isTrash { TrashView() } else { list }
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.query) {
            // Debounce typing.
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            await model.reloadNotes()
        }
        .confirmationDialog("Delete everything in Trash?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { Task { await model.emptyTrash() } }
        }
        .confirmationDialog(
            "Delete \(model.pickedNotes.count) forever?", isPresented: $confirmPurge, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await model.purgePicked() } }
        }
        .sheet(item: $moving) { note in
            MovePicker(title: "Move", current: note.folderId) { target in
                Task { await model.moveNote(note.id, to: target) }
            }
        }
        .sheet(isPresented: $movingPicked) {
            MovePicker(title: "Move", current: nil) { target in
                Task { await model.movePickedNotes(to: target) }
            }
        }
    }

    /// All header actions sit together on the right.
    @ViewBuilder
    private var actions: some View {
        if model.selectingNotes {
            Button(model.allNotesPicked ? "None" : "All") { model.toggleAllNotes() }
            if isTrash {
                IconButton(systemName: "arrow.uturn.backward", label: "Restore") {
                    Task { await model.restorePicked() }
                }
                .disabled(nothingPicked)
                IconButton(systemName: "trash", label: "Delete") { confirmPurge = true }
                    .disabled(nothingPicked)
            } else {
                IconButton(systemName: "folder", label: "Move") { movingPicked = true }
                    .disabled(nothingPicked)
                IconButton(systemName: "trash", label: "Delete") {
                    Task { await model.trashPickedNotes() }
                }
                .disabled(nothingPicked)
            }
            Button("Done") { model.endNoteSelection() }
        } else if isTrash {
            Button("Select") { model.selectingNotes = true }.disabled(trashIsEmpty)
            Button("Empty") { confirmEmpty = true }.disabled(trashIsEmpty)
        } else {
            IconButton(systemName: "checkmark.circle", label: "Select") { model.selectingNotes = true }
                .disabled(model.notes.isEmpty)
            IconButton(systemName: "square.and.pencil", label: "New Note") {
                Task {
                    await model.createNote()
                    nav.compactColumn = .detail
                }
            }
        }
    }

    /// Back on iPhone, sidebar toggle on iPad.
    private var leading: (icon: String, label: String, action: () -> Void) {
        if sizeClass == .compact {
            return ("chevron.left", "Home", { nav.compactColumn = .sidebar })
        }
        return ("sidebar.left", "Sidebar", {
            nav.columns = nav.columns == .all ? .doubleColumn : .all
        })
    }

    private var list: some View {
        List {
            ForEach(model.notes) { note in
                let open = !model.selectingNotes && model.selectedNoteId == note.id
                Button {
                    if model.selectingNotes {
                        model.toggleNote(note.id)
                    } else {
                        model.selectedNoteId = note.id
                        nav.compactColumn = .detail
                    }
                } label: {
                    HStack(spacing: 10) {
                        if model.selectingNotes {
                            SelectMark(picked: model.pickedNotes.contains(note.id))
                        }
                        NoteRow(note: note)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(open ? Theme.accent.opacity(0.12) : Color.clear)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.notes.isEmpty {
                if model.query.isEmpty {
                    // Writing never requires a folder.
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "note.text")
                    } actions: {
                        Button("New Note") {
                            Task {
                                await model.createNote()
                                nav.compactColumn = .detail
                            }
                        }
                    }
                } else {
                    ContentUnavailableView { Label("No Results", systemImage: "magnifyingglass") }
                }
            }
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.pinned {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                }
                Text(note.title.isEmpty ? "New Note" : note.title)
                    .font(.system(.headline, design: .serif))
                    .lineLimit(1)
            }
            Text(note.snippet.isEmpty ? "No additional text" : note.snippet)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(note.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(Theme.meta)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
