import Foundation
import GRDB

public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// On-disk database (WAL) for the app.
    public static func open(at url: URL) throws -> AppDatabase {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        return try AppDatabase(writer: pool)
    }

    /// In-memory database for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "folder") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("parentId", .blob).references("folder", onDelete: .cascade)
                t.column("sortOrder", .double).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(index: "folder_parent", on: "folder", columns: ["parentId"])

            try db.create(table: "note") { t in
                t.primaryKey("id", .blob)
                t.column("folderId", .blob).references("folder", onDelete: .cascade)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("snippet", .text).notNull().defaults(to: "")
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(index: "note_list", on: "note", columns: ["folderId", "deletedAt", "updatedAt"])

            try db.create(table: "block") { t in
                t.primaryKey("id", .blob)
                t.column("noteId", .blob).notNull().references("note", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("meta", .text)
                t.column("position", .integer).notNull()
            }
            try db.create(index: "block_note", on: "block", columns: ["noteId", "position"])

            // Trigram tokenizer: substring matching that also works for Korean (no word spaces).
            try db.execute(sql: """
                CREATE VIRTUAL TABLE noteSearch USING fts5(
                    noteId UNINDEXED, title, body, tokenize = 'trigram'
                )
                """)
        }

        // Folders are one level only. Older databases may have folders inside folders:
        // they move up to the top level, their notes stay where they are.
        migrator.registerMigration("v2-flat-folders") { db in
            try db.execute(sql: "UPDATE folder SET parentId = NULL WHERE parentId IS NOT NULL")
        }

        // Previews used to include table cells ("| | |"). Work them out again for saved notes.
        migrator.registerMigration("v3-refresh-previews") { db in
            for var note in try Note.fetchAll(db) {
                let blocks = try Block.filter(Column("noteId") == note.id).fetchAll(db)
                let summary = NoteSummary.derive(from: blocks)
                guard summary.title != note.title || summary.snippet != note.snippet else { continue }
                note.title = summary.title
                note.snippet = summary.snippet
                try note.update(db)
            }
        }

        // Folders are never kept in Recently Deleted any more. Folders that were in the trash are
        // removed for good, their notes stay in Recently Deleted without a folder.
        migrator.registerMigration("v4-no-folder-trash") { db in
            try db.execute(sql: """
                UPDATE note SET folderId = NULL
                WHERE folderId IN (SELECT id FROM folder WHERE deletedAt IS NOT NULL)
                """)
            try db.execute(sql: "DELETE FROM folder WHERE deletedAt IS NOT NULL")
        }

        return migrator
    }
}
