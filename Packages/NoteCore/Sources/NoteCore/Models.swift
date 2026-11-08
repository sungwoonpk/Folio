import Foundation
import GRDB

public enum BlockKind: String, Codable, Sendable, CaseIterable {
    case text, bullet, number, checklist, table, image, audio
}

public struct Folder: Codable, Identifiable, Equatable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "folder"

    public var id: UUID
    public var name: String
    public var parentId: UUID?
    public var sortOrder: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), name: String, parentId: UUID? = nil, sortOrder: Double = 0,
        createdAt: Date = Date(), updatedAt: Date = Date(), deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct Note: Codable, Identifiable, Equatable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "note"

    public var id: UUID
    public var folderId: UUID?
    /// Derived from the first block. Cached so lists never load bodies.
    public var title: String
    /// Derived from the following blocks. Cached for list rows.
    public var snippet: String
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), folderId: UUID? = nil, title: String = "", snippet: String = "",
        pinned: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date(), deletedAt: Date? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.snippet = snippet
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct Block: Codable, Identifiable, Equatable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "block"

    public var id: UUID
    public var noteId: UUID
    public var kind: BlockKind
    /// Plain text. For table/image/audio blocks this is a searchable text form
    /// (table cells joined, image caption, audio transcript).
    public var content: String
    /// Structured JSON for table, image, audio blocks. Nil for text kinds.
    public var meta: String?
    public var position: Int

    public init(
        id: UUID = UUID(), noteId: UUID, kind: BlockKind = .text, content: String = "",
        meta: String? = nil, position: Int = 0
    ) {
        self.id = id
        self.noteId = noteId
        self.kind = kind
        self.content = content
        self.meta = meta
        self.position = position
    }
}

/// Title and snippet rules: first line of the first non-empty block is the title,
/// the next non-empty blocks form the snippet.
enum NoteSummary {
    static let titleLimit = 200
    static let snippetLimit = 140

    static func derive(from blocks: [Block]) -> (title: String, snippet: String) {
        // Table cells are searchable but never shown as the title or preview.
        let lines = blocks
            .filter { $0.kind != .table }
            .sorted { $0.position < $1.position }
            .flatMap { $0.content.split(whereSeparator: \.isNewline) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return ("", "") }
        let title = String(first.prefix(titleLimit))
        let snippet = String(lines.dropFirst().joined(separator: " ").prefix(snippetLimit))
        return (title, snippet)
    }
}
