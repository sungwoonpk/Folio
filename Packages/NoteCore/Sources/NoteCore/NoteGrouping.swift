import Foundation

public struct NoteSection: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var notes: [Note]
}

/// Groups notes by when they were last modified:
/// Pinned, Today, Last 7 Days, Last 30 Days, then one section per month of this year
/// (September, August, ...), then one per earlier year (2025, 2024, ...).
public enum NoteGrouping {
    public static func sections(
        _ notes: [Note],
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "en_US")
    ) -> [NoteSection] {
        let startOfToday = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
        let monthStart = calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
        let thisYear = calendar.component(.year, from: now)

        let monthName = DateFormatter()
        monthName.locale = locale
        monthName.calendar = calendar
        monthName.dateFormat = "LLLL"

        var sections: [NoteSection] = []
        func add(_ id: String, _ title: String, _ note: Note) {
            if let index = sections.firstIndex(where: { $0.id == id }) {
                sections[index].notes.append(note)
            } else {
                sections.append(NoteSection(id: id, title: title, notes: [note]))
            }
        }

        // Newest first. Pinned notes are pulled into their own section at the top.
        let newestFirst = notes.sorted { $0.updatedAt > $1.updatedAt }
        for note in newestFirst where note.pinned { add("pinned", "Pinned", note) }

        for note in newestFirst where !note.pinned {
            let date = note.updatedAt
            if date >= startOfToday {
                add("today", "Today", note)
            } else if date >= weekStart {
                add("7d", "Last 7 Days", note)
            } else if date >= monthStart {
                add("30d", "Last 30 Days", note)
            } else {
                let year = calendar.component(.year, from: date)
                if year == thisYear {
                    let month = calendar.component(.month, from: date)
                    add("m-\(year)-\(month)", monthName.string(from: date), note)
                } else {
                    add("y-\(year)", String(year), note)
                }
            }
        }
        return sections
    }
}
