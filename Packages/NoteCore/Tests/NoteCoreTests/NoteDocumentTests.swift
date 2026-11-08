import XCTest
@testable import NoteCore

final class NoteDocumentTests: XCTestCase {
    /// Segments without their random ids, for comparing.
    private func shape(_ segments: [Segment]) -> [String] {
        segments.map {
            switch $0 {
            case .text(_, let text): "text:\(text)"
            case .table(_, let table): "table:\(table.rows)"
            }
        }
    }

    func testBulletsRoundTripWithoutThePrefixInStorage() {
        let noteId = UUID()
        let segments: [Segment] = [.text(id: UUID(), "Title\n• one\n• two\nplain")]
        let blocks = NoteDocument.blocks(from: segments, noteId: noteId)
        XCTAssertEqual(blocks.map(\.kind), [.text, .bullet, .bullet, .text])
        XCTAssertEqual(blocks.map(\.content), ["Title", "one", "two", "plain"])
        XCTAssertEqual(shape(NoteDocument.segments(from: blocks)), ["text:Title\n• one\n• two\nplain"])
    }

    func testTableRoundTripKeepsCellsAndSurroundingText() {
        let noteId = UUID()
        var table = TableContent.blank(rows: 2, columns: 2)
        table.rows[0] = ["a", "b"]
        table.rows[1] = ["c", "d"]
        let segments: [Segment] = [
            .text(id: UUID(), "Before"), .table(id: UUID(), table), .text(id: UUID(), "After"),
        ]
        let blocks = NoteDocument.blocks(from: segments, noteId: noteId)
        XCTAssertEqual(blocks.map(\.kind), [.text, .table, .text])
        XCTAssertEqual(shape(NoteDocument.segments(from: blocks)), shape(segments))
    }

    func testEditorAlwaysHasTextBeforeBetweenAndAfterTables() {
        let noteId = UUID()
        let table = TableContent.blank()
        let blocks = [
            Block(noteId: noteId, kind: .table, content: table.plainText, meta: table.encoded(), position: 0),
            Block(noteId: noteId, kind: .table, content: table.plainText, meta: table.encoded(), position: 1),
        ]
        let segments = NoteDocument.segments(from: blocks)
        XCTAssertEqual(segments.count, 5)
        XCTAssertEqual(
            segments.map { if case .text = $0 { "t" } else { "T" } }.joined(), "tTtTt"
        )
        XCTAssertEqual(shape(NoteDocument.segments(from: [])), ["text:"])
    }

    func testBlankDetection() {
        XCTAssertTrue(NoteDocument.isBlank([.text(id: UUID(), "  \n ")]))
        XCTAssertFalse(NoteDocument.isBlank([.text(id: UUID(), ""), .table(id: UUID(), .blank())]))
        XCTAssertFalse(NoteDocument.isBlank([.text(id: UUID(), "hi")]))
    }

    func testTableEditing() {
        var table = TableContent.blank(rows: 2, columns: 2)
        table.addRow()
        table.addColumn()
        XCTAssertEqual(table.rowCount, 3)
        XCTAssertEqual(table.columnCount, 3)
        table.removeRow(at: 0)
        table.removeColumn(at: 2)
        XCTAssertEqual(table.rowCount, 2)
        XCTAssertEqual(table.columnCount, 2)

        var tiny = TableContent.blank(rows: 1, columns: 1)
        tiny.removeRow(at: 0)
        tiny.removeColumn(at: 0)
        XCTAssertEqual(tiny.rowCount, 1, "a table keeps at least one row")
        XCTAssertEqual(tiny.columnCount, 1, "and one column")
    }

    func testTableMetaRoundTrip() {
        var table = TableContent.blank(rows: 2, columns: 2)
        table.rows[1][1] = "한글 cell"
        XCTAssertEqual(TableContent.decode(table.encoded()), table)
        XCTAssertNil(TableContent.decode("not json"))
        XCTAssertNil(TableContent.decode(nil))
    }

