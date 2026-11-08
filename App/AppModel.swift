import CoreTransferable
import Foundation
import NoteCore
import Observation
import SwiftUI
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

@MainActor @Observable
final class AppModel {
    let store: NoteStore

    var folders: [Folder] = []
    /// Every active note, or the search results while a query is typed.
    var notes: [Note] = []
    var trash = TrashContents(folders: [], notes: [])

    var selectedNoteId: UUID?
    var query = ""
    /// Notes inside each folder, including its subfolders.
    private(set) var folderNoteCounts: [UUID: Int] = [:]

    // Multi-select, used by the screen currently showing.
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

    // MARK: Screen contents

    /// Folders directly inside `parent` (nil = main screen), most recently changed first.
    func subfolders(of parent: UUID?) -> [Folder] { folders.filter { $0.parentId == parent } }

    /// Notes directly inside a folder (nil = notes without a folder).
    func notes(in folderId: UUID?) -> [Note] { notes.filter { $0.folderId == folderId } }

    func folder(_ id: UUID?) -> Folder? { id.flatMap { id in folders.first { $0.id == id } } }

    /// How many notes are inside a folder, counting its subfolders too.
    func noteCount(in folderId: UUID) -> Int { folderNoteCounts[folderId] ?? 0 }

    private func rebuildCounts() {
        var direct: [UUID: Int] = [:]
        for note in notes { if let id = note.folderId { direct[id, default: 0] += 1 } }
        let parent = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.parentId) })
        var total: [UUID: Int] = [:]
        for (id, count) in direct {
            var current: UUID? = id
            while let folder = current {
                total[folder, default: 0] += count
                current = parent[folder] ?? nil
            }
        }
        folderNoteCounts = total
    }

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
            rebuildCounts()
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
        await reloadAll()
    }

    func renameFolder(_ id: UUID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? await store.renameFolder(id: id, to: trimmed)
        await reloadAll()
    }

    /// Same order the database uses: unarranged folders first (newest on top), then arranged ones.
    static func folderOrder(_ a: Folder, _ b: Folder) -> Bool {
        let aManual = a.sortOrder > 0
        let bManual = b.sortOrder > 0
        if aManual != bManual { return !aManual }
        if aManual { return a.sortOrder < b.sortOrder }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.name < b.name
    }

    /// Drag-to-reorder in Edit mode. Updates the list right away, then saves.
    func moveFolders(in parent: UUID?, from source: IndexSet, to destination: Int) async {
        var ordered = subfolders(of: parent)
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in ordered.enumerated() {
            if let i = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[i].sortOrder = Double(index + 1)
            }
        }
        folders.sort(by: Self.folderOrder)
        try? await store.reorderFolders(ordered.map(\.id))
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
        await reloadAll()
    }

    // MARK: Note actions

    /// New note. `folderId` nil puts it in "Notes", no folder needed.
    func createNote(in folderId: UUID? = nil) async {
        guard let note = try? await store.createNote(folderId: folderId) else { return }
        query = ""
        await reloadAll()
        selectedNoteId = note.id
    }

    func moveNote(_ id: UUID, to folderId: UUID?) async {
        try? await store.moveNote(id: id, to: folderId)
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

    /// Drop onto a folder moves into it. Drop with folderId nil moves to the top level.
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

    /// Select everything on a screen, or clear if it is all selected already.
    func toggleAll(notes: [Note], folders: [Folder]) {
        let noteIDs = Set(notes.map(\.id))
        let folderIDs = Set(folders.map(\.id))
        if pickedCount > 0, pickedNotes == noteIDs, pickedFolders == folderIDs {
            pickedNotes = []
            pickedFolders = []
        } else {
            pickedNotes = noteIDs
            pickedFolders = folderIDs
        }
    }

    func allPicked(notes: [Note], folders: [Folder]) -> Bool {
        pickedCount > 0 && pickedNotes == Set(notes.map(\.id)) && pickedFolders == Set(folders.map(\.id))
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
