import PDFKit
import PencilKit
import SwiftUI

/// Owns one open note: loading, page settings, and saving.
///
/// Ink, text boxes and images live in the canvas views while editing and are
/// read from there when saving, so writing never re-renders SwiftUI views.
/// Autosave writes off the main thread after a pause; the library thumbnail is
/// only re-rendered when leaving the note.
@MainActor
final class EditorSession: ObservableObject {
    @Published private(set) var metadata: NoteMetadata?
    @Published private(set) var background: NoteBackground?
    @Published private(set) var loadError: String?
    /// The content as of the last save, for page thumbnails. Refreshed after
    /// each save rather than on every stroke.
    @Published private(set) var snapshot: NoteContent? {
        didSet { snapshotRevision += 1 }
    }
    @Published private(set) var snapshotRevision = 0
    /// The content the canvas is created from.
    private(set) var initialContent: NoteContent?

    let canvas = CanvasController()
    /// Recording and playback. Views observe it directly, so its frequent
    /// updates do not re-render the whole editor.
    let audio = AudioController()

    static let autosaveDelay: Duration = .seconds(2)

    private var store: LibraryStore?
    private(set) var noteID: UUID?
    /// Metadata, PDF and folder; ink and elements are taken from the canvas.
    private var baseContent: NoteContent?
    private var editGeneration = 0
    /// Something changed since the note was opened.
    var wasEdited: Bool { editGeneration > 0 }
    private var savedGeneration = 0
    private var thumbnailGeneration = 0
    private var isSaving = false
    private var pendingSave: Bool?
    private var autosaveTask: Task<Void, Never>?
    /// Old PDF files to remove once the note has been saved without them.
    private var replacedFiles: [URL] = []

    func load(noteID: UUID, store: LibraryStore) {
        guard self.store == nil else { return }
        self.noteID = noteID
        self.store = store
        canvas.onEdit = { [weak self] in self?.markEdited() }
        canvas.onInkTapped = { [weak self] date in self?.audio.play(from: date) }
        audio.onRecordingFinished = { [weak self] recording in self?.addRecording(recording) }
        audio.onPlaybackPosition = { [weak self] recording, time in
            self?.canvas.showReplay(of: recording, at: time)
        }
        audio.onError = { [weak store] message in store?.errorMessage = message }
        do {
            let content = try store.loadContent(for: noteID)
            baseContent = content
            initialContent = content
            snapshot = content
            metadata = content.metadata
            background = content.makeBackground()
        } catch {
            loadError = error.localizedDescription
        }
    }

    var imageDirectory: URL? { baseContent?.imageDirectory }

    func updateMetadata(_ change: (inout NoteMetadata) -> Void) {
        guard var content = baseContent else { return }
        change(&content.metadata)
        guard content.metadata != baseContent?.metadata else { return }
        baseContent = content
        metadata = content.metadata
        background = content.makeBackground()
        markEdited()
    }

    var pageCount: Int { background?.layout.pageRects.count ?? 0 }

    /// Inserts a paper page after `index`, moving later ink and elements down.
    func insertPage(after index: Int) {
        guard let content = baseContent, let rects = background?.layout.pageRects, rects.indices.contains(index) else { return }
        var pages = content.metadata.resolvedPages(pdfPageCount: content.pdf?.pageCount ?? 0)
        pages.insert(.paper, at: index + 1)
        canvas.shiftContent(
            below: rects[index].maxY + PageLayout.pageGap / 2,
            by: PageLayout.templatePageSize.height + PageLayout.pageGap,
            removing: nil
        )
        setPages(pages)
        scrollAfterLayout(to: index + 1)
    }

    /// Deletes a page and what is written on it; later pages move up.
    /// The imported PDF file itself is never changed.
    func deletePage(at index: Int) {
        guard let content = baseContent, let rects = background?.layout.pageRects,
              rects.count > 1, rects.indices.contains(index) else { return }
        var pages = content.metadata.resolvedPages(pdfPageCount: content.pdf?.pageCount ?? 0)
        pages.remove(at: index)
        let rect = rects[index]
        let gap = PageLayout.pageGap
        canvas.shiftContent(
            below: rect.maxY + gap / 2,
            by: -(rect.height + gap),
            removing: (rect.minY - gap / 2)...(rect.maxY + gap / 2)
        )
        setPages(pages)
        scrollAfterLayout(to: min(index, pages.count - 1))
    }

