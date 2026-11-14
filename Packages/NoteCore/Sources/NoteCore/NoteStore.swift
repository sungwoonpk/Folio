import Foundation
import GRDB

public enum NoteStoreError: Error {
    case notFound
    case invalidMove
    /// Folders cannot be nested deeper than the store allows.
    case tooDeep
    /// A folder name that is empty after trimming.
    case invalidName
}

public enum NoteScope: Sendable, Equatable {
    case all
    case folder(UUID)
}

/// All persistence operations the UI needs. Every method runs in one transaction.
public final class NoteStore: Sendable {
    /// Folder names longer than this are cut.
    public static let maxFolderNameLength = 120
    /// Deleted notes wait in Recently Deleted this many days, then they are removed for good.
    public static let trashRetentionDays = 30

    public let database: AppDatabase
    /// How many folder levels are allowed. 1 means folders only at the top, none inside folders.
    public let maxFolderDepth: Int
    private var writer: any DatabaseWriter { database.writer }

    public init(database: AppDatabase, maxFolderDepth: Int = 1) {
        self.database = database
        self.maxFolderDepth = maxFolderDepth
    }

    // MARK: - Folders

    public func folders() async throws -> [Folder] {
        try await writer.read { db in
            // Folders the user never arranged come first, most recently modified on top.
            // Arranged folders (sortOrder > 0) follow, in the order the user set.
            try Folder.filter(Column("deletedAt") == nil)
                .order(sql: """
                    sortOrder > 0, CASE WHEN sortOrder > 0 THEN sortOrder END, updatedAt DESC, name
                    """)
                .fetchAll(db)
        }
    }

    @discardableResult
    public func createFolder(name: String, parentId: UUID? = nil) async throws -> Folder {
        let name = try Self.cleanFolderName(name)
        return try await writer.write { [maxFolderDepth] db -> Folder in
            if let parentId, try Self.depth(db, of: parentId) + 1 > maxFolderDepth { throw NoteStoreError.tooDeep }
            // sortOrder 0 means automatic: most recently modified first.
            let folder = Folder(name: name, parentId: parentId)
            try folder.insert(db)
            return folder
        }
    }

    public func renameFolder(id: UUID, to name: String) async throws {
        let name = try Self.cleanFolderName(name)
        try await writer.write { db in
            guard var folder = try Folder.fetchOne(db, key: id) else { throw NoteStoreError.notFound }
            folder.name = name
            folder.updatedAt = Date()
            try folder.update(db)
        }
    }

    /// Saves a hand-arranged order for folders that share a parent. First id is shown first.
    public func reorderFolders(_ ids: [UUID]) async throws {
        try await writer.write { db in
            for (index, id) in ids.enumerated() {
                try Folder.filter(Column("id") == id).updateAll(db, Column("sortOrder").set(to: Double(index + 1)))
            }
        }
    }

    public func moveFolder(id: UUID, to parentId: UUID?) async throws {
        try await writer.write { [maxFolderDepth] db in
            guard var folder = try Folder.fetchOne(db, key: id) else { throw NoteStoreError.notFound }
            if let parentId {
                if try Self.subtreeIDs(db, root: id).contains(parentId) { throw NoteStoreError.invalidMove }
                if try Self.depth(db, of: parentId) + Self.height(db, of: id) > maxFolderDepth {
                    throw NoteStoreError.tooDeep
                }
            }
            let oldParent = folder.parentId
            folder.parentId = parentId
            folder.updatedAt = Date()
            try folder.update(db)
            try Self.touchFolders(db, from: oldParent)
            try Self.touchFolders(db, from: parentId)
        }
    }

    /// Deep copy of a folder with its folders, notes and blocks.
    @discardableResult
    public func duplicateFolder(id: UUID) async throws -> Folder {
        try await writer.write { db -> Folder in
            guard let root = try Folder.fetchOne(db, key: id) else { throw NoteStoreError.notFound }
            let ids = try Self.subtreeIDs(db, root: id) // parents come before children
            var idMap: [UUID: UUID] = [:]
            var newRoot = root
            for oldId in ids {
                guard var folder = try Folder.fetchOne(db, key: oldId), folder.deletedAt == nil else { continue }
                let newId = UUID()
                idMap[oldId] = newId
                folder.id = newId
                folder.sortOrder = 0
                folder.createdAt = Date()
                folder.updatedAt = Date()
                if oldId == id {
                    folder.name = String((folder.name + " Copy").prefix(Self.maxFolderNameLength))
                } else if let parent = folder.parentId {
                    folder.parentId = idMap[parent]
                }
                try folder.insert(db)
                if oldId == id { newRoot = folder }
            }
            let notes = try Note
                .filter(ids.contains(Column("folderId")) && Column("deletedAt") == nil)
                .fetchAll(db)
            for note in notes {
                try Self.copyNote(db, note, into: note.folderId.flatMap { idMap[$0] })
            }
            return newRoot
        }
    }

