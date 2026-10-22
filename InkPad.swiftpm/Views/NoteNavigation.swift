import SwiftUI

/// Lets any view open a note, a [[link]] by title, or a #tag, without
/// knowing how the library navigates. Provided by `LibraryView`.
struct NoteNavigation {
    var openNote: (UUID) -> Void = { _ in }
    /// Opens the note with this title, creating a text note if none exists
    /// (like following an unresolved link in Obsidian).
    var openTitle: (String) -> Void = { _ in }
    var openTag: (String) -> Void = { _ in }
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

    static func tag(_ tag: String) -> URL? {
        URL(string: "\(scheme)://tag/\(encode(tag))")
    }

    static func handle(_ url: URL, with navigation: NoteNavigation) -> OpenURLAction.Result {
        guard url.scheme == scheme else { return .systemAction }
        let value = url.path.dropFirst().removingPercentEncoding.map(String.init) ?? ""
        switch url.host {
        case "note": navigation.openTitle(value)
        case "tag": navigation.openTag(value)
        default: return .discarded
        }
        return .handled
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
