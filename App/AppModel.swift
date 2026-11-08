import Foundation
import NoteCore
import Observation

enum SidebarItem: Hashable {
    case all
    case folder(UUID)
    case trash
}

struct FolderNode: Identifiable, Hashable {
    let folder: Folder
    var children: [FolderNode]?
    var id: UUID { folder.id }

    static func tree(_ folders: [Folder], parent: UUID? = nil) -> [FolderNode]? {
        let nodes = folders.filter { $0.parentId == parent }.map {
            FolderNode(folder: $0, children: tree(folders, parent: $0.id))
        }
        return nodes.isEmpty ? nil : nodes
    }
}

@MainActor @Observable
final class AppModel {
    let store: NoteStore

    var folders: [Folder] = []
    var notes: [Note] = []
    var trash = TrashContents(folders: [], notes: [])

    var sidebar: SidebarItem? = .all
    var selectedNoteId: UUID?
    var query = ""

    init() {
        let database: AppDatabase
        do {
            let dir = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            database = try AppDatabase.open(at: dir.appendingPathComponent("notes.sqlite"))
        } catch {
            // Never crash on launch. Fall back to a temporary database.
            database = try! AppDatabase.inMemory()
        }
        store = NoteStore(database: database)
    }

    var folderTree: [FolderNode] { FolderNode.tree(folders) ?? [] }

    var currentFolderId: UUID? {
        if case .folder(let id) = sidebar { return id }
        return nil
    }

    var title: String {
        switch sidebar {
        case .folder(let id): folders.first { $0.id == id }?.name ?? "Notes"
        case .trash: "Trash"
        default: "Notes"
        }
    }

    // MARK: Loading

    func reloadAll() async {
        folders = (try? await store.folders()) ?? []
        await reloadNotes()
    }

    func reloadNotes() async {
        if sidebar == .trash {
            trash = (try? await store.trash()) ?? TrashContents(folders: [], notes: [])
            return
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            let scope: NoteScope = currentFolderId.map { .folder($0) } ?? .all
            notes = (try? await store.notes(in: scope)) ?? []
        } else {
            notes = (try? await store.search(q, in: currentFolderId)) ?? []
        }
    }

    // MARK: Folder actions

    func createFolder(name: String, parentId: UUID?) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = try? await store.createFolder(name: trimmed, parentId: parentId)
        await reloadAll()
    }

    func renameFolder(_ id: UUID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? await store.renameFolder(id: id, to: trimmed)
        await reloadAll()
    }

    func moveFolder(_ id: UUID, to parentId: UUID?) async {
        try? await store.moveFolder(id: id, to: parentId)
        await reloadAll()
    }

    func duplicateFolder(_ id: UUID) async {
        _ = try? await store.duplicateFolder(id: id)
        await reloadAll()
    }

    func trashFolder(_ id: UUID) async {
        try? await store.trashFolder(id: id)
        if let current = currentFolderId, current == id || isDescendant(current, of: id) {
            sidebar = .all
            selectedNoteId = nil
        }
        await reloadAll()
    }

    // MARK: Note actions

    func createNote() async {
        guard let note = try? await store.createNote(folderId: currentFolderId) else { return }
        query = ""
        await reloadNotes()
        selectedNoteId = note.id
    }

    func moveNote(_ id: UUID, to folderId: UUID?) async {
        try? await store.moveNote(id: id, to: folderId)
        await reloadNotes()
    }

    func duplicateNote(_ id: UUID) async {
        _ = try? await store.duplicateNote(id: id)
        await reloadNotes()
    }

    func togglePin(_ note: Note) async {
        try? await store.setPinned(id: note.id, !note.pinned)
        await reloadNotes()
    }

    func trashNote(_ id: UUID) async {
        try? await store.trashNote(id: id)
        if selectedNoteId == id { selectedNoteId = nil }
        await reloadNotes()
    }

    /// Notes opened and left empty are removed, like Apple Notes.
    func discardIfEmpty(_ id: UUID) async {
        try? await store.purgeNote(id: id)
        if selectedNoteId == id { selectedNoteId = nil }
        await reloadNotes()
    }

    // MARK: Trash actions

    func restoreNote(_ id: UUID) async {
        try? await store.restoreNote(id: id)
        await reloadAll()
    }

    func restoreFolder(_ id: UUID) async {
        try? await store.restoreFolder(id: id)
        await reloadAll()
    }

    func purgeNote(_ id: UUID) async {
        try? await store.purgeNote(id: id)
        await reloadNotes()
    }

    func purgeFolder(_ id: UUID) async {
        try? await store.purgeFolder(id: id)
        await reloadNotes()
    }

    func emptyTrash() async {
        try? await store.emptyTrash()
        await reloadNotes()
    }

    // MARK: Helpers

    func isDescendant(_ id: UUID, of ancestor: UUID) -> Bool {
        var current = folders.first { $0.id == id }?.parentId
        while let parent = current {
            if parent == ancestor { return true }
            current = folders.first { $0.id == parent }?.parentId
        }
        return false
    }

    /// Folders a folder or note can be moved into, as indented rows.
    func moveTargets(excluding folderId: UUID? = nil) -> [(folder: Folder, depth: Int)] {
        func walk(_ nodes: [FolderNode]?, depth: Int) -> [(Folder, Int)] {
            (nodes ?? []).flatMap { node -> [(Folder, Int)] in
                if node.id == folderId { return [] }
                return [(node.folder, depth)] + walk(node.children, depth: depth + 1)
            }
        }
        return walk(FolderNode.tree(folders), depth: 0).map { (folder: $0.0, depth: $0.1) }
    }
}
