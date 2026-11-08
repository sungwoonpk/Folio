import NoteCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    @State private var showSettings = false
    @State private var showNewFolder = false
    @State private var newFolderParent: UUID?
    @State private var nameText = ""
    @State private var renaming: Folder?
    @State private var moving: Folder?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            Label("Notes", systemImage: "note.text").tag(SidebarItem.all)

            Section("Folders") {
                OutlineGroup(model.folderTree, children: \.children) { node in
                    Label(node.folder.name, systemImage: "folder")
                        .tag(SidebarItem.folder(node.id))
                        .contextMenu { menu(for: node.folder) }
                }
            }

            Label("Trash", systemImage: "trash").tag(SidebarItem.trash)
        }
        .navigationTitle("Folders")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("New Folder", systemImage: "folder.badge.plus") {
                    newFolderParent = nil
                    nameText = ""
                    showNewFolder = true
                }
            }
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $nameText)
            Button("Create") { Task { await model.createFolder(name: nameText, parentId: newFolderParent) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $nameText)
            Button("Save") {
                if let folder = renaming { Task { await model.renameFolder(folder.id, to: nameText) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $moving) { folder in
            MovePicker(title: "Move", excluding: folder.id, current: folder.parentId) { target in
                Task { await model.moveFolder(folder.id, to: target) }
            }
        }
    }

    @ViewBuilder
    private func menu(for folder: Folder) -> some View {
        Button("New Folder", systemImage: "folder.badge.plus") {
            newFolderParent = folder.id
            nameText = ""
            showNewFolder = true
        }
        Button("Rename", systemImage: "pencil") {
            nameText = folder.name
            renaming = folder
        }
        Button("Move", systemImage: "folder") { moving = folder }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            Task { await model.duplicateFolder(folder.id) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            Task { await model.trashFolder(folder.id) }
        }
    }
}

/// Pick a destination folder, or the top level.
struct MovePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let title: String
    var excluding: UUID?
    var current: UUID?
    let onPick: (UUID?) -> Void

    var body: some View {
        NavigationStack {
            List {
                row("Notes", systemImage: "note.text", depth: 0, target: nil)
                ForEach(model.moveTargets(excluding: excluding), id: \.folder.id) { item in
                    row(item.folder.name, systemImage: "folder", depth: item.depth + 1, target: item.folder.id)
                }
            }
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
                Label(name, systemImage: systemImage)
                Spacer()
                if target == current { Image(systemName: "checkmark") }
            }
            .padding(.leading, CGFloat(depth) * 18)
        }
        .foregroundStyle(.primary)
    }
}
