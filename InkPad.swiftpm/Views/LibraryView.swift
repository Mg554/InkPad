import SwiftUI

/// Root view: folders in the sidebar, notes in the detail column, and the
/// editor pushed on top of the notes grid.
struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var scope: LibraryScope? = .allNotes
    @State private var path: [UUID] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(scope: $scope)
        } detail: {
            NavigationStack(path: $path) {
                NotesGridView(scope: scope ?? .allNotes) { path.append($0) }
                    .navigationDestination(for: UUID.self) { noteID in
                        NoteEditorView(noteID: noteID)
                    }
            }
        }
        .onChange(of: scope) {
            path = []
        }
        .onChange(of: path) {
            // Give the editor the whole screen; bring the sidebar back in the library.
            columnVisibility = path.isEmpty ? .automatic : .detailOnly
        }
        .alert(
            "InkPad",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
