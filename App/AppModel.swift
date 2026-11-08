import CoreTransferable
import Foundation
import NoteCore
import Observation
import UniformTypeIdentifiers

/// What gets dragged between rows.
struct ItemRef: Codable, Hashable, Transferable {
    enum Kind: String, Codable { case note, folder }
    var kind: Kind
    var id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

enum HomeRow: Identifiable {
    case folder(Folder, depth: Int)
    case note(Note, depth: Int)

    var id: UUID {
        switch self {
        case .folder(let folder, _): folder.id
        case .note(let note, _): note.id
        }
    }
}

@MainActor @Observable
final class AppModel {
    let store: NoteStore

    var folders: [Folder] = []
    /// Every active note, or the search results while a query is typed.
    var notes: [Note] = []
    var trash = TrashContents(folders: [], notes: [])

    var selectedNoteId: UUID?
    var query = ""
    var expanded: Set<UUID> = []

    // Multi-select on the home screen.
    var selecting = false
    var pickedNotes: Set<UUID> = []
    var pickedFolders: Set<UUID> = []

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

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Home layout

    /// Folders section: folders by recent change, open folders show subfolders then their notes.
    var folderRows: [HomeRow] {
        func rows(parent: UUID?, depth: Int) -> [HomeRow] {
            var out: [HomeRow] = []
            for folder in folders where folder.parentId == parent {
                out.append(.folder(folder, depth: depth))
                if expanded.contains(folder.id) {
                    out += rows(parent: folder.id, depth: depth + 1)
                    for note in notes where note.folderId == folder.id {
                        out.append(.note(note, depth: depth + 1))
                    }
                }
            }
            return out
        }
        return rows(parent: nil, depth: 0)
    }

    /// Notes without a folder, shown below the folders.
    var looseNotes: [Note] { notes.filter { $0.folderId == nil } }

    func noteCount(in folderId: UUID) -> Int { notes.filter { $0.folderId == folderId }.count }

    // MARK: Loading

    func reloadAll() async {
        folders = (try? await store.folders()) ?? []
        trash = (try? await store.trash()) ?? TrashContents(folders: [], notes: [])
        await reloadNotes()
    }

    func reloadNotes() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            notes = (try? await store.notes(in: .all)) ?? []
            // The open note vanished (its folder was deleted, for example).
            if let id = selectedNoteId, !notes.contains(where: { $0.id == id }) {
                selectedNoteId = nil
            }
        } else {
            notes = (try? await store.search(q)) ?? []
        }
    }

    func reloadTrash() async {
        trash = (try? await store.trash()) ?? TrashContents(folders: [], notes: [])
    }

    // MARK: Folder actions

    func createFolder(name: String, parentId: UUID?) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = try? await store.createFolder(name: trimmed, parentId: parentId)
        if let parentId { expanded.insert(parentId) }
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
        if let parentId { expanded.insert(parentId) }
        await reloadAll()
    }

    func duplicateFolder(_ id: UUID) async {
        _ = try? await store.duplicateFolder(id: id)
        await reloadAll()
    }

    func trashFolder(_ id: UUID) async {
        try? await store.trashFolder(id: id)
        await reloadAll()
    }

    // MARK: Note actions

    /// New note. `folderId` nil puts it at the top level, no folder needed.
    func createNote(in folderId: UUID? = nil) async {
        guard let note = try? await store.createNote(folderId: folderId) else { return }
        query = ""
        if let folderId { expanded.insert(folderId) }
        await reloadAll()
        selectedNoteId = note.id
    }

    func moveNote(_ id: UUID, to folderId: UUID?) async {
        try? await store.moveNote(id: id, to: folderId)
        if let folderId { expanded.insert(folderId) }
        await reloadAll()
    }

    func duplicateNote(_ id: UUID) async {
        _ = try? await store.duplicateNote(id: id)
        await reloadAll()
    }

    func togglePin(_ note: Note) async {
        try? await store.setPinned(id: note.id, !note.pinned)
        await reloadNotes()
    }

    func trashNote(_ id: UUID) async {
        try? await store.trashNote(id: id)
        if selectedNoteId == id { selectedNoteId = nil }
        await reloadAll()
    }

    /// Notes opened and left empty are removed.
    func discardIfEmpty(_ id: UUID) async {
        try? await store.purgeNote(id: id)
        if selectedNoteId == id { selectedNoteId = nil }
        await reloadNotes()
    }

    // MARK: Drag and drop

    /// Drop onto a folder moves into it. Drop onto the top level (folderId nil) moves out of any folder.
    func drop(_ items: [ItemRef], onto folderId: UUID?) async {
        for item in items {
            switch item.kind {
            case .note:
                try? await store.moveNote(id: item.id, to: folderId)
            case .folder:
                guard item.id != folderId else { continue }
                try? await store.moveFolder(id: item.id, to: folderId)
            }
        }
        if let folderId { expanded.insert(folderId) }
        await reloadAll()
    }

    // MARK: Multi-select

    func endSelection() {
        selecting = false
        pickedNotes = []
        pickedFolders = []
    }

    func toggleNote(_ id: UUID) {
        if pickedNotes.contains(id) { pickedNotes.remove(id) } else { pickedNotes.insert(id) }
    }

    func toggleFolder(_ id: UUID) {
        if pickedFolders.contains(id) { pickedFolders.remove(id) } else { pickedFolders.insert(id) }
    }

    var pickedCount: Int { pickedNotes.count + pickedFolders.count }

    /// Everything visible on the home list.
    private var visibleNoteIDs: Set<UUID> {
        if isSearching { return Set(notes.map(\.id)) }
        var ids = Set(looseNotes.map(\.id))
        for case .note(let note, _) in folderRows { ids.insert(note.id) }
        return ids
    }

    private var visibleFolderIDs: Set<UUID> {
        isSearching ? [] : Set(folderRows.compactMap { row -> UUID? in
            if case .folder(let folder, _) = row { return folder.id }
            return nil
        })
    }

    var allPicked: Bool {
        pickedCount > 0 && pickedNotes == visibleNoteIDs && pickedFolders == visibleFolderIDs
    }

    func toggleAll() {
        if allPicked {
            pickedNotes = []
            pickedFolders = []
        } else {
            pickedNotes = visibleNoteIDs
            pickedFolders = visibleFolderIDs
        }
    }

    func trashPicked() async {
        for id in pickedFolders { try? await store.trashFolder(id: id) }
        for id in pickedNotes { try? await store.trashNote(id: id) }
        endSelection()
        await reloadAll()
    }

    func movePicked(to folderId: UUID?) async {
        for id in pickedFolders where id != folderId { try? await store.moveFolder(id: id, to: folderId) }
        for id in pickedNotes { try? await store.moveNote(id: id, to: folderId) }
        if let folderId { expanded.insert(folderId) }
        endSelection()
        await reloadAll()
    }

    // MARK: Trash actions

    func restore(ids: Set<UUID>) async {
        let folderIds = Set(trash.folders.map(\.id))
        for id in ids {
            if folderIds.contains(id) {
                try? await store.restoreFolder(id: id)
            } else {
                try? await store.restoreNote(id: id)
            }
        }
        await reloadAll()
    }

    func purge(ids: Set<UUID>) async {
        let folderIds = Set(trash.folders.map(\.id))
        for id in ids {
            if folderIds.contains(id) {
                try? await store.purgeFolder(id: id)
            } else {
                try? await store.purgeNote(id: id)
            }
        }
        await reloadTrash()
    }

    func emptyTrash() async {
        try? await store.emptyTrash()
        await reloadTrash()
    }

    // MARK: Helpers

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