    func testTableCellsAreSearchableAndBulletsStaySearchable() async throws {
        let store = NoteStore(database: try AppDatabase.inMemory())
        let note = try await store.createNote()
        var table = TableContent.blank(rows: 2, columns: 2)
        table.rows[0] = ["name", "price"]
        table.rows[1] = ["apple", "3000"]
        let segments: [Segment] = [
            .text(id: UUID(), "Shopping\n• milk"), .table(id: UUID(), table), .text(id: UUID(), ""),
        ]
        try await store.saveNote(id: note.id, blocks: NoteDocument.blocks(from: segments, noteId: note.id))

        let byCell = try await store.search("apple")
        XCTAssertEqual(byCell.map(\.id), [note.id])
        let byBullet = try await store.search("milk")
        XCTAssertEqual(byBullet.map(\.id), [note.id])
        let saved = try await store.note(id: note.id)
        XCTAssertEqual(saved?.title, "Shopping")
    }
}

final class PreviewTests: XCTestCase {
    func testTablesDoNotLeakIntoTheListPreviewButStayInSearch() async throws {
        let store = NoteStore(database: try AppDatabase.inMemory())
        let note = try await store.createNote()
        var table = TableContent.blank(rows: 2, columns: 2)
        table.rows[0] = ["name", "price"]
        let segments: [Segment] = [
            .text(id: UUID(), "Groceries\n• milk"), .table(id: UUID(), table), .text(id: UUID(), "thanks"),
        ]
        try await store.saveNote(id: note.id, blocks: NoteDocument.blocks(from: segments, noteId: note.id))

        let saved = try await store.note(id: note.id)
        XCTAssertEqual(saved?.title, "Groceries")
        XCTAssertEqual(saved?.snippet, "milk thanks", "no table cells or | separators in the preview")
        let found = try await store.search("price")
        XCTAssertEqual(found.map(\.id), [note.id], "table text is still searchable")
    }

    func testANoteThatStartsWithATableGetsItsTitleFromTheTextAfter() async throws {
        let store = NoteStore(database: try AppDatabase.inMemory())
        let note = try await store.createNote()
        let segments: [Segment] = [
            .text(id: UUID(), ""), .table(id: UUID(), .blank()), .text(id: UUID(), "Real title"),
        ]
        try await store.saveNote(id: note.id, blocks: NoteDocument.blocks(from: segments, noteId: note.id))
        let saved = try await store.note(id: note.id)
        XCTAssertEqual(saved?.title, "Real title")
        XCTAssertEqual(saved?.snippet, "")
    }
}

final class ChecklistDocumentTests: XCTestCase {
    func testChecklistRoundTripKeepsCheckedState() {
        let noteId = UUID()
        let segments: [Segment] = [.text(id: UUID(), "Todo\n○ milk\n◉ eggs\n• plain bullet\nnormal")]
        let blocks = NoteDocument.blocks(from: segments, noteId: noteId)

        XCTAssertEqual(blocks.map(\.kind), [.text, .checklist, .checklist, .bullet, .text])
        XCTAssertEqual(blocks.map(\.content), ["Todo", "milk", "eggs", "plain bullet", "normal"])
        XCTAssertNil(blocks[1].meta, "unchecked has no meta")
        XCTAssertEqual(blocks[2].meta, "done", "checked is stored as done")

        guard case .text(_, let text)? = NoteDocument.segments(from: blocks).first else { return XCTFail("no text") }
        XCTAssertEqual(text, "Todo\n○ milk\n◉ eggs\n• plain bullet\nnormal")
    }

    func testChecklistTextIsSearchableAndKeepsTheMarkerOutOfPreview() async throws {
        let store = NoteStore(database: try AppDatabase.inMemory())
        let note = try await store.createNote()
        let segments: [Segment] = [.text(id: UUID(), "Shopping\n○ milk\n◉ eggs")]
        try await store.saveNote(id: note.id, blocks: NoteDocument.blocks(from: segments, noteId: note.id))

        let saved = try await store.note(id: note.id)
        XCTAssertEqual(saved?.title, "Shopping")
        XCTAssertEqual(saved?.snippet, "milk eggs", "no ○ or ◉ in the preview")
        let found = try await store.search("eggs")
        XCTAssertEqual(found.map(\.id), [note.id])
    }

    func testEveryListPrefixIsTwoUTF16UnitsLong() {
        // The editor relies on this when it skips over the marker.
        for prefix in NoteDocument.listPrefixes {
            XCTAssertEqual((prefix as NSString).length, 2, prefix)
        }
    }
}
