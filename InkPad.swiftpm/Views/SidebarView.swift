import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var scope: LibraryScope?
    @State private var prompt: NamePrompt?
    @State private var folderToDelete: Folder?

    var body: some View {
        List(selection: $scope) {
            Section("Library") {
                Label("All Notes", systemImage: "tray.full")
                    .tag(LibraryScope.allNotes)
                Label("Unfiled", systemImage: "tray")
                    .tag(LibraryScope.unfiled)
            }

            Section("Folders") {
                ForEach(store.folders) { folder in
                    Label(folder.name, systemImage: "folder")
                        .tag(LibraryScope.folder(folder.id))
                        .contextMenu {
                            Button {
                                prompt = NamePrompt(
                                    title: "Rename Folder",
                                    initialText: folder.name,
                                    confirmTitle: "Rename"
                                ) { store.renameFolder(folder.id, to: $0) }
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                folderToDelete = folder
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("InkPad")
        .toolbar {
            Button {
                prompt = NamePrompt(
                    title: "New Folder",
                    initialText: "",
                    confirmTitle: "Create"
                ) { name in
                    if let folder = store.createFolder(named: name) {
                        scope = .folder(folder.id)
                    }
                }
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
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
                    scope = .allNotes
                }
                store.deleteFolder(folder.id)
            }
        } message: { _ in
            Text("Notes in this folder will move to Unfiled.")
        }
    }
}
