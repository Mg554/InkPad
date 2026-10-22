import SwiftUI

/// "Create Slides", like NotebookLM's slide decks: choose the notes to draw
/// on, the kind of deck, its length, focus and look. InkPad writes the deck
/// on this iPad and opens it.
struct DeckGeneratorView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    /// Notes open in the editor, with ink not saved yet.
    let liveContent: [UUID: NoteContent]

    @StateObject private var generator = DeckGenerator()
    @State private var sources: [UUID]
    @State private var options = DeckGenerator.Options()
    @State private var isPickingNotes = false
    @State private var createdDeckID: UUID?
    @State private var isShowingAISettings = false
    @ObservedObject private var ai = AISettings.shared

    init(sources: [UUID], liveContent: [UUID: NoteContent] = [:]) {
        _sources = State(initialValue: sources)
        self.liveContent = liveContent
        var options = DeckGenerator.Options()
        options.writer = AISettings.shared.isReady ? .connected : .offline
        _options = State(initialValue: options)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let createdDeckID {
                    SlideDeckView(deckID: createdDeckID)
                } else {
                    form
                        .navigationTitle("Create Slides")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdDeckID == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(generator.stage != nil)
                }
            }
        }
        .overlay {
            if let stage = generator.stage {
                progressCard(stage)
            }
        }
        .sheet(isPresented: $isShowingAISettings) {
            AISettingsView()
        }
        .sheet(isPresented: $isPickingNotes) {
            NotePicker(selection: $sources)
                .environmentObject(store)
        }
        .alert(
            "Slides",
            isPresented: Binding(get: { generator.notice != nil }, set: { if !$0 { generator.notice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(generator.notice ?? "")
        }
    }

    private var form: some View {
        Form {
            Section {
                ForEach(sources, id: \.self) { id in
                    let note = store.note(id)
                    Label(note?.title ?? "Missing Note", systemImage: note?.isText == true ? "doc.text" : "pencil.and.scribble")
                }
                .onDelete { sources.remove(atOffsets: $0) }
                Button {
                    isPickingNotes = true
                } label: {
                    Label("Choose Notes…", systemImage: "plus.circle")
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Like NotebookLM, one deck can draw on several notes: handwritten, PDFs and text notes.")
            }

            Section {
                Picker("Format", selection: $options.format) {
                    ForEach(DeckFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                Text(options.format.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("Length", selection: $options.length) {
                    ForEach(DeckLength.allCases) { length in
                        Text(length.title).tag(length)
                    }
                }
            } header: {
                Text("Kind of Deck")
            }

            Section {
                TextField("For example: explain it for beginners, or focus on the formulas", text: $options.focus, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Focus (Optional)")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(SlideTheme.allCases) { theme in
                            themeSwatch(theme)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Toggle(isOn: $options.includesPages) {
                    Label("Add Pictures of Handwritten Pages", systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("Look")
            }

            Section {
                Picker("Written by", selection: $options.writer) {
                    Text(ai.isReady ? ai.provider.title : "AI (not set up)").tag(DeckGenerator.Writer.connected)
                    Text("InkPad, without AI").tag(DeckGenerator.Writer.offline)
                }
                if options.writer == .connected, let problem = ai.problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button {
                    isShowingAISettings = true
                } label: {
                    Label("AI Settings…", systemImage: "gearshape")
                }
            } header: {
                Text("Writing")
            } footer: {
                Text(ai.provider == .apple || options.writer == .offline
                    ? "Everything happens on this iPad: handwriting is read with on-device text recognition."
                    : "Handwriting is read on this iPad. The text of the chosen notes is sent to \(ai.provider.title) to write the slides.")
            }

            Section {
                Button {
                    generate()
                } label: {
                    Label("Create Slides", systemImage: "rectangle.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(sources.isEmpty || generator.stage != nil)
            }
        }
    }

    private func themeSwatch(_ theme: SlideTheme) -> some View {
        let isSelected = options.theme == theme
        return Button {
            options.theme = theme
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.background)
                    .frame(width: 104, height: 58)
                    .overlay(alignment: .bottomLeading) {
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: 34, height: 5)
                            .padding(10)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 3 : 1)
                    )
                Text(theme.title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title) Theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func progressCard(_ stage: String) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(stage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("This can take a minute for long or handwritten notes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func generate() {
        Task {
            let deck = await generator.generate(
                sources: sources,
                options: options,
                store: store,
                workspace: workspace,
                liveContent: liveContent
            )
            if let deck {
                createdDeckID = deck.id
            }
        }
    }
}

/// Picks notes to make slides from or to study.
struct NotePicker: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: [UUID]
    @State private var search = ""

    private var notes: [NoteSummary] {
        let all = store.notes(in: .allNotes)
        guard !search.isEmpty else { return all }
        return all.filter { store.matches($0, search: search) }
    }

    var body: some View {
        NavigationStack {
            List(notes) { note in
                Button {
                    if let index = selection.firstIndex(of: note.id) {
                        selection.remove(at: index)
                    } else {
                        selection.append(note.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: note.isText ? "doc.text" : "pencil.and.scribble")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(note.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(note.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search notes")
            .navigationTitle("Choose Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
