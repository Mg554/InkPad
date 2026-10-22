import SwiftUI

/// Turns notes into a slide deck, like NotebookLM: reads them (recognizing
/// handwriting on the iPad), writes the slides with the connected AI
/// service, Apple Intelligence or the offline outliner, adds pictures of the
/// pages, and saves the deck.
@MainActor
final class DeckGenerator: ObservableObject {
    /// Who writes the slides.
    enum Writer: String, CaseIterable, Identifiable {
        /// The AI service chosen in AI Settings.
        case connected
        /// InkPad's own outliner, on the iPad without AI.
        case offline

        var id: Self { self }
    }

    struct Options {
        var format: DeckFormat = .presenter
        var length: DeckLength = .standard
        var theme: SlideTheme = .aurora
        var focus = ""
        var writer: Writer = .connected
        var includesPages = true
    }

    /// What it is doing; `nil` when idle.
    @Published private(set) var stage: String?
    /// Something to tell when done, e.g. why Apple Intelligence wasn't used.
    @Published var notice: String?

    static let maxPagesPerNote = 30
    static let maxPictures = 12

    private struct Picture {
        let noteTitle: String
        let page: Int
        let jpeg: Data
    }

    /// - Parameter liveContent: notes open in the editor, with ink not saved yet.
    func generate(
        sources: [UUID],
        options: Options,
        store: LibraryStore,
        workspace: WorkspaceStore,
        liveContent: [UUID: NoteContent]
    ) async -> SlideDeck? {
        guard stage == nil else { return nil }
        stage = "Reading your notes…"
        defer { stage = nil }

        var texts: [SlideSource] = []
        var pictures: [Picture] = []
        for id in sources {
            guard let summary = store.note(id) else { continue }
            if summary.isText {
                if let markdown = try? store.loadMarkdown(for: id) {
                    texts.append(SlideSource(title: summary.title, text: markdown, isMarkdown: true))
                }
                continue
            }
            guard let content = liveContent[id] ?? (try? store.loadContent(for: id)) else { continue }
            let background = content.makeBackground()
            let count = min(background.layout.pageRects.count, Self.maxPagesPerNote)
            var pageTexts: [String] = []
            for index in 0..<count {
                stage = "Reading \(summary.title): page \(index + 1) of \(count)…"
                let wantsImage = options.includesPages && pictures.count < Self.maxPictures
                let page = await Task.detached(priority: .userInitiated) {
                    NoteReader.read(page: index, of: content, background: background, wantsImage: wantsImage)
                }.value
                if !page.text.isEmpty { pageTexts.append(page.text) }
                if let jpeg = page.image {
                    pictures.append(Picture(noteTitle: summary.title, page: index + 1, jpeg: jpeg))
                }
            }
            let recognized = pageTexts.joined(separator: "\n\n")
            if count == background.layout.pageRects.count {
                store.saveRecognizedText(recognized, for: id)
            }
            texts.append(SlideSource(title: summary.title, text: recognized, isMarkdown: false))
        }

        let hasText = texts.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasText || !pictures.isEmpty else {
            notice = "There wasn't any writing in these notes to make slides from."
            return nil
        }

        // Write the slides.
        var outline: DeckOutline?
        var isAIWritten = false
        if hasText, options.writer == .connected, let client = AISettings.shared.client() {
            do {
                if client.kind == .apple {
                    outline = try await SlideWriterAI.outline(
                        texts,
                        format: options.format,
                        length: options.length,
                        focus: options.focus
                    ) { [weak self] message in
                        self?.stage = message
                    }
                } else {
                    stage = "\(client.kind.title) is writing your slides…"
                    let notes = NoteTexts.context(
                        texts.map { StudySource(id: UUID(), title: $0.title, text: $0.text) },
                        budget: client.kind.contextBudget
                    )
                    let reply = try await client.complete(
                        system: "You turn study notes into excellent, well structured presentation slides.",
                        messages: [AIMessage(.user, StudyAI.slidesPrompt(
                            notes: notes, format: options.format, length: options.length, focus: options.focus
                        ))]
                    )
                    outline = try StudyAI.outline(fromSlidesReply: reply, format: options.format)
                }
                isAIWritten = outline != nil
            } catch {
                notice = "The AI couldn't write these slides (\(error.localizedDescription)), so InkPad outlined them itself."
            }
        }
        if outline == nil {
            stage = "Outlining your notes…"
            let format = options.format
            let length = options.length
            let focus = options.focus
            let sourceTexts = texts
            outline = await Task.detached(priority: .userInitiated) {
                SlideOutliner.outline(sourceTexts, format: format, length: length, focus: focus)
            }.value
        }
        guard let outline else { return nil }

        // Assemble: title, overview, content, pages, takeaways.
        stage = "Designing your slides…"
        let words = DeckWords(for: texts.map { $0.text }.joined(separator: "\n"))
        let title = outline.title.isEmpty ? words.combinedTitle(sources.compactMap { store.note($0)?.title }) : outline.title
        let deckID = UUID()
        var slides: [Slide] = [Slide(
            layout: .title,
            title: title,
            subtitle: outline.subtitle.isEmpty ? words.subtitle(noteCount: sources.count) : outline.subtitle,
            speakerNotes: outline.subtitle,
            symbol: SlideSymbols.symbol(for: title + " " + outline.slides.map { $0.title }.joined(separator: " "))
        )]
        if outline.slides.count >= 3 {
            slides.append(Slide(
                layout: .agenda,
                title: words.overview,
                bullets: outline.slides.prefix(8).map { $0.title },
                speakerNotes: outline.slides.prefix(8).map { $0.title }.joined(separator: ". "),
                symbol: "list.bullet.rectangle"
            ))
        }
        slides += outline.slides
        for picture in pictures {
            guard let file = workspace.addDeckImage(picture.jpeg, to: deckID) else { continue }
            slides.append(Slide(
                layout: .image,
                title: words.page(picture.page, of: picture.noteTitle),
                symbol: "photo",
                imageFile: file
            ))
        }
        if !outline.takeaways.isEmpty {
            slides.append(Slide(
                layout: .summary,
                title: words.takeaways,
                bullets: Array(outline.takeaways.prefix(4)),
                speakerNotes: outline.takeaways.prefix(4).joined(separator: " "),
                symbol: "checkmark.seal.fill"
            ))
        }

        let now = Date()
        let deck = SlideDeck(
            id: deckID,
            title: title,
            slides: slides,
            theme: options.theme,
            format: options.format,
            sourceNoteIDs: sources,
            isAIWritten: isAIWritten,
            createdAt: now,
            modifiedAt: now
        )
        workspace.save(deck)
        return deck
    }
}
