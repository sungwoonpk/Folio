import NoteCore
import SwiftUI

/// Home: folders on top, notes without a folder below.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Nav.self) private var nav

    @State private var showSettings = false
    @State private var showNewFolder = false
    @State private var newFolderParent: UUID?
    @State private var nameText = ""
    @State private var renaming: Folder?
    @State private var movingFolder: Folder?
    @State private var movingNote: Note?
    @State private var movingPicked = false

    private var headerTitle: String {
        guard model.selecting else { return "Note AI" }
        return model.pickedCount == 0 ? "Select" : "\(model.pickedCount) Selected"
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Header(title: headerTitle) { actions }
            SearchField(text: $model.query)
            if model.isSearching { searchList } else { homeList }
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.query) {
            // Debounce typing.
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            await model.reloadNotes()
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $nameText)
            Button("Create") { Task { await model.createFolder(name: nameText, parentId: newFolderParent) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $nameText)
            Button("Save") {
                if let folder = renaming { Task { await model.renameFolder(folder.id, to: nameText) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $movingFolder) { folder in
            MovePicker(title: "Move", excluding: folder.id, current: folder.parentId) { target in
                Task { await model.moveFolder(folder.id, to: target) }
            }
        }
        .sheet(item: $movingNote) { note in
            MovePicker(title: "Move", current: note.folderId) { target in
                Task { await model.moveNote(note.id, to: target) }
            }
        }
        .sheet(isPresented: $movingPicked) {
            MovePicker(title: "Move", current: nil) { target in
                Task { await model.movePicked(to: target) }
            }
        }
    }

    // MARK: Header actions, all together on the right

    @ViewBuilder
    private var actions: some View {
        if model.selecting {
            Button(model.allPicked ? "None" : "All") { model.toggleAll() }
            IconButton(systemName: "folder", label: "Move") { movingPicked = true }
                .disabled(model.pickedCount == 0)
            IconButton(systemName: "trash", label: "Delete") { Task { await model.trashPicked() } }
                .disabled(model.pickedCount == 0)
            Button("Done") { model.endSelection() }
        } else {
            IconButton(systemName: "checkmark.circle", label: "Select") { model.selecting = true }
                .disabled(model.notes.isEmpty && model.folders.isEmpty)
            IconButton(systemName: "folder.badge.plus", label: "New Folder") {
                newFolderParent = nil
                nameText = ""
                showNewFolder = true
            }
            IconButton(systemName: "square.and.pencil", label: "New Note") { newNote(in: nil) }
            IconButton(systemName: "gearshape", label: "Settings") { showSettings = true }
        }
    }

    private func newNote(in folderId: UUID?) {
        Task {
            await model.createNote(in: folderId)
            nav.compactColumn = .detail
        }
    }

    // MARK: Lists

    private var homeList: some View {
        List {
            Section {
                ForEach(model.folderRows) { row in
                    switch row {
                    case .folder(let folder, let depth): folderRow(folder, depth: depth)
                    case .note(let note, let depth): noteRow(note, depth: depth)
                    }
                }
                trashRow
            } header: {
                sectionHeader("FOLDERS")
            }

            Section {
                ForEach(model.looseNotes) { note in noteRow(note, depth: 0) }
            } header: {
                sectionHeader("NOTES")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.notes.isEmpty && model.folders.isEmpty {
                ContentUnavailableView {
                    Label("No Notes", systemImage: "note.text")
                } actions: {
                    Button("New Note") { newNote(in: nil) }
                }
            }
        }
    }

    private var searchList: some View {
        List {
            ForEach(model.notes) { note in noteRow(note, depth: 0) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.notes.isEmpty {
                ContentUnavailableView { Label("No Results", systemImage: "magnifyingglass") }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(Theme.meta).foregroundStyle(.secondary)
    }

    // MARK: Rows

    private func folderRow(_ folder: Folder, depth: Int) -> some View {
        let isOpen = model.expanded.contains(folder.id)
        return Button {
            if model.selecting {
                model.toggleFolder(folder.id)
            } else {
                withAnimation(.snappy(duration: 0.2)) {
                    if isOpen { model.expanded.remove(folder.id) } else { model.expanded.insert(folder.id) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                if model.selecting { SelectMark(picked: model.pickedFolders.contains(folder.id)) }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 14)
                Image(systemName: isOpen ? "folder.fill" : "folder").foregroundStyle(Theme.accent)
                Text(folder.name).font(Theme.serifBody)
                Spacer()
                Text("\(model.noteCount(in: folder.id))").font(Theme.meta).foregroundStyle(.secondary)
            }
            .padding(.leading, CGFloat(depth) * 20)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashFolder(folder.id) }
            }
        }
        .contextMenu {
            Button("New Note", systemImage: "square.and.pencil") { newNote(in: folder.id) }
            Button("New Folder", systemImage: "folder.badge.plus") {
                newFolderParent = folder.id
                nameText = ""
                showNewFolder = true
            }
            Button("Rename", systemImage: "pencil") {
                nameText = folder.name
                renaming = folder
            }
            Button("Move", systemImage: "folder") { movingFolder = folder }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                Task { await model.duplicateFolder(folder.id) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashFolder(folder.id) }
            }
        }
    }

    private func noteRow(_ note: Note, depth: Int) -> some View {
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
            .padding(.leading, depth > 0 ? CGFloat(depth) * 20 + 24 : 0)
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
            Button("Move", systemImage: "folder") { movingNote = note }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                Task { await model.duplicateNote(note.id) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashNote(note.id) }
            }
        }
    }

    private var trashRow: some View {
        let count = model.trash.folders.count + model.trash.notes.count
        return Button {
            nav.showTrash = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).hidden().frame(width: 14)
                Image(systemName: "trash").foregroundStyle(Theme.accent)
                Text("Trash").font(Theme.serifBody)
                Spacer()
                if count > 0 { Text("\(count)").font(Theme.meta).foregroundStyle(.secondary) }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }
}
