import PDFKit
import SwiftUI

/// Something the book panel opens over the note.
enum BookResult: Identifiable {
    case mindMap(UUID)
    case conceptGraph(title: String, graph: ChapterMaps.ConceptGraph, first: Int, last: Int)

    var id: String {
        switch self {
        case let .mindMap(id): "map-\(id)"
        case let .conceptGraph(title, _, first, _): "graph-\(title)-\(first)"
        }
    }
}

/// The side panel of a PDF book: its chapters (from the book's outline),
/// bookmarks and reading progress. Each chapter can become a mind map, a
/// concept graph or a note of its own.
struct BookPanel: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var ai = AISettings.shared
    @ObservedObject private var ocr = OCRCenter.shared
    @ObservedObject var session: EditorSession
    @ObservedObject var canvas: CanvasController
    let noteID: UUID
    let open: (BookResult) -> Void

    @State private var tab = 0
    @State private var chapters: [BookChapter] = []
    @State private var working: String?
    @State private var message: String?
    @State private var bookmarkPrompt: NamePrompt?
    @State private var rangeText = ""
    @State private var scanCount: Int?
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var isSearching = false

    struct SearchHit: Identifiable {
        let id = UUID()
        let page: Int
        let snippet: String
    }

    private var document: PDFDocument? { session.snapshot?.pdf?.pdfDocument }
    private var pages: [PageSource] {
        let content = session.snapshot
        return content?.metadata.resolvedPages(pdfPageCount: content?.pdf?.pageCount ?? 0) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            ocrBanner
            Picker("Show", selection: $tab) {
                Text("Chapters").tag(0)
                Text("Bookmarks").tag(1)
                Text("Search").tag(2)
                Text("Ask").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            if let working {
                ProgressView(working).padding(.vertical, 6)
            }
            if let message {
                Text(trMessage(message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .onTapGesture { self.message = nil }
            }
            switch tab {
            case 0: chapterList
            case 1: bookmarkList
            case 2: searchList
            default:
                AskBookView(
                    noteID: noteID,
                    bookTitle: store.note(noteID)?.title ?? "Book",
                    document: document,
                    chapter: currentChapter,
                    goToPage: { go(toPDFPage: $0) }
                )
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .namePrompt($bookmarkPrompt)
        .task {
            OCRCenter.shared.session = session
            guard chapters.isEmpty, let document else { return }
            let found = await Task.detached(priority: .userInitiated) {
                PDFToolKit.chapters(of: document)
            }.value
            chapters = found
            scanCount = await Task.detached(priority: .utility) { BookOCR.scanCount(in: document) }.value
        }
        .onChange(of: session.snapshot?.pdf?.fileURL) {
            // A searchable copy replaced the PDF: count again.
            guard let document else { return }
            Task {
                scanCount = await Task.detached(priority: .utility) { BookOCR.scanCount(in: document) }.value
            }
        }
        .onChange(of: canvas.currentPage) {
            session.noteReadingPage(canvas.currentPage)
        }
    }

    // MARK: OCR

    @ViewBuilder
    private var ocrBanner: some View {
        if let job = ocr.job, job.noteID == noteID {
            let total = max(job.progress.total, 1)
            let fraction: Double = Double(job.progress.done) / Double(total)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Reading pages… \(job.progress.done) of \(job.progress.total)", systemImage: "text.viewfinder")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Stop") { ocr.cancel() }.font(.caption)
                }
                ProgressView(value: fraction)
                Text("You can keep reading; it goes on in the background.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.inkAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 8)
        } else if let scanCount, scanCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(scanCount) scanned pages have no text", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                Text("Make Searchable reads them on this iPad (English and Arabic) and adds hidden text, so you can search, select, highlight and copy it. Your writing stays in place.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    ocr.start(noteID: noteID, store: store)
                } label: {
                    Label("Make Searchable (OCR)", systemImage: "text.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(ocr.job != nil)
            }
            .padding(10)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: Search

    private var searchList: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search the whole book", text: $query)
                    .submitLabel(.search)
                    .onSubmit(search)
                if isSearching { ProgressView() }
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            List(results) { hit in
                VStack(alignment: .leading, spacing: 3) {
                    Text("Page \(hit.page + 1)").font(.caption.weight(.semibold)).foregroundStyle(Color.inkAccent)
                    Text(hit.snippet).font(.callout).lineLimit(3)
                }
                .contentShape(Rectangle())
                .onTapGesture { go(toPDFPage: hit.page) }
            }
            .listStyle(.plain)
            .overlay {
                if results.isEmpty && !query.isEmpty && !isSearching {
                    Text((scanCount ?? 0) > 0 ? "Nothing found. Scanned pages are found after Make Searchable." : "Nothing found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }

    private func search() {
        guard let document, query.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
        let text = query
        isSearching = true
        Task {
            let found: [SearchHit] = await Task.detached(priority: .userInitiated) {
                let selections = document.findString(text, withOptions: [.caseInsensitive, .diacriticInsensitive])
                return selections.prefix(300).compactMap { selection -> SearchHit? in
                    guard let page = selection.pages.first else { return nil }
                    let index = document.index(for: page)
                    let line = selection.copy() as? PDFSelection
                    line?.extendForLineBoundaries()
                    let snippet = (line?.string ?? selection.string ?? "").replacingOccurrences(of: "\n", with: " ")
                    return SearchHit(page: index, snippet: snippet)
                }
            }.value
            results = found
            isSearching = false
        }
    }

    // MARK: Progress

    private var progressHeader: some View {
        let total = max(pages.count, 1)
        let furthest = (session.metadata?.furthestPage ?? canvas.currentPage) + 1
        let fraction: Double = Double(min(furthest, total)) / Double(total)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Page \(canvas.currentPage + 1) of \(pages.count)").font(.headline)
                Spacer()
                Text("\(Int(fraction * 100))% read").font(.caption.weight(.semibold)).foregroundStyle(Color.inkAccent)
            }
            ProgressView(value: fraction).tint(Color.inkAccent)
            if let chapter = currentChapter {
                Label(tr(chapter.title), systemImage: "book").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding()
    }

    private var currentPDFPage: Int? {
        guard pages.indices.contains(canvas.currentPage), case let .pdf(index) = pages[canvas.currentPage] else { return nil }
        return index
    }

    private var currentChapter: BookChapter? {
        guard let page = currentPDFPage else { return nil }
        return chapters.last { $0.firstPage <= page && page <= $0.lastPage }
    }

    // MARK: Chapters

    @ViewBuilder
    private var chapterList: some View {
        if chapters.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(document == nil
                     ? "This note has no PDF."
                     : "This PDF has no chapter list of its own. You can still make a mind map from some of its pages.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let document {
                    TextField("Pages, like 12-30", text: $rangeText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let picked = PDFToolKit.pages(from: rangeText, pageCount: document.pageCount)
                        if let first = picked.min(), let last = picked.max() {
                            let chapter = BookChapter(id: "range", title: "Pages \(first + 1)–\(last + 1)", firstPage: first, lastPage: last, depth: 0)
                            makeMindMap(chapter, useAI: false)
                        }
                    } label: {
                        Label("Mind Map from These Pages", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(rangeText.isEmpty || working != nil)
                }
            }
            .padding()
            Spacer()
        } else {
            List {
                ForEach(chapters) { chapter in
                    chapterRow(chapter)
                }
            }
            .listStyle(.plain)
        }
    }

    private func chapterRow(_ chapter: BookChapter) -> some View {
        let isCurrent = currentChapter?.id == chapter.id
        let furthestPDF = furthestPDFPage
        let done = furthestPDF >= chapter.lastPage
        return HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : isCurrent ? "location.fill" : "circle")
                .foregroundStyle(done ? Color.green : isCurrent ? Color.inkAccent : Color.secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr(chapter.title))
                    .font(chapter.depth == 0 ? .subheadline.weight(.semibold) : .subheadline)
                    .lineLimit(2)
                Text(trMessage(chapter.pageLabel)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                Button {
                    makeMindMap(chapter, useAI: false)
                } label: {
                    Label("Mind Map of This Chapter", systemImage: "point.3.connected.trianglepath.dotted")
                }
                if ai.problem == nil {
                    Button {
                        makeMindMap(chapter, useAI: true)
                    } label: {
                        Label("Mind Map with AI", systemImage: "sparkles")
                    }
                }
                Button {
                    makeConceptGraph(chapter)
                } label: {
                    Label("Concept Graph", systemImage: "circle.hexagongrid")
                }
                Button {
                    sendToNewNote(chapter)
                } label: {
                    Label("Send to a New Note", systemImage: "doc.badge.plus")
                }
                if ai.problem == nil {
                    Section("With AI") {
                        Button {
                            study(chapter, .summary)
                        } label: {
                            Label("Summary Notes", systemImage: "doc.text")
                        }
                        Button {
                            study(chapter, .flashcards)
                        } label: {
                            Label("Flashcards", systemImage: "rectangle.stack")
                        }
                        Button {
                            study(chapter, .exam)
                        } label: {
                            Label("Exam Questions", systemImage: "checklist")
                        }
                        Button {
                            study(chapter, .glossary)
                        } label: {
                            Label("Glossary", systemImage: "character.book.closed")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .disabled(working != nil)
        }
        .padding(.leading, CGFloat(chapter.depth) * 14)
        .listRowBackground(isCurrent ? Color.inkAccent.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { go(toPDFPage: chapter.firstPage) }
    }

    private var furthestPDFPage: Int {
        let furthest = session.metadata?.furthestPage ?? 0
        var best = -1
        for (index, source) in pages.enumerated() where index <= furthest {
            if case let .pdf(page) = source { best = max(best, page) }
        }
        return best
    }

    private func go(toPDFPage page: Int) {
        if let index = PDFToolKit.layoutIndex(ofPDFPage: page, in: pages) {
            canvas.scrollToPage(index)
        }
    }

    // MARK: Bookmarks

    private var bookmarkList: some View {
        let bookmarks = session.metadata?.bookmarks ?? []
        return List {
            Button {
                let page = canvas.currentPage
                bookmarkPrompt = NamePrompt(title: "Bookmark Page \(page + 1)", initialText: currentChapter?.title ?? "Page \(page + 1)", confirmTitle: "Add") { title in
                    var all = session.metadata?.bookmarks ?? []
                    let color = FolderColor.allCases[all.count % FolderColor.allCases.count]
                    all.append(NoteBookmark(page: page, title: title, color: color))
                    session.setBookmarks(all.sorted { $0.page < $1.page })
                }
            } label: {
                Label("Bookmark This Page", systemImage: "bookmark.fill")
            }
            ForEach(bookmarks) { bookmark in
                HStack {
                    Image(systemName: "bookmark.fill").foregroundStyle(bookmark.color.color)
                    VStack(alignment: .leading) {
                        Text(tr(bookmark.title)).lineLimit(2)
                        Text("Page \(bookmark.page + 1)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(FolderColor.allCases) { color in
                            Button {
                                recolor(bookmark, color)
                            } label: {
                                Label { Text(tr(color.title)) } icon: { color.menuDot(selected: bookmark.color == color) }
                            }
                        }
                    } label: {
                        Image(systemName: "paintpalette").foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { canvas.scrollToPage(bookmark.page) }
            }
            .onDelete { offsets in
                var all = bookmarks
                all.remove(atOffsets: offsets)
                session.setBookmarks(all)
            }
            if bookmarks.isEmpty {
                Text("Bookmarks keep important pages one tap away.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    private func recolor(_ bookmark: NoteBookmark, _ color: FolderColor) {
        var all = session.metadata?.bookmarks ?? []
        if let index = all.firstIndex(where: { $0.id == bookmark.id }) {
            all[index].color = color
            session.setBookmarks(all)
        }
    }

    // MARK: Chapter actions

    private func chapterText(_ chapter: BookChapter) async -> String {
        guard let document else { return "" }
        let range = chapter.firstPage...chapter.lastPage
        return await Task.detached(priority: .userInitiated) {
            PDFToolKit.text(of: range, in: document)
        }.value
    }

    private func makeMindMap(_ chapter: BookChapter, useAI: Bool) {
        guard let document else { return }
        let client = useAI ? ai.client() : nil
        if useAI {
            guard let client, store.mayUseAI(noteID, onDevice: client.kind.isOnDevice) else {
                message = NoteTexts.firewallMessage(onDevice: client?.kind.isOnDevice ?? false)
                return
            }
        }
        working = useAI ? "Asking AI for the chapter's map…" : "Reading the chapter…"
        let sections = PDFToolKit.sections(of: chapter, in: chapters)
        Task {
            defer { working = nil }
            let text = await chapterText(chapter)
            guard !text.isEmpty else {
                message = "No text was found on these pages."
                return
            }
            do {
                let map: MindMap
                if let client {
                    map = try await ChapterMaps.mindMapWithAI(title: chapter.title, text: text, client: client)
                } else {
                    var parts: [(title: String, text: String)] = []
                    for section in sections {
                        let range = section.firstPage...section.lastPage
                        let sectionText = await Task.detached { PDFToolKit.text(of: range, in: document, limit: 12_000) }.value
                        parts.append((section.title, sectionText))
                    }
                    let title = chapter.title
                    map = await Task.detached { ChapterMaps.mindMap(title: title, text: text, sections: parts) }.value
                }
                workspace.save(map)
                open(.mindMap(map.id))
            } catch {
                message = "The mind map couldn't be made: \(error.localizedDescription)"
            }
        }
    }

    private func makeConceptGraph(_ chapter: BookChapter) {
        working = "Finding the chapter's concepts…"
        Task {
            defer { working = nil }
            let text = await chapterText(chapter)
            let title = chapter.title
            let graph = await Task.detached { ChapterMaps.conceptGraph(text: text, title: title) }.value
            guard graph.concepts.count >= 2 else {
                message = "Not enough text on these pages for a graph."
                return
            }
            open(.conceptGraph(title: chapter.title, graph: graph, first: chapter.firstPage, last: chapter.lastPage))
        }
    }

    enum StudyKind {
        case summary, flashcards, exam, glossary
    }

    /// Summary notes, flashcards, exam questions or a glossary of a
    /// chapter, made by the AI from the chapter's pages (AI Firewall).
    private func study(_ chapter: BookChapter, _ kind: StudyKind) {
        guard let document, let client = ai.client() else { return }
        guard store.mayUseAI(noteID, onDevice: client.kind.isOnDevice) else {
            message = NoteTexts.firewallMessage(onDevice: client.kind.isOnDevice)
            return
        }
        let book = store.note(noteID)?.title ?? "Book"
        let folder = store.note(noteID)?.folderID
        working = "Asking AI about “\(chapter.title)”…"
        Task {
            defer { working = nil }
            let index = await Task.detached(priority: .userInitiated) { BookIndex(document: document) }.value
            let excerpt = index.excerpt(Array(chapter.firstPage...chapter.lastPage), limit: 24_000)
            guard !excerpt.isEmpty else {
                message = "These pages have no text yet. If they are scanned, use Make Searchable first."
                return
            }
            do {
                switch kind {
                case .summary:
                    let reply = try await client.complete(system: "You write clear study notes from books.",
                                                          messages: [AIMessage(.user, BookAI.summaryPrompt(chapter: chapter.title, book: book, excerpt: excerpt))])
                    let text = reply + "\n\nFrom [[\(book)]], \(chapter.pageLabel)."
                    if store.createTextNote(titled: "Summary: \(chapter.title)", in: folder, extraText: text) != nil {
                        CommandCenter.shared.say("“Summary: \(chapter.title)” is a new text note")
                    }
                case .flashcards:
                    let reply = try await client.complete(system: "You make study flashcards.",
                                                          messages: [AIMessage(.user, StudyAI.flashcardsPrompt(notes: excerpt, count: 20))])
                    let cards = try StudyAI.flashcards(from: reply)
                    workspace.save(FlashcardDeck(id: UUID(), title: chapter.title, sourceNoteIDs: [noteID], cards: cards, createdAt: Date(), modifiedAt: Date()))
                    CommandCenter.shared.say("\(cards.count) flashcards are in Study with AI")
                case .exam:
                    let reply = try await client.complete(system: "You write exam questions.",
                                                          messages: [AIMessage(.user, StudyAI.quizPrompt(notes: BookAI.examNotes(excerpt), count: 15))])
                    let questions = try StudyAI.quizQuestions(from: reply)
                    workspace.save(Quiz(id: UUID(), title: "Exam: \(chapter.title)", sourceNoteIDs: [noteID], questions: questions, bestScore: nil, createdAt: Date()))
                    CommandCenter.shared.say("\(questions.count) exam questions are in Study with AI")
                case .glossary:
                    let reply = try await client.complete(system: "You build glossaries. Reply with JSON only.",
                                                          messages: [AIMessage(.user, BookAI.glossaryPrompt(chapter: chapter.title, excerpt: excerpt))])
                    let terms = try BookAI.terms(from: reply)
                    let text = BookAI.glossaryMarkdown(terms, chapter: chapter.title, book: book)
                    if store.createTextNote(titled: "Glossary: \(chapter.title)", in: folder, extraText: text) != nil {
                        CommandCenter.shared.say("\(terms.count) terms in “Glossary: \(chapter.title)”")
                    }
                }
            } catch {
                message = "AI couldn't do it: \(error.localizedDescription)"
            }
        }
    }

    /// The chapter's pages, with what is written on them, as a new note.
    private func sendToNewNote(_ chapter: BookChapter) {
        guard let content = session.currentContent() else { return }
        let layoutPages = pages.indices.filter { index in
            if case let .pdf(page) = pages[index] { return page >= chapter.firstPage && page <= chapter.lastPage }
            return false
        }
        var options = PDFExportOptions()
        options.pageSet = Set(layoutPages)
        let title = chapter.title
        let folder = store.note(noteID)?.folderID
        working = "Making “\(title)”…"
        Task {
            defer { working = nil }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try PDFExporter.export(content, title: title, options: options)
                }.value
                if store.importPDF(from: url, into: folder) != nil {
                    CommandCenter.shared.say("“\(title)” is a new note next to the book")
                }
            } catch {
                message = "Couldn't make the note: \(error.localizedDescription)"
            }
        }
    }
}
