import PencilKit
import SwiftUI

/// The command palette: a glass panel in the middle of the screen. Type,
/// write with the Pencil or speak a command, a search, or where to go.
struct CommandPalette: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var center = CommandCenter.shared
    @ObservedObject private var ai = AISettings.shared
    @StateObject private var voice = VoiceCommandListener()
    @AppStorage("voiceCommandLanguage") private var language = VoiceCommandListener.Language.preferred

    @State private var query = ""
    @State private var selection = 0
    @State private var isWriting = false
    @State private var ink = PKDrawing()
    @State private var inkTask: Task<Void, Never>?
    @State private var aiItems: [PaletteItem] = []
    @State private var isAsking = false
    @State private var aiProblem: String?
    @FocusState private var isFocused: Bool

    /// Plain gray: the material's vibrant .secondary is too faint here.
    private static let faint = Color(uiColor: .secondaryLabel)

    private var catalog: CommandCatalog {
        CommandCatalog(store: store, workspace: workspace, center: center) { text in
            query = text
            isFocused = true
        }
    }

    var body: some View {
        let items = catalog.items(for: query, aiItems: aiItems + askAIItem)
        ZStack(alignment: .top) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                field(items)
                if isWriting { writingPad }
                if voice.isListening || voice.problem != nil || aiProblem != nil { status }
                Divider().opacity(0.5)
                results(items)
                footer
            }
            .frame(maxWidth: 660)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.6), Color.inkAccent.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: Color.inkAccent.opacity(0.25), radius: 30)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
            .padding(.horizontal, 20)
            .padding(.top, 70)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .onAppear {
            query = center.prefill
            selection = 0
            // Once the panel is on screen, or the field can't take focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isFocused = true }
        }
        .onChange(of: center.prefill) { query = center.prefill }
        .onChange(of: query) {
            selection = 0
            aiItems = []
            aiProblem = nil
        }
        .onDisappear {
            voice.stop()
            inkTask?.cancel()
        }
    }

    // MARK: Pieces

    private func field(_ items: [PaletteItem]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "command")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.inkAccent)
            TextField("Type a command, a search, or where to go… · اكتب أمراً", text: $query)
                .font(.title3)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .submitLabel(.go)
                .onSubmit { runSelected(items) }
                .onKeyPress(.downArrow) {
                    selection = min(selection + 1, max(items.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selection = max(selection - 1, 0)
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    ink = PKDrawing()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Self.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
            Button {
                withAnimation(.snappy) { isWriting.toggle() }
                if isWriting { voice.stop() }
            } label: {
                Image(systemName: "applepencil.tip")
                    .font(.title3)
                    .foregroundStyle(isWriting ? Color.inkAccent : Self.faint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Write with Apple Pencil")
            Menu {
                Picker("Language", selection: $language) {
                    ForEach(VoiceCommandListener.Language.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Image(systemName: voice.isListening ? "waveform.circle.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(voice.isListening ? Color.red : Self.faint)
                    .symbolEffect(.pulse, isActive: voice.isListening)
            } primaryAction: {
                if voice.isListening {
                    voice.stop()
                } else {
                    isWriting = false
                    voice.start(language: language) { spoken in query = spoken }
                }
            }
            .accessibilityLabel("Speak a Command")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var writingPad: some View {
        ZStack(alignment: .topTrailing) {
            InkCanvas(drawing: $ink, showsToolPicker: false)
                .frame(height: 110)
                .background(Color(uiColor: .systemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .bottomLeading) {
                    if ink.strokes.isEmpty {
                        Text("Write your command here")
                            .font(.callout)
                            .foregroundStyle(Self.faint)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
            Button("Clear") {
                ink = PKDrawing()
                query = ""
            }
            .font(.caption.weight(.semibold))
            .padding(8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onChange(of: ink) {
            // Read the writing once the pencil rests.
            inkTask?.cancel()
            let drawing = ink
            inkTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, !drawing.strokes.isEmpty else { return }
                let text = await Task.detached { MindSketchReader.readText(drawing) }.value
                if !Task.isCancelled, !text.isEmpty { query = text }
            }
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            if voice.isListening {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: true)
                    .foregroundStyle(.red)
                Text(voice.text.isEmpty ? "Listening… (\(language.title))" : voice.text)
            } else if let problem = voice.problem ?? aiProblem {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(problem)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func results(_ items: [PaletteItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                    if items.isEmpty {
                        Text(query.isEmpty ? "" : "Nothing found for \"\(query)\".")
                            .foregroundStyle(Self.faint)
                            .padding(18)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index == 0 || items[index - 1].section != item.section {
                            Text(index == 0 && query.isEmpty && item.subtitle == "Recent" ? "Recent" : item.section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Self.faint)
                                .textCase(.uppercase)
                                .padding(.horizontal, 18)
                                .padding(.top, index == 0 ? 8 : 14)
                                .padding(.bottom, 4)
                        }
                        row(item, isSelected: index == selection)
                            .id(item.id)
                            .onTapGesture { center.run(item) }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 440)
            .onChange(of: selection) {
                if items.indices.contains(selection) {
                    withAnimation(.snappy) { proxy.scrollTo(items[selection].id, anchor: .center) }
                }
            }
        }
    }

    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(item.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                if let subtitle = item.subtitle, subtitle != "Recent" {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Self.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(Self.faint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Self.faint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.inkAccent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("move", systemImage: "arrow.up.arrow.down")
            Label("run", systemImage: "return")
            Label("close", systemImage: "escape")
            Spacer()
            Text("⌘K · three fingers down")
        }
        .font(.caption2)
        .foregroundStyle(Self.faint)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Self.faint.opacity(0.06))
    }

    // MARK: AI

    /// "Ask AI" when there's text and an AI is set up.
    private var askAIItem: [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, ai.problem == nil, aiItems.isEmpty else { return [] }
        return [PaletteItem(id: "ai-ask", title: isAsking ? "Asking \(ai.provider.title)…" : "Ask AI What “\(trimmed)” Means",
                            subtitle: "Only this sentence is sent to \(ai.provider.title), never your notes",
                            systemImage: "sparkles", tint: .indigo, section: .ai, closesPalette: false) { askAI(trimmed) }]
    }

    private func askAI(_ text: String) {
        guard !isAsking, let client = ai.client() else { return }
        isAsking = true
        aiProblem = nil
        Task {
            defer { isAsking = false }
            do {
                let answer = try await CommandAI.interpret(text, client: client)
                guard text == query.trimmingCharacters(in: .whitespaces) else { return }
                aiItems = [item(for: answer)]
            } catch {
                aiProblem = "AI couldn't read it: \(error.localizedDescription)"
            }
        }
    }

    private func item(for answer: CommandAI.Answer) -> PaletteItem {
        switch answer {
        case let .intent(intent):
            let look = CommandCenter.describe(intent, money: workspace.money)
            return PaletteItem(id: "ai-intent", title: look.title, subtitle: "From AI · " + look.subtitle, systemImage: look.systemImage,
                               tint: look.tint, shortcut: "↩", section: .suggested) { [store, workspace, center] in
                center.perform(intent, store: store, workspace: workspace)
            }
        case let .open(scope):
            return PaletteItem(id: "ai-open", title: "Open \(String(describing: scope).capitalized)", subtitle: "From AI",
                               systemImage: "arrow.right.circle", section: .suggested) { [center] in center.navigate(scope) }
        case let .search(text):
            return PaletteItem(id: "ai-search", title: "Search for “\(text)”", subtitle: "From AI", systemImage: "magnifyingglass",
                               section: .suggested, closesPalette: false) { query = text }
        }
    }

    // MARK: Actions

    private func runSelected(_ items: [PaletteItem]) {
        guard items.indices.contains(selection) else { return }
        center.run(items[selection])
    }

    private func close() {
        voice.stop()
        center.hide()
    }
}

/// Where the floating ⌘ button is, and whether it shows.
enum CommandButtonSettings {
    static let showsKey = "commandButtonShows"
    static let xKey = "commandButtonX"
    static let yKey = "commandButtonY"
}

/// A small floating ⌘ button that opens the palette; drag it anywhere.
/// Inside a note it keeps a place of its own, apart from the library's.
struct FloatingCommandButton: View {
    @AppStorage(CommandButtonSettings.showsKey) private var shows = true
    @ObservedObject private var center = CommandCenter.shared

    var body: some View {
        if shows {
            let inNote = center.noteCommands != nil
            FloatingPlacement(key: inNote ? "commandButton.note" : "commandButton.library", x: 0.96, y: inNote ? 0.78 : 0.82) {
                Image(systemName: "command")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.inkAccent.gradient, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: Color.inkAccent.opacity(0.5), radius: 10)
                    .opacity(0.9)
                    .contentShape(Circle())
                    .onTapGesture { CommandCenter.shared.show() }
                    .accessibilityLabel("Command Anywhere")
                    .accessibilityHint("Drag to move it")
                    .accessibilityAddTraits(.isButton)
            }
            .id(inNote)
        }
    }
}

/// Opens the palette with a three-finger swipe down anywhere in the window.
struct ThreeFingerSwipe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = WindowHook()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class WindowHook: UIView, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, window !== installedWindow else { return }
            installedWindow = window
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped))
            swipe.direction = .down
            swipe.numberOfTouchesRequired = 3
            swipe.cancelsTouchesInView = false
            swipe.delegate = self
            window.addGestureRecognizer(swipe)
        }

        @objc private func swiped() {
            Task { @MainActor in CommandCenter.shared.show() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Keyboard shortcuts for the palette and common commands.
struct CommandShortcuts: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var center = CommandCenter.shared
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            shortcut("Command Anywhere", "k") { center.toggle() }
            shortcut("New Note", "n") { center.perform(.note(title: ""), store: store, workspace: workspace) }
            shortcut("New Text Note", "n", [.command, .shift]) { center.perform(.textNote(title: ""), store: store, workspace: workspace) }
            shortcut("New Reminder", "r", [.command, .shift]) { center.show(prefill: "remind me ") }
            shortcut("New Task", "t", [.command, .shift]) { center.show(prefill: "task ") }
            shortcut("New Expense", "e", [.command, .shift]) { center.show(prefill: "spent ") }
            shortcut("New Mind Map", "m", [.command, .shift]) { center.show(prefill: "mind map ") }
            shortcut("Back Up Now", "b", [.command, .shift]) {
                Task {
                    let done = await store.makeAutomaticBackupIfDue(force: true)
                    center.say(done ? "Backed up to InkPad Automatic Backups" : "The backup couldn't be made")
                }
            }
            shortcut("Dark Mode", "d", [.command, .shift]) {
                appearance = colorScheme == .dark ? .light : .dark
            }
            ForEach(Array(Self.sections.enumerated()), id: \.offset) { index, section in
                shortcut(section.0, KeyEquivalent(Character(String(index + 1)))) { center.navigate(section.1) }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private static let sections: [(String, LibraryScope)] = [
        ("All Notes", .allNotes), ("Reminders", .reminders), ("Planner", .planner), ("Expenses", .expenses),
        ("Mind Maps", .mindMaps), ("Study with AI", .study), ("Graph", .graph), ("Flowmodoro", .flowmodoro),
    ]

    private func shortcut(_ title: String, _ key: KeyEquivalent, _ modifiers: EventModifiers = .command, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: modifiers)
    }
}

/// The confirmation shown after a command.
struct CommandToast: View {
    @ObservedObject private var center = CommandCenter.shared

    var body: some View {
        if let toast = center.toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.inkAccent.opacity(0.4)))
                .shadow(color: Color.inkAccent.opacity(0.3), radius: 12)
                .padding(.bottom, 30)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
