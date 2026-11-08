import NoteCore
import SwiftUI

/// Inside a folder: its notes. Create notes, delete, select and move here.
/// folderId nil is the notes that are in no folder, only reachable if some are left over.
struct FolderScreen: View {
    let folderId: UUID?

    @Environment(AppModel.self) private var model
    @Environment(Nav.self) private var nav

    @State private var movingNote: Note?
    @State private var movingPicked = false

    private var folder: Folder? { model.folder(folderId) }
    private var notes: [Note] { model.notes(in: folderId) }

    private var title: String {
        guard model.selecting else { return folderId == nil ? "Notes" : (folder?.name ?? "") }
        return model.pickedCount == 0 ? "Edit" : "\(model.pickedCount) Selected"
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(title: title, leading: ("chevron.left", "Back", { nav.back() })) { actions }
            list
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { model.endSelection() }
        // This folder was deleted: leave the screen.
        .onChange(of: model.folders.count) {
            if let id = folderId, folder == nil { nav.path.removeAll { $0 == .folder(id) } }
        }
        .sheet(item: $movingNote) { note in
            MovePicker(current: note.folderId) { target in
                Task { await model.moveNote(note.id, to: target) }
            }
        }
        .sheet(isPresented: $movingPicked) {
            MovePicker(current: folderId) { target in
                Task { await model.movePicked(to: target) }
            }
        }
    }

    // MARK: Header actions

    @ViewBuilder
    private var actions: some View {
        if model.selecting {
            Button(model.allPicked(notes: notes, folders: []) ? "Deselect All" : "Select All") {
                model.toggleAll(notes: notes, folders: [])
            }
            IconButton(image: MoveIcon.image, label: "Move") { movingPicked = true }
                .disabled(model.pickedCount == 0)
            IconButton(systemName: "trash", label: "Delete") { Task { await model.trashPicked() } }
                .disabled(model.pickedCount == 0)
            Button("Done") { model.endSelection() }
        } else {
            Button("Edit") { model.selecting = true }
            IconButton(systemName: "square.and.pencil", label: "New Note") { newNote() }
        }
    }

    private func newNote() {
        Task {
            await model.createNote(in: folderId)
            nav.compactColumn = .detail
        }
    }

    // MARK: List

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .serif, weight: .bold))
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    private var list: some View {
        List {
            // Notes by last change: Today, Last 7 Days, Last 30 Days, months, years.
            ForEach(NoteGrouping.sections(notes)) { section in
                Section {
                    ForEach(section.notes) { note in noteRow(note) }
                } header: {
                    sectionTitle(section.title)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView {
                    Label(model.selecting ? "Nothing to Edit" : "No Notes", systemImage: "note.text")
                } actions: {
                    Button("New Note") { newNote() }
                }
            }
        }
    }

    private func noteRow(_ note: Note) -> some View {
        let open = !model.selecting && model.selectedNoteId == note.id
        return Button {
            if model.selecting {
                model.toggleNote(note.id)
            } else {
                model.selectedNoteId = note.id
                nav.compactColumn = .detail
            }
        } label: {
            HStack(spacing: 10) {
                if model.selecting { SelectMark(picked: model.pickedNotes.contains(note.id)) }
                NoteRow(note: note)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(open ? Theme.accent.opacity(0.12) : Color.clear)
                .padding(.horizontal, 8)
        )
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
            Button { movingNote = note } label: { Label { Text("Move") } icon: { MoveIcon.image } }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                Task { await model.duplicateNote(note.id) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashNote(note.id) }
            }
        }
    }
}
