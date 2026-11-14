import NoteCore
import SwiftUI

/// Screens pushed on top of the main folder list.
enum Route: Hashable {
    /// A folder's contents. nil is "Notes", the notes that are not in any folder.
    case folder(UUID?)
    case trash
}

/// Column navigation state. We draw our own headers, so we also drive back and sidebar toggles.
@MainActor @Observable
final class Nav {
    var columns: NavigationSplitViewVisibility = .automatic
    /// A compact screen opens on the main screen.
    var compactColumn: NavigationSplitViewColumn = .sidebar
    var path: [Route] = []

    func back() {
        if !path.isEmpty { path.removeLast() }
    }
}

/// Plain icon button. No circle, no glass.
struct IconButton: View {
    var systemName: String = ""
    /// Used instead of the system symbol when set.
    var image: Image?
    var label: String = ""
    /// What the button currently shows, read out by VoiceOver and checked by tests.
    var value: String = ""
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            (image ?? Image(systemName: systemName))
                .font(.system(size: 19, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(label.isEmpty ? systemName : label)
        .accessibilityValue(value)
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
            .accessibilityLabel(picked ? "Selected" : "Not selected")
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
                    .accessibilityLabel("Clear")
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
                        .accessibilityLabel("Pinned")
                }
                Text(note.title.isEmpty ? "New Note" : note.title)
                    .font(.system(.headline, design: .serif))
                    .lineLimit(1)
            }
            Text(note.snippet.isEmpty ? "No additional text" : note.snippet)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(note.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(Theme.meta)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

/// Pick a folder to move notes into. Folders are one level, so this is a flat list.
/// It can also make a folder, so restoring is never stuck when no folder exists.
struct MovePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var title = "Move"
    var current: UUID?
    let onPick: (UUID) -> Void

    @State private var showNewFolder = false
    @State private var nameText = ""

    var body: some View {
        NavigationStack {
            List(model.folders) { folder in
                Button {
                    onPick(folder.id)
                    dismiss()
                } label: {
                    HStack {
                        Label(folder.name, systemImage: "folder").font(Theme.serifBody)
                        Spacer()
                        if folder.id == current { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                    }
                }
                .foregroundStyle(.primary)
            }
            .listStyle(.plain)
            .overlay {
                if model.folders.isEmpty {
                    ContentUnavailableView {
                        Label("No Folders", systemImage: "folder")
                    } actions: {
                        Button("New Folder") { startNewFolder() }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !model.folders.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Folder", systemImage: "folder.badge.plus") { startNewFolder() }
                    }
                }
            }
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("Name", text: $nameText)
                Button("Create") {
                    Task {
                        // The new folder is the one the user wants, so use it right away.
                        if let id = await model.createFolder(name: nameText) {
                            onPick(id)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func startNewFolder() {
        nameText = ""
        showNewFolder = true
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
                Text("\(count)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
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

/// Folder with an arrow inside, so it reads as "move to a folder" at a glance.
enum MoveIcon {
    /// Drawn once into a template image, so it tints like a system symbol, also inside menus.
    @MainActor static let image: Image = {
        let drawing = ZStack {
            Image(systemName: "folder").font(.system(size: 20, weight: .medium))
            Image(systemName: "arrow.right").font(.system(size: 9, weight: .heavy)).offset(y: 1.5)
        }
        .frame(width: 28, height: 24)
        .foregroundStyle(.black)
        let renderer = ImageRenderer(content: drawing)
        renderer.scale = 3
        guard let rendered = renderer.uiImage else { return Image(systemName: "folder") }
        return Image(uiImage: rendered.withRenderingMode(.alwaysTemplate))
    }()
}
