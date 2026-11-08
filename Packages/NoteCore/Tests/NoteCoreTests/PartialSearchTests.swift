import XCTest
@testable import NoteCore

/// "Test3" must be found by "est", "3", "test", "TEST", not only by the full word.
final class PartialSearchTests: XCTestCase {
    // "프로젝트" is Korean test data on purpose: folder search must match inside Korean words too.
    func testFoldersMatchAnyPartOfTheNameInAnyCase() {
        let folders = [Folder(name: "Test3"), Folder(name: "Work"), Folder(name: "프로젝트")]
        for query in ["Test3", "est", "3", "test", "TEST", "t3", "  test  "] {
            XCTAssertEqual(FolderSearch.matching(folders, query: query).map(\.name), ["Test3"], "query \(query)")
        }
        XCTAssertTrue(FolderSearch.matching(folders, query: "e3").isEmpty, "e3 is not inside Test3")
        XCTAssertEqual(FolderSearch.matching(folders, query: "젝트").map(\.name), ["프로젝트"])
        XCTAssertTrue(FolderSearch.matching(folders, query: "").isEmpty)
        XCTAssertTrue(FolderSearch.matching(folders, query: "zzz").isEmpty)
    }

    func testNotesMatchAnyPartOfTheTitleInAnyCase() async throws {
        let store = NoteStore(database: try AppDatabase.inMemory())
        let note = try await store.createNote()
        try await store.saveNote(id: note.id, blocks: [Block(noteId: note.id, content: "Test3")])
        for query in ["Test3", "est", "3", "test", "TEST", "Tes", "t3"] {
            let found = try await store.search(query)
            XCTAssertEqual(found.map(\.id), [note.id], "query \(query)")
        }
        let none = try await store.search("t3x")
        XCTAssertTrue(none.isEmpty)
    }
}
