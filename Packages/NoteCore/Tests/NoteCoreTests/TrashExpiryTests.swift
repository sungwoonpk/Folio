import XCTest
@testable import NoteCore

/// Notes stay in Recently Deleted for 30 days, then they are removed for good.
final class TrashExpiryTests: XCTestCase {
    private let day: TimeInterval = 86_400

    private func makeStore() throws -> NoteStore {
        NoteStore(database: try AppDatabase.inMemory())
    }

    private func deletedNote(_ store: NoteStore, in folder: Folder, text: String) async throws -> Note {
        let note = try await store.createNote(folderId: folder.id)
        try await store.saveNote(id: note.id, blocks: [Block(noteId: note.id, content: text)])
        try await store.trashNote(id: note.id)
        return note
    }

    func testRetentionIsThirtyDays() {
        XCTAssertEqual(NoteStore.trashRetentionDays, 30)
    }

    func testANoteDeletedMoreThanThirtyDaysAgoIsRemovedForGood() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Work")
        let note = try await deletedNote(store, in: folder, text: "old news")

        let removed = try await store.purgeExpiredNotes(now: Date().addingTimeInterval(31 * day))

        XCTAssertEqual(removed, 1)
        let stored = try await store.note(id: note.id)
        XCTAssertNil(stored)
        let blocks = try await store.blocks(noteId: note.id)
        XCTAssertTrue(blocks.isEmpty, "the blocks go with the note")
        let trash = try await store.deletedNotes()
        XCTAssertTrue(trash.isEmpty)
    }

    func testANoteDeletedLessThanThirtyDaysAgoStays() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Work")
        let note = try await deletedNote(store, in: folder, text: "recent")

        let removed = try await store.purgeExpiredNotes(now: Date().addingTimeInterval(29 * day))

        XCTAssertEqual(removed, 0)
        let trash = try await store.deletedNotes()
        XCTAssertEqual(trash.map(\.id), [note.id])
    }

    func testTheThirtiethDayIsTheLimit() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Work")
        let note = try await deletedNote(store, in: folder, text: "boundary")
        let trashed = try await store.deletedNotes()
        let deletedAt = try XCTUnwrap(trashed.first?.deletedAt)

        let justBefore = try await store.purgeExpiredNotes(now: deletedAt.addingTimeInterval(30 * day - 1))
        XCTAssertEqual(justBefore, 0, "one second short of 30 days")
        let exactly = try await store.purgeExpiredNotes(now: deletedAt.addingTimeInterval(30 * day))
        XCTAssertEqual(exactly, 1, "30 days is enough")
        let stored = try await store.note(id: note.id)
        XCTAssertNil(stored)
    }

    func testNotesThatWereNeverDeletedAreNeverRemoved() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Work")
        let live = try await store.createNote(folderId: folder.id)
        try await store.saveNote(id: live.id, blocks: [Block(noteId: live.id, content: "still here")])

        // Far in the future: a live note is old, but it was never deleted.
        let removed = try await store.purgeExpiredNotes(now: Date().addingTimeInterval(3_650 * day))

        XCTAssertEqual(removed, 0)
        let notes = try await store.notes(in: .all)
        XCTAssertEqual(notes.map(\.id), [live.id])
        let found = try await store.search("still")
        XCTAssertEqual(found.map(\.id), [live.id], "search is untouched")
    }

    func testOnlyTheExpiredNotesGoAndTheyAreCounted() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Work")
        let old = try await deletedNote(store, in: folder, text: "old")
        // Deleted a moment after the first one, so it is not yet 30 days old when the first one is.
        try await Task.sleep(for: .milliseconds(20))
        let fresh = try await deletedNote(store, in: folder, text: "fresh")
        let trashed = try await store.deletedNotes() // newest first, so the old one is last
        let oldDeletedAt = try XCTUnwrap(trashed.last?.deletedAt)

        let removed = try await store.purgeExpiredNotes(now: oldDeletedAt.addingTimeInterval(30 * day))

        XCTAssertEqual(removed, 1)
        let trash = try await store.deletedNotes()
        XCTAssertEqual(trash.map(\.id), [fresh.id])
        let gone = try await store.note(id: old.id)
        XCTAssertNil(gone)
    }

    func testNotesThatLostTheirFolderExpireToo() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Doomed")
        let note = try await store.createNote(folderId: folder.id)
        try await store.saveNote(id: note.id, blocks: [Block(noteId: note.id, content: "orphan")])
        try await store.deleteFolder(id: folder.id) // the note goes to Recently Deleted without a folder

        let removed = try await store.purgeExpiredNotes(now: Date().addingTimeInterval(31 * day))

        XCTAssertEqual(removed, 1)
        let trash = try await store.deletedNotes()
        XCTAssertTrue(trash.isEmpty)
    }

    func testRunningItTwiceIsHarmless() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Work")
        _ = try await deletedNote(store, in: folder, text: "once")
        let later = Date().addingTimeInterval(31 * day)

        let first = try await store.purgeExpiredNotes(now: later)
        let second = try await store.purgeExpiredNotes(now: later)

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
    }
}
