import NoteCore
import SwiftUI

/// Main screen: only folders, one level. Tap one to go inside, where the notes are.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Nav.self) private var nav

    @State private var showSettings = false
    @State private var showNewFolder = false
    @State private var nameText = ""
    @State private var renaming: Folder?
    @State private var movingSearchNote: Note?

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
            if model.isSearching {
                searchList
            } else {
                folderList
                trashButton
            }
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
            Button("Create") { Task { await model.createFolder(name: nameText) } }
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
        .sheet(item: $movingSearchNote) { note in
            MovePicker(current: note.folderId) { target in
                Task { await model.moveNote(note.id, to: target) }
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
            IconButton(systemName: "trash", label: "Delete") { Task { await model.trashPicked() } }
                .disabled(model.pickedCount == 0)
            Button("Done") { model.endSelection() }
        } else {
            IconButton(systemName: "folder.badge.plus", label: "New Folder") { startNewFolder() }
            Button("Edit") { model.selecting = true }
            IconButton(systemName: "gearshape", label: "Settings") { showSettings = true }
        }
    }

    private func startNewFolder() {
        nameText = ""
        showNewFolder = true
    }

    // MARK: Lists

    private var folderList: some View {
        List {
            Section {
                ForEach(folders) { folder in folderRow(folder) }
                    .onMove { source, destination in
                        Task { await model.moveFolders(in: nil, from: source, to: destination) }
                    }
            }
        }
        .environment(\.editMode, .constant(model.selecting ? .active : .inactive))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if folders.isEmpty {
                ContentUnavailableView {
                    Label(model.selecting ? "Nothing to Edit" : "No Folders", systemImage: "folder")
                } actions: {
                    Button("New Folder") { startNewFolder() }
                }
            }
        }
    }

    /// Search finds folders by name and notes by text. Any part of a word matches, any case.
    private var searchList: some View {
        List {
            if !model.matchingFolders.isEmpty {
                Section {
                    ForEach(model.matchingFolders) { folder in
                        Button {
                            nav.path.append(.folder(folder.id))
                        } label: {
                            FolderCard(title: folder.name, icon: "folder", count: model.noteCount(in: folder.id))
                        }
                        .buttonStyle(.plain)
                        .cardRow()
                    }
                } header: {
                    sectionTitle("Folders")
                }
            }
            if !model.notes.isEmpty {
                Section {
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
                        .contextMenu {
                            Button("Move", systemImage: "folder") { movingSearchNote = note }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.trashNote(note.id) }
                            }
                        }
                    }
                } header: {
                    if !model.matchingFolders.isEmpty { sectionTitle("Notes") }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.notes.isEmpty && model.matchingFolders.isEmpty {
                ContentUnavailableView { Label("No Results", systemImage: "magnifyingglass") }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .serif, weight: .bold))
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    /// Small and out of the way, at the bottom.
    private var trashButton: some View {
        let count = model.trash.folders.count + model.trash.notes.count
        return Button {
            nav.path.append(.trash)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "trash")
                Text(count > 0 ? "Trash \(count)" : "Trash")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    // MARK: Rows

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
                picked: model.selecting ? model.pickedFolders.contains(folder.id) : nil
            )
        }
        .buttonStyle(.plain)
        .cardRow()
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashFolder(folder.id) }
            }
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                nameText = folder.name
                renaming = folder
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                Task { await model.duplicateFolder(folder.id) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task { await model.trashFolder(folder.id) }
            }
        }
    }
}
