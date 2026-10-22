import SwiftUI

/// Root view: folders in the sidebar, notes in the detail column, and the
/// editor pushed on top of the notes grid.
struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var scope: LibraryScope? = .allNotes
    @State private var path: [UUID] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    private var navigation: NoteNavigation {
        NoteNavigation(
            openNote: { open($0) },
            openTitle: { title in
                if let note = store.note(titled: title) {
                    open(note.id)
                } else if let created = store.createTextNote(titled: title, in: nil) {
                    open(created.id)
                }
            },
            openTag: { tag in scope = .tag(tag) }
        )
    }

    /// Opens a note from anywhere, leaving workspace pages for the notes area.
    private func open(_ id: UUID) {
        switch scope {
        case .planner?, .expenses?, .mindMaps?, .slides?:
            scope = .allNotes
            // Changing the scope clears the path; push after that.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { path = [id] }
        default:
            path.append(id)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(scope: $scope)
        } detail: {
            switch scope {
            case .planner:
                NavigationStack { PlannerView() }
            case .expenses:
                NavigationStack { ExpensesView() }
            case .mindMaps:
                MindMapsView()
            case .slides:
                SlideDecksView()
            default:
                NavigationStack(path: $path) {
                    Group {
                        if scope == .graph {
                            GraphView()
                        } else {
                            NotesGridView(scope: scope ?? .allNotes) { path.append($0) }
                        }
                    }
                    .navigationDestination(for: UUID.self) { noteID in
                        if store.note(noteID)?.isText == true {
                            MarkdownNoteView(noteID: noteID)
                        } else {
                            NoteEditorView(noteID: noteID)
                        }
                    }
                }
            }
        }
        .environment(\.noteNavigation, navigation)
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
        .alert(
            "InkPad",
            isPresented: Binding(
                get: { workspace.errorMessage != nil },
                set: { if !$0 { workspace.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(workspace.errorMessage ?? "")
        }
    }
}
