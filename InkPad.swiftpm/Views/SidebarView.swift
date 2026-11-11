import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.noteNavigation) private var navigation
    @Binding var scope: LibraryScope?
    @State private var prompt: NamePrompt?
    @State private var folderToDelete: Folder?
    @State private var collapsed: Set<UUID> = []
    @State private var showsBackup = false
    @State private var showsRecentlyDeleted = false
    @State private var showsThemes = false
    /// Applied once the Themes sheet has closed (applying rebuilds the app).
    @State private var themeToApply: ThemeRecipe?
    @AppStorage(BackupView.lastBackupKey) private var lastBackupAt: Double = 0
    @AppStorage(AutoBackupFrequency.lastKey) private var lastAutomaticAt: Double = 0

    /// No backup of any kind for two weeks while there are notes.
    private var backupIsOverdue: Bool {
        !store.notes.isEmpty && Date().timeIntervalSince1970 - max(lastBackupAt, lastAutomaticAt) > 14 * 86_400
    }

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
                Label("Study with AI", systemImage: "graduationcap")
                    .tag(LibraryScope.study)
                Button {
                    showsRecentlyDeleted = true
                } label: {
                    HStack {
                        Label("Recently Deleted", systemImage: "trash")
                        Spacer()
                        if !store.trashedNotes.isEmpty {
                            Text("\(store.trashedNotes.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Workspace") {
                Label("Reminders", systemImage: "list.bullet.circle")
                    .tag(LibraryScope.reminders)
                Label("Planner", systemImage: "checklist")
                    .tag(LibraryScope.planner)
                Label("Expenses", systemImage: "creditcard")
                    .tag(LibraryScope.expenses)
                Label("Mind Maps", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(LibraryScope.mindMaps)
                Label("Slides", systemImage: "rectangle.on.rectangle.angled")
                    .tag(LibraryScope.slides)
                Label("PDF Tools", systemImage: "doc.on.doc")
                    .tag(LibraryScope.pdfTools)
                Label("Knowledge GPS", systemImage: "location.north.circle")
                    .tag(LibraryScope.gps)
                HStack {
                    Label("Flowmodoro", systemImage: "timer")
                    Spacer()
                    if workspace.flowTimer?.phase == .working {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Work session running")
                    }
                }
                .tag(LibraryScope.flowmodoro)
                Button {
                    CommandCenter.shared.sheet = .distractions
                } label: {
                    HStack {
                        Label("Distraction Box", systemImage: "tray.full")
                        Spacer()
                        let waiting = workspace.distractions.filter { !$0.isDone }.count
                        if waiting > 0 {
                            Text("\(waiting)").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        }
                    }
                }
                .foregroundStyle(Color(uiColor: .label))
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
        .themedBackground(sidebar: true)
        .navigationTitle("InkPad")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsBackup = true
                } label: {
                    Label("Backup", systemImage: backupIsOverdue ? "externaldrive.badge.exclamationmark" : "externaldrive.badge.icloud")
                        .foregroundStyle(backupIsOverdue ? Color.orange : Color.inkAccent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsThemes = true
                } label: {
                    Label("Themes", systemImage: "paintbrush")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                AppearanceMenu()
            }
            ToolbarItem(placement: .topBarTrailing) {
                LanguageButton()
            }
        }
        .sheet(isPresented: $showsBackup) {
            BackupView()
        }
        .sheet(isPresented: $showsThemes, onDismiss: {
            if let themeToApply {
                self.themeToApply = nil
                DispatchQueue.main.async { ThemeSettings.shared.apply(themeToApply) }
            }
        }) {
            ThemeView { themeToApply = $0 }
        }
        .sheet(isPresented: $showsRecentlyDeleted) {
            RecentlyDeletedView()
        }
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
                Text(tr(folder.name))
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(folder.color.tint)
            }
            if folder.aiAccess != .allowed {
                Spacer()
                AIAccessBadge(access: folder.aiAccess)
                    .font(.caption)
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
                        Label { Text(tr(color.title)) } icon: { color.menuDot(selected: folder.color == color) }
                    }
                }
            } label: {
                Label("Color", systemImage: "paintpalette")
            }
            AIAccessMenu(
                current: folder.aiAccess,
                inherited: store.folderAIAccess(folder.parentID)
            ) { store.setAIAccess($0, forFolder: folder.id) }
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