    /// Moves a page to a new position, with what is written on it.
    func movePage(from source: Int, to destination: Int) {
        guard let content = baseContent, let rects = background?.layout.pageRects,
              rects.indices.contains(source), rects.indices.contains(destination), source != destination
        else { return }
        let pages = content.metadata.resolvedPages(pdfPageCount: content.pdf?.pageCount ?? 0)
        guard pages.count == rects.count else { return }
        var order = Array(rects.indices)
        order.insert(order.remove(at: source), at: destination)
        let newRects = PageLayout(pageSizes: order.map { rects[$0].size }).pageRects
        var newTop = Array(repeating: CGFloat(0), count: rects.count)
        for (newIndex, oldIndex) in order.enumerated() {
            newTop[oldIndex] = newRects[newIndex].minY
        }
        let gap = PageLayout.pageGap
        canvas.moveContent { y in
            // Content belongs to the page it is on, or the nearest one below
            // the gap; anything past the last page stays with it.
            let page = rects.firstIndex { y < $0.maxY + gap / 2 } ?? rects.count - 1
            return newTop[page] - rects[page].minY
        }
        setPages(order.map { pages[$0] })
        scrollAfterLayout(to: destination)
    }

    /// Puts pages of another PDF into this note after layout page `index`,
    /// moving later ink and elements down. The note gets a new PDF file
    /// with its old pages followed by the new ones.
    func insertPDFPages(_ newPages: [Int], from source: PDFDocument, after index: Int) throws {
        guard let content = baseContent, let rects = background?.layout.pageRects, !newPages.isEmpty else { return }
        let after = min(max(index, -1), rects.count - 1)
        let existing: PDFDocument? = content.pdf?.pdfDocument
        let oldCount: Int = content.pdf?.pageCount ?? 0
        let combined: PDFDocument = existing.map { PDFToolKit.document(with: Array(0..<oldCount), from: $0) } ?? PDFDocument()
        for page in newPages {
            guard let copy = source.page(at: page)?.copy() as? PDFPage else { continue }
            combined.insert(copy, at: combined.pageCount)
        }
        let fileName = "document-\(UUID().uuidString.prefix(8)).pdf"
        let url = content.directory.appendingPathComponent(fileName)
        guard combined.write(to: url) else { throw PDFToolError.cannotWrite }
        let pdf = try PDFBackground(url: url)

        var pages = content.metadata.resolvedPages(pdfPageCount: oldCount)
        let inserted: [PageSource] = (0..<newPages.count).map { PageSource.pdf(oldCount + $0) }
        pages.insert(contentsOf: inserted, at: after + 1)
        var metadata = content.metadata
        metadata.pdfFile = fileName
        metadata.pages = pages
        metadata.pageCount = pages.filter { $0 == .paper }.count
        let updated = NoteContent(metadata: metadata, drawing: content.drawing, pdf: pdf, directory: content.directory)
        let newRects = updated.makeBackground().layout.pageRects

        // Move what was written on later pages down by the room the new pages take.
        let firstLater = after + 1
        if firstLater < rects.count, firstLater + inserted.count < newRects.count {
            let shift: CGFloat = newRects[firstLater + inserted.count].minY - rects[firstLater].minY
            let below: CGFloat = after >= 0 ? rects[after].maxY + PageLayout.pageGap / 2 : rects[0].minY - PageLayout.pageGap / 2
            canvas.shiftContent(below: below, by: shift, removing: nil)
        }
        if let old = content.pdf?.fileURL { replacedFiles.append(old) }
        baseContent = updated
        self.metadata = metadata
        background = updated.makeBackground()
        markEdited()
        snapshot = currentContent()
        scrollAfterLayout(to: after + 1)
    }

