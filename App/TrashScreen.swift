import NoteCore
import SwiftUI

/// Recently Deleted: deleted notes only. Restoring asks which folder the note should go into.
struct TrashScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selecting = false
    @State private var picked: Set<UUID> = []
    @State private var confirmPurge = false
    @State private var restoreIds: Set<UUID> = []
    @State private var showRestorePicker = false

    private var isEmpty: Bool { model.deleted.isEmpty }
    private var allIDs: Set<UUID> { Set(model.deleted.map(\.id)) }

    private var title: String {
        guard selecting else { return "Recently Deleted" }
        return picked.isEmpty ? "Edit" : "\(picked.count) Selected"
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(title: title, leading: ("chevron.left", "Back", { dismiss() })) { actions }
            list
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.reloadTrash() }
        .onDisappear { endSelection() }
        .confirmationDialog("Delete \(picked.count) forever?", isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let ids = picked
                endSelection()
                Task { await model.purge(ids: ids) }
            }
        }
        // Where should the restored notes go?
        .sheet(isPresented: $showRestorePicker) {
            MovePicker(title: "Restore to", current: nil) { folderId in
                let ids = restoreIds
                endSelection()
                Task { await model.restore(ids: ids, to: folderId) }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if selecting {
            Button(!allIDs.isEmpty && picked == allIDs ? "Deselect All" : "Select All") {
                picked = picked == allIDs ? [] : allIDs
            }
            IconButton(systemName: "arrow.uturn.backward", label: "Restore") {
                restoreIds = picked
                showRestorePicker = true
            }
            .disabled(picked.isEmpty)
            IconButton(systemName: "trash", label: "Delete") { confirmPurge = true }
                .disabled(picked.isEmpty)
            Button("Done") { endSelection() }
        } else {
            Button("Edit") { selecting = true }
        }
    }

    private func endSelection() {
        selecting = false
        picked = []
    }

    private func toggle(_ id: UUID) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    private var list: some View {
        List {
            ForEach(model.deleted) { note in
                HStack(spacing: 10) {
                    if selecting { SelectMark(picked: picked.contains(note.id)) }
                    NoteRow(note: note)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { if selecting { toggle(note.id) } }
                .swipeActions(edge: .leading) {
                    Button("Restore", systemImage: "arrow.uturn.backward") {
                        restoreIds = [note.id]
                        showRestorePicker = true
                    }
                    .tint(Theme.accent)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await model.purge(ids: [note.id]) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if isEmpty {
                ContentUnavailableView(selecting ? "Nothing to Edit" : "No Deleted Notes", systemImage: "trash")
            }
        }
    }
}
