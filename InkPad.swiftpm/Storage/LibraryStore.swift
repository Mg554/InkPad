import Foundation
import PencilKit
import UIKit

enum StoreError: LocalizedError {
    case newerFormat(file: String, version: Int)
    case noteNotFound
    case invalidPDFReference(String)
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case let .newerFormat(file, version):
            "\(file) was written by a newer version of InkPad (format \(version))."
        case .noteNotFound:
            "This note no longer exists."
        case let .invalidPDFReference(name):
            "note.json refers to an invalid PDF file name (\(name))."
        case .unreadableImage:
            "The image could not be read."
        }
    }
}

/// File names inside a note's folder.
private enum NoteFiles {
    static let metadataFile = "note.json"
    static let drawingFile = "drawing.data"
    static let thumbnailFile = "thumbnail.png"
    static let pdfFile = "document.pdf"
    static let markdownFile = "note.md"
    static let audioFolder = "audio"
    static let textFile = "text.json"
}

/// What the library knows about a text note's contents, read from its
/// Markdown when the library opens and after every save.
struct TextNoteInfo: Equatable {
    var text: String
    var links: [NoteLinks.Link]
    var tags: [String]

    init(text: String) {
        self.text = text
        links = NoteLinks.links(in: text)
        tags = NoteLinks.tags(in: text)
    }

    /// The first lines without Markdown heading marks, for cards.
    var preview: String {
        String(text.prefix(400))
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(8)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .joined(separator: "\n")
    }
}

