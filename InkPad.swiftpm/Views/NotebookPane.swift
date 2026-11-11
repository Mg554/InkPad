import PDFKit
import PencilKit
import SwiftUI

/// The notebook written beside a book: a paper note linked to it, with a
/// page for each chapter, the book pages each page was written beside,
/// and pieces sent from the book.
@MainActor
final class NotebookController: ObservableObject {
    let session = EditorSession()
    @Published private(set) var isOpen = false
    @Published private(set) var bookChapters: [BookChapter] = []
    /// The book's chapter at the page being read.
    @Published private(set) var currentChapter: BookChapter?
    @Published var follows: Bool = UserDefaults.standard.object(forKey: "notebookFollows") as? Bool ?? true {
        didSet { UserDefaults.standard.set(follows, forKey: "notebookFollows") }
    }

    private weak var book: EditorSession?
    /// Set while InkPad itself writes (chapter headings, pieces sent from the book).
    private var isPlacing = false
    private var store: LibraryStore?
    private(set) var notebookID: UUID?

    var title: String { notebookID.flatMap { store?.note($0)?.title } ?? "Notebook" }

    /// Opens the book's notebook, making one the first time.
    func open(book: EditorSession, bookID: UUID, store: LibraryStore) {
        self.book = book
        self.store = store
        if !isOpen {
            var id = book.metadata?.notebookID
            if id.flatMap({ store.note($0) }) == nil {
                let bookTitle = store.note(bookID)?.title ?? "Book"
                guard let note = store.createNote(in: store.note(bookID)?.folderID, template: .lined) else { return }
                store.renameNote(note.id, to: "Notebook — \(bookTitle)")
                book.updateMetadata { $0.notebookID = note.id }
                id = note.id
            }
            guard let id else { return }
            notebookID = id
            session.load(noteID: id, store: store)
            session.canvas.onEdit = { [weak self] in
                self?.session.markEdited()
                self?.recordEdit()
            }
            if session.metadata?.notebookFor != bookID {
                session.updateMetadata { $0.notebookFor = bookID }
            }
        }
        isOpen = true
        loadChapters()
    }

    func close() {
        session.save(thumbnail: true)
        isOpen = false
    }

    private func loadChapters() {
        guard bookChapters.isEmpty, let document = book?.snapshot?.pdf?.pdfDocument else { return }
        Task {
            let chapters = await Task.detached(priority: .userInitiated) { PDFToolKit.chapters(of: document, maxDepth: 0) }.value
            bookChapters = chapters
            if let book { bookPageChanged(book.canvas.currentPage) }
        }
    }

    // MARK: Book pages

    /// The PDF page shown at a layout page of the book.
    func pdfPage(atLayout page: Int) -> Int? {
        guard let book, let metadata = book.metadata else { return nil }
        let pages = metadata.resolvedPages(pdfPageCount: book.snapshot?.pdf?.pageCount ?? 0)
        guard pages.indices.contains(page), case let .pdf(index) = pages[page] else { return nil }
        return index
    }

    func layoutPage(ofPDF page: Int) -> Int? {
        guard let book, let metadata = book.metadata else { return nil }
        let pages = metadata.resolvedPages(pdfPageCount: book.snapshot?.pdf?.pageCount ?? 0)
        return pages.firstIndex(of: .pdf(page))
    }

    /// The book page that holds a rectangle of the book's canvas.
    func layoutPage(containing rect: CGRect) -> Int? {
        guard let rects = book?.background?.layout.pageRects else { return nil }
        return rects.firstIndex { $0.minY <= rect.midY && rect.midY <= $0.maxY }
    }

    func showBookPage(_ pdfPage: Int) {
        guard let page = layoutPage(ofPDF: pdfPage) else { return }
        book?.canvas.scrollToPage(page)
    }

    // MARK: Chapters

    private func chapter(atPDF page: Int) -> BookChapter? {
        bookChapters.last { $0.firstPage <= page && page <= $0.lastPage }
    }

    /// The notebook page where a chapter's notes start.
    func notebookPage(for chapter: BookChapter) -> Int? {
        let entries = session.metadata?.notebookChapters ?? []
        let found = entries.first { $0.bookPage == chapter.firstPage && $0.title == chapter.title }
        guard let page = found?.page, page < max(session.pageCount, 1) else { return nil }
        return page
    }

    var notebookChapters: [NotebookChapter] {
        (session.metadata?.notebookChapters ?? []).sorted { $0.page < $1.page }
    }

