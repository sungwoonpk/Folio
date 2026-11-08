import NoteCore
import SwiftUI

/// Screens pushed on top of the main folder list.
enum Route: Hashable {
    /// A folder's contents. nil is "Notes", the notes that are not in any folder.
    case folder(UUID?)
}

/// Column navigation state. We draw our own headers, so we also drive back and sidebar toggles.
@MainActor @Observable
final class Nav {
    var columns: NavigationSplitViewVisibility = .automatic
    /// iPhone opens on the main screen.
    var compactColumn: NavigationSplitViewColumn = .sidebar
    var path: [Route] = []

    func back() {
        if !path.isEmpty { path.removeLast() }
    }
}

/// Plain icon button. No circle, no glass.
struct IconButton: View {
    let systemName: String
    var label: String = ""
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(label.isEmpty ? systemName : label)
    }
}

/// Round check shown in front of rows while selecting.
struct SelectMark: View {
    let picked: Bool

    var body: some View {
        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(picked ? Theme.accent : Color.secondary)
            .frame(width: 26)
    }
}

/// One header for every screen: back or sidebar toggle on the left,
/// all actions together on the right, title below.
struct Header<Actions: View>: View {
    let title: String
    var leading: (icon: String, label: String, action: () -> Void)?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let leading {
                    IconButton(systemName: leading.icon, label: leading.label, action: leading.action)
                }
                Spacer()
                actions()
            }
            .foregroundStyle(Theme.accent)
            if !title.isEmpty {
                Text(title)
                    .font(Theme.serifTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.pinned {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                }
                Text(note.title.isEmpty ? "New Note" : note.title)
                    .font(.system(.headline, design: .serif))
                    .lineLimit(1)
            }
            Text(note.snippet.isEmpty ? "No additional text" : note.snippet)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(note.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(Theme.meta)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

/// Pick a destination folder, or the top level.
struct MovePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let title: String
    /// Name of the top-level choice: "Notes" for notes, "Note" for folders.
    var rootTitle: String = "Notes"
    /// Notes always live in a folder, so only folders get a top-level choice.
    var allowRoot = true
    var excluding: UUID?
    var current: UUID?
    let onPick: (UUID?) -> Void

    var body: some View {
        NavigationStack {
            List {
                if allowRoot { row(rootTitle, systemImage: "house", depth: 0, target: nil) }
                ForEach(model.moveTargets(excluding: excluding), id: \.folder.id) { item in
                    row(item.folder.name, systemImage: "folder", depth: item.depth + 1, target: item.folder.id)
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ name: String, systemImage: String, depth: Int, target: UUID?) -> some View {
        Button {
            onPick(target)
            dismiss()
        } label: {
            HStack {
                Label(name, systemImage: systemImage).font(Theme.serifBody)
                Spacer()
                if target == current { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .padding(.leading, CGFloat(depth) * 18)
        }
        .foregroundStyle(.primary)
    }
}

/// Accepts dragged notes and folders and moves them into `folderId` (nil = top level).
struct ItemDrop: ViewModifier {
    let folderId: UUID?
    let key: String
    let enabled: Bool
    @Binding var highlight: String?
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: ItemRef.self) { items, _ in
                Task { await model.drop(items, onto: folderId) }
                return true
            } isTargeted: { targeted in
                if targeted {
                    highlight = key
                } else if highlight == key {
                    highlight = nil
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func acceptsItems(
        into folderId: UUID?, key: String, enabled: Bool = true, highlight: Binding<String?>
    ) -> some View {
        modifier(ItemDrop(folderId: folderId, key: key, enabled: enabled, highlight: highlight))
    }
}

extension View {
    /// Drag source that switches off while editing, so it does not fight the reorder handles.
    @ViewBuilder
    func draggableItem(_ item: ItemRef, enabled: Bool) -> some View {
        if enabled { draggable(item) } else { self }
    }
}

/// Folder row: icon on the left, title, note count and an arrow on the right.
/// The soft card and the arrow make it read as something you can tap.
struct FolderCard: View {
    let title: String
    let icon: String
    let count: Int?
    var picked: Bool?
    var highlighted = false
    var muted = false

    var body: some View {
        HStack(spacing: 12) {
            if let picked { SelectMark(picked: picked) }
            Image(systemName: icon)
                .foregroundStyle(muted ? Color.secondary : Theme.accent)
                .frame(width: 24)
            Text(title)
                .font(Theme.serifBody)
                .foregroundStyle(muted ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let count {
                Text("\(count)").font(Theme.meta).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            highlighted ? Theme.accent.opacity(0.2) : Theme.card,
            in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

extension View {
    /// Row that sits on a clear background so the card inside is the only thing drawn.
    func cardRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
    }
}
