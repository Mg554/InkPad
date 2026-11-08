import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// The PDF tools, PDF24-style: pick a tool, pick PDFs (from the library or
/// Files), and the result becomes a new note. Originals are never changed.
enum PDFTool: String, CaseIterable, Identifiable {
    case merge, split, extract, remove, rotate, ocr

    var id: Self { self }

    var title: String {
        switch self {
        case .merge: "Merge PDFs"
        case .split: "Split PDF"
        case .extract: "Pages to a New Note"
        case .remove: "Remove Pages"
        case .rotate: "Rotate Pages"
        case .ocr: "Make Searchable (OCR)"
        }
    }

    var detail: String {
        switch self {
        case .merge: "Join several PDFs into one, in the order you choose."
        case .split: "By chapters, every few pages, or page ranges you type."
        case .extract: "Take some pages out to study them deeply on their own."
        case .remove: "A copy without the pages you don't need."
        case .rotate: "Turn pages that are sideways or upside down."
        case .ocr: "Read scanned pages (English and Arabic) so they can be searched and copied."
        }
    }

    var systemImage: String {
        switch self {
        case .merge: "rectangle.stack.badge.plus"
        case .split: "scissors"
        case .extract: "doc.badge.plus"
        case .remove: "trash"
        case .rotate: "rotate.right"
        case .ocr: "text.viewfinder"
        }
    }

    var tint: Color {
        switch self {
        case .merge: .blue
        case .split: .orange
        case .extract: .green
        case .remove: .red
        case .rotate: .purple
        case .ocr: .teal
        }
    }

    var takesSeveralFiles: Bool { self == .merge }
    var picksPages: Bool { self == .extract || self == .remove || self == .rotate }
}

