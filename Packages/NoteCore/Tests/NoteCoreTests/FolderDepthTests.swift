import GRDB
import XCTest
@testable import NoteCore

final class FolderDepthTests: XCTestCase {
    func testDefaultStoreOnlyAllowsTopLevelFolders() async throws {
        let store = NoteStore(database: try AppDatabase.inMemory())
        let top = try await store.createFolder(name: "Top")
        let other = try await store.createFolder(name: "Other")

        do {
            _ = try await store.createFolder(name: "Inside", parentId: top.id)
            XCTFail("a folder inside a folder must be rejected")
        } catch NoteStoreError.tooDeep {}

        do {
            try await store.moveFolder(id: other.id, to: top.id)
            XCTFail("moving a folder into a folder must be rejected")
        } catch NoteStoreError.tooDeep {}

        let folders = try await store.folders()
        XCTAssertEqual(Set(folders.map(\.id)), [top.id, other.id])
        XCTAssertTrue(folders.allSatisfy { $0.parentId == nil })
    }

    func testMovingAFolderToTheTopLevelIsAlwaysAllowed() async throws {
        let store = NoteStore(database: try AppDatabase.inMemory(), maxFolderDepth: 2)
        let a = try await store.createFolder(name: "A")
        let b = try await store.createFolder(name: "B", parentId: a.id)
        try await store.moveFolder(id: b.id, to: nil)
        let folders = try await store.folders()
        XCTAssertNil(folders.first { $0.id == b.id }?.parentId)
    }

    func testDepthLimitCountsTheMovedSubtree() async throws {
        let store = NoteStore(database: try AppDatabase.inMemory(), maxFolderDepth: 2)
        let a = try await store.createFolder(name: "A")
        let b = try await store.createFolder(name: "B")
        _ = try await store.createFolder(name: "B child", parentId: b.id)
        do {
            // B has a child, so putting B inside A would make three levels.
            try await store.moveFolder(id: b.id, to: a.id)
            XCTFail("three levels must be rejected when the limit is two")
        } catch NoteStoreError.tooDeep {}
    }

    func testOlderDatabasesGetNestedFoldersFlattenedAndKeepTheirNotes() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v1")

        let parent = UUID(), child = UUID(), note = UUID()
        try queue.write { db in
            try Folder(id: parent, name: "Parent").insert(db)
            try Folder(id: child, name: "Child", parentId: parent).insert(db)
            try Note(id: note, folderId: child, title: "kept").insert(db)
        }

        try AppDatabase.migrator.migrate(queue) // runs v2

        try queue.read { db in
            XCTAssertNil(try Folder.fetchOne(db, key: child)?.parentId, "child folder moved to the top level")
            XCTAssertEqual(try Note.fetchOne(db, key: note)?.folderId, child, "its note stays inside it")
            XCTAssertEqual(try Folder.fetchCount(db), 2, "nothing is deleted")
        }
    }
}

final class PreviewMigrationTests: XCTestCase {
    func testSavedNotesLoseTableCellsFromTheirPreview() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v2-flat-folders")

        let noteId = UUID()
        try queue.write { db in
            try Note(id: noteId, title: "Daddy", snippet: "fesdfsdf | | | Sdfsdfsd").insert(db)
            try Block(noteId: noteId, kind: .bullet, content: "Daddy", position: 0).insert(db)
            try Block(noteId: noteId, kind: .bullet, content: "fesdfsdf", position: 1).insert(db)
            try Block(noteId: noteId, kind: .table, content: " | \n | ", meta: TableContent.blank().encoded(), position: 2).insert(db)
            try Block(noteId: noteId, kind: .text, content: "Sdfsdfsd", position: 3).insert(db)
        }

        try AppDatabase.migrator.migrate(queue)

        try queue.read { db in
            let note = try Note.fetchOne(db, key: noteId)
            XCTAssertEqual(note?.title, "Daddy")
            XCTAssertEqual(note?.snippet, "fesdfsdf Sdfsdfsd")
        }
    }
}
