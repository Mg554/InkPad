import CoreSpotlight
import UniformTypeIdentifiers

/// Keeps the library in the iPad's Spotlight search: notes appear by title
/// with a line of their content, and open InkPad when tapped. Locked notes
/// are never in the index — locking a note takes it out, unlocking puts it
/// back, and a re-locked (backgrounded) note leaves again.
@MainActor
enum SpotlightIndex {
    /// Groups every InkPad entry, so bulk operations can replace the domain.
    static let domain = "com.mg554.inkpad.notes"

    /// The latest indexing failure, shown when a rebuild is asked for.
    private(set) static var lastError: String?

    /// Adds or updates one note's entry. Call for unlocked notes only.
    static func update(_ note: NoteSummary, preview: String?) {
        index([item(for: note, preview: preview)])
    }

    /// Takes one note out of the index (it was locked, deleted or trashed).
    static func remove(_ id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString]) { error in
            record(error, "removing a note")
        }
    }

    /// Replaces the whole library's entries with the given unlocked notes.
    /// Returns a line for the owner: what happened.
    @discardableResult
    static func reindex(_ notes: [NoteSummary], previews: [UUID: String]) async -> String {
        let index = CSSearchableIndex.default()
        guard CSSearchableIndex.isIndexingAvailable() else {
            lastError = "Spotlight indexing is unavailable on this iPad right now"
            return trMessage("Spotlight search couldn't be rebuilt: \(tr(lastError!))")
        }
        let items = notes.map { item(for: $0, preview: previews[$0.id]) }
        do {
            try await run { index.deleteSearchableItems(withDomainIdentifiers: [domain], completionHandler: $0) }
            if !items.isEmpty {
                try await run { index.indexSearchableItems(items, completionHandler: $0) }
            }
            lastError = nil
            return trMessage("Spotlight search rebuilt: \(String(items.count)) notes")
        } catch {
            lastError = error.localizedDescription
            return trMessage("Spotlight search couldn't be rebuilt: \(error.localizedDescription)")
        }
    }

    // MARK: Pieces

    private static func item(for note: NoteSummary, preview: String?) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
        attributes.title = note.title
        if let preview, !preview.isEmpty {
            attributes.contentDescription = String(preview.prefix(200))
        }
        attributes.contentModificationDate = note.modifiedAt
        if let tags = note.tags, !tags.isEmpty {
            attributes.keywords = tags
        }
        let searchable = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attributes
        )
        searchable.expirationDate = .distantFuture
        return searchable
    }

    private static func index(_ items: [CSSearchableItem]) {
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            record(error, "adding a note")
        }
    }

    private static func run(_ body: (@escaping (Error?) -> Void) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            body { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Failures used to be swallowed; now they land in `lastError` (and the
    /// system log) so a stuck index can be diagnosed.
    private nonisolated static func record(_ error: Error?, _ what: String) {
        guard let error else { return }
        NSLog("InkPad Spotlight, %@: %@", what, error.localizedDescription)
        Task { @MainActor in lastError = error.localizedDescription }
    }
}
