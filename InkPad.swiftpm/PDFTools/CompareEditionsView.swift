import PDFKit
import SwiftUI

/// Compare Editions: two editions of a book matched chapter by chapter,
/// with the pages side by side and the changed words marked.
struct CompareEditionsView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var oldSource: PDFSourceItem?
    @State private var newSource: PDFSourceItem?
    @State private var picking: Side?
    @State private var pickingFile: Side?
    @State private var oldDocument: PDFDocument?
    @State private var newDocument: PDFDocument?
    @State private var comparison: EditionComparison?
    @State private var progress: Double?
    @State private var filter: ChapterChangeKind?
    @State private var problem: String?
    @State private var message: String?

    enum Side: String, Identifiable {
        case old, new
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let comparison, let oldDocument, let newDocument {
                    results(comparison, old: oldDocument, new: newDocument)
                } else {
                    chooser
                }
            }
            .navigationTitle("Compare Editions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .themedBackground()
            .overlay { progressOverlay }
            .alert("Compare Editions", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .sheet(item: $picking) { side in
                PDFNotePicker { notes in
                    picking = nil
                    if let note = notes.first { set(side, PDFSourceItem(kind: .note(note.id), title: note.title)) }
                }
                .environmentObject(store)
            }
            .sheet(item: $pickingFile) { side in
                DocumentPicker(contentTypes: [.pdf]) { urls in
                    pickingFile = nil
                    if let url = urls.first {
                        set(side, PDFSourceItem(kind: .file(url), title: url.deletingPathExtension().lastPathComponent))
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
        }
        if let comparison {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        saveReport(comparison)
                    } label: {
                        Label("Save Report as Note", systemImage: "doc.text")
                    }
                    Button {
                        moveBookmarks(comparison)
                    } label: {
                        Label("Move Bookmarks to the New Edition", systemImage: "bookmark")
                    }
                    .disabled(!bothNotes)
                    Button {
                        self.comparison = nil
                    } label: {
                        Label("Compare Other Books", systemImage: "arrow.left.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if let progress {
            VStack(spacing: 10) {
                ProgressView(value: progress)
                    .frame(width: 220)
                Text("Reading both editions…").font(.callout)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Choosing

    private var chooser: some View {
        Form {
            Section {
                Text("Find what changed between two editions of a book: new, removed and changed chapters, the pages side by side with added words in green and removed words in red, and an AI explanation of the changes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            sourceSection(.old, title: "Old Edition", item: oldSource)
            sourceSection(.new, title: "New Edition", item: newSource)
            Section {
                Button {
                    compare()
                } label: {
                    Label("Compare", systemImage: "arrow.left.arrow.right.circle.fill")
                        .font(.headline)
                }
                .disabled(oldSource == nil || newSource == nil || progress != nil)
            } footer: {
                Text("Everything is read on this iPad. Scanned books need Make Searchable first.")
            }
        }
    }

    private func sourceSection(_ side: Side, title: String, item: PDFSourceItem?) -> some View {
        Section(tr(title)) {
            if let item {
                Label(tr(item.title), systemImage: side == .old ? "book.closed" : "book")
            }
            Button {
                picking = side
            } label: {
                Label("From the Library…", systemImage: "books.vertical")
            }
            Button {
                pickingFile = side
            } label: {
                Label("From Files…", systemImage: "folder")
            }
        }
    }

    private func set(_ side: Side, _ item: PDFSourceItem) {
        if side == .old { oldSource = item } else { newSource = item }
    }

    private var bothNotes: Bool {
        noteID(oldSource) != nil && noteID(newSource) != nil
    }

    private func noteID(_ item: PDFSourceItem?) -> UUID? {
        if case let .note(id) = item?.kind { return id }
        return nil
    }

    // MARK: Comparing

    private func open(_ item: PDFSourceItem) async throws -> PDFDocument {
        switch item.kind {
        case let .file(url):
            return try await Task.detached { try PDFToolKit.open(url) }.value
        case let .note(id):
            // The book itself, without the ink, so its pages keep their numbers.
            let content = try store.loadContent(for: id)
            guard let url = content.pdf?.fileURL else { throw PDFToolError.noPages }
            return try await Task.detached { try PDFToolKit.open(url) }.value
        }
    }

    private func compare() {
        guard let oldSource, let newSource else { return }
        progress = 0
        Task {
            defer { progress = nil }
            do {
                let old = try await open(oldSource)
                let new = try await open(newSource)
                let oldTitle = oldSource.title
                let newTitle = newSource.title
                let result = await Task.detached(priority: .userInitiated) {
                    EditionCompare.compare(old: old, new: new, oldTitle: oldTitle, newTitle: newTitle) { value in
                        Task { @MainActor in progress = value }
                    }
                }.value
                oldDocument = old
                newDocument = new
                comparison = result
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    // MARK: Results

    private func results(_ comparison: EditionComparison, old: PDFDocument, new: PDFDocument) -> some View {
        List {
            Section {
                summary(comparison)
                if !comparison.usedOutline {
                    Text("One of the books has no chapters (outline), so they were compared 10 pages at a time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if comparison.scannedPages > 0 {
                    Text("\(comparison.scannedPages) pages have no text (scans). Use Make Searchable on them to compare them too.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let message {
                    Label(trMessage(message), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            Section {
                Picker("Show", selection: $filter) {
                    Text("All").tag(ChapterChangeKind?.none)
                    ForEach(ChapterChangeKind.allCases) { kind in
                        Text("\(kind.title) (\(comparison.count(kind)))").tag(Optional(kind))
                    }
                }
                .pickerStyle(.segmented)
                ForEach(shown(comparison)) { change in
                    NavigationLink {
                        ChapterCompareView(change: change, comparison: comparison, old: old, new: new, oldNoteID: noteID(oldSource), newNoteID: noteID(newSource))
                    } label: {
                        row(change)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func shown(_ comparison: EditionComparison) -> [ChapterChange] {
        guard let filter else { return comparison.changes }
        return comparison.changes.filter { $0.kind == filter }
    }

    private func summary(_ comparison: EditionComparison) -> some View {
        HStack(spacing: 12) {
            ForEach([ChapterChangeKind.added, .removed, .changed, .same]) { kind in
                VStack(spacing: 4) {
                    Text("\(comparison.count(kind))")
                        .font(.title2.bold())
                        .foregroundStyle(kind.color)
                    Text(tr(kind.title)).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }

    private func row(_ change: ChapterChange) -> some View {
        HStack(spacing: 12) {
            Image(systemName: change.kind.systemImage)
                .font(.title3)
                .foregroundStyle(change.kind.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(change.title)).font(.body.weight(.medium)).lineLimit(2)
                Text(trMessage(change.pagesLabel)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if change.kind == .changed {
                Text("\(change.percentChanged)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
        }
    }

    // MARK: Actions

    private func saveReport(_ comparison: EditionComparison) {
        let text = EditionCompare.report(comparison)
        let title = "Changes: \(comparison.newTitle)"
        if store.createTextNote(titled: title, in: nil, extraText: text) != nil {
            message = "The report is a new text note"
            CommandCenter.shared.say("Saved the report")
        }
    }

    /// Copies the old note's bookmarks to the matching pages of the new note.
    private func moveBookmarks(_ comparison: EditionComparison) {
        guard let oldID = noteID(oldSource), let newID = noteID(newSource) else { return }
        do {
            let oldContent = try store.loadContent(for: oldID)
            var newContent = try store.loadContent(for: newID)
            let oldLayout = oldContent.metadata.resolvedPages(pdfPageCount: oldContent.pdf?.pageCount ?? 0)
            let newLayout = newContent.metadata.resolvedPages(pdfPageCount: newContent.pdf?.pageCount ?? 0)
            var bookmarks = newContent.metadata.bookmarks ?? []
            var moved = 0
            for bookmark in oldContent.metadata.bookmarks ?? [] {
                guard bookmark.page < oldLayout.count, case let .pdf(oldPage) = oldLayout[bookmark.page] else { continue }
                guard let newPage = comparison.newPage(matching: oldPage) else { continue }
                guard let layoutPage = newLayout.firstIndex(of: .pdf(newPage)) else { continue }
                let exists = bookmarks.contains { $0.page == layoutPage && $0.title == bookmark.title }
                guard !exists else { continue }
                bookmarks.append(NoteBookmark(page: layoutPage, title: bookmark.title, color: bookmark.color))
                moved += 1
            }
            guard moved > 0 else {
                problem = "No bookmarks could be moved: the old edition has none, or their pages weren't found in the new one."
                return
            }
            newContent.metadata.bookmarks = bookmarks.sorted { $0.page < $1.page }
            let content = newContent
            Task {
                if await store.saveContent(content, for: newID, thumbnail: false) {
                    message = "\(moved) bookmarks moved to “\(comparison.newTitle)”"
                }
            }
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// One chapter in both editions: what changed, the pages side by side, and
/// an AI explanation.
struct ChapterCompareView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var ai = AISettings.shared
    let change: ChapterChange
    let comparison: EditionComparison
    let old: PDFDocument
    let new: PDFDocument
    let oldNoteID: UUID?
    let newNoteID: UUID?

    @State private var offset = 0
    @State private var oldImage: UIImage?
    @State private var newImage: UIImage?
    @State private var shownPages: (old: Int?, new: Int?) = (nil, nil)
    @State private var sentences: (added: [String], removed: [String]) = ([], [])
    @State private var explanation: String?
    @State private var isExplaining = false
    @State private var problem: String?

    /// The pages walked through: the new chapter's, or the old one's when it was removed.
    private var steps: [Int] {
        if let chapter = change.new { return Array(chapter.firstPage...max(chapter.lastPage, chapter.firstPage)) }
        if let chapter = change.old { return Array(chapter.firstPage...max(chapter.lastPage, chapter.firstPage)) }
        return []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                pagesView
                aiSection
                sentenceList("Added", sentences.added, color: .green)
                sentenceList("Removed", sentences.removed, color: .red)
            }
            .padding()
        }
        .navigationTitle(tr(change.title))
        .navigationBarTitleDisplayMode(.inline)
        .themedBackground()
        .task {
            let comparison = comparison
            let change = change
            sentences = await Task.detached(priority: .userInitiated) { comparison.sentenceChanges(of: change) }.value
        }
        .task(id: offset) { await showPages() }
    }

    private var header: some View {
        HStack {
            Label(tr(change.kind.title), systemImage: change.kind.systemImage)
                .foregroundStyle(change.kind.color)
                .font(.headline)
            if change.kind == .changed {
                Text("about \(change.percentChanged)% changed").foregroundStyle(.secondary)
            }
            Spacer()
            Text(trMessage(change.pagesLabel)).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Pages

    private var pagesView: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    offset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(offset <= 0)
                Spacer()
                Text(trMessage(pageCaption)).font(.callout.monospacedDigit())
                Spacer()
                Button {
                    offset += 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(offset >= steps.count - 1)
            }
            .buttonStyle(.bordered)
            HStack(alignment: .top, spacing: 12) {
                pageColumn("Old", image: oldImage, missing: shownPages.old == nil)
                pageColumn("New", image: newImage, missing: shownPages.new == nil)
            }
            HStack(spacing: 16) {
                Label("Removed", systemImage: "square.fill").foregroundStyle(.red)
                Label("Added", systemImage: "square.fill").foregroundStyle(.green)
            }
            .font(.caption)
        }
        .padding(12)
        .themedCard()
    }

    private var pageCaption: String {
        let oldText: String = shownPages.old.map { "old p. \($0 + 1)" } ?? "not in old"
        let newText: String = shownPages.new.map { "new p. \($0 + 1)" } ?? "not in new"
        return "\(oldText)  ·  \(newText)"
    }

    private func pageColumn(_ title: String, image: UIImage?, missing: Bool) -> some View {
        VStack(spacing: 6) {
            Text(tr(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .aspectRatio(0.75, contentMode: .fit)
                    .overlay {
                        if missing {
                            Text("No matching page").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func showPages() async {
        guard offset >= 0, offset < steps.count else { return }
        let step = steps[offset]
        var oldPage: Int?
        var newPage: Int?
        if change.new != nil {
            newPage = step
            let range: ClosedRange<Int>? = change.old.map { $0.firstPage...$0.lastPage }
            oldPage = change.old == nil ? nil : comparison.oldPage(matching: step, in: range)
        } else {
            oldPage = step
        }
        shownPages = (oldPage, newPage)
        oldImage = nil
        newImage = nil
        let oldText: String = oldPage.map { comparison.oldPages[$0] } ?? ""
        let newText: String = newPage.map { comparison.newPages[$0] } ?? ""
        let old = old
        let new = new
        let images = await Task.detached(priority: .userInitiated) { () -> (UIImage?, UIImage?) in
            // The page's own text (not trimmed), so marked places line up.
            let oldPDFPage = oldPage.flatMap { old.page(at: $0) }
            let newPDFPage = newPage.flatMap { new.page(at: $0) }
            let changes = EditionCompare.wordChanges(old: oldPDFPage?.string ?? oldText, new: newPDFPage?.string ?? newText)
            let oldPicture = oldPDFPage.map { EditionCompare.image(of: $0, marking: newPDFPage == nil ? [] : changes.removed, color: .systemRed) }
            let newPicture = newPDFPage.map { EditionCompare.image(of: $0, marking: oldPDFPage == nil ? [] : changes.added, color: .systemGreen) }
            return (oldPicture, newPicture)
        }.value
        guard !Task.isCancelled else { return }
        oldImage = images.0
        newImage = images.1
    }

    // MARK: AI

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("What Changed (AI)", systemImage: "sparkles").font(.headline)
                Spacer()
                if isExplaining {
                    ProgressView()
                } else if explanation == nil {
                    Button("Explain") { explain() }
                        .buttonStyle(.borderedProminent)
                        .disabled(ai.problem != nil || change.kind == .same)
                }
            }
            if ai.problem != nil {
                Text("Set up an AI service in AI Settings to explain the changes.").font(.caption).foregroundStyle(.secondary)
            }
            if let problem {
                Text(trMessage(problem)).font(.caption).foregroundStyle(.red)
            }
            if let explanation {
                Text(LocalizedStringKey(explanation)).font(.callout).textSelection(.enabled)
                Button {
                    let text = "From [[\(comparison.oldTitle)]] to [[\(comparison.newTitle)]]. #editions\n\n\(explanation)"
                    if store.createTextNote(titled: "Changes: \(change.title)", in: nil, extraText: text) != nil {
                        CommandCenter.shared.say("Saved as a text note")
                    }
                } label: {
                    Label("Save as Note", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
            } else {
                Text("Only the changed sentences of this chapter are sent, if the AI Firewall allows it for both books.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .themedCard()
    }

    private func explain() {
        guard let client = ai.client() else { return }
        let onDevice = client.kind.isOnDevice
        for id in [oldNoteID, newNoteID].compactMap({ $0 }) where !store.mayUseAI(id, onDevice: onDevice) {
            problem = NoteTexts.firewallMessage(onDevice: onDevice)
            return
        }
        let prompt = EditionCompare.aiPrompt(for: change, in: comparison)
        problem = nil
        isExplaining = true
        Task {
            defer { isExplaining = false }
            do {
                explanation = try await client.complete(system: "You explain changes between book editions to students.", messages: [AIMessage(.user, prompt)])
            } catch {
                problem = "Couldn't explain: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Sentences

    @ViewBuilder
    private func sentenceList(_ title: String, _ items: [String], color: Color) -> some View {
        if !items.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { item in
                        Text(tr(item.element))
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("\(title) sentences (\(items.count))", systemImage: color == .green ? "plus" : "minus")
                    .foregroundStyle(color)
                    .font(.headline)
            }
            .padding(12)
            .themedCard()
        }
    }
}