    /// Deletes a folder for good. Its notes are not lost: they go to Recently Deleted, without a folder.
    public func deleteFolder(id: UUID) async throws {
        try await writer.write { db in
            let ids = try Self.subtreeIDs(db, root: id)
            let noteIds = try UUID.fetchAll(db, Note.filter(ids.contains(Column("folderId"))).select(Column("id")))
            // Notes that were already deleted keep their original deleted time.
            try Note.filter(noteIds.contains(Column("id")) && Column("deletedAt") == nil)
                .updateAll(db, Column("deletedAt").set(to: Date()))
            try Note.filter(noteIds.contains(Column("id"))).updateAll(db, Column("folderId").set(to: nil))
            for noteId in noteIds { try Self.reindex(db, noteId: noteId) }
            _ = try Folder.deleteOne(db, key: id) // only subfolders cascade, the notes are detached
        }
    }

    // MARK: - Notes

    public func notes(in scope: NoteScope) async throws -> [Note] {
        try await writer.read { db in
            var request = Note.filter(Column("deletedAt") == nil)
            if case .folder(let folderId) = scope {
                request = request.filter(Column("folderId") == folderId)
            }
            return try request.order(Column("pinned").desc, Column("updatedAt").desc).fetchAll(db)
        }
    }

    public func note(id: UUID) async throws -> Note? {
        try await writer.read { db in try Note.fetchOne(db, key: id) }
    }

    public func blocks(noteId: UUID) async throws -> [Block] {
        try await writer.read { db in
            try Block.filter(Column("noteId") == noteId).order(Column("position")).fetchAll(db)
        }
    }

    /// New note with one empty text block, ready for typing.
    @discardableResult
    public func createNote(folderId: UUID? = nil) async throws -> Note {
        try await writer.write { db -> Note in
            let note = Note(folderId: folderId)
            try note.insert(db)
            let block = Block(noteId: note.id)
            try block.insert(db)
            try Self.touchFolders(db, from: folderId)
            return note
        }
    }

    /// Replaces a note's blocks, refreshes title/snippet and the search index.
    public func saveNote(id: UUID, blocks: [Block]) async throws {
        try await writer.write { db in
            guard var note = try Note.fetchOne(db, key: id) else { throw NoteStoreError.notFound }
            try Block.filter(Column("noteId") == id).deleteAll(db)
            var ordered: [Block] = []
            for (index, var block) in blocks.enumerated() {
                block.noteId = id
                block.position = index
                try block.insert(db)
                ordered.append(block)
            }
            let summary = NoteSummary.derive(from: ordered)
            note.title = summary.title
            note.snippet = summary.snippet
            note.updatedAt = Date()
            try note.update(db)
            try Self.reindex(db, noteId: id)
            try Self.touchFolders(db, from: note.folderId)
        }
    }

    public func setPinned(id: UUID, _ pinned: Bool) async throws {
        try await writer.write { db in
            _ = try Note.filter(Column("id") == id).updateAll(db, Column("pinned").set(to: pinned))
        }
    }

    public func moveNote(id: UUID, to folderId: UUID?) async throws {
        try await writer.write { db in
            let old = try Note.fetchOne(db, key: id)?.folderId
            try Note.filter(Column("id") == id).updateAll(db, Column("folderId").set(to: folderId))
            try Self.touchFolders(db, from: old)
            try Self.touchFolders(db, from: folderId)
        }
    }

    @discardableResult
    public func duplicateNote(id: UUID) async throws -> Note {
        try await writer.write { db -> Note in
            guard let note = try Note.fetchOne(db, key: id) else { throw NoteStoreError.notFound }
            return try Self.copyNote(db, note, into: note.folderId)
        }
    }

    public func trashNote(id: UUID) async throws {
        try await writer.write { db in
            try Note.filter(Column("id") == id && Column("deletedAt") == nil)
                .updateAll(db, Column("deletedAt").set(to: Date()))
            try Self.reindex(db, noteId: id)
        }
    }

    /// Brings a deleted note back into the folder the user picked.
    public func restoreNote(id: UUID, to folderId: UUID) async throws {
        try await writer.write { db in
            guard var note = try Note.fetchOne(db, key: id),
                  try Folder.fetchOne(db, key: folderId) != nil else { throw NoteStoreError.notFound }
            // Only deleted notes can be restored. A live note must not be moved by accident.
            guard note.deletedAt != nil else { return }
            note.folderId = folderId
            note.deletedAt = nil
            try note.update(db)
            try Self.reindex(db, noteId: id)
            try Self.touchFolders(db, from: folderId)
        }
    }

    // MARK: - Recently Deleted

    /// Deleted notes, most recently deleted first. Folders are never kept here.
    public func deletedNotes() async throws -> [Note] {
        try await writer.read { db in
            try Note.filter(Column("deletedAt") != nil).order(Column("deletedAt").desc).fetchAll(db)
        }
    }

