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
    /// The content the canvas is created from.
    private(set) var initialContent: NoteContent?

    let canvas = CanvasController()

    static let autosaveDelay: Duration = .seconds(2)

    private var store: LibraryStore?
    private(set) var noteID: UUID?
    /// Metadata, PDF and folder; ink and elements are taken from the canvas.
    private var baseContent: NoteContent?
    private var editGeneration = 0
    private var savedGeneration = 0
    private var thumbnailGeneration = 0
    private var isSaving = false
    private var pendingSave: Bool?
    private var autosaveTask: Task<Void, Never>?

    func load(noteID: UUID, store: LibraryStore) {
        guard self.store == nil else { return }
        self.noteID = noteID
        self.store = store
        canvas.onEdit = { [weak self] in self?.markEdited() }
        do {
            let content = try store.loadContent(for: noteID)
            baseContent = content
            initialContent = content
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
