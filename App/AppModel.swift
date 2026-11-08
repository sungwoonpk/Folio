import Foundation
import NoteCore
import Observation
import SwiftUI

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

    /// Folders whose name contains the search text, any case.
    var matchingFolders: [Folder] { FolderSearch.matching(folders, query: query) }

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
            // A failed load must not wipe the list or close the note being edited.
            guard let all = try? await store.notes(in: .all) else { return }
            notes = all
            rebuildCounts()
            // Close the editor only if the note is really gone (deleted or in the trash).
            if let id = selectedNoteId, !all.contains(where: { $0.id == id }) {
                let stillThere = (try? await store.note(id: id)).flatMap { $0 }
                if stillThere == nil || stillThere?.deletedAt != nil { selectedNoteId = nil }
            }
        } else if let found = try? await store.search(q) {
            notes = found
        }
    }

    /// After a note is saved its folder moved up too, so folder order and counts refresh with the notes.
    func reloadAfterEdit() async {
        if let fresh = try? await store.folders() { folders = fresh }
        await reloadNotes()
    }

    func reloadTrash() async {
        trash = (try? await store.trash()) ?? TrashContents(folders: [], notes: [])
    }

    // MARK: Folder actions

    func createFolder(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = try? await store.createFolder(name: trimmed)
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

    func moveNote(_ id: UUID, to folderId: UUID) async {
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
        // Only remove it if what is saved is really empty. Never trust the editor alone.
        let saved = (try? await store.blocks(noteId: id)) ?? []
        guard saved.allSatisfy({ $0.kind == .text && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        try? await store.purgeNote(id: id)
        if selectedNoteId == id { selectedNoteId = nil }
        await reloadNotes()
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

    func movePicked(to folderId: UUID) async {
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
                // Bring the note's folder back first (no-op if it is not in trash).
                if let folderId = trash.notes.first(where: { $0.id == id })?.folderId {
                    try? await store.restoreFolder(id: folderId)
                }
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
}
