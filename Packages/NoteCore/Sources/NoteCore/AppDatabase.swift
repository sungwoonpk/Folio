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

    private static var migrator: DatabaseMigrator {
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

        return migrator
    }
}
