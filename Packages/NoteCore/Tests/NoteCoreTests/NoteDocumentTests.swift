import XCTest
@testable import NoteCore

final class NoteDocumentTests: XCTestCase {
    /// Segments without their random ids, for comparing.
    private func shape(_ segments: [Segment]) -> [String] {
        segments.map {
            switch $0 {
            case .text(_, let text): "text:\(text)"
            case .table(_, let table): "table:\(table.rows)"
            case .image(_, let image): "image:\(image.file)"
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

final class ImageDocumentTests: XCTestCase {
    private func shape(_ segments: [Segment]) -> [String] {
        segments.map {
            switch $0 {
            case .text(_, let text): "text:\(text)"
            case .table: "table"
            case .image(_, let image): "image:\(image.file)"
            }
        }
    }

    func testImageRoundTripWithSurroundingText() {
        let noteId = UUID()
        let image = ImageContent(file: "a.jpg", width: 1200, height: 800, caption: "beach")
        let segments: [Segment] = [
            .text(id: UUID(), "Trip"), .image(id: UUID(), image), .text(id: UUID(), "Day two"),
        ]
        let blocks = NoteDocument.blocks(from: segments, noteId: noteId)
        XCTAssertEqual(blocks.map(\.kind), [.text, .image, .text])
        XCTAssertEqual(blocks[1].content, "beach")
        XCTAssertEqual(shape(NoteDocument.segments(from: blocks)), ["text:Trip", "image:a.jpg", "text:Day two"])
    }

    func testPicturesAndTablesSitNextToEachOtherWithTextBetween() {
        let noteId = UUID()
        let blocks = [
            Block(noteId: noteId, kind: .image, meta: ImageContent(file: "a.jpg", width: 1, height: 1).encoded(), position: 0),
            Block(noteId: noteId, kind: .table, content: "", meta: TableContent.blank().encoded(), position: 1),
        ]
        XCTAssertEqual(shape(NoteDocument.segments(from: blocks)), ["text:", "image:a.jpg", "text:", "table", "text:"])
    }

    func testBrokenImageDataIsDroppedNotShownBroken() {
        let blocks = [Block(noteId: UUID(), kind: .image, content: "", meta: "not json", position: 0)]
        XCTAssertEqual(shape(NoteDocument.segments(from: blocks)), ["text:"])
    }

    func testAPictureAloneIsNotBlank() {
        let image = ImageContent(file: "a.jpg", width: 10, height: 10)
        XCTAssertFalse(NoteDocument.isBlank([.text(id: UUID(), ""), .image(id: UUID(), image), .text(id: UUID(), "")]))
    }

    func testAspectRatioAndMetaRoundTrip() {
        let image = ImageContent(file: "a.jpg", width: 300, height: 200, caption: "한글")
        XCTAssertEqual(image.aspectRatio, 1.5, accuracy: 0.0001)
        XCTAssertEqual(ImageContent.decode(image.encoded()), image)
        XCTAssertEqual(ImageContent(file: "x", width: 5, height: 0).aspectRatio, 1)
    }

    func testPictureCaptionIsSearchable() async throws {
        let store = NoteStore(database: try AppDatabase.inMemory())
        let note = try await store.createNote()
        let image = ImageContent(file: "a.jpg", width: 10, height: 10, caption: "sunset over the harbour")
        let segments: [Segment] = [.text(id: UUID(), "Trip"), .image(id: UUID(), image), .text(id: UUID(), "")]
        try await store.saveNote(id: note.id, blocks: NoteDocument.blocks(from: segments, noteId: note.id))
        let found = try await store.search("harbour")
        XCTAssertEqual(found.map(\.id), [note.id])
    }
}