    /// Keeps the page being read, and how far the reader got.
    func noteReadingPage(_ page: Int) {
        guard var content = baseContent else { return }
        let furthest = max(content.metadata.furthestPage ?? 0, page)
        guard content.metadata.readingPage != page || content.metadata.furthestPage != furthest else { return }
        // Only the reading place changes: no need to rebuild the pages.
        content.metadata.readingPage = page
        content.metadata.furthestPage = furthest
        baseContent = content
        metadata = content.metadata
        markEdited()
    }

    func setBookmarks(_ bookmarks: [NoteBookmark]) {
        updateMetadata { $0.bookmarks = bookmarks }
    }

    private func setPages(_ pages: [PageSource]) {
        updateMetadata {
            $0.pages = pages
            $0.pageCount = pages.filter { $0 == .paper }.count
        }
        snapshot = currentContent()
    }

    /// The canvas picks up the new pages on SwiftUI's next update.
    private func scrollAfterLayout(to index: Int) {
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            canvas.scrollToPage(index)
        }
    }

    // MARK: Audio

    var recordings: [AudioRecording] { metadata?.recordings ?? [] }

    func startRecording() {
        guard let noteID, let store else { return }
        guard !store.isReadOnly else {
            store.errorMessage = "The library is read-only because it could not be read safely."
            return
        }
        let directory = store.audioDirectory(for: noteID)
        Task { await self.audio.startRecording(into: directory) }
    }

    func openRecording(_ recording: AudioRecording) {
        guard let noteID, let store else { return }
        audio.open(recording, in: store.audioDirectory(for: noteID))
    }

    func renameRecording(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateMetadata { metadata in
            guard let index = metadata.recordings?.firstIndex(where: { $0.id == id }) else { return }
            metadata.recordings?[index].title = trimmed
        }
    }

    /// Deletes the audio; the ink written while recording stays.
    func deleteRecording(_ id: UUID) {
        guard let noteID, let store, !store.isReadOnly,
              let recording = recordings.first(where: { $0.id == id })
        else { return }
        if audio.current?.id == id { audio.closePlayer() }
        updateMetadata { metadata in
            metadata.recordings?.removeAll { $0.id == id }
            if metadata.recordings?.isEmpty == true { metadata.recordings = nil }
        }
        save(thumbnail: false)
        store.deleteAudioFile(recording.file, for: noteID)
    }

    private func addRecording(_ recording: AudioRecording) {
        var recording = recording
        recording.title = "Recording \(recordings.count + 1)"
        updateMetadata { $0.recordings = ($0.recordings ?? []) + [recording] }
        save(thumbnail: false)
    }

    // MARK: Saving

    /// Everything as it is on screen now.
    func currentContent() -> NoteContent? {
        guard var content = baseContent else { return nil }
        if let drawing = canvas.drawing { content.drawing = drawing }
        if let elements = canvas.elements { content.metadata.elements = elements }
        return content
    }

    func markEdited() {
        editGeneration += 1
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.save(thumbnail: false)
        }
    }

    func save(thumbnail: Bool) {
        autosaveTask?.cancel()
        let needsWrite = editGeneration != savedGeneration
        let needsThumbnail = thumbnail && thumbnailGeneration != editGeneration
        guard needsWrite || needsThumbnail else { return }
        guard !isSaving else {
            // Save again once the current write finishes.
            pendingSave = (pendingSave ?? false) || thumbnail
            return
        }
        guard let store, let noteID, let content = currentContent() else { return }

        isSaving = true
        let generation = editGeneration
        Task {
            let saved = await store.saveContent(content, for: noteID, thumbnail: needsThumbnail)
            isSaving = false
            if saved {
                for file in replacedFiles where file != content.pdf?.fileURL {
                    try? FileManager.default.removeItem(at: file)
                }
                replacedFiles = []
                snapshot = content
                savedGeneration = max(savedGeneration, generation)
                if needsThumbnail { thumbnailGeneration = generation }
            }
            if let pending = pendingSave {
                pendingSave = nil
                if saved { save(thumbnail: pending) }
            }
        }
    }
}
