import Foundation

/// A table inside a note: rows of cells.
public struct TableContent: Codable, Equatable, Sendable {
    public var rows: [[String]]

    public init(rows: [[String]]) {
        self.rows = rows.isEmpty ? [[""]] : rows
    }

    public static func blank(rows: Int = 3, columns: Int = 2) -> TableContent {
        TableContent(rows: Array(repeating: Array(repeating: "", count: max(columns, 1)), count: max(rows, 1)))
    }

    public var rowCount: Int { rows.count }
    public var columnCount: Int { rows.first?.count ?? 0 }

    public mutating func addRow() {
        rows.append(Array(repeating: "", count: max(columnCount, 1)))
    }

    public mutating func addColumn() {
        for index in rows.indices { rows[index].append("") }
    }

    /// A table always keeps at least one row and one column.
    public mutating func removeRow(at index: Int) {
        guard rows.count > 1, rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    public mutating func removeColumn(at index: Int) {
        guard columnCount > 1, index >= 0, index < columnCount else { return }
        for row in rows.indices { rows[row].remove(at: index) }
    }

    /// Searchable text: cells joined by " | ", rows by line breaks.
    public var plainText: String {
        rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
    }

    /// Stored in Block.meta.
    public func encoded() -> String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public static func decode(_ meta: String?) -> TableContent? {
        guard let data = meta?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TableContent.self, from: data)
    }
}

/// What the editor shows: runs of text (with bullet lines) separated by tables.
public enum Segment: Equatable, Identifiable, Sendable {
    case text(id: UUID, String)
    case table(id: UUID, TableContent)

    public var id: UUID {
        switch self {
        case .text(let id, _), .table(let id, _): id
        }
    }
}

/// Converts between stored blocks and editor segments.
/// A bullet line is shown as "• text" in the editor and stored as a bullet block without the prefix.
/// A checklist line is "○ text" or "◉ text" and stored as a checklist block, checked ones with meta "done".
public enum NoteDocument {
    public static let bulletPrefix = "• "
    public static let uncheckedPrefix = "○ "
    public static let checkedPrefix = "◉ "
    /// Marks a checked checklist block.
    public static let doneMeta = "done"

    /// Every prefix that makes a line a list item.
    public static var listPrefixes: [String] { [bulletPrefix, uncheckedPrefix, checkedPrefix] }

    /// Always starts and ends with a text segment, and has a text segment between any two tables,
    /// so there is always somewhere to put the cursor.
    public static func segments(from blocks: [Block]) -> [Segment] {
        var segments: [Segment] = []
        var lines: [String] = []
        for block in blocks.sorted(by: { $0.position < $1.position }) {
            switch block.kind {
            case .table:
                segments.append(.text(id: UUID(), lines.joined(separator: "\n")))
                lines = []
                segments.append(.table(id: UUID(), TableContent.decode(block.meta) ?? .blank()))
            case .bullet:
                lines.append(bulletPrefix + block.content)
            case .checklist:
                lines.append((block.meta == doneMeta ? checkedPrefix : uncheckedPrefix) + block.content)
            default:
                lines.append(block.content)
            }
        }
        segments.append(.text(id: UUID(), lines.joined(separator: "\n")))
        return segments
    }

    public static func blocks(from segments: [Segment], noteId: UUID) -> [Block] {
        var blocks: [Block] = []
        for segment in segments {
            switch segment {
            case .text(_, let text):
                for line in text.components(separatedBy: "\n") {
                    if line.hasPrefix(bulletPrefix) {
                        blocks.append(Block(noteId: noteId, kind: .bullet, content: String(line.dropFirst(bulletPrefix.count))))
                    } else if line.hasPrefix(checkedPrefix) {
                        blocks.append(Block(
                            noteId: noteId, kind: .checklist,
                            content: String(line.dropFirst(checkedPrefix.count)), meta: doneMeta
                        ))
                    } else if line.hasPrefix(uncheckedPrefix) {
                        blocks.append(Block(
                            noteId: noteId, kind: .checklist, content: String(line.dropFirst(uncheckedPrefix.count))
                        ))
                    } else {
                        blocks.append(Block(noteId: noteId, kind: .text, content: line))
                    }
                }
            case .table(_, let table):
                blocks.append(Block(noteId: noteId, kind: .table, content: table.plainText, meta: table.encoded()))
            }
        }
        return blocks
    }

    /// True when there is nothing worth keeping: only whitespace and no tables.
    public static func isBlank(_ segments: [Segment]) -> Bool {
        segments.allSatisfy { segment in
            if case .text(_, let text) = segment {
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }
    }
}
