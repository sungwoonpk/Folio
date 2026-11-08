import NoteCore
import SwiftUI

/// Week 1 editor: plain text. The first line becomes the title, each line is a text block.
/// The block editor (bullets, tables, images, audio) replaces this next.
struct EditorView: View {
    let noteId: UUID
    @Environment(AppModel.self) private var model

    @State private var text = ""
    @State private var lastSaved = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .focused($focused)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let blocks = (try? await model.store.blocks(noteId: noteId)) ?? []
                let joined = blocks.map(\.content).joined(separator: "\n")
                lastSaved = joined
                text = joined
                loaded = true
                if joined.isEmpty { focused = true }
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
