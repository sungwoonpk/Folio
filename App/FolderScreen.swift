import NoteCore
import SwiftUI

/// Inside a folder: its subfolders and notes. folderId nil is "Notes", the notes without a folder.
/// Create notes, delete, select and move here.
struct FolderScreen: View {
    let folderId: UUID?

    @Environment(AppModel.self) private var model
    @Environment(Nav.self) private var nav

    @State private var showNewFolder = false
    @State private var nameText = ""
    @State private var renaming: Folder?
    @State private var movingFolder: Folder?
    @State private var movingNote: Note?
    @State private var movingPicked = false
    @State private var dropHighlight: String?

    private var folder: Folder? { model.folder(folderId) }
    private var subfolders: [Folder] { folderId == nil ? [] : model.subfolders(of: folderId) }
    private var notes: [Note] { model.notes(in: folderId) }
    private var isEmpty: Bool { subfolders.isEmpty && notes.isEmpty }

    private var title: String {
        guard model.selecting else { return folderId == nil ? "Notes" : (folder?.name ?? "") }
        return model.pickedCount == 0 ? "Edit" : "\(model.pickedCount) Selected"
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(title: title, leading: ("chevron.left", "Back", { nav.back() })) { actions }
                .background(dropHighlight == "header" ? Theme.accent.opacity(0.15) : Color.clear)
                // Drop on the header to take an item out, up to the parent folder.
                .acceptsItems(into: folder?.parentId, key: "header", enabled: folder?.parentId != nil, highlight: $dropHighlight)
            list
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { model.endSelection() }
        // This folder was deleted or moved to trash: leave the screen.
        .onChange(of: model.folders.count) {
            if let id = folderId, folder == nil { nav.path.removeAll { $0 == .folder(id) } }
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $nameText)
            Button("Create") { Task { await model.createFolder(name: nameText, parentId: folderId) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $nameText)
            Button("Save") {
                if let folder = renaming { Task { await model.renameFolder(folder.id, to: nameText) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $movingFolder) { sub in
            MovePicker(title: "Move", rootTitle: "Note", excluding: sub.id, current: sub.parentId) { target in
                Task { await model.moveFolder(sub.id, to: target) }
            }
        }
        .sheet(item: $movingNote) { note in
            MovePicker(title: "Move", allowRoot: false, current: note.folderId) { target in
                Task { await model.moveNote(note.id, to: target) }
            }
        }
        .sheet(isPresented: $movingPicked) {
            MovePicker(title: "Move", allowRoot: model.pickedNotes.isEmpty, current: folderId) { target in
                Task { await model.movePicked(to: target) }
            }
        }
    }

    // MARK: Header actions

    @ViewBuilder
    private var actions: some View {
        if model.selecting {
            Button(model.allPicked(notes: notes, folders: subfolders) ? "Deselect All" : "Select All") {
                model.toggleAll(notes: notes, folders: subfolders)
            }
            IconButton(systemName: "folder", label: "Move") { movingPicked = true }
                .disabled(model.pickedCount == 0)
            IconButton(systemName: "trash", label: "Delete") { Task { await model.trashPicked() } }
                .disabled(model.pickedCount == 0)
            Button("Done") { model.endSelection() }
        } else {
            if folderId != nil {
                IconButton(systemName: "folder.badge.plus", label: "New Folder") {
                    nameText = ""
                    showNewFolder = true
                }
            }
            Button("Edit") { model.selecting = true }.disabled(isEmpty)
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
            if !subfolders.isEmpty {
                Section {
                    ForEach(subfolders) { sub in subfolderRow(sub) }
                        .onMove { source, destination in
                            Task { await model.moveFolders(in: folderId, from: source, to: destination) }
                        }
                } header: {
                    sectionTitle("Folders")
                }
            }
            // Notes by last change: Today, Last 7 Days, Last 30 Days, months, years.
            ForEach(NoteGrouping.sections(notes)) { section in
                Section {
                    ForEach(section.notes) { note in noteRow(note) }
                } header: {
                    sectionTitle(section.title)
                }
            }
        }
        .environment(\.editMode, .constant(model.selecting ? .active : .inactive))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if isEmpty {
                ContentUnavailableView {
                    Label("No Notes", systemImage: "note.text")
                } actions: {
                    Button("New Note") { newNote() }
                }
            }
        }
    }

    private func subfolderRow(_ sub: Folder) -> some View {
        Button {
            if model.selecting {
                model.toggleFolder(sub.id)
            } else {
                nav.path.append(.folder(sub.id))
            }
        } label: {
            FolderCard(
                title: sub.name, icon: "folder", count: model.noteCount(in: sub.id),
                picked: model.selecting ? model.pickedFolders.contains(sub.id) : nil,
                highlighted: dropHighlight == sub.id.uuidString
            )
        }
        .buttonStyle(.plain)
        .cardRow()
        .draggableItem(ItemRef(kind: .folder, id: sub.id), enabled: !model.selecting)
        .acceptsItems(into: sub.id, key: sub.id.uuidString, highlight: $dropHighlight)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashFolder(sub.id) }
            }
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                nameText = sub.name
                renaming = sub
            }
            Button("Move", systemImage: "folder") { movingFolder = sub }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                Task { await model.duplicateFolder(sub.id) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashFolder(sub.id) }
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
        .draggableItem(ItemRef(kind: .note, id: note.id), enabled: !model.selecting)
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
            Button("Move", systemImage: "folder") { movingNote = note }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                Task { await model.duplicateNote(note.id) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashNote(note.id) }
            }
        }
    }
}