/// Owns everything InkPad stores on disk.
///
/// Layout under `Documents/InkPad/`:
/// - `library.json`: folders and note summaries
/// - `notes/<id>/note.json`: per-note metadata
/// - `notes/<id>/drawing.data`: PencilKit drawing
/// - `notes/<id>/document.pdf`: imported PDF (PDF notes only, never modified)
/// - `notes/<id>/images/<name>.jpg`: images placed on the pages
/// - `notes/<id>/thumbnail.png`: first-page preview (derived, safe to lose)
/// - `notes/<id>/note.md`: a text note's Markdown
/// - `notes/<id>/audio/<name>.m4a`: audio recordings (written by the recorder)
/// - `notes/<id>/text.json`: handwriting and PDF text read with Vision
///   (derived, safe to lose; used by search and AI study)
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var folders: [Folder] = []
    @Published private(set) var notes: [NoteSummary] = []
    @Published var errorMessage: String?
    /// Set when the existing library could not be read safely. Writes are
    /// refused so the unreadable data is never overwritten.
    @Published private(set) var isReadOnly = false
    /// Contents of text notes, for links, backlinks, tags, search and previews.
    @Published private(set) var textIndex: [UUID: TextNoteInfo] = [:]
    @Published private(set) var customTemplates: [TextTemplate] = []
    /// Recognized handwriting of handwritten notes, for search.
    @Published private(set) var recognizedText: [UUID: String] = [:]

    private let rootURL: URL
    private let fileManager = FileManager.default
    /// Note files are written here, off the main thread, one save at a time.
    private let writeQueue = DispatchQueue(label: "InkPad.noteWrites", qos: .userInitiated)

    private var indexURL: URL { rootURL.appendingPathComponent("library.json") }

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InkPad", isDirectory: true)
        loadIndex()
        loadTextIndex()
        loadRecognizedText()
    }

    // MARK: Queries

    func note(_ id: UUID) -> NoteSummary? {
        notes.first { $0.id == id }
    }

    func folder(_ id: UUID) -> Folder? {
        folders.first { $0.id == id }
    }

    func notes(in scope: LibraryScope) -> [NoteSummary] {
        let matching: [NoteSummary]
        switch scope {
        case .allNotes: matching = notes
        case .unfiled: matching = notes.filter { $0.folderID == nil }
        case .planner, .expenses, .mindMaps, .slides, .study, .graph: matching = []
        case let .tag(tag):
            let key = NoteLinks.key(tag)
            matching = notes.filter { tags(of: $0).contains { NoteLinks.key($0) == key } }
        case let .folder(id): matching = notes.filter { $0.folderID == id }
        }
        return matching.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Library tags plus, for text notes, the #tags in the text.
    func tags(of note: NoteSummary) -> [String] {
        var seen: Set<String> = []
        return ((note.tags ?? []) + (textIndex[note.id]?.tags ?? [])).filter { seen.insert(NoteLinks.key($0)).inserted }
    }

    var allTags: [String] {
        var seen: Set<String> = []
        return notes.flatMap { tags(of: $0) }
            .filter { seen.insert(NoteLinks.key($0)).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Title, tags, and for text notes the whole text.
    func matches(_ note: NoteSummary, search: String) -> Bool {
        note.title.localizedCaseInsensitiveContains(search)
            || tags(of: note).contains { $0.localizedCaseInsensitiveContains(search.trimmingCharacters(in: CharacterSet(charactersIn: "#"))) }
            || (textIndex[note.id]?.text.localizedCaseInsensitiveContains(search) ?? false)
            || (recognizedText[note.id]?.localizedCaseInsensitiveContains(search) ?? false)
    }

    func note(titled title: String) -> NoteSummary? {
        let key = NoteLinks.key(title)
        return notes.first { NoteLinks.key($0.title) == key }
    }

    /// Notes whose text links to this note, with the line of each mention.
    func backlinks(to id: UUID) -> [(note: NoteSummary, line: String)] {
        guard let target = note(id) else { return [] }
        let key = NoteLinks.key(target.title)
        return notes.compactMap { other -> (note: NoteSummary, line: String)? in
            guard other.id != id, let info = textIndex[other.id],
                  info.links.contains(where: { NoteLinks.key($0.title) == key })
            else { return nil }
            let line = info.text
                .split(separator: "\n")
                .first { line in NoteLinks.links(in: String(line)).contains { NoteLinks.key($0.title) == key } }
            return (other, line.map(String.init) ?? "")
        }
        .sorted { $0.note.modifiedAt > $1.note.modifiedAt }
    }

    func setTags(_ tags: [String], for id: UUID) {
        guard canWrite(), let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].tags = tags.isEmpty ? nil : tags
        saveIndex()
    }

    func thumbnail(for id: UUID) -> UIImage? {
        UIImage(contentsOfFile: noteDirectory(id).appendingPathComponent(NoteFiles.thumbnailFile).path)
    }

    // MARK: Folders

    /// Folders in tree order. A folder whose parent is missing is shown at the
    /// top level, and its stored `parentID` is kept as-is.
    func folderTree(expanded: Set<UUID>? = nil) -> [FolderRow] {
        let ids = Set(folders.map(\.id))
        var children: [UUID?: [Folder]] = [:]
        for folder in folders {
            let parent = folder.parentID.flatMap { ids.contains($0) ? $0 : nil }
            children[parent, default: []].append(folder)
        }
        var rows: [FolderRow] = []
        var visited: Set<UUID> = []
        func visit(_ parent: UUID?, depth: Int) {
            let sorted = (children[parent] ?? []).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            for folder in sorted where visited.insert(folder.id).inserted {
                let hasChildren = !(children[folder.id] ?? []).isEmpty
                rows.append(FolderRow(folder: folder, depth: depth, hasChildren: hasChildren))
                if expanded?.contains(folder.id) ?? true {
                    visit(folder.id, depth: depth + 1)
                }
            }
        }
        visit(nil, depth: 0)
        return rows
    }

    @discardableResult
    func createFolder(named name: String, in parentID: UUID? = nil) -> Folder? {
        guard canWrite() else { return nil }
        let parent = parentID.flatMap { folder($0) }
        let newFolder = Folder(name: cleaned(name, fallback: "New Folder"), parentID: parent?.id, color: parent?.color)
        folders.append(newFolder)
        saveIndex()
        return newFolder
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard canWrite(), let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = cleaned(name, fallback: folders[index].name)
        saveIndex()
    }

    func setFolderColor(_ id: UUID, to color: FolderColor?) {
        guard canWrite(), let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].color = color
        saveIndex()
    }

    /// Deletes the folder only. Its notes and subfolders move to its parent
    /// (or to the top level / Unfiled).
    func deleteFolder(_ id: UUID) {
        guard canWrite(), let deleted = folder(id) else { return }
        folders.removeAll { $0.id == id }
        for index in folders.indices where folders[index].parentID == id {
            folders[index].parentID = deleted.parentID
        }
        for index in notes.indices where notes[index].folderID == id {
            notes[index].folderID = deleted.parentID
        }
        saveIndex()
    }

    // MARK: Notes

    func createNote(in folderID: UUID?, template: PageTemplate, paper: PaperColor = .white) -> NoteSummary? {
        guard canWrite() else { return nil }
        let now = Date()
        let id = UUID()
        var metadata = NoteMetadata(template: template)
        metadata.paperColor = paper == .white ? nil : paper
        let content = NoteContent(
            metadata: metadata,
            drawing: PKDrawing(),
            pdf: nil,
            directory: noteDirectory(id)
        )
        do {
            try Self.write(content, thumbnail: true)
        } catch {
            try? fileManager.removeItem(at: noteDirectory(id))
            errorMessage = "Could not create the note: \(error.localizedDescription)"
            return nil
        }
        return addNote(id: id, title: "Note \(now.formatted(date: .abbreviated, time: .shortened))", folderID: folderID)
    }

    /// Copies the PDF into a new note; the original file is left untouched.
    func importPDF(from sourceURL: URL, into folderID: UUID?) -> NoteSummary? {
        guard canWrite() else { return nil }
        let id = UUID()
        let directory = noteDirectory(id)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let pdfURL = directory.appendingPathComponent(NoteFiles.pdfFile)
            let isScoped = sourceURL.startAccessingSecurityScopedResource()
            defer { if isScoped { sourceURL.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(at: sourceURL, to: pdfURL)
            let content = NoteContent(
                metadata: NoteMetadata(template: .blank, pageCount: 0, pdfFile: NoteFiles.pdfFile),
                drawing: PKDrawing(),
                pdf: try PDFBackground(url: pdfURL),
                directory: directory
            )
            try Self.write(content, thumbnail: true)
        } catch {
            try? fileManager.removeItem(at: directory)
            errorMessage = "Could not import the PDF: \(error.localizedDescription)"
            return nil
        }
        let title = sourceURL.deletingPathExtension().lastPathComponent
        return addNote(id: id, title: cleaned(title, fallback: "Imported PDF"), folderID: folderID)
    }

    // MARK: Text notes

    var templates: [TextTemplate] { TextTemplate.builtIns + customTemplates }

    func createTextNote(titled title: String, template: TextTemplate? = nil, in folderID: UUID?, extraText: String = "") -> NoteSummary? {
        guard canWrite() else { return nil }
        let id = UUID()
        let name = cleaned(title, fallback: "Untitled")
        let body = (template?.filled(title: name) ?? "# \(name)\n\n") + extraText
        do {
            try writeMarkdown(body, for: id)
        } catch {
            try? fileManager.removeItem(at: noteDirectory(id))
            errorMessage = "Could not create the note: \(error.localizedDescription)"
            return nil
        }
        textIndex[id] = TextNoteInfo(text: body)
        return addNote(id: id, title: name, folderID: folderID, kind: .text)
    }

    func loadMarkdown(for id: UUID) throws -> String {
        guard note(id)?.isText == true else { throw StoreError.noteNotFound }
        return try String(contentsOf: noteDirectory(id).appendingPathComponent(NoteFiles.markdownFile), encoding: .utf8)
    }

    @discardableResult
    func saveMarkdown(_ text: String, for id: UUID) -> Bool {
        guard canWrite(), let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        do {
            try writeMarkdown(text, for: id)
        } catch {
            errorMessage = "Could not save the note: \(error.localizedDescription)"
            return false
        }
        textIndex[id] = TextNoteInfo(text: text)
        notes[index].modifiedAt = Date()
        saveIndex()
        return true
    }

    /// Opens today's note in "Daily Notes", creating both if needed.
    /// `tasks` (from the planner) are listed in a new note.
    func dailyNote(for date: Date = Date(), tasks: [String] = []) -> NoteSummary? {
        let title = date.formatted(.iso8601.year().month().day())
        let folder = folders.first { $0.parentID == nil && $0.name == "Daily Notes" }
            ?? createFolder(named: "Daily Notes")
        if let existing = notes.first(where: { $0.title == title && $0.folderID == folder?.id }) {
            return existing
        }
        let template = templates.first { $0.id == TextTemplate.dailyNoteID }
        let taskList = tasks.isEmpty ? "" : "\n## Today's Tasks\n" + tasks.map { "- [ ] \($0)" }.joined(separator: "\n") + "\n"
        return createTextNote(titled: title, template: template, in: folder?.id, extraText: taskList)
    }

    func saveTemplate(named name: String, body: String) {
        guard canWrite() else { return }
        customTemplates.append(TextTemplate(name: cleaned(name, fallback: "My Template"), body: body))
        saveIndex()
    }

    func deleteTemplate(_ id: UUID) {
        guard canWrite() else { return }
        customTemplates.removeAll { $0.id == id }
        saveIndex()
    }

    private func writeMarkdown(_ text: String, for id: UUID) throws {
        let directory = noteDirectory(id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(NoteFiles.markdownFile), options: .atomic)
    }

    private func loadTextIndex() {
        var index: [UUID: TextNoteInfo] = [:]
        for note in notes where note.isText {
            if let text = try? String(contentsOf: noteDirectory(note.id).appendingPathComponent(NoteFiles.markdownFile), encoding: .utf8) {
                index[note.id] = TextNoteInfo(text: text)
            }
        }
        textIndex = index
    }

    /// Renames the note and, like Obsidian, updates [[links]] to it in text notes.
    func renameNote(_ id: UUID, to title: String) {
        guard canWrite(), let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let oldTitle = notes[index].title
        let newTitle = cleaned(title, fallback: oldTitle)
        notes[index].title = newTitle
        saveIndex()
        guard NoteLinks.key(oldTitle) != NoteLinks.key(newTitle) else { return }
        let oldKey = NoteLinks.key(oldTitle)
        for (otherID, info) in textIndex where otherID != id {
            let written = Set(info.links.map(\.title).filter { NoteLinks.key($0) == oldKey })
            guard !written.isEmpty else { continue }
            var text = info.text
            for spelling in written {
                text = text
                    .replacingOccurrences(of: "[[\(spelling)]]", with: "[[\(newTitle)]]")
                    .replacingOccurrences(of: "[[\(spelling)|", with: "[[\(newTitle)|")
            }
            saveMarkdown(text, for: otherID)
        }
    }

    func moveNote(_ id: UUID, to folderID: UUID?) {
        guard canWrite(), let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].folderID = folderID
        saveIndex()
    }

    /// Removes the note's files first; the note stays in the library if that fails.
    func deleteNote(_ id: UUID) {
        guard canWrite() else { return }
        let directory = noteDirectory(id)
        if fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.removeItem(at: directory)
            } catch {
                errorMessage = "Could not delete the note: \(error.localizedDescription)"
                return
            }
        }
        notes.removeAll { $0.id == id }
        textIndex[id] = nil
        recognizedText[id] = nil
        saveIndex()
    }

    func loadContent(for id: UUID) throws -> NoteContent {
        guard note(id) != nil else { throw StoreError.noteNotFound }
        let directory = noteDirectory(id)
        let metadataData = try Data(contentsOf: directory.appendingPathComponent(NoteFiles.metadataFile))
        let metadata = try JSONDecoder.inkpad.decode(NoteMetadata.self, from: metadataData)
        guard metadata.version <= NoteMetadata.currentVersion else {
            throw StoreError.newerFormat(file: NoteFiles.metadataFile, version: metadata.version)
        }
        let drawingData = try Data(contentsOf: directory.appendingPathComponent(NoteFiles.drawingFile))
        var pdf: PDFBackground?
        if let pdfFile = metadata.pdfFile {
            // Only a plain file name inside the note's own folder is accepted.
            guard isPlainFileName(pdfFile) else { throw StoreError.invalidPDFReference(pdfFile) }
            pdf = try PDFBackground(url: directory.appendingPathComponent(pdfFile))
        }
        return NoteContent(
            metadata: metadata,
            drawing: try PKDrawing(data: drawingData),
            pdf: pdf,
            directory: directory
        )
    }

    /// Writes the note off the main thread. Returns `false` when nothing was
    /// written, so the caller keeps its unsaved changes.
    func saveContent(_ content: NoteContent, for id: UUID, thumbnail: Bool) async -> Bool {
        guard canWrite(), note(id) != nil else { return false }
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            writeQueue.async {
                continuation.resume(returning: Result { try Self.write(content, thumbnail: thumbnail) })
            }
        }
        switch result {
        case .success:
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].modifiedAt = Date()
                saveIndex()
            }
            return true
        case let .failure(error):
            errorMessage = "Could not save the note: \(error.localizedDescription)"
            return false
        }
    }

    /// Stores an image for placing on a page. Returns its file name and pixel size.
    func addImage(_ data: Data, to id: UUID) async -> (file: String, size: CGSize)? {
        guard canWrite(), note(id) != nil else { return nil }
        let directory = noteDirectory(id).appendingPathComponent("images", isDirectory: true)
        let result: Result<(String, CGSize), Error> = await withCheckedContinuation { continuation in
            writeQueue.async {
                continuation.resume(returning: Result { try Self.writeImage(data, to: directory) })
            }
        }
        switch result {
        case let .success((file, size)):
            return (file, size)
        case let .failure(error):
            errorMessage = "Could not add the image: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Audio

    /// Where the recorder writes a note's audio.
    func audioDirectory(for id: UUID) -> URL {
        noteDirectory(id).appendingPathComponent(NoteFiles.audioFolder, isDirectory: true)
    }

    func deleteAudioFile(_ file: String, for id: UUID) {
        guard canWrite(), isPlainFileName(file) else { return }
        try? fileManager.removeItem(at: audioDirectory(for: id).appendingPathComponent(file))
    }

    /// A copy of the recording named after the note, for sharing.
    func exportedAudioURL(_ recording: AudioRecording, of id: UUID) -> URL? {
        guard isPlainFileName(recording.file) else { return nil }
        let source = audioDirectory(for: id).appendingPathComponent(recording.file)
        let name = exportFileName("\(note(id)?.title ?? "Note") - \(recording.title)", fallback: "Recording")
        let target = fileManager.temporaryDirectory.appendingPathComponent(name).appendingPathExtension("m4a")
        do {
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: source, to: target)
            return target
        } catch {
            errorMessage = "Could not share the recording: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Recognized text

    private struct RecognizedText: Codable {
        /// When it was read, as seconds since 2001.
        var readAt: TimeInterval
        var text: String
    }

    /// The note's recognized text, if it was read since the note last changed.
    func cachedRecognizedText(for id: UUID) -> String? {
        guard let note = note(id),
              let data = try? Data(contentsOf: noteDirectory(id).appendingPathComponent(NoteFiles.textFile)),
              let saved = try? JSONDecoder().decode(RecognizedText.self, from: data),
              saved.readAt + 1 >= note.modifiedAt.timeIntervalSinceReferenceDate
        else { return nil }
        return saved.text
    }

    func saveRecognizedText(_ text: String, for id: UUID) {
        guard !isReadOnly, note(id) != nil else { return }
        let saved = RecognizedText(readAt: Date().timeIntervalSinceReferenceDate, text: text)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: noteDirectory(id).appendingPathComponent(NoteFiles.textFile), options: .atomic)
        recognizedText[id] = text
    }

    private func loadRecognizedText() {
        var index: [UUID: String] = [:]
        for note in notes where !note.isText {
            if let data = try? Data(contentsOf: noteDirectory(note.id).appendingPathComponent(NoteFiles.textFile)),
               let saved = try? JSONDecoder().decode(RecognizedText.self, from: data) {
                index[note.id] = saved.text
            }
        }
        recognizedText = index
    }

    // MARK: Persistence

    func noteDirectory(_ id: UUID) -> URL {
        rootURL
            .appendingPathComponent("notes", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func addNote(id: UUID, title: String, folderID: UUID?, kind: NoteKind? = nil) -> NoteSummary {
        let now = Date()
        let summary = NoteSummary(id: id, title: title, folderID: folderID, createdAt: now, modifiedAt: now, kind: kind)
        notes.append(summary)
        saveIndex()
        return summary
    }

    private nonisolated static func write(_ content: NoteContent, thumbnail: Bool) throws {
        let directory = content.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try content.drawing.dataRepresentation()
            .write(to: directory.appendingPathComponent(NoteFiles.drawingFile), options: .atomic)
        try JSONEncoder.inkpad.encode(content.metadata)
            .write(to: directory.appendingPathComponent(NoteFiles.metadataFile), options: .atomic)
        // The thumbnail is derived data; failing to write it must not fail the save.
        if thumbnail, let png = ThumbnailRenderer.pngData(for: content) {
            try? png.write(to: directory.appendingPathComponent(NoteFiles.thumbnailFile), options: .atomic)
        }
    }

    /// Downscales large photos so pages stay responsive; keeps the aspect ratio.
    private nonisolated static func writeImage(_ data: Data, to directory: URL) throws -> (String, CGSize) {
        guard let image = UIImage(data: data) else { throw StoreError.unreadableImage }
        let maxSide: CGFloat = 2048
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor = min(1, maxSide / max(pixelSize.width, pixelSize.height))
        let size = CGSize(width: (pixelSize.width * factor).rounded(), height: (pixelSize.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { throw StoreError.unreadableImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = UUID().uuidString + ".jpg"
        try jpeg.write(to: directory.appendingPathComponent(file), options: .atomic)
        return (file, size)
    }

    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        do {
            let index = try JSONDecoder.inkpad.decode(LibraryIndex.self, from: Data(contentsOf: indexURL))
            guard index.version <= LibraryIndex.currentVersion else {
                throw StoreError.newerFormat(file: "library.json", version: index.version)
            }
            folders = index.folders
            notes = index.notes
            customTemplates = index.textTemplates ?? []
        } catch {
            isReadOnly = true
            errorMessage = "Your library could not be read (\(error.localizedDescription)). "
                + "InkPad opened read-only so nothing is overwritten."
        }
    }

    private func saveIndex() {
        let index = LibraryIndex(
            version: LibraryIndex.currentVersion,
            folders: folders,
            notes: notes,
            textTemplates: customTemplates.isEmpty ? nil : customTemplates
        )
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try JSONEncoder.inkpad.encode(index).write(to: indexURL, options: .atomic)
        } catch {
            errorMessage = "Could not save the library: \(error.localizedDescription)"
        }
    }

    private func canWrite() -> Bool {
        if isReadOnly {
            errorMessage = "The library is read-only because it could not be read safely."
        }
        return !isReadOnly
    }

    private func cleaned(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

extension JSONEncoder {
    static var inkpad: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var inkpad: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