    /// Follows the book: shows the notes of the chapter being read.
    func bookPageChanged(_ layoutPage: Int) {
        guard let pdf = pdfPage(atLayout: layoutPage) else { return }
        let found = chapter(atPDF: pdf)
        guard found?.id != currentChapter?.id else { return }
        currentChapter = found
        guard follows, let found, let page = notebookPage(for: found), page != session.canvas.currentPage else { return }
        session.canvas.scrollToPage(page)
    }

    /// A new page headed with the chapter's title (the first, empty page
    /// is used for the first chapter).
    func startNotes(for chapter: BookChapter) {
        if let page = notebookPage(for: chapter) {
            session.canvas.scrollToPage(page)
            return
        }
        let entries = session.metadata?.notebookChapters ?? []
        let strokes = session.canvas.drawing?.strokes.count ?? 0
        let elements = session.canvas.elements?.count ?? 0
        let isBlank = entries.isEmpty && session.pageCount == 1 && strokes == 0 && elements == 0
        let page: Int
        if isBlank {
            page = 0
        } else {
            session.insertPage(after: max(session.pageCount - 1, 0))
            page = session.pageCount - 1
        }
        let entry = NotebookChapter(title: chapter.title, bookPage: chapter.firstPage, page: page)
        var links = session.metadata?.bookPageLinks ?? []
        links.removeAll { $0.page == page }
        links.append(NotebookPageLink(page: page, bookPages: [chapter.firstPage]))
        session.updateMetadata {
            $0.notebookChapters = entries + [entry]
            $0.bookPageLinks = links
        }
        let heading = TextBoxStyle.attributed(markdown: "## \(chapter.title)\nNotes from the book, from p. \(chapter.firstPage + 1)")
        Task {
            // The canvas grows to the new page on SwiftUI's next update.
            try? await Task.sleep(for: .milliseconds(250))
            guard let rects = session.background?.layout.pageRects, rects.indices.contains(page) else { return }
            let rect = rects[page]
            session.canvas.scrollToPage(page)
            isPlacing = true
            session.canvas.placeText(heading, below: CGRect(x: rect.minX + 40, y: rect.minY + 8, width: 520, height: 0))
            isPlacing = false
            try? await Task.sleep(for: .milliseconds(250))
            session.canvas.scrollToPage(page)
        }
    }

    // MARK: Page links

    /// Remembers which book page was open while this notebook page was written.
    private func recordEdit() {
        guard !isPlacing, let book, let pdf = pdfPage(atLayout: book.canvas.currentPage) else { return }
        let page = session.canvas.currentPage
        var links = session.metadata?.bookPageLinks ?? []
        if let index = links.firstIndex(where: { $0.page == page }) {
            guard !links[index].bookPages.contains(pdf) else { return }
            links[index].bookPages = Array((links[index].bookPages + [pdf]).suffix(8))
        } else {
            links.append(NotebookPageLink(page: page, bookPages: [pdf]))
        }
        session.updateMetadata { $0.bookPageLinks = links }
    }

    func bookPages(writtenOn page: Int) -> [Int] {
        let links = session.metadata?.bookPageLinks ?? []
        return (links.first { $0.page == page }?.bookPages ?? []).sorted()
    }

    // MARK: Sending from the book

    /// Puts a picture of part of the book on the notebook page shown, with its page number.
    func send(image: UIImage, fromLayoutPage layoutPage: Int?) async {
        guard let store, let notebookID, let data = image.pngData() else { return }
        let pdf = layoutPage.flatMap { pdfPage(atLayout: $0) }
        guard let added = await store.addImage(data, to: notebookID),
              let directory = session.imageDirectory,
              let picture = UIImage(contentsOfFile: directory.appendingPathComponent(added.file).path)
        else { return }
        let caption = pdf.map { TextBoxStyle.attributed(markdown: "From the book, p. \($0 + 1)") }
        isPlacing = true
        session.canvas.insertImage(file: added.file, image: picture, pixelSize: added.size, caption: caption)
        isPlacing = false
        if let pdf { addLink(to: pdf) }
    }

