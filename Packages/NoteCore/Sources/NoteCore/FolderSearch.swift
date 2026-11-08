import Foundation

/// Finds folders by name. Any part of the name matches, upper or lower case, accents ignored.
public enum FolderSearch {
    public static func matching(_ folders: [Folder], query: String) -> [Folder] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return folders.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
