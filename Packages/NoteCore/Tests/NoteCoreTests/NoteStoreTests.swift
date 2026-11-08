import XCTest
@testable import NoteCore

final class NoteStoreTests: XCTestCase {
    private func makeStore() throws -> NoteStore {
        NoteStore(database: try AppDatabase.inMemory())
    }

    private func write(_ store: NoteStore, _ note: Note, _ lines: [String]) async throws {
        let blocks = lines.map { Block(noteId: note.id, content: $0) }
        try await store.saveNote(id: note.id, blocks: blocks)
    }

    // MARK: Title and snippet

    func testFirstLineIsTitleRestIsSnippet() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        try await write(store, note, ["Groceries", "milk", "eggs"])
        let saved = try await store.note(id: note.id)
        XCTAssertEqual(saved?.title, "Groceries")
        XCTAssertEqual(saved?.snippet, "milk eggs")
    }

    func testMultilineFirstBlockSplitsTitleAndSnippet() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        try await write(store, note, ["Title\nbody line"])
        let saved = try await store.note(id: note.id)
        XCTAssertEqual(saved?.title, "Title")
        XCTAssertEqual(saved?.snippet, "body line")
    }

    // MARK: Folders

    func testNestedFoldersAndMove() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let b = try await store.createFolder(name: "B", parentId: a.id)
        let c = try await store.createFolder(name: "C")
        try await store.moveFolder(id: c.id, to: b.id)
        let folders = try await store.folders()
        XCTAssertEqual(folders.first { $0.id == c.id }?.parentId, b.id)
    }

    func testMovingFolderIntoItsOwnDescendantFails() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let b = try await store.createFolder(name: "B", parentId: a.id)
        do {
            try await store.moveFolder(id: a.id, to: b.id)
            XCTFail("expected invalidMove")
        } catch NoteStoreError.invalidMove {}
    }

    func testDuplicateFolderCopiesSubtreeAndNotes() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let b = try await store.createFolder(name: "B", parentId: a.id)
        let n1 = try await store.createNote(folderId: a.id)
        let n2 = try await store.createNote(folderId: b.id)
        try await write(store, n1, ["one"])
        try await write(store, n2, ["two"])

        let copy = try await store.duplicateFolder(id: a.id)
        XCTAssertEqual(copy.name, "A Copy")
        let folders = try await store.folders()
        XCTAssertEqual(folders.count, 4)
        let copyChild = folders.first { $0.parentId == copy.id }
        XCTAssertEqual(copyChild?.name, "B")
        let copiedNotes = try await store.notes(in: .folder(copy.id))
        XCTAssertEqual(copiedNotes.map(\.title), ["one"])
        let all = try await store.notes(in: .all)
        XCTAssertEqual(all.count, 4)
    }

    // MARK: Notes

    func testMoveDuplicatePinNote() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "F")
        let note = try await store.createNote()
        try await write(store, note, ["hello", "world"])

        try await store.moveNote(id: note.id, to: folder.id)
        let inFolder = try await store.notes(in: .folder(folder.id))
        XCTAssertEqual(inFolder.count, 1)

        let copy = try await store.duplicateNote(id: note.id)
        XCTAssertNotEqual(copy.id, note.id)
        let copyBlocks = try await store.blocks(noteId: copy.id)
        XCTAssertEqual(copyBlocks.map(\.content), ["hello", "world"])

        try await store.setPinned(id: note.id, true)
        let ordered = try await store.notes(in: .folder(folder.id))
        XCTAssertEqual(ordered.first?.id, note.id)
    }

    // MARK: Trash

    func testTrashAndRestoreNote() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        try await write(store, note, ["keep me"])

        try await store.trashNote(id: note.id)
        let active = try await store.notes(in: .all)
        XCTAssertTrue(active.isEmpty)
        let trashed = try await store.trash()
        XCTAssertEqual(trashed.notes.map(\.id), [note.id])
        let found = try await store.search("keep")
        XCTAssertTrue(found.isEmpty, "trashed notes must leave the search index")

        try await store.restoreNote(id: note.id)
        let restored = try await store.search("keep")
        XCTAssertEqual(restored.map(\.id), [note.id])
    }

    func testTrashFolderTakesContentsAndRestoreBringsThemBack() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let b = try await store.createFolder(name: "B", parentId: a.id)
        let n = try await store.createNote(folderId: b.id)
        try await write(store, n, ["nested note"])
        let loose = try await store.createNote(folderId: a.id)
        try await write(store, loose, ["loose note"])
        try await store.trashNote(id: loose.id) // separately trashed earlier
        try await Task.sleep(nanoseconds: 5_000_000) // distinct timestamps

        try await store.trashFolder(id: a.id)
        let folders = try await store.folders()
        XCTAssertTrue(folders.isEmpty)
        let trash = try await store.trash()
        XCTAssertEqual(trash.folders.map(\.id), [a.id], "only the top folder is listed")
        // The nested note stays inside the trashed folder. The earlier-trashed note is listed on its own.
        XCTAssertEqual(trash.notes.map(\.id), [loose.id])
        XCTAssertFalse(trash.notes.contains { $0.id == n.id })

        try await store.restoreFolder(id: a.id)
        let restoredFolders = try await store.folders()
        XCTAssertEqual(Set(restoredFolders.map(\.id)), [a.id, b.id])
        let nested = try await store.notes(in: .folder(b.id))
        XCTAssertEqual(nested.map(\.id), [n.id])
        let hits = try await store.search("nested")
        XCTAssertEqual(hits.count, 1)
    }

    func testRestoreFolderKeepsSeparatelyTrashedNotesInTrash() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let inside = try await store.createNote(folderId: a.id)
        try await write(store, inside, ["inside"])
        let early = try await store.createNote(folderId: a.id)
        try await write(store, early, ["early"])
        try await store.trashNote(id: early.id)
        try await Task.sleep(nanoseconds: 5_000_000) // distinct timestamps

        try await store.trashFolder(id: a.id)
        try await store.restoreFolder(id: a.id)

        let active = try await store.notes(in: .folder(a.id))
        XCTAssertEqual(active.map(\.id), [inside.id])
        let trash = try await store.trash()
        XCTAssertEqual(trash.notes.map(\.id), [early.id])
        let found = try await store.search("inside")
        XCTAssertEqual(found.count, 1)
    }

    func testRestoreNoteWhoseFolderIsTrashedGoesToTopLevel() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let n = try await store.createNote(folderId: a.id)
        try await write(store, n, ["orphan"])
        try await store.trashNote(id: n.id)
        try await Task.sleep(nanoseconds: 5_000_000)
        try await store.trashFolder(id: a.id)

        try await store.restoreNote(id: n.id)
        let restored = try await store.note(id: n.id)
        XCTAssertNil(restored?.folderId)
        XCTAssertNil(restored?.deletedAt)
    }

    func testEmptyTrashRemovesEverything() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let n1 = try await store.createNote(folderId: a.id)
        let n2 = try await store.createNote()
        try await write(store, n1, ["x"])
        try await write(store, n2, ["y"])
        try await store.trashFolder(id: a.id)
        try await store.trashNote(id: n2.id)

        try await store.emptyTrash()
        let trash = try await store.trash()
        XCTAssertTrue(trash.folders.isEmpty)
        XCTAssertTrue(trash.notes.isEmpty)
        let gone1 = try await store.note(id: n1.id)
        XCTAssertNil(gone1)
    }

    func testPurgeOlderThanKeepsRecentTrash() async throws {
        let store = try makeStore()
        let n = try await store.createNote()
        try await write(store, n, ["recent"])
        try await store.trashNote(id: n.id)
        try await store.purgeTrash(olderThan: Date().addingTimeInterval(-3600))
        let still = try await store.trash()
        XCTAssertEqual(still.notes.count, 1)
        try await store.purgeTrash(olderThan: Date().addingTimeInterval(3600))
        let gone = try await store.trash()
        XCTAssertTrue(gone.notes.isEmpty)
    }

    // MARK: Search

    func testSearchFindsTitleAndBodySubstringsCaseInsensitive() async throws {
        let store = try makeStore()
        let n = try await store.createNote()
        try await write(store, n, ["Meeting Notes", "discuss the roadmap"])
        let byTitle = try await store.search("meeting")
        XCTAssertEqual(byTitle.count, 1)
        let byBody = try await store.search("oadmap")
        XCTAssertEqual(byBody.count, 1)
    }

    func testSearchKoreanAndShortQueries() async throws {
        let store = try makeStore()
        let n = try await store.createNote()
        try await write(store, n, ["장보기 목록", "우유 계란 두부"])
        let three = try await store.search("계란 ")
        XCTAssertEqual(three.count, 1)
        let short = try await store.search("두부")
        XCTAssertEqual(short.count, 1)
        let none = try await store.search("라면")
        XCTAssertTrue(none.isEmpty)
    }

    func testSearchIsUpdatedWhenNoteChangesAndScopedToFolder() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let sub = try await store.createFolder(name: "Sub", parentId: a.id)
        let other = try await store.createFolder(name: "Other")
        let inSub = try await store.createNote(folderId: sub.id)
        let inOther = try await store.createNote(folderId: other.id)
        try await write(store, inSub, ["alpha project"])
        try await write(store, inOther, ["alpha elsewhere"])

        let scoped = try await store.search("alpha", in: a.id)
        XCTAssertEqual(scoped.map(\.id), [inSub.id])

        try await write(store, inSub, ["beta project"])
        let stale = try await store.search("alpha", in: a.id)
        XCTAssertTrue(stale.isEmpty)
    }

    func testSearchHandlesQuotesAndWildcards() async throws {
        let store = try makeStore()
        let n = try await store.createNote()
        try await write(store, n, ["say \"hi\" 100%_done"])
        let q1 = try await store.search("\"hi\"")
        XCTAssertEqual(q1.count, 1)
        let q2 = try await store.search("%_")
        XCTAssertEqual(q2.count, 1)
        let q3 = try await store.search("zz")
        XCTAssertTrue(q3.isEmpty)
    }

    // MARK: Performance

    func testSearchOverTenThousandNotesIsFast() async throws {
        let store = try makeStore()
        try await store.database.writer.write { db in
            for i in 0..<10_000 {
                var note = Note(title: "Note \(i)", snippet: "")
                try note.insert(db)
                try db.execute(
                    sql: "INSERT INTO noteSearch(noteId, title, body) VALUES (?, ?, ?)",
                    arguments: [note.id.uuidString, note.title, "lorem ipsum dolor \(i) sit amet"]
                )
            }
        }
        let start = Date()
        let hits = try await store.search("dolor 4242")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(hits.count, 1)
        XCTAssertLessThan(elapsed, 0.05, "search took \(elapsed)s")
    }
}
