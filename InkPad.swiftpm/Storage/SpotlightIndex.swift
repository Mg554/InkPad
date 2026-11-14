import CoreSpotlight
import UniformTypeIdentifiers

/// Keeps the library in the iPad's Spotlight search: notes appear by title
/// with a line of their content, and open InkPad when tapped. Locked notes
/// are never in the index — locking a note takes it out, unlocking puts it
/// back, and a re-locked (backgrounded) note leaves again.
enum SpotlightIndex {
    /// Groups every InkPad entry, so bulk operations can replace the domain.
    static let domain = "com.mg554.inkpad.notes"

    /// Adds or updates one note's entry. Call for unlocked notes only.
    static func update(_ note: NoteSummary, preview: String?) {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
        attributes.title = note.title
        if let preview, !preview.isEmpty {
            attributes.contentDescription = String(preview.prefix(200))
        }
        attributes.contentModificationDate = note.modifiedAt
        if let tags = note.tags, !tags.isEmpty {
            attributes.keywords = tags
        }
        let item = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attributes
        )
        item.expirationDate = .distantFuture
        CSSearchableIndex.default().indexSearchableItems([item], completionHandler: { _ in })
    }

    /// Takes one note out of the index (it was locked, deleted or trashed).
    static func remove(_ id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString], completionHandler: { _ in })
    }

    /// Replaces the whole library's entries with the given unlocked notes.
    static func reindex(_ notes: [NoteSummary], previews: [UUID: String]) {
        let items = notes.map { note -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
            attributes.title = note.title
            if let preview = previews[note.id], !preview.isEmpty {
                attributes.contentDescription = String(preview.prefix(200))
            }
            attributes.contentModificationDate = note.modifiedAt
            if let tags = note.tags, !tags.isEmpty {
                attributes.keywords = tags
            }
            let item = CSSearchableItem(
                uniqueIdentifier: note.id.uuidString,
                domainIdentifier: domain,
                attributeSet: attributes
            )
            item.expirationDate = .distantFuture
            return item
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain], completionHandler: { _ in
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items, completionHandler: { _ in })
        })
    }
}
