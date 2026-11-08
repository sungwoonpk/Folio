import XCTest
@testable import NoteCore

final class NoteGroupingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func note(_ title: String, _ updated: Date, pinned: Bool = false) -> Note {
        Note(title: title, pinned: pinned, createdAt: updated, updatedAt: updated)
    }

    func testSectionsFollowTodayWeekMonthMonthsYears() {
        let now = date(2026, 11, 7, 15)
        let notes = [
            note("today", date(2026, 11, 7, 9)),
            note("yesterday", date(2026, 11, 6)),
            note("six days ago", date(2026, 11, 1)),
            note("two weeks ago", date(2026, 10, 24)),
            note("october early", date(2026, 10, 2)),
            note("september", date(2026, 9, 20)),
            note("august", date(2026, 8, 3)),
            note("last year", date(2025, 12, 31)),
            note("older", date(2024, 1, 5)),
        ]
        let sections = NoteGrouping.sections(notes, now: now, calendar: calendar)

        XCTAssertEqual(
            sections.map(\.title),
            ["Today", "Last 7 Days", "Last 30 Days", "October", "September", "August", "2025", "2024"]
        )
        XCTAssertEqual(sections[0].notes.map(\.title), ["today"])
        XCTAssertEqual(sections[1].notes.map(\.title), ["yesterday", "six days ago"])
        XCTAssertEqual(sections[2].notes.map(\.title), ["two weeks ago"])
    }

    func testPinnedGoFirstAndAreNotRepeated() {
        let now = date(2026, 11, 7)
        let notes = [
            note("old pinned", date(2024, 3, 1), pinned: true),
            note("today", date(2026, 11, 7, 9)),
        ]
        let sections = NoteGrouping.sections(notes, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["Pinned", "Today"])
        XCTAssertEqual(sections.flatMap(\.notes).count, 2)
    }

    func testEmptySectionsAreOmittedAndNewestComesFirstInsideASection() {
        let now = date(2026, 11, 7)
        let sections = NoteGrouping.sections(
            [note("a", date(2026, 11, 7, 8)), note("b", date(2026, 11, 7, 11))], now: now, calendar: calendar
        )
        XCTAssertEqual(sections.map(\.title), ["Today"])
        XCTAssertEqual(sections[0].notes.map(\.title), ["b", "a"])
        XCTAssertTrue(NoteGrouping.sections([], now: now, calendar: calendar).isEmpty)
    }
}