    public func purgeNote(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM noteSearch WHERE noteId = ?", arguments: [id.uuidString])
            _ = try Note.deleteOne(db, key: id)
        }
    }

    public func emptyTrash() async throws {
        try await writer.write { db in
            _ = try Note.filter(Column("deletedAt") != nil).deleteAll(db) // deleted notes are not indexed
        }
    }

    /// Removes notes that have been in Recently Deleted for `trashRetentionDays` or longer.
    /// Returns how many were removed. A note that was never deleted is never touched.
    @discardableResult
    public func purgeExpiredNotes(now: Date = Date()) async throws -> Int {
        let cutoff = now.addingTimeInterval(-Double(Self.trashRetentionDays) * 86_400)
        return try await writer.write { db in
            // Deleted notes are not indexed, so only the note rows go (blocks cascade).
            try Note.filter(Column("deletedAt") != nil && Column("deletedAt") <= cutoff).deleteAll(db)
        }
    }

    // MARK: - Search

    /// Matches title and body anywhere in the text. Optionally limited to a folder and its subfolders.
    public func search(_ query: String, in folderId: UUID? = nil, limit: Int = 100) async throws -> [Note] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return try await writer.read { db in
            let matches: [String]
            if q.count >= 3 {
                let phrase = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                matches = try String.fetchAll(
                    db, sql: "SELECT noteId FROM noteSearch WHERE noteSearch MATCH ?", arguments: [phrase]
                )
            } else {
                // Trigram needs 3+ characters. Short queries fall back to a scan.
                let escaped = q
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                let pattern = "%" + escaped + "%"
                matches = try String.fetchAll(
                    db,
                    sql: "SELECT noteId FROM noteSearch WHERE title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\'",
                    arguments: [pattern, pattern]
                )
            }
            let ids = matches.compactMap { UUID(uuidString: $0) }
            var request = Note.filter(ids.contains(Column("id")) && Column("deletedAt") == nil)
            if let folderId {
                let scope = try Self.subtreeIDs(db, root: folderId)
                request = request.filter(scope.contains(Column("folderId")))
            }
            return try request.order(Column("pinned").desc, Column("updatedAt").desc).limit(limit).fetchAll(db)
        }
    }

    // MARK: - Helpers

    /// Trims a folder name, rejects an empty one and cuts a very long one.
    static func cleanFolderName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NoteStoreError.invalidName }
        return String(trimmed.prefix(maxFolderNameLength))
    }

    /// Marks a folder and its ancestors as modified now, so recency sorting follows the notes inside.
    static func touchFolders(_ db: Database, from folderId: UUID?) throws {
        let now = Date()
        var current = folderId
        while let id = current {
            guard let folder = try Folder.fetchOne(db, key: id) else { break }
            try Folder.filter(Column("id") == id).updateAll(db, Column("updatedAt").set(to: now))
            current = folder.parentId
        }
    }

    /// Level of a folder: 1 at the top, 2 inside a folder, and so on.
    static func depth(_ db: Database, of id: UUID) throws -> Int {
        var level = 1
        var current = try Folder.fetchOne(db, key: id)?.parentId
        while let parent = current {
            level += 1
            current = try Folder.fetchOne(db, key: parent)?.parentId
        }
        return level
    }

    /// Levels in a folder's own subtree: 1 for a folder with no subfolders.
    static func height(_ db: Database, of id: UUID) throws -> Int {
        var levels = 1
        var frontier = [id]
        while true {
            let children = try UUID.fetchAll(
                db, Folder.filter(frontier.contains(Column("parentId"))).select(Column("id"))
            )
            if children.isEmpty { return levels }
            levels += 1
            frontier = children
        }
    }

    /// The folder and all descendants, parents before children.
    static func subtreeIDs(_ db: Database, root: UUID) throws -> [UUID] {
        var result = [root]
        var frontier = [root]
        while !frontier.isEmpty {
            let children = try UUID.fetchAll(
                db, Folder.filter(frontier.contains(Column("parentId"))).select(Column("id"))
            )
            result += children
            frontier = children
        }
        return result
    }

    @discardableResult
    static func copyNote(_ db: Database, _ note: Note, into folderId: UUID?) throws -> Note {
        var copy = note
        copy.id = UUID()
        copy.folderId = folderId
        copy.pinned = false
        copy.deletedAt = nil
        copy.createdAt = Date()
        copy.updatedAt = Date()
        try copy.insert(db)
        let blocks = try Block.filter(Column("noteId") == note.id).order(Column("position")).fetchAll(db)
        for var block in blocks {
            block.id = UUID()
            block.noteId = copy.id
            try block.insert(db)
        }
        try reindex(db, noteId: copy.id)
        return copy
    }

    static func reindex(_ db: Database, noteId: UUID) throws {
        try db.execute(sql: "DELETE FROM noteSearch WHERE noteId = ?", arguments: [noteId.uuidString])
        guard let note = try Note.fetchOne(db, key: noteId), note.deletedAt == nil else { return }
        let body = try Block.filter(Column("noteId") == noteId)
            .order(Column("position")).fetchAll(db)
            .map(\.content).joined(separator: "\n")
        if note.title.isEmpty && body.isEmpty { return }
        try db.execute(
            sql: "INSERT INTO noteSearch(noteId, title, body) VALUES (?, ?, ?)",
            arguments: [noteId.uuidString, note.title, body]
        )
    }
}
