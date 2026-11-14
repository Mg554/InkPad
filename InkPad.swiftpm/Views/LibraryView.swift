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
    @ObservedObject private var commands = CommandCenter.shared
    @ObservedObject private var focusSession = FocusSession.shared

    /// A note's focus session ended: its wrap-up (the Focus screen shows its own).
    private var noteWrapUp: FocusSummary? {
        // The Focus screen shows its own wrap-up while it is open.
        guard let summary = focusSession.summary else { return nil }
        if summary.noteID == nil, CommandCenter.shared.showsFocusScreen { return nil }
        return summary
    }
    @State private var themeToApply: ThemeRecipe?

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
            openTag: { tag in scope = .tag(tag) },
            openConcept: { CommandCenter.shared.sheet = .concept($0) }
        )
    }

    /// Opens a note from anywhere, leaving workspace pages for the notes area.
    private func open(_ id: UUID) {
        // Locked notes open only after Face ID (or the passcode).
        guard store.isUnlocked(id) else {
            unlockThenOpen(id)
            return
        }
        switch scope {
        case .planner?, .expenses?, .mindMaps?, .slides?, .study?, .flowmodoro?, .reminders?, .pdfTools?, .gps?:
            // Changing the scope clears the path; the note opens once the
            // notes section is up (see `switchSection`).
            noteAfterSwitch = id
            scope = .allNotes
        default:
            path.append(id)
        }
    }

    /// Asks for Face ID first; the note opens only on success.
    private func unlockThenOpen(_ id: UUID) {
        let title = store.note(id)?.title ?? ""
        Task {
            let outcome = await NoteLock.authenticate(
                reason: trMessage("Unlock \(title).")
            )
            switch outcome {
            case .unlocked:
                store.unlockNote(id)
                open(id)
            case .failed:
                CommandCenter.shared.say("Locked notes open with Face ID or the passcode.")
            case .needsPasscode:
                CommandCenter.shared.say("Set a passcode on this iPad — locked notes open with Face ID or the passcode.")
            }
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
        case .pdfTools: "pdfTools"
        case .gps: "gps"
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
        case .pdfTools:
            NavigationStack { PDFToolsView() }
        case .gps:
            NavigationStack { KnowledgeMapsView() }
        default:
            NavigationStack(path: $path) {
                Group {
                    if shownScope == .graph {
                        GraphView()
                    } else {
                        NotesGridView(scope: shownScope ?? .allNotes) { open($0) }
                    }
                }
                .navigationDestination(for: UUID.self) { noteID in
                    NoteLockGate(noteID: noteID) {
                        if store.note(noteID)?.isText == true {
                            MarkdownNoteView(noteID: noteID)
                        } else {
                            NoteEditorView(noteID: noteID)
                        }
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

    // The body is split into parts, each type-checked on its own: one long
    // modifier chain is too slow for Swift Playgrounds on the iPad.
    var body: some View {
        withLiving
            .onChange(of: scope) {
                switchSection()
            }
            .onChange(of: store.libraryGeneration) {
                // A restored backup replaced the library: close what was open.
                path = []
                scope = .allNotes
            }
            .onChange(of: store.lockRevision) {
                // A locked note cannot stay open on screen.
                path.removeAll { !store.isUnlocked($0) }
            }
            .onChange(of: path) {
                // Give the editor the whole screen; bring the sidebar back in the library.
                columnVisibility = path.isEmpty ? .automatic : .detailOnly
            }
            .alert("InkPad", isPresented: storeErrorShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .alert("InkPad", isPresented: workspaceErrorShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(workspace.errorMessage ?? "")
            }
    }

    private var storeErrorShown: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }

    private var workspaceErrorShown: Binding<Bool> {
        Binding(get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(scope: $scope)
        } detail: {
            // Each section gets its own identity, so SwiftUI builds its
            // navigation stack afresh instead of reusing another section's
            // (their paths hold different types, which crashes). Between two
            // sections an empty view stands in for one update.
            detailColumn
        }
        .environment(\.noteNavigation, navigation)
    }

    private var detailColumn: some View {
        let identity: String = isSwitchingSection ? "switching" : section(of: shownScope)
        return Group {
            if isSwitchingSection {
                Color.clear
            } else {
                detail
            }
        }
        .id(identity)
    }

    /// Command Anywhere: ⌘K, the floating button, three fingers down.
    private var withCommands: some View {
        splitView
            .background {
                ThreeFingerSwipe()
                CommandShortcuts()
            }
            .overlay { FloatingCommandButton().opacity(commands.isPresented ? 0 : 1) }
            .overlay(alignment: .bottom) { CommandToast() }
            .overlay {
                if commands.isPresented {
                    CommandPalette()
                }
            }
            .onAppear {
                commands.navigate = { scope = $0 }
                commands.openNote = { navigation.openNote($0) }
            }
            .sheet(item: $commands.sheet, onDismiss: applyPendingTheme) { sheet in
                commandSheet(sheet)
            }
    }

    private func applyPendingTheme() {
        if let themeToApply {
            self.themeToApply = nil
            DispatchQueue.main.async { ThemeSettings.shared.apply(themeToApply) }
        }
    }

    @ViewBuilder
    private func commandSheet(_ sheet: CommandSheet) -> some View {
        switch sheet {
        case .themes:
            ThemeView { themeToApply = $0 }
        case let .history(note):
            NoteHistoryView(note: note)
        case let .reminder(draft):
            ReminderEditor(draft: draft)
        case let .concept(key):
            ConceptCardView(key: key)
        case .distractions:
            DistractionBoxView()
        case .catchDistraction:
            DistractionCapture()
        case .garden:
            FocusGardenView()
        }
    }

    private func syncOpenTaskNotes() {
        let ids: Set<UUID> = Set(workspace.tasks.filter { $0.status != .done }.compactMap(\.noteID))
        if store.openTaskNotes != ids { store.openTaskNotes = ids }
    }

    /// Notes with unfinished Planner tasks, for the Unfinished Tasks collection.
    private var withTaskSync: some View {
        withCommands
            .task { syncOpenTaskNotes() }
            .onChange(of: workspace.tasks) { syncOpenTaskNotes() }
            .modifier(FocusExtras())
    }

    /// Living Notes keeps its index of concepts up to date.
    private var withLiving: some View {
        withTaskSync
            .task { LivingNotes.shared.refresh(store: store) }
            .onChange(of: store.notes) { LivingNotes.shared.refresh(store: store) }
            .onChange(of: store.textIndex) { LivingNotes.shared.refresh(store: store) }
            .onChange(of: store.recognizedText) { LivingNotes.shared.refresh(store: store) }
            .sheet(item: wrapUpBinding) { summary in
                FocusWrapUpView(summary: summary)
                    .environmentObject(store)
                    .environmentObject(workspace)
            }
            .overlay(alignment: .bottom) {
                if focusSession.openEditors == 0, !focusSession.isActive {
                    OrganizeBanner()
                        .padding(.horizontal, 20)
                }
            }
            .animation(.snappy, value: OrganizeAdvisor.shared.pending)
            .overlay(alignment: .bottom) {
                if focusSession.isActive, focusSession.openEditors == 0, !CommandCenter.shared.showsFocusScreen {
                    FocusPill()
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: showsFocusScreen) {
                FocusScreenView()
                    .environmentObject(store)
                    .environmentObject(workspace)
            }
    }

    private var wrapUpBinding: Binding<FocusSummary?> {
        Binding(
            get: { noteWrapUp },
            set: { if $0 == nil { FocusSession.shared.summary = nil } }
        )
    }

    private var showsFocusScreen: Binding<Bool> {
        Binding(
            get: { CommandCenter.shared.showsFocusScreen },
            set: { CommandCenter.shared.showsFocusScreen = $0 }
        )
    }
}

/// The catch bubble while focusing, and the plant that grew after a session.
private struct FocusExtras: ViewModifier {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var gardenToast = GardenToastCenter.shared
    @ObservedObject private var commands = CommandCenter.shared
    @AppStorage(DistractionPrefs.bubble) private var catchBubble = true

    private var showsBubble: Bool {
        catchBubble && workspace.flowTimer?.phase == .working && !commands.showsFocusScreen
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if showsBubble {
                    FloatingCatchBubble()
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let toast = gardenToast.toast {
                    GardenGrowthToast(toast: toast)
                        .padding(.top, 70)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // Ambient sound follows the Flowmodoro timer, wherever you are in InkPad.
            .task {
                FocusSoundController.workspace = workspace
                FocusSoundController.update()
            }
            .onChange(of: workspace.flowTimer?.phase) { before, after in
                FocusSoundController.update()
                FocusSession.shared.timerChanged(workspace)
                if before == .working, after == .breakReady { GardenToastCenter.shared.sessionEnded(workspace) }
            }
            .onChange(of: workspace.flowTimer?.taskID) { FocusSession.shared.timerChanged(workspace) }
    }
}