struct PDFToolsView: View {
    @State private var tool: PDFTool?
    @State private var extra: PDFExtraTool?
    @State private var isComparing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Free and private: everything happens on this iPad, without the internet (only Web Page to PDF loads the page). Results are saved as new notes; your PDFs are never changed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                section("Organize", tools: PDFTool.allCases)
                extraSection("Convert", tools: PDFExtraTool.convert)
                extraSection("Protect & Edit", tools: PDFExtraTool.protect)
                compareSection
                VStack(alignment: .leading, spacing: 6) {
                    Label("Inside a PDF note", systemImage: "book")
                        .font(.headline)
                    Text("Open a book and use Chapters (the book button) for its outline, bookmarks, reading progress, and a mind map or concept graph of any chapter. In More: Insert Pages from Another PDF, and Send Pages to a New Note.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .themedCard()
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .themedBackground()
        .navigationTitle("PDF Tools")
        .sheet(item: $tool) { tool in
            PDFToolSheet(tool: tool)
        }
        .sheet(item: $extra) { tool in
            PDFExtraToolSheet(tool: tool)
        }
        .fullScreenCover(isPresented: $isComparing) {
            CompareEditionsView()
        }
    }

    private var compareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Study").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                Button {
                    isComparing = true
                } label: {
                    card(title: "Compare Editions", detail: "What changed between two editions of a book, chapter by chapter.", systemImage: "arrow.left.arrow.right", tint: .teal)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func extraSection(_ title: String, tools: [PDFExtraTool]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                ForEach(tools) { item in
                    Button {
                        extra = item
                    } label: {
                        card(title: item.title, detail: item.detail, systemImage: item.systemImage, tint: item.tint)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func section(_ title: String, tools: [PDFTool]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                ForEach(tools) { item in
                    Button {
                        tool = item
                    } label: {
                        toolCard(item)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func toolCard(_ item: PDFTool) -> some View {
        card(title: item.title, detail: item.detail, systemImage: item.systemImage, tint: item.tint)
    }

    private func card(title: String, detail: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: tint.opacity(0.4), radius: 8)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .padding(12)
        .themedCard(cornerRadius: 18)
    }
}

/// A PDF to work on: a note in the library, or a file from Files.
struct PDFSourceItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case note(UUID)
        case file(URL)
    }

    let id = UUID()
    let kind: Kind
    let title: String

    var isFile: Bool {
        if case .file = kind { return true }
        return false
    }
}

/// One tool: choose PDFs, pages and options, then make the new note(s).
struct PDFToolSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let tool: PDFTool

    @State private var sources: [PDFSourceItem] = []
    @State private var document: PDFDocument?
    @State private var chapters: [BookChapter] = []
    @State private var selection: Set<Int> = []
    @State private var rangeText = ""
    @State private var splitMode = 0
    @State private var everyPages = 20
    @State private var degrees = 90
    @State private var isPickingFile = false
    @State private var isPickingNote = false
    @State private var working: String?
    @State private var problem: String?
    @State private var made: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if tool == .split, document != nil { splitSection }
                if tool == .rotate {
                    Section("Turn") {
                        Picker("Degrees", selection: $degrees) {
                            Text("90° right").tag(90)
                            Text("180°").tag(180)
                            Text("90° left").tag(270)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if tool.picksPages, let document { pagesSection(document) }
                if !made.isEmpty {
                    Section("Done") {
                        ForEach(made, id: \.self) { title in
                            Label(title, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle(tool.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(made.isEmpty ? "Cancel" : "Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Make") { run() }
                        .disabled(!canRun || working != nil)
                }
            }
            .overlay {
                if let working {
                    ProgressView(working)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("PDF Tools", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .sheet(isPresented: $isPickingFile) {
                DocumentPicker(contentTypes: [.pdf]) { urls in
                    isPickingFile = false
                    let items = urls.map { PDFSourceItem(kind: .file($0), title: $0.deletingPathExtension().lastPathComponent) }
                    add(items)
                }
            }
            .sheet(isPresented: $isPickingNote) {
                PDFNotePicker { notes in
                    isPickingNote = false
                    add(notes.map { PDFSourceItem(kind: .note($0.id), title: $0.title) })
                }
                .environmentObject(store)
            }
        }
    }

    private var canRun: Bool {
        guard !sources.isEmpty else { return false }
        switch tool {
        case .merge: return sources.count >= 2
        case .split, .ocr: return document != nil
        case .extract, .remove, .rotate: return !selection.isEmpty
        }
    }

    // MARK: Sections

    private var sourceSection: some View {
        Section {
            ForEach(sources) { source in
                Label(source.title, systemImage: source.isFile ? "doc" : "doc.richtext")
            }
            .onMove { from, to in sources.move(fromOffsets: from, toOffset: to) }
            .onDelete { offsets in
                sources.remove(atOffsets: offsets)
                if sources.isEmpty { document = nil }
            }
            if tool.takesSeveralFiles || sources.isEmpty {
                Button {
                    isPickingNote = true
                } label: {
                    Label("From the Library…", systemImage: "books.vertical")
                }
                Button {
                    isPickingFile = true
                } label: {
                    Label("From Files…", systemImage: "folder")
                }
            }
        } header: {
            Text(tool.takesSeveralFiles ? "PDFs, in order" : "PDF")
        } footer: {
            if tool.takesSeveralFiles { Text("Drag to change the order.") }
        }
    }

    private var splitSection: some View {
        Section {
            Picker("Split", selection: $splitMode) {
                Text("By Chapters").tag(0)
                Text("Every N Pages").tag(1)
                Text("Page Ranges").tag(2)
            }
            .pickerStyle(.segmented)
            switch splitMode {
            case 0:
                let top = chapters.filter { $0.depth == 0 }
                if top.isEmpty {
                    Text("This PDF has no chapter list; use another way.").foregroundStyle(.secondary)
                } else {
                    Text("\(top.count) chapters: \(top.prefix(3).map(\.title).joined(separator: ", "))…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case 1:
                Stepper("Every \(everyPages) pages", value: $everyPages, in: 1...500)
            default:
                TextField("Ranges, like 1-20, 21-45, 46-80", text: $rangeText)
            }
        } header: {
            Text("Parts")
        } footer: {
            Text("Each part becomes a note in a new folder.")
        }
    }

    private func pagesSection(_ document: PDFDocument) -> some View {
        Section {
            HStack {
                TextField("Pages, like 1-5, 9", text: $rangeText)
                    .onSubmit { selectTyped(document) }
                Button("Select") { selectTyped(document) }
                    .disabled(rangeText.isEmpty)
            }
            HStack {
                Text("\(selection.count) of \(document.pageCount) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("All") { selection = Set(0..<document.pageCount) }
                Button("None") { selection = [] }
            }
            .buttonStyle(.borderless)
            PageThumbnailGrid(document: document, selection: $selection)
                .frame(minHeight: 300)
        } header: {
            Text("Pages")
        }
    }

    private func selectTyped(_ document: PDFDocument) {
        selection = Set(PDFToolKit.pages(from: rangeText, pageCount: document.pageCount))
    }

    // MARK: Loading

    private func add(_ items: [PDFSourceItem]) {
        if tool.takesSeveralFiles {
            sources += items
        } else if let first = items.first {
            sources = [first]
            load(first)
        }
    }

    private func load(_ source: PDFSourceItem) {
        working = "Opening “\(source.title)”…"
        Task {
            defer { working = nil }
            do {
                let opened = try await loadDocument(source)
                document = opened
                selection = []
                chapters = await Task.detached { PDFToolKit.chapters(of: opened, maxDepth: 0) }.value
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func loadDocument(_ source: PDFSourceItem) async throws -> PDFDocument {
        try await store.pdfDocument(for: source)
    }

    // MARK: Making

    private func run() {
        working = "Making…"
        Task {
            defer { working = nil }
            do {
                switch tool {
                case .merge:
                    var documents: [PDFDocument] = []
                    for source in sources {
                        working = "Reading “\(source.title)”…"
                        documents.append(try await loadDocument(source))
                    }
                    working = "Joining…"
                    let title = sources.map(\.title).prefix(2).joined(separator: " + ")
                    let merged = PDFToolKit.merge(documents)
                    try await save(merged, title: title, folder: nil)
                case .split:
                    guard let document, let source = sources.first else { return }
                    let parts: [PDFToolKit.Part]
                    switch splitMode {
                    case 0: parts = PDFToolKit.parts(byChapters: chapters)
                    case 1: parts = PDFToolKit.parts(every: everyPages, pageCount: document.pageCount, title: source.title)
                    default:
                        parts = rangeText.split(separator: ",").map { range in
                            let pages = PDFToolKit.pages(from: String(range), pageCount: document.pageCount)
                            return PDFToolKit.Part(title: "\(source.title) (\(range.trimmingCharacters(in: .whitespaces)))", pages: pages)
                        }
                        .filter { !$0.pages.isEmpty }
                    }
                    guard !parts.isEmpty else { throw PDFToolError.noPages }
                    let folder = store.createFolder(named: "\(source.title) (parts)")
                    for (offset, part) in parts.enumerated() {
                        working = "Part \(offset + 1) of \(parts.count)…"
                        let piece = PDFToolKit.document(with: part.pages, from: document)
                        try await save(piece, title: part.title, folder: folder?.id)
                    }
                case .extract:
                    guard let document, let source = sources.first else { return }
                    let pages = selection.sorted()
                    let title = "\(source.title) (pp. \(pageList(pages)))"
                    try await save(PDFToolKit.document(with: pages, from: document), title: title, folder: nil)
                case .remove:
                    guard let document, let source = sources.first else { return }
                    try await save(PDFToolKit.removing(selection, from: document), title: "\(source.title) (shorter)", folder: nil)
                case .rotate:
                    guard let document, let source = sources.first else { return }
                    try await save(PDFToolKit.rotating(selection, by: degrees, in: document), title: "\(source.title) (rotated)", folder: nil)
                case .ocr:
                    guard let document, let source = sources.first else { return }
                    let title = "\(source.title) (searchable)"
                    let url = PDFToolKit.temporaryURL(named: title)
                    let flag = CancelFlag()
                    let read = try await Task.detached(priority: .userInitiated) {
                        try BookOCR.searchable(document, to: url, progress: { progress in
                            Task { @MainActor in working = "Reading page \(progress.done) of \(progress.total)…" }
                        }, isCancelled: { flag.isCancelled })
                    }.value
                    guard store.importPDF(from: url, into: nil) != nil else { throw PDFToolError.cannotWrite }
                    made.append("\(title): \(read) pages read")
                }
                CommandCenter.shared.say(made.count == 1 ? "“\(made[0])” is in the library" : "\(made.count) new notes are in the library")
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func save(_ document: PDFDocument, title: String, folder: UUID?) async throws {
        let url = try await Task.detached(priority: .userInitiated) {
            try PDFToolKit.write(document, title: title)
        }.value
        guard store.importPDF(from: url, into: folder) != nil else { throw PDFToolError.cannotWrite }
        made.append(title)
    }

    private func pageList(_ pages: [Int]) -> String {
        guard let first = pages.first, let last = pages.last else { return "" }
        return pages.count == last - first + 1 ? "\(first + 1)–\(last + 1)" : "\(pages.count) pages"
    }
}

/// Small pictures of a PDF's pages; tap to select.
struct PageThumbnailGrid: View {
    let document: PDFDocument
    @Binding var selection: Set<Int>

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 12) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    PageThumb(document: document, index: index, isSelected: selection.contains(index))
                        .onTapGesture {
                            if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
                        }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(height: 420)
    }
}

private struct PageThumb: View {
    let document: PDFDocument
    let index: Int
    let isSelected: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Color(uiColor: .secondarySystemBackground)
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.inkAccent : Color.secondary.opacity(0.3), lineWidth: isSelected ? 3 : 1))
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color.inkAccent)
                        .padding(4)
                }
            }
            Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: index) {
            let document = document
            let index = index
            image = await Task.detached(priority: .utility) {
                document.page(at: index)?.thumbnail(of: CGSize(width: 180, height: 240), for: .cropBox)
            }.value
        }
    }
}

/// Choose notes that have a PDF.
struct PDFNotePicker: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let pick: ([NoteSummary]) -> Void
    @State private var chosen: Set<UUID> = []
    @State private var search = ""

    private var notes: [NoteSummary] {
        store.notes
            .filter { !$0.isText }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        NavigationStack {
            List(notes) { note in
                HStack {
                    Image(systemName: chosen.contains(note.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(chosen.contains(note.id) ? Color.inkAccent : Color.secondary)
                    Text(note.title)
                    Spacer()
                    Text(note.modifiedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if chosen.contains(note.id) { chosen.remove(note.id) } else { chosen.insert(note.id) }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Choose Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        pick(notes.filter { chosen.contains($0.id) })
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
    }
}

@MainActor
extension LibraryStore {
    /// A note's pages with what is written on them (or its PDF as is, when
    /// nothing is written), or a file's PDF.
    func pdfDocument(for source: PDFSourceItem) async throws -> PDFDocument {
        switch source.kind {
        case let .file(url):
            return try await Task.detached { try PDFToolKit.open(url) }.value
        case let .note(id):
            let content = try loadContent(for: id)
            let pages = content.metadata.resolvedPages(pdfPageCount: content.pdf?.pageCount ?? 0)
            let plain = content.drawing.strokes.isEmpty && (content.metadata.elements ?? []).isEmpty
            let inOrder = pages == (0..<(content.pdf?.pageCount ?? 0)).map { PageSource.pdf($0) }
            if plain, inOrder, let url = content.pdf?.fileURL {
                return try await Task.detached { try PDFToolKit.open(url) }.value
            }
            let title = source.title
            let url = try await Task.detached(priority: .userInitiated) {
                try PDFExporter.export(content, title: title)
            }.value
            return try PDFToolKit.open(url)
        }
    }
}
