import NoteCore
import SwiftUI

struct TrashScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(Nav.self) private var nav

    @State private var selecting = false
    @State private var picked: Set<UUID> = []
    @State private var confirmPurge = false

    private var isEmpty: Bool { model.trash.folders.isEmpty && model.trash.notes.isEmpty }
    private var allIDs: Set<UUID> { Set(model.trash.folders.map(\.id)).union(model.trash.notes.map(\.id)) }

    private var title: String {
        guard selecting else { return "Trash" }
        return picked.isEmpty ? "Edit" : "\(picked.count) Selected"
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(title: title, leading: ("chevron.left", "Home", { nav.back() })) { actions }
            list
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.reloadTrash() }
        .confirmationDialog("Delete \(picked.count) forever?", isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let ids = picked
                endSelection()
                Task { await model.purge(ids: ids) }
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
                let ids = picked
                endSelection()
                Task { await model.restore(ids: ids) }
            }
            .disabled(picked.isEmpty)
            IconButton(systemName: "trash", label: "Delete") { confirmPurge = true }
                .disabled(picked.isEmpty)
            Button("Done") { endSelection() }
        } else {
            Button("Edit") { selecting = true }.disabled(isEmpty)
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
            if !model.trash.folders.isEmpty {
                Section {
                    ForEach(model.trash.folders) { folder in
                        HStack(spacing: 10) {
                            if selecting { SelectMark(picked: picked.contains(folder.id)) }
                            Label(folder.name, systemImage: "folder").font(Theme.serifBody)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if selecting { toggle(folder.id) } }
                        .swipeActions(edge: .leading) {
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                Task { await model.restore(ids: [folder.id]) }
                            }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.purge(ids: [folder.id]) }
                            }
                        }
                    }
                } header: {
                    Text("FOLDERS").font(Theme.meta)
                }
            }
            if !model.trash.notes.isEmpty {
                Section {
                    ForEach(model.trash.notes) { note in
                        HStack(spacing: 10) {
                            if selecting { SelectMark(picked: picked.contains(note.id)) }
                            NoteRow(note: note)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if selecting { toggle(note.id) } }
                        .swipeActions(edge: .leading) {
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                Task { await model.restore(ids: [note.id]) }
                            }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await model.purge(ids: [note.id]) }
                            }
                        }
                    }
                } header: {
                    Text("NOTES").font(Theme.meta)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if isEmpty { ContentUnavailableView("Trash is Empty", systemImage: "trash") }
        }
    }
}