    /// Puts the text of part of the book on the notebook page shown, as a quote.
    func sendText(of image: UIImage, fromLayoutPage layoutPage: Int?) async {
        guard let cgImage = image.cgImage else { return }
        let lines = await Task.detached(priority: .userInitiated) { BookOCR.lines(in: cgImage) }.value
        let text = BookOCR.text(of: lines).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            CommandCenter.shared.say("No text was found there")
            return
        }
        let pdf = layoutPage.flatMap { pdfPage(atLayout: $0) }
        let source: String = pdf.map { "\n\n— p. \($0 + 1)" } ?? ""
        isPlacing = true
        session.canvas.placeTextInView(TextBoxStyle.attributed(markdown: "“\(text)”" + source))
        isPlacing = false
        if let pdf { addLink(to: pdf) }
    }

    private func addLink(to pdf: Int) {
        let page = session.canvas.currentPage
        var links = session.metadata?.bookPageLinks ?? []
        if let index = links.firstIndex(where: { $0.page == page }) {
            if !links[index].bookPages.contains(pdf) { links[index].bookPages.append(pdf) }
        } else {
            links.append(NotebookPageLink(page: page, bookPages: [pdf]))
        }
        session.updateMetadata { $0.bookPageLinks = links }
    }
}

/// The notebook beside the book.
struct NotebookPane: View {
    @EnvironmentObject private var palette: ToolPalette
    @ObservedObject var notebook: NotebookController
    /// Observed so new pages reach the canvas.
    @ObservedObject var session: EditorSession
    @ObservedObject var bookCanvas: CanvasController
    let pencilOnly: Bool
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            NotebookHeader(notebook: notebook, session: session, canvas: session.canvas, close: close)
                .zIndex(1)
            Divider()
            if let content = session.initialContent, let background = session.background {
                NoteCanvas(
                    initialContent: content,
                    background: background,
                    pencilOnly: pencilOnly,
                    controller: session.canvas,
                    palette: palette
                )
                .clipped()
            } else if let error = session.loadError {
                ContentUnavailableView("Could Not Open the Notebook", systemImage: "exclamationmark.triangle", description: Text(trMessage(error)))
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .onReceive(palette.objectWillChange) {
            // Same pen in the book and the notebook.
            DispatchQueue.main.async { notebook.session.canvas.applyTool() }
        }
        .onChange(of: bookCanvas.currentPage) {
            notebook.bookPageChanged(bookCanvas.currentPage)
        }
    }
}

/// The notebook's bar: chapter, follow the book, page links and pages.
private struct NotebookHeader: View {
    @ObservedObject var notebook: NotebookController
    @ObservedObject var session: EditorSession
    @ObservedObject var canvas: CanvasController
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow
            chapterRow
            linksRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.pages").foregroundStyle(Color.inkAccent)
            Text(tr(notebook.title)).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer()
            Button {
                canvas.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!canvas.canUndo)
            Button {
                canvas.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!canvas.canRedo)
            chaptersMenu
            Button {
                notebook.session.insertPage(after: canvas.currentPage)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            Button(action: close) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close Notebook")
        }
        .buttonStyle(.borderless)
    }

    private var chaptersMenu: some View {
        Menu {
            Toggle(isOn: $notebook.follows) {
                Label("Follow the Book", systemImage: "arrow.triangle.2.circlepath")
            }
            if !notebook.notebookChapters.isEmpty {
                Section("Chapters in This Notebook") {
                    ForEach(notebook.notebookChapters) { entry in
                        Button(tr(entry.title)) { canvas.scrollToPage(entry.page) }
                    }
                }
            }
            if !notebook.bookChapters.isEmpty {
                Menu("Start Notes for a Chapter") {
                    ForEach(notebook.bookChapters) { chapter in
                        Button(tr(chapter.title)) { notebook.startNotes(for: chapter) }
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet.indent")
        }
    }

    @ViewBuilder
    private var chapterRow: some View {
        if let chapter = notebook.currentChapter {
            HStack(spacing: 8) {
                Image(systemName: notebook.follows ? "arrow.triangle.2.circlepath" : "book")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(tr(chapter.title)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let page = notebook.notebookPage(for: chapter) {
                    if page != canvas.currentPage {
                        Button("Go to Its Notes") { canvas.scrollToPage(page) }
                            .font(.caption)
                    }
                } else {
                    Button {
                        notebook.startNotes(for: chapter)
                    } label: {
                        Label("Start Notes", systemImage: "plus")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
        }
    }

    @ViewBuilder
    private var linksRow: some View {
        let pages = notebook.bookPages(writtenOn: canvas.currentPage)
        if !pages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Written beside").font(.caption2).foregroundStyle(.secondary)
                    ForEach(pages, id: \.self) { page in
                        Button("p. \(page + 1)") { notebook.showBookPage(page) }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            }
        }
    }
}
