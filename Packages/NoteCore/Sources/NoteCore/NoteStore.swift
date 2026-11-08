import Foundation
import GRDB

public enum NoteStoreError: Error {
    case notFound
    case invalidMove
}

public enum NoteScope: Sendable, Equatable {
    case all
    case folder(UUID)
}

public struct TrashContents: Sendable, Equatable {
    public var folders: [Folder]
    public var notes: [Note]

    public init(folders: [Folder], notes: [Note]) {
        self.folders = folders
        self.notes = notes
    }
}

/// All persistence operations the UI needs. Every method runs in one transaction.
public final class NoteStore: Sendable {
    public let database: AppDatabase
    private var writer: any DatabaseWriter { database.writer }

    public init(database: AppDatabase) {
        self.database = database
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
        try await writer.write { db -> Folder in
            // sortOrder 0 means automatic: most recently modified first.
            var folder = Folder(name: name, parentId: parentId)
            try folder.insert(db)
            return folder
        }
    }

    public func renameFolder(id: UUID, to name: String) async throws {
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
        try await writer.write { db in
            guard var folder = try Folder.fetchOne(db, key: id) else { throw NoteStoreError.notFound }
            if let parentId, try Self.subtreeIDs(db, root: id).contains(parentId) {
                throw NoteStoreError.invalidMove
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
                    folder.name += " Copy"
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

    public func trashFolder(id: UUID) async throws {
        try await writer.write { db in
            let ids = try Self.subtreeIDs(db, root: id)
            let stamp = Date()
            try Folder.filter(ids.contains(Column("id")) && Column("deletedAt") == nil)
                .updateAll(db, Column("deletedAt").set(to: stamp))
            let noteIds = try UUID.fetchAll(
                db, Note.filter(ids.contains(Column("folderId")) && Column("deletedAt") == nil).select(Column("id"))
            )
            try Note.filter(noteIds.contains(Column("id"))).updateAll(db, Column("deletedAt").set(to: stamp))
            for noteId in noteIds { try Self.reindex(db, noteId: noteId) }
        }
    }

    public func restoreFolder(id: UUID) async throws {
        try await writer.write { db in
            guard var folder = try Folder.fetchOne(db, key: id), let stamp = folder.deletedAt else { return }
            // Parent still in trash: restore to top level.
            if let parentId = folder.parentId,
               let parent = try Folder.fetchOne(db, key: parentId), parent.deletedAt != nil {
                folder.parentId = nil
                try folder.update(db)
            }
            let ids = try Self.subtreeIDs(db, root: id)
            try Folder.filter(ids.contains(Column("id")) && Column("deletedAt") == stamp)
                .updateAll(db, Column("deletedAt").set(to: nil))
            let noteIds = try UUID.fetchAll(
                db, Note.filter(ids.contains(Column("folderId")) && Column("deletedAt") == stamp).select(Column("id"))
            )
            try Note.filter(noteIds.contains(Column("id"))).updateAll(db, Column("deletedAt").set(to: nil))
            for noteId in noteIds { try Self.reindex(db, noteId: noteId) }
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
            var note = Note(folderId: folderId)
            try note.insert(db)
            var block = Block(noteId: note.id)
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
            try Note.filter(Column("id") == id).updateAll(db, Column("pinned").set(to: pinned))
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

    public func restoreNote(id: UUID) async throws {
        try await writer.write { db in
            guard var note = try Note.fetchOne(db, key: id) else { return }
            note.deletedAt = nil
            // Folder still in trash or gone: restore to top level.
            if let folderId = note.folderId,
               try Folder.filter(Column("id") == folderId && Column("deletedAt") == nil).isEmpty(db) {
                note.folderId = nil
            }
            try note.update(db)
            try Self.reindex(db, noteId: id)
        }
    }

    // MARK: - Trash

    /// Top-level trashed items only. Contents of a trashed folder stay inside it.
    public func trash() async throws -> TrashContents {
        try await writer.read { db in
            let trashedFolders = try Folder.filter(Column("deletedAt") != nil).fetchAll(db)
            let byId = Dictionary(uniqueKeysWithValues: trashedFolders.map { ($0.id, $0) })
            let topFolders = trashedFolders.filter { folder in
                guard let parent = folder.parentId.flatMap({ byId[$0] }) else { return true }
                return parent.deletedAt != folder.deletedAt
            }
            let notes = try Note.filter(Column("deletedAt") != nil).order(Column("deletedAt").desc).fetchAll(db)
            let topNotes = notes.filter { note in
                guard let folder = note.folderId.flatMap({ byId[$0] }) else { return true }
                return folder.deletedAt != note.deletedAt
            }
            return TrashContents(
                folders: topFolders.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) },
                notes: topNotes
            )
        }
    }

    public func purgeNote(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM noteSearch WHERE noteId = ?", arguments: [id.uuidString])
            _ = try Note.deleteOne(db, key: id)
        }
    }

    public func purgeFolder(id: UUID) async throws {
        try await writer.write { db in
            let ids = try Self.subtreeIDs(db, root: id)
            let noteIds = try UUID.fetchAll(db, Note.filter(ids.contains(Column("folderId"))).select(Column("id")))
            for noteId in noteIds {
                try db.execute(sql: "DELETE FROM noteSearch WHERE noteId = ?", arguments: [noteId.uuidString])
            }
            _ = try Folder.deleteOne(db, key: id) // cascades to child folders, notes, blocks
        }
    }

    public func emptyTrash() async throws {
        try await purgeTrash(olderThan: nil)
    }

    /// Permanently deletes trash older than the cutoff (nil = everything in trash).
    public func purgeTrash(olderThan cutoff: Date?) async throws {
        try await writer.write { db in
            func expired(_ column: String) -> SQLExpression {
                if let cutoff { return Column(column) != nil && Column(column) < cutoff }
                return Column(column) != nil
            }
            let folderIds = try UUID.fetchAll(db, Folder.filter(expired("deletedAt")).select(Column("id")))
            for folderId in folderIds {
                // Cascade removes child folders, notes and blocks. Trashed notes are already unindexed.
                _ = try Folder.deleteOne(db, key: folderId)
            }
            _ = try Note.filter(expired("deletedAt")).deleteAll(db)
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
