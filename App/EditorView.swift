import NoteCore
import SwiftUI

/// Plain-text editor for now. The first line becomes the title, each line is a text block.
/// The block editor (bullets, tables, images, audio) replaces this next.
struct EditorView: View {
    let noteId: UUID
    @Environment(AppModel.self) private var model
    @Environment(Nav.self) private var nav
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var text = ""
    @State private var lastSaved = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var autofocus = false

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "", leading: leading) { EmptyView() }
            NoteTextView(text: $text, autofocus: autofocus)
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            let blocks = (try? await model.store.blocks(noteId: noteId)) ?? []
            let joined = blocks.map(\.content).joined(separator: "\n")
            lastSaved = joined
            text = joined
            loaded = true
            autofocus = joined.isEmpty
        }
        .onChange(of: text) {
            guard loaded, text != lastSaved else { return }
            saveTask?.cancel()
            saveTask = Task {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                await save()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            let finalText = text
            let id = noteId
            let wasLoaded = loaded
            Task { await finish(id: id, text: finalText, wasLoaded: wasLoaded) }
        }
    }

    /// Back on iPhone, list and sidebar toggle on iPad.
    private var leading: (icon: String, label: String, action: () -> Void)? {
        if sizeClass == .compact {
            return ("chevron.left", "Notes", { nav.compactColumn = .content })
        }
        return ("sidebar.left", "Sidebar", {
            nav.columns = nav.columns == .detailOnly ? .all : .detailOnly
        })
    }

    private func save() async {
        let current = text
        try? await model.store.saveNote(id: noteId, blocks: Self.blocks(from: current, noteId: noteId))
        lastSaved = current
        await model.reloadNotes()
    }

    private func finish(id: UUID, text: String, wasLoaded: Bool) async {
        guard wasLoaded else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await model.discardIfEmpty(id)
        } else if text != lastSaved {
            try? await model.store.saveNote(id: id, blocks: Self.blocks(from: text, noteId: id))
            await model.reloadNotes()
        }
    }

    private static func blocks(from text: String, noteId: UUID) -> [Block] {
        text.components(separatedBy: "\n").map { Block(noteId: noteId, content: $0) }
    }
}
