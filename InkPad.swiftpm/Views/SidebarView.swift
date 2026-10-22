import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.noteNavigation) private var navigation
    @Binding var scope: LibraryScope?
    @State private var prompt: NamePrompt?
    @State private var folderToDelete: Folder?
    @State private var collapsed: Set<UUID> = []

    private var expandedFolders: Set<UUID> {
        Set(store.folders.map(\.id)).subtracting(collapsed)
    }

    var body: some View {
        List(selection: $scope) {
            Section("Library") {
                Label("All Notes", systemImage: "tray.full")
                    .tag(LibraryScope.allNotes)
                Label("Unfiled", systemImage: "tray")
                    .tag(LibraryScope.unfiled)
                Button {
                    let today = workspace.tasks
                        .filter { task in task.status != .done && (task.dueDate.map(Calendar.current.isDateInToday) ?? false) }
                        .map(\.title)
                    if let note = store.dailyNote(tasks: today) {
                        scope = .allNotes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { navigation.openNote(note.id) }
                    }
                } label: {
                    Label("Today's Note", systemImage: "calendar.badge.clock")
                }
                Label("Graph", systemImage: "circle.hexagongrid")
                    .tag(LibraryScope.graph)
            }

            Section("Workspace") {
                Label("Planner", systemImage: "checklist")
                    .tag(LibraryScope.planner)
                Label("Expenses", systemImage: "creditcard")
                    .tag(LibraryScope.expenses)
                Label("Mind Maps", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(LibraryScope.mindMaps)
            }

            if !store.allTags.isEmpty {
                Section("Tags") {
                    ForEach(store.allTags, id: \.self) { tag in
                        Label("#\(tag)", systemImage: "number")
                            .tag(LibraryScope.tag(tag))
                    }
                }
            }

            Section {
                ForEach(store.folderTree(expanded: expandedFolders)) { row in
                    folderRow(row)
                }
            } header: {
                HStack {
                    Text("Folders")
                    Spacer()
                    Button {
                        promptNewFolder(in: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Folder")
                }
            }
        }
        .navigationTitle("InkPad")
        .namePrompt($prompt)
        .confirmationDialog(
            "Delete \"\(folderToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: folderToDelete
        ) { folder in
            Button("Delete Folder", role: .destructive) {
                if scope == .folder(folder.id) {
                    scope = folder.parentID.map { LibraryScope.folder($0) } ?? .allNotes
                }
                store.deleteFolder(folder.id)
            }
        } message: { _ in
            Text("Its notes and subfolders move up one level. No notes are deleted.")
        }
    }

    private func folderRow(_ row: FolderRow) -> some View {
        let folder = row.folder
        return HStack(spacing: 6) {
            if row.hasChildren {
                Button {
                    if collapsed.contains(folder.id) {
                        collapsed.remove(folder.id)
                    } else {
                        collapsed.insert(folder.id)
                    }
                } label: {
                    Image(systemName: collapsed.contains(folder.id) ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 16)
            }
            Label {
                Text(folder.name)
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(folder.color.tint)
            }
        }
        .padding(.leading, CGFloat(row.depth) * 18)
        .tag(LibraryScope.folder(folder.id))
        .contextMenu {
            Button {
                promptNewFolder(in: folder.id)
            } label: {
                Label("New Subfolder", systemImage: "folder.badge.plus")
            }
            Button {
                prompt = NamePrompt(
                    title: "Rename Folder",
                    initialText: folder.name,
                    confirmTitle: "Rename"
                ) { store.renameFolder(folder.id, to: $0) }
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Menu {
                ForEach(FolderColor.allCases) { color in
                    Button {
                        store.setFolderColor(folder.id, to: color)
                    } label: {
                        Label(color.title, systemImage: folder.color == color ? "checkmark.circle.fill" : "circle.fill")
                    }
                    .tint(color.color)
                }
            } label: {
                Label("Color", systemImage: "paintpalette")
            }
            Button(role: .destructive) {
                folderToDelete = folder
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func promptNewFolder(in parentID: UUID?) {
        prompt = NamePrompt(
            title: parentID == nil ? "New Folder" : "New Subfolder",
            initialText: "",
            confirmTitle: "Create"
        ) { name in
            if let folder = store.createFolder(named: name, in: parentID) {
                if let parentID { collapsed.remove(parentID) }
                scope = .folder(folder.id)
            }
        }
    }
}
