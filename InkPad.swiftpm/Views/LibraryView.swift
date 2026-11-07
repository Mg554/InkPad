import SwiftUI

/// Root view: folders in the sidebar, notes in the detail column, and the
/// editor pushed on top of the notes grid.
struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var scope: LibraryScope? = .allNotes
    /// The section the detail column shows. It follows `scope` one step
    /// behind: see `switchSection`.
    @State private var shownScope: LibraryScope? = .allNotes
    /// True for the moment between taking one section's navigation stack
    /// down and putting the next one up.
    @State private var isSwitchingSection = false
    @State private var path: [UUID] = []
    /// A note to open once the section switch in progress has finished.
    @State private var noteAfterSwitch: UUID?
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
        case .planner?, .expenses?, .mindMaps?, .slides?, .study?, .flowmodoro?, .reminders?:
            // Changing the scope clears the path; the note opens once the
            // notes section is up (see `switchSection`).
            noteAfterSwitch = id
            scope = .allNotes
        default:
            path.append(id)
        }
    }

    /// Which kind of page a scope shows; each has its own navigation stack.
    private func section(of scope: LibraryScope?) -> String {
        switch scope {
        case .planner: "planner"
        case .expenses: "expenses"
        case .mindMaps: "mindMaps"
        case .slides: "slides"
        case .study: "study"
        case .flowmodoro: "flowmodoro"
        case .reminders: "reminders"
        default: "notes"
        }
    }

    /// The page for `shownScope`.
    @ViewBuilder private var detail: some View {
        switch shownScope {
        case .planner:
            NavigationStack { PlannerView() }
        case .expenses:
            NavigationStack { ExpensesView() }
        case .mindMaps:
            MindMapsView()
        case .slides:
            SlideDecksView()
        case .study:
            StudyView()
        case .flowmodoro:
            NavigationStack { FlowmodoroView() }
        case .reminders:
            NavigationStack { RemindersView() }
        default:
            NavigationStack(path: $path) {
                Group {
                    if shownScope == .graph {
                        GraphView()
                    } else {
                        NotesGridView(scope: shownScope ?? .allNotes) { path.append($0) }
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

    /// Changes section in two steps. SwiftUI keeps one navigation state for
    /// the detail column and crashes (`comparisonTypeMismatch`) when a stack
    /// whose path holds one type replaces a stack holding another type while
    /// a page is open, for example opening Study with AI from the sidebar
    /// while a note is open. So the open note is closed and the old stack is
    /// taken down first; the new section's stack comes up on the next update.
    private func switchSection() {
        path = []
        guard section(of: scope) != section(of: shownScope) else {
            shownScope = scope
            openNoteAfterSwitch()
            return
        }
        isSwitchingSection = true
        DispatchQueue.main.async {
            shownScope = scope
            isSwitchingSection = false
            DispatchQueue.main.async { openNoteAfterSwitch() }
        }
    }

    private func openNoteAfterSwitch() {
        guard let id = noteAfterSwitch else { return }
        noteAfterSwitch = nil
        path = [id]
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(scope: $scope)
        } detail: {
            // Each section gets its own identity, so SwiftUI builds its
            // navigation stack afresh instead of reusing another section's
            // (their paths hold different types, which crashes). Between two
            // sections an empty view stands in for one update.
            Group {
                if isSwitchingSection {
                    Color.clear
                } else {
                    detail
                }
            }
            .id(isSwitchingSection ? "switching" : section(of: shownScope))
        }
        .environment(\.noteNavigation, navigation)
        .onChange(of: scope) {
            switchSection()
        }
        .onChange(of: store.libraryGeneration) {
            // A restored backup replaced the library: close what was open.
            path = []
            scope = .allNotes
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
