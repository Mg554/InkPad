import SwiftUI

/// Lets any view open a note, a [[link]] by title, or a #tag, without
/// knowing how the library navigates. Provided by `LibraryView`.
struct NoteNavigation {
    var openNote: (UUID) -> Void
    /// Opens the note with this title, creating a text note if none exists
    /// (like following an unresolved link in Obsidian).
    var openTitle: (String) -> Void
    var openTag: (String) -> Void

    init(
        openNote: @escaping (UUID) -> Void = { _ in },
        openTitle: @escaping (String) -> Void = { _ in },
        openTag: @escaping (String) -> Void = { _ in }
    ) {
        self.openNote = openNote
        self.openTitle = openTitle
        self.openTag = openTag
    }
}

private struct NoteNavigationKey: EnvironmentKey {
    static let defaultValue = NoteNavigation()
}

extension EnvironmentValues {
    var noteNavigation: NoteNavigation {
        get { self[NoteNavigationKey.self] }
        set { self[NoteNavigationKey.self] = newValue }
    }
}

/// `inkpad://note/<title>` and `inkpad://tag/<tag>` links inside rendered Markdown.
enum InkPadLink {
    static let scheme = "inkpad"

    static func note(_ title: String) -> URL? {
        URL(string: "\(scheme)://note/\(encode(title))")
    }

    /// A link to one note by its id (stored in reminders made from notes).
    static func noteID(_ id: UUID) -> URL? {
        URL(string: "\(scheme)://id/\(id.uuidString)")
    }

    static func tag(_ tag: String) -> URL? {
        URL(string: "\(scheme)://tag/\(encode(tag))")
    }

    static func handle(_ url: URL, with navigation: NoteNavigation) -> OpenURLAction.Result {
        guard url.scheme == scheme else { return .systemAction }
        let value = String(url.path.dropFirst()).removingPercentEncoding ?? ""
        switch url.host {
        case "note": navigation.openTitle(value)
        case "tag": navigation.openTag(value)
        case "id":
            guard let id = UUID(uuidString: value) else { return .discarded }
            navigation.openNote(id)
        default: return .discarded
        }
        return .handled
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
