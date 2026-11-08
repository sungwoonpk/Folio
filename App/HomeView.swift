import NoteCore
import SwiftUI

/// Main screen: only folders. Tap one to go inside, where the notes are.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Nav.self) private var nav

    @State private var showSettings = false
    @State private var showNewFolder = false
    @State private var newFolderParent: UUID?
    @State private var nameText = ""
    @State private var renaming: Folder?
    @State private var movingFolder: Folder?
    @State private var movingPicked = false
    @State private var dropHighlight: String?

    private var folders: [Folder] { model.subfolders(of: nil) }

    private var headerTitle: String {
        guard model.selecting else { return "Note" }
        return model.pickedCount == 0 ? "Edit" : "\(model.pickedCount) Selected"
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Header(title: headerTitle) { actions }
            SearchField(text: $model.query)
            if model.isSearching { searchList } else { folderList }
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.query) {
            // Debounce typing.
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            await model.reloadNotes()
        }
        .onDisappear { model.endSelection() }
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
            MovePicker(title: "Move", rootTitle: "Note", excluding: folder.id, current: folder.parentId) { target in
                Task { await model.moveFolder(folder.id, to: target) }
            }
        }
        .sheet(isPresented: $movingPicked) {
            MovePicker(title: "Move", rootTitle: "Note") { target in
                Task { await model.movePicked(to: target) }
            }
        }
    }

    // MARK: Header actions, all together on the right

    @ViewBuilder
    private var actions: some View {
        if model.selecting {
            Button(model.allPicked(notes: [], folders: folders) ? "Deselect All" : "Select All") {
                model.toggleAll(notes: [], folders: folders)
            }
            IconButton(systemName: "folder", label: "Move") { movingPicked = true }
                .disabled(model.pickedCount == 0)
            IconButton(systemName: "trash", label: "Delete") { Task { await model.trashPicked() } }
                .disabled(model.pickedCount == 0)
            Button("Done") { model.endSelection() }
        } else {
            IconButton(systemName: "folder.badge.plus", label: "New Folder") {
                newFolderParent = nil
                nameText = ""
                showNewFolder = true
            }
            Button("Edit") { model.selecting = true }.disabled(folders.isEmpty)
            IconButton(systemName: "gearshape", label: "Settings") { showSettings = true }
        }
    }

    // MARK: Lists

    private var folderList: some View {
        List {
            Section {
                // Only shows if notes without a folder are left over, so none get lost.
                if !model.notes(in: nil).isEmpty { notesRow }
                ForEach(folders) { folder in folderRow(folder) }
                    .onMove { source, destination in
                        Task { await model.moveFolders(in: nil, from: source, to: destination) }
                    }
            }
            // Trash stays out of the way, at the very bottom.
            Section { trashRow }
        }
        .environment(\.editMode, .constant(model.selecting ? .active : .inactive))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if folders.isEmpty && model.notes(in: nil).isEmpty {
                ContentUnavailableView {
                    Label("No Folders", systemImage: "folder")
                } actions: {
                    Button("New Folder") {
                        newFolderParent = nil
                        nameText = ""
                        showNewFolder = true
                    }
                }
            }
        }
    }

    private var searchList: some View {
        List {
            ForEach(model.notes) { note in
                Button {
                    model.selectedNoteId = note.id
                    nav.compactColumn = .detail
                } label: {
                    NoteRow(note: note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.notes.isEmpty {
                ContentUnavailableView { Label("No Results", systemImage: "magnifyingglass") }
            }
        }
    }

    // MARK: Rows

    /// Notes that are not in any folder. Always there, so writing never needs a folder.
    private var notesRow: some View {
        Button {
            nav.path.append(.folder(nil))
        } label: {
            FolderCard(
                title: "Notes", icon: "note.text", count: model.notes(in: nil).count,
                highlighted: dropHighlight == "notes"
            )
        }
        .buttonStyle(.plain)
        .cardRow()
        .acceptsItems(into: nil, key: "notes", highlight: $dropHighlight)
    }

    private func folderRow(_ folder: Folder) -> some View {
        Button {
            if model.selecting {
                model.toggleFolder(folder.id)
            } else {
                nav.path.append(.folder(folder.id))
            }
        } label: {
            FolderCard(
                title: folder.name, icon: "folder", count: model.noteCount(in: folder.id),
                picked: model.selecting ? model.pickedFolders.contains(folder.id) : nil,
                highlighted: dropHighlight == folder.id.uuidString
            )
        }
        .buttonStyle(.plain)
        .cardRow()
        .draggableItem(ItemRef(kind: .folder, id: folder.id), enabled: !model.selecting)
        .acceptsItems(into: folder.id, key: folder.id.uuidString, highlight: $dropHighlight)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashFolder(folder.id) }
            }
        }
        .contextMenu {
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

    private var trashRow: some View {
        let count = model.trash.folders.count + model.trash.notes.count
        return Button {
            nav.path.append(.trash)
        } label: {
            FolderCard(title: "Trash", icon: "trash", count: count > 0 ? count : nil, muted: true)
        }
        .buttonStyle(.plain)
        .cardRow()
    }
}
