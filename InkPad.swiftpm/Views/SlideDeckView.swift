import SwiftUI

/// A slide deck: its slides down the side, the chosen slide large with its
/// words to edit, and Present, theme and export in the toolbar.
struct SlideDeckView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var store: LibraryStore
    let deckID: UUID

    @State private var deck: SlideDeck?
    @State private var images: [String: UIImage] = [:]
    @State private var selection: UUID?
    @State private var isDirty = false
    @State private var saveTask: Task<Void, Never>?
    @State private var isPresenting = false
    @State private var exportedFile: ExportedFile?
    @State private var prompt: NamePrompt?
    @State private var message: String?

    var body: some View {
        Group {
            if let deck {
                editor(deck)
            } else {
                ContentUnavailableView("Slide Deck Not Found", systemImage: "rectangle.on.rectangle.slash")
            }
        }
        .navigationTitle(deck?.title ?? "Slides")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onAppear(perform: load)
        .onDisappear { saveNow() }
        .fullScreenCover(isPresented: $isPresenting) {
            if let deck {
                SlidePresenter(deck: deck, images: images, startIndex: selectedIndex ?? 0)
            }
        }
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: file.urls)
        }
        .namePrompt($prompt)
        .alert(
            "Slides",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var selectedIndex: Int? {
        deck?.slides.firstIndex { $0.id == selection }
    }

    // MARK: Layout

    private func editor(_ deck: SlideDeck) -> some View {
        HStack(spacing: 0) {
            slideList(deck)
                .frame(width: 230)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let index = selectedIndex, let slide = binding(for: deck.slides[index].id) {
                        SlideView(
                            slide: deck.slides[index],
                            theme: deck.theme,
                            image: image(for: deck.slides[index]),
                            number: index + 1,
                            total: deck.slides.count
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                        SlideFields(slide: slide)
                    }
                }
                .padding(24)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private func slideList(_ deck: SlideDeck) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(Array(deck.slides.enumerated()), id: \.element.id) { item in
                    let isSelected = item.element.id == selection
                    Button {
                        selection = item.element.id
                    } label: {
                        VStack(spacing: 4) {
                            SlideView(
                                slide: item.element,
                                theme: deck.theme,
                                image: image(for: item.element),
                                number: item.offset + 1,
                                total: deck.slides.count
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 3 : 1)
                            )
                            Text("\(item.offset + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { slideMenu(item.element.id) }
                }
                Button {
                    addSlide()
                } label: {
                    Label("Add Slide", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func slideMenu(_ id: UUID) -> some View {
        Button {
            duplicateSlide(id)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button {
            moveSlide(id, by: -1)
        } label: {
            Label("Move Up", systemImage: "arrow.up")
        }
        Button {
            moveSlide(id, by: 1)
        } label: {
            Label("Move Down", systemImage: "arrow.down")
        }
        Button(role: .destructive) {
            deleteSlide(id)
        } label: {
            Label("Delete Slide", systemImage: "trash")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                ForEach(SlideTheme.allCases) { theme in
                    Button {
                        updateDeck { $0.theme = theme }
                    } label: {
                        Label(theme.title, systemImage: deck?.theme == theme ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            Menu {
                Section("Export") {
                    ForEach(ExportKind.allCases) { kind in
                        Button {
                            export(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                }
                .disabled(deck?.slides.isEmpty ?? true)
                Section {
                    Button {
                        saveAsNote()
                    } label: {
                        Label("Save as Note to Write On", systemImage: "pencil.and.outline")
                    }
                    Button {
                        saveOutlineAsNote()
                    } label: {
                        Label("Save Outline as Text Note", systemImage: "doc.text")
                    }
                }
                Button {
                    prompt = NamePrompt(title: "Rename Slide Deck", initialText: deck?.title ?? "", confirmTitle: "Rename") { name in
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        updateDeck { $0.title = trimmed }
                    }
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                saveNow()
                isPresenting = true
            } label: {
                Label("Present", systemImage: "play.rectangle.fill")
            }
            .disabled(deck?.slides.isEmpty ?? true)
        }
    }

    // MARK: Editing

    private func load() {
        guard deck == nil, let stored = workspace.decks.first(where: { $0.id == deckID }) else { return }
        deck = stored
        selection = stored.slides.first?.id
        images = SlideImages.load(for: stored, from: workspace.deckDirectory(stored.id))
    }

    private func image(for slide: Slide) -> UIImage? {
        slide.imageFile.flatMap { images[$0] }
    }

    private func binding(for id: UUID) -> Binding<Slide>? {
        guard let slide = deck?.slides.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { deck?.slides.first(where: { $0.id == id }) ?? slide },
            set: { newValue in
                updateDeck { deck in
                    if let index = deck.slides.firstIndex(where: { $0.id == id }) {
                        deck.slides[index] = newValue
                    }
                }
            }
        )
    }

    private func updateDeck(_ change: (inout SlideDeck) -> Void) {
        guard var edited = deck else { return }
        change(&edited)
        deck = edited
        isDirty = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        guard isDirty, let deck else { return }
        workspace.save(deck)
        isDirty = false
    }

    private func addSlide() {
        let slide = Slide(layout: .bullets, title: "New Slide", bullets: ["Your point"], symbol: "sparkles")
        updateDeck { deck in
            let index = deck.slides.firstIndex(where: { $0.id == selection }).map { $0 + 1 } ?? deck.slides.count
            deck.slides.insert(slide, at: min(index, deck.slides.count))
        }
        selection = slide.id
    }

    private func duplicateSlide(_ id: UUID) {
        guard let index = deck?.slides.firstIndex(where: { $0.id == id }), let original = deck?.slides[index] else { return }
        let copy = original.duplicated()
        updateDeck { $0.slides.insert(copy, at: index + 1) }
        selection = copy.id
    }

    private func moveSlide(_ id: UUID, by offset: Int) {
        updateDeck { deck in
            guard let index = deck.slides.firstIndex(where: { $0.id == id }) else { return }
            let target = index + offset
            guard deck.slides.indices.contains(target) else { return }
            deck.slides.swapAt(index, target)
        }
    }

    private func deleteSlide(_ id: UUID) {
        guard let index = deck?.slides.firstIndex(where: { $0.id == id }) else { return }
        updateDeck { $0.slides.remove(at: index) }
        if selection == id, let slides = deck?.slides, !slides.isEmpty {
            selection = slides[min(index, slides.count - 1)].id
        }
    }

    // MARK: Sharing

    private enum ExportKind: CaseIterable, Identifiable {
        case powerPoint, pdf, pictures, outline

        var id: Self { self }

        var title: String {
            switch self {
            case .powerPoint: "PowerPoint (.pptx)"
            case .pdf: "PDF"
            case .pictures: "Pictures (PNG)"
            case .outline: "Outline (Markdown)"
            }
        }

        var symbol: String {
            switch self {
            case .powerPoint: "rectangle.on.rectangle.angled"
            case .pdf: "doc.richtext"
            case .pictures: "photo.on.rectangle"
            case .outline: "list.bullet.rectangle"
            }
        }
    }

    private func export(_ kind: ExportKind) {
        guard let deck else { return }
        saveNow()
        do {
            switch kind {
            case .powerPoint:
                exportedFile = ExportedFile(url: try PPTXExporter.export(deck, images: images))
            case .pdf:
                exportedFile = ExportedFile(url: try SlideExporter.pdf(for: deck, images: images))
            case .pictures:
                exportedFile = ExportedFile(urls: try SlideExporter.pictures(for: deck, images: images))
            case .outline:
                exportedFile = ExportedFile(url: try SlideExporter.outline(for: deck))
            }
        } catch {
            message = "Could not export the slides: \(error.localizedDescription)"
        }
    }

    /// Adds the deck's words to the library as a text note.
    private func saveOutlineAsNote() {
        guard let deck else { return }
        saveNow()
        guard let note = store.createTextNote(titled: deck.title, in: nil) else { return }
        store.saveMarkdown(SlideExporter.outlineText(for: deck), for: note.id)
        message = "\"\(note.title)\" is now in All Notes as a text note."
    }

    /// Adds the slides to the library as a PDF note, to write on with Apple Pencil.
    private func saveAsNote() {
        guard let deck else { return }
        saveNow()
        do {
            let url = try SlideExporter.pdf(for: deck, images: images)
            if let note = store.importPDF(from: url, into: nil) {
                message = "\"\(note.title)\" is now in All Notes. Open it to write on your slides."
            }
        } catch {
            message = "Could not save the slides as a note: \(error.localizedDescription)"
        }
    }
}

/// The words of one slide, to edit.
private struct SlideFields: View {
    enum Field: Hashable {
        case title, subtitle, bullets, notes
    }

    @Binding var slide: Slide
    @FocusState private var focus: Field?
    @State private var lastFocus: Field = .title
    @State private var keyboardHelp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Layout", selection: $slide.layout) {
                    ForEach(Slide.Layout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                Button {
                    showKeyboard()
                } label: {
                    Label("Show Keyboard", systemImage: "keyboard")
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("After tapping a field with Apple Pencil, iPadOS hides the keyboard. This brings it up.")
            }

            field(slide.layout == .quote ? "Quote" : "Title") {
                TextField("Title", text: $slide.title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .focused($focus, equals: .title)
            }
            if slide.layout == .title || slide.layout == .quote {
                field(slide.layout == .quote ? "Who Said It" : "Subtitle") {
                    TextField("Subtitle", text: $slide.subtitle, axis: .vertical)
                        .focused($focus, equals: .subtitle)
                }
            }
            if slide.layout != .title && slide.layout != .quote {
                field("Points, One per Line") {
                    TextEditor(text: bulletsText)
                        .focused($focus, equals: .bullets)
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                }
            }
            field("Speaker Notes (Read Aloud When Narrating)") {
                TextEditor(text: $slide.speakerNotes)
                    .focused($focus, equals: .notes)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
            }
        }
        .onChange(of: focus) {
            if let focus { lastFocus = focus }
        }
        .alert(
            "Keyboard",
            isPresented: Binding(get: { keyboardHelp != nil }, set: { if !$0 { keyboardHelp = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(keyboardHelp ?? "")
        }
    }

    /// Edits the field again, which shows the keyboard when this button was
    /// tapped with a finger.
    private func showKeyboard() {
        if TextInputMode.current == .pencil {
            TextInputMode.set(.keyboard)
        }
        let field = focus ?? lastFocus
        focus = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focus = field }
        KeyboardHelp.checkAfterShowing { keyboardHelp = $0 }
    }

    /// Blank lines stay while typing; slides skip them.
    private var bulletsText: Binding<String> {
        Binding(
            get: { slide.bullets.joined(separator: "\n") },
            set: { slide.bullets = $0.components(separatedBy: "\n") }
        )
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(10)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
