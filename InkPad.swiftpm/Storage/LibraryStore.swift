import Foundation
import PencilKit
import UIKit

enum StoreError: LocalizedError {
    case newerFormat(file: String, version: Int)
    case noteNotFound
    case invalidPDFReference(String)

    var errorDescription: String? {
        switch self {
        case let .newerFormat(file, version):
            "\(file) was written by a newer version of InkPad (format \(version))."
        case .noteNotFound:
            "This note no longer exists."
        case let .invalidPDFReference(name):
            "note.json refers to an invalid PDF file name (\(name))."
        }
    }
}

/// Owns everything InkPad stores on disk.
///
/// Layout under `Documents/InkPad/`:
/// - `library.json`: folders and note summaries
/// - `notes/<id>/note.json`: per-note metadata
/// - `notes/<id>/drawing.data`: PencilKit drawing
/// - `notes/<id>/document.pdf`: imported PDF (PDF notes only, never modified)
/// - `notes/<id>/thumbnail.png`: first-page preview (derived, safe to lose)
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var folders: [Folder] = []
    @Published private(set) var notes: [NoteSummary] = []
    @Published var errorMessage: String?
    /// Set when the existing library could not be read safely. Writes are
    /// refused so the unreadable data is never overwritten.
    @Published private(set) var isReadOnly = false

    private static let metadataFile = "note.json"
    private static let drawingFile = "drawing.data"
    private static let thumbnailFile = "thumbnail.png"
    private static let pdfFile = "document.pdf"

    private let rootURL: URL
    private let fileManager = FileManager.default

    private var indexURL: URL { rootURL.appendingPathComponent("library.json") }

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InkPad", isDirectory: true)
        loadIndex()
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
        case let .folder(id): matching = notes.filter { $0.folderID == id }
        }
        return matching.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func thumbnail(for id: UUID) -> UIImage? {
        UIImage(contentsOfFile: noteDirectory(id).appendingPathComponent(Self.thumbnailFile).path)
    }

    // MARK: Folders

    @discardableResult
    func createFolder(named name: String) -> Folder? {
        guard canWrite() else { return nil }
        let folder = Folder(name: cleaned(name, fallback: "New Folder"))
        folders.append(folder)
        saveIndex()
        return folder
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard canWrite(), let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = cleaned(name, fallback: folders[index].name)
        saveIndex()
    }

    /// Deletes the folder only. Its notes move to Unfiled.
    func deleteFolder(_ id: UUID) {
        guard canWrite() else { return }
        folders.removeAll { $0.id == id }
        for index in notes.indices where notes[index].folderID == id {
            notes[index].folderID = nil
        }
        saveIndex()
    }

    // MARK: Notes

    func createNote(in folderID: UUID?, template: PageTemplate) -> NoteSummary? {
        guard canWrite() else { return nil }
        let now = Date()
        let id = UUID()
        let content = NoteContent(metadata: NoteMetadata(template: template), drawing: PKDrawing(), pdf: nil)
        do {
            try writeContent(content, for: id)
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
            let pdfURL = directory.appendingPathComponent(Self.pdfFile)
            let isScoped = sourceURL.startAccessingSecurityScopedResource()
            defer { if isScoped { sourceURL.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(at: sourceURL, to: pdfURL)
            let content = NoteContent(
                metadata: NoteMetadata(template: .blank, pageCount: 0, pdfFile: Self.pdfFile),
                drawing: PKDrawing(),
                pdf: try PDFBackground(url: pdfURL)
            )
            try writeContent(content, for: id)
        } catch {
            try? fileManager.removeItem(at: directory)
            errorMessage = "Could not import the PDF: \(error.localizedDescription)"
            return nil
        }
        let title = sourceURL.deletingPathExtension().lastPathComponent
        return addNote(id: id, title: cleaned(title, fallback: "Imported PDF"), folderID: folderID)
    }

    func renameNote(_ id: UUID, to title: String) {
        guard canWrite(), let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].title = cleaned(title, fallback: notes[index].title)
        saveIndex()
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
        saveIndex()
    }

    func loadContent(for id: UUID) throws -> NoteContent {
        guard note(id) != nil else { throw StoreError.noteNotFound }
        let directory = noteDirectory(id)
        let metadataData = try Data(contentsOf: directory.appendingPathComponent(Self.metadataFile))
        let metadata = try JSONDecoder.inkpad.decode(NoteMetadata.self, from: metadataData)
        guard metadata.version <= NoteMetadata.currentVersion else {
            throw StoreError.newerFormat(file: Self.metadataFile, version: metadata.version)
        }
        let drawingData = try Data(contentsOf: directory.appendingPathComponent(Self.drawingFile))
        var pdf: PDFBackground?
        if let pdfFile = metadata.pdfFile {
            // Only a plain file name inside the note's own folder is accepted.
            guard !pdfFile.isEmpty, (pdfFile as NSString).lastPathComponent == pdfFile, pdfFile != ".." else {
                throw StoreError.invalidPDFReference(pdfFile)
            }
            pdf = try PDFBackground(url: directory.appendingPathComponent(pdfFile))
        }
        return NoteContent(metadata: metadata, drawing: try PKDrawing(data: drawingData), pdf: pdf)
    }

    /// Returns `false` when nothing was written, so the caller keeps its unsaved changes.
    @discardableResult
    func saveContent(_ content: NoteContent, for id: UUID) -> Bool {
        guard canWrite(), let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        do {
            try writeContent(content, for: id)
        } catch {
            errorMessage = "Could not save the note: \(error.localizedDescription)"
            return false
        }
        notes[index].modifiedAt = Date()
        saveIndex()
        return true
    }

    // MARK: Persistence

    private func noteDirectory(_ id: UUID) -> URL {
        rootURL
            .appendingPathComponent("notes", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func addNote(id: UUID, title: String, folderID: UUID?) -> NoteSummary {
        let now = Date()
        let summary = NoteSummary(id: id, title: title, folderID: folderID, createdAt: now, modifiedAt: now)
        notes.append(summary)
        saveIndex()
        return summary
    }

    private func writeContent(_ content: NoteContent, for id: UUID) throws {
        let directory = noteDirectory(id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try content.drawing.dataRepresentation()
            .write(to: directory.appendingPathComponent(Self.drawingFile), options: .atomic)
        try JSONEncoder.inkpad.encode(content.metadata)
            .write(to: directory.appendingPathComponent(Self.metadataFile), options: .atomic)
        // The thumbnail is derived data; failing to write it must not fail the save.
        if let thumbnail = ThumbnailRenderer.pngData(for: content) {
            try? thumbnail.write(to: directory.appendingPathComponent(Self.thumbnailFile), options: .atomic)
        }
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
        } catch {
            isReadOnly = true
            errorMessage = "Your library could not be read (\(error.localizedDescription)). "
                + "InkPad opened read-only so nothing is overwritten."
        }
    }

    private func saveIndex() {
        let index = LibraryIndex(version: LibraryIndex.currentVersion, folders: folders, notes: notes)
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
