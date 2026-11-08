import NoteCore
import SwiftUI

/// Note editor: runs of text (title, bullets) with tables in between.
/// The first line is the title. Everything saves as blocks.
struct EditorView: View {
    let noteId: UUID
    @Environment(AppModel.self) private var model
    @Environment(Nav.self) private var nav
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var segments: [Segment] = [.text(id: UUID(), "")]
    @State private var lastSaved: [Segment] = []
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var loading = false
    @State private var saveTask: Task<Void, Never>?
    @State private var focus: UUID?
    @State private var controller = EditorController()

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "", leading: leading) {
                IconButton(systemName: "list.bullet", label: "Bullet List") { controller.toggleBullet() }
                IconButton(systemName: "checklist", label: "Checklist") { controller.toggleChecklist() }
                IconButton(systemName: "tablecells", label: "Table") { addTable() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(segments) { segment in
                        switch segment {
                        case .text(let id, _):
                            NoteTextView(
                                text: textBinding(id), segmentId: id, isFirst: id == segments.first?.id,
                                focusRequest: $focus, controller: controller
                            )
                        case .table(let id, _):
                            TableBlockView(table: tableBinding(id)) { deleteTable(id) }
                        }
                    }
                    // Tap below the last line to keep writing.
                    Color.clear.frame(height: 160).contentShape(Rectangle())
                        .onTapGesture { focus = segments.last?.id }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Never let anyone type into a note that has not loaded: saving would overwrite it.
            .allowsHitTesting(loaded)
            .opacity(loaded ? 1 : 0)
            .overlay {
                if loadFailed {
                    ContentUnavailableView {
                        Label("Couldn't Open", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                }
            }
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        // Not .task: SwiftUI cancels it during navigation and does not restart it, which left notes unloaded.
        .onAppear { Task { await load() } }
        .onChange(of: segments) {
            guard loaded, segments != lastSaved else { return }
            saveTask?.cancel()
            saveTask = Task {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                await save()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            let finalSegments = segments
            let id = noteId
            let wasLoaded = loaded
            Task { await finish(id: id, segments: finalSegments, wasLoaded: wasLoaded) }
        }
    }

    /// Back on iPhone, sidebar toggle on iPad.
    private var leading: (icon: String, label: String, action: () -> Void)? {
        if sizeClass == .compact {
            return ("chevron.left", "Back", { nav.compactColumn = .sidebar })
        }
        return ("sidebar.left", "Sidebar", {
            nav.columns = nav.columns == .detailOnly ? .all : .detailOnly
        })
    }

    // MARK: Segment bindings and edits

    private func textBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                if case .text(_, let text)? = segments.first(where: { $0.id == id }) { return text }
                return ""
            },
            set: { value in
                if let index = segments.firstIndex(where: { $0.id == id }) {
                    segments[index] = .text(id: id, value)
                }
            }
        )
    }

    private func tableBinding(_ id: UUID) -> Binding<TableContent> {
        Binding(
            get: {
                if case .table(_, let table)? = segments.first(where: { $0.id == id }) { return table }
                return .blank()
            },
            set: { value in
                if let index = segments.firstIndex(where: { $0.id == id }) {
                    segments[index] = .table(id: id, value)
                }
            }
        )
    }

    /// Table button: goes where the cursor is, or at the end if nothing is being edited.
    private func addTable() {
        if let id = controller.activeSegmentId, let cursor = controller.cursor,
           segments.contains(where: { $0.id == id }) {
            insertTable(in: id, at: cursor)
        } else if case .text(let id, let text)? = segments.last {
            insertTable(in: id, at: (text as NSString).length)
        }
    }

    /// Splits the text at the cursor and puts a new table in between.
    private func insertTable(in id: UUID, at cursor: Int) {
        guard let index = segments.firstIndex(where: { $0.id == id }),
              case .text(_, let text) = segments[index] else { return }
        let ns = text as NSString
        let at = min(max(cursor, 0), ns.length)
        var before = ns.substring(to: at)
        var after = ns.substring(from: at)
        if before.hasSuffix("\n") { before.removeLast() }
        if after.hasPrefix("\n") { after.removeFirst() }
        let afterId = UUID()
        segments.replaceSubrange(index...index, with: [
            .text(id: id, before), .table(id: UUID(), .blank()), .text(id: afterId, after),
        ])
        focus = afterId
    }

    /// Removes a table and joins the text on both sides.
    private func deleteTable(_ id: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == id }),
              index > 0, index < segments.count - 1,
              case .text(let beforeId, let before) = segments[index - 1],
              case .text(_, let after) = segments[index + 1] else { return }
        let joined = before.isEmpty ? after : (after.isEmpty ? before : before + "\n" + after)
        segments.replaceSubrange((index - 1)...(index + 1), with: [.text(id: beforeId, joined)])
    }

    // MARK: Loading

    /// A failed read must never turn into an empty note.
    /// The editor stays locked and tries again; only a successful read unlocks it.
    /// Runs as its own task, so leaving and re-entering the screen cannot cancel it half way.
    private func load() async {
        guard !loaded, !loading else { return }
        loading = true
        loadFailed = false
        defer { loading = false }
        for attempt in 0..<4 {
            do {
                let blocks = try await model.store.blocks(noteId: noteId)
                segments = NoteDocument.segments(from: blocks)
                lastSaved = segments
                loaded = true
                if NoteDocument.isBlank(segments) { focus = segments.first?.id }
                return
            } catch {
                try? await Task.sleep(for: .milliseconds(150 * (attempt + 1)))
            }
        }
        loadFailed = true
    }

    // MARK: Saving

    private func save() async {
        let current = segments
        try? await model.store.saveNote(id: noteId, blocks: NoteDocument.blocks(from: current, noteId: noteId))
        lastSaved = current
        await model.reloadAfterEdit()
    }

    private func finish(id: UUID, segments: [Segment], wasLoaded: Bool) async {
        guard wasLoaded else { return }
        if NoteDocument.isBlank(segments) {
            await model.discardIfEmpty(id)
        } else if segments != lastSaved {
            try? await model.store.saveNote(id: id, blocks: NoteDocument.blocks(from: segments, noteId: id))
            await model.reloadAfterEdit()
        }
    }
}
