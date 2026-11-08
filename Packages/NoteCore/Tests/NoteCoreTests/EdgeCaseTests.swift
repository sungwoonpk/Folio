import XCTest
@testable import NoteCore

/// Odd input and boundary situations. Each test is a way the app could be hurt in real use.
final class EdgeCaseTests: XCTestCase {
    private func makeStore() throws -> NoteStore { NoteStore(database: try AppDatabase.inMemory()) }

    private func save(_ store: NoteStore, _ note: Note, _ lines: [String]) async throws {
        try await store.saveNote(id: note.id, blocks: lines.map { Block(noteId: note.id, content: $0) })
    }

    // MARK: Search must never throw or misbehave on strange queries

    func testSearchSurvivesCharactersThatBreakFullTextSyntax() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        try await save(store, note, ["He said \"hello\" (loudly) * OR NOT -1 AND NEAR/2 ^caret: colon back\\slash"])

        let queries = [
            "\"", "\"\"", "\"hello\"", "(", ")", "()", "*", "**", "-", "-1", "OR", "AND", "NOT", "NEAR/2",
            "^caret", "colon:", "back\\slash", "a\" OR \"b", "%", "_", "%_%", "'", "' OR 1=1 --", ";",
            "hello* OR", "\u{0}", "\n", "\t", "  ", "",
        ]
        for query in queries {
            do { _ = try await store.search(query) } catch { XCTFail("search threw for \(query.debugDescription): \(error)") }
        }
        let quoted = try await store.search("\"hello\"")
        XCTAssertEqual(quoted.map(\.id), [note.id], "quotes in the text can be searched for")
        let paren = try await store.search("(loudly)")
        XCTAssertEqual(paren.map(\.id), [note.id])
        let star = try await store.search("*")
        XCTAssertEqual(star.map(\.id), [note.id])
        let none = try await store.search("zzzzqq")
        XCTAssertTrue(none.isEmpty)
    }

    func testSearchWithVeryLongAndUnicodeQueries() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        try await save(store, note, ["Party 🎉 plans", "café résumé naïve", "e\u{0301}clair"])

        let long = String(repeating: "x", count: 20_000)
        let none = try await store.search(long)
        XCTAssertTrue(none.isEmpty)
        let emoji = try await store.search("🎉")
        XCTAssertEqual(emoji.map(\.id), [note.id])
        let accents = try await store.search("café")
        XCTAssertEqual(accents.map(\.id), [note.id])
    }

    // MARK: Big and odd content

    func testHugeNoteSavesAndKeepsTitleAndPreviewShort() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        let huge = String(repeating: "word ", count: 60_000) // 300k characters in one line
        try await save(store, note, [huge, "second"])

        let saved = try await store.note(id: note.id)
        XCTAssertLessThanOrEqual(saved?.title.count ?? 0, 200)
        XCTAssertLessThanOrEqual(saved?.snippet.count ?? 0, 140)
        let blocks = try await store.blocks(noteId: note.id)
        XCTAssertEqual(blocks.first?.content.count, huge.count, "nothing is cut from the stored text")
        let found = try await store.search("second")
        XCTAssertEqual(found.map(\.id), [note.id])
    }

    func testThousandBlocksKeepTheirOrder() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        try await save(store, note, (0..<1000).map { "line \($0)" })
        let blocks = try await store.blocks(noteId: note.id)
        XCTAssertEqual(blocks.count, 1000)
        XCTAssertEqual(blocks.map(\.position), Array(0..<1000))
        XCTAssertEqual(blocks[999].content, "line 999")
    }

    func testWindowsLineEndingsDoNotLeaveStrayCarriageReturns() {
        let noteId = UUID()
        let segments: [Segment] = [.text(id: UUID(), "Title\r\n• one\r\n☐ ignored\r\nlast\rend")]
        let blocks = NoteDocument.blocks(from: segments, noteId: noteId)
        XCTAssertTrue(blocks.allSatisfy { !$0.content.contains("\r") }, "got \(blocks.map(\.content))")
        XCTAssertEqual(blocks.map(\.content), ["Title", "one", "☐ ignored", "last", "end"])
    }

    func testEmojiAndCombiningCharactersAreNeverCutInTheMiddle() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        let family = "👨‍👩‍👧‍👦" // one character made of several scalars
        try await save(store, note, [String(repeating: family, count: 300)])
        let saved = try await store.note(id: note.id)
        XCTAssertEqual(saved?.title.count, 200)
        XCTAssertTrue(saved?.title.allSatisfy { String($0) == family } ?? false, "title cut inside a character")
    }

    // MARK: Folders

    func testFolderNamesAreTrimmedAndCannotBeEmpty() async throws {
        let store = try makeStore()
        for bad in ["", "   ", "\n\t "] {
            do {
                _ = try await store.createFolder(name: bad)
                XCTFail("created a folder named \(bad.debugDescription)")
            } catch NoteStoreError.invalidName {}
        }
        let folder = try await store.createFolder(name: "  Work  ")
        XCTAssertEqual(folder.name, "Work")

        do {
            try await store.renameFolder(id: folder.id, to: "  ")
            XCTFail("renamed to empty")
        } catch NoteStoreError.invalidName {}
        let folders = try await store.folders()
        XCTAssertEqual(folders.map(\.name), ["Work"])
    }

    func testVeryLongFolderNamesAreCapped() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: String(repeating: "n", count: 10_000))
        XCTAssertEqual(folder.name.count, NoteStore.maxFolderNameLength)
        try await store.renameFolder(id: folder.id, to: String(repeating: "m", count: 5_000))
        let renamed = try await store.folders().first
        XCTAssertEqual(renamed?.name.count, NoteStore.maxFolderNameLength)
    }

    func testTwoFoldersMayShareAName() async throws {
        let store = try makeStore()
        _ = try await store.createFolder(name: "Same")
        _ = try await store.createFolder(name: "Same")
        let folders = try await store.folders()
        XCTAssertEqual(folders.map(\.name), ["Same", "Same"])
    }

    func testNotesCannotPointAtAFolderThatDoesNotExist() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "Real")
        let note = try await store.createNote(folderId: folder.id)

        do {
            try await store.moveNote(id: note.id, to: UUID())
            XCTFail("moved into a folder that does not exist")
        } catch {}
        let after = try await store.note(id: note.id)
        XCTAssertEqual(after?.folderId, folder.id, "the failed move changed nothing")

        do {
            _ = try await store.createNote(folderId: UUID())
            XCTFail("created a note in a folder that does not exist")
        } catch {}
        let all = try await store.notes(in: .all)
        XCTAssertEqual(all.count, 1)
    }

    func testDeletingAFolderThatIsAlreadyGoneIsHarmless() async throws {
        let store = try makeStore()
        let keep = try await store.createFolder(name: "Keep")
        try await store.deleteFolder(id: UUID())
        let folders = try await store.folders()
        XCTAssertEqual(folders.map(\.id), [keep.id])
    }

    func testReorderingWithUnknownOrRepeatedIdsDoesNotHurt() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let b = try await store.createFolder(name: "B")
        try await store.reorderFolders([b.id, UUID(), b.id, a.id])
        let order = try await store.folders().map(\.id)
        XCTAssertEqual(Set(order), [a.id, b.id])
        XCTAssertEqual(order.count, 2)
    }

    func testDuplicatingTheSameFolderTwiceKeepsBothCopies() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "A")
        let note = try await store.createNote(folderId: folder.id)
        try await save(store, note, ["hello"])
        let one = try await store.duplicateFolder(id: folder.id)
        let two = try await store.duplicateFolder(id: folder.id)
        XCTAssertNotEqual(one.id, two.id)
        let counts = try await [one.id, two.id, folder.id].asyncMap { try await store.notes(in: .folder($0)).count }
        XCTAssertEqual(counts, [1, 1, 1])
    }

    // MARK: Notes

    func testRestoreOnlyAppliesToDeletedNotes() async throws {
        let store = try makeStore()
        let a = try await store.createFolder(name: "A")
        let b = try await store.createFolder(name: "B")
        let note = try await store.createNote(folderId: a.id)
        try await save(store, note, ["live"])
        try await store.restoreNote(id: note.id, to: b.id) // not deleted: must not silently move it
        let after = try await store.note(id: note.id)
        XCTAssertEqual(after?.folderId, a.id)
    }

    func testSavingNothingEmptiesTheNoteAndItsPreview() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        try await save(store, note, ["something", "else"])
        try await store.saveNote(id: note.id, blocks: [])
        let saved = try await store.note(id: note.id)
        XCTAssertEqual(saved?.title, "")
        XCTAssertEqual(saved?.snippet, "")
        let blocks = try await store.blocks(noteId: note.id)
        XCTAssertTrue(blocks.isEmpty)
        let found = try await store.search("something")
        XCTAssertTrue(found.isEmpty, "an emptied note must leave the search index")
    }

    func testManySavesAtOnceNeverMixTwoVersionsOfANote() async throws {
        let store = try makeStore()
        let note = try await store.createNote()
        await withTaskGroup(of: Void.self) { group in
            for version in 1...25 {
                group.addTask {
                    let lines = (0..<version).map { "v\(version) line \($0)" }
                    try? await store.saveNote(
                        id: note.id, blocks: lines.map { Block(noteId: note.id, content: $0) }
                    )
                }
            }
        }
        let blocks = try await store.blocks(noteId: note.id)
        let versions = Set(blocks.map { $0.content.split(separator: " ")[0] })
        XCTAssertEqual(versions.count, 1, "blocks from different saves got mixed: \(versions)")
        XCTAssertEqual(blocks.count, Int(versions.first!.dropFirst())!, "a save was applied only partly")
    }

    func testPinnedAndDeletedNoteStaysPinnedWhenRestored() async throws {
        let store = try makeStore()
        let folder = try await store.createFolder(name: "F")
        let note = try await store.createNote(folderId: folder.id)
        try await save(store, note, ["keep pinned"])
        try await store.setPinned(id: note.id, true)
        try await store.trashNote(id: note.id)
        try await store.restoreNote(id: note.id, to: folder.id)
        let restored = try await store.note(id: note.id)
        XCTAssertEqual(restored?.pinned, true)
    }

    // MARK: Date groups

    func testGroupingHandlesTheFutureMidnightAndEqualTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 0, minute: 0, second: 30))!
        let justAfterMidnight = now.addingTimeInterval(-10)
        let justBeforeMidnight = now.addingTimeInterval(-60)
        let future = now.addingTimeInterval(86_400 * 3)

        func note(_ title: String, _ date: Date) -> Note { Note(title: title, createdAt: date, updatedAt: date) }
        let sections = NoteGrouping.sections(
            [note("future", future), note("after", justAfterMidnight), note("before", justBeforeMidnight),
             note("tie1", now), note("tie2", now)],
            now: now, calendar: calendar
        )
        XCTAssertEqual(sections.map(\.title), ["Today", "Last 7 Days"])
        XCTAssertEqual(Set(sections[0].notes.map(\.title)), ["future", "after", "tie1", "tie2"])
        XCTAssertEqual(sections[1].notes.map(\.title), ["before"], "one minute before midnight is yesterday")
        XCTAssertEqual(sections.flatMap(\.notes).count, 5, "no note is lost or repeated")
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
