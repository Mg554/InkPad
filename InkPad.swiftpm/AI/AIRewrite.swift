import Foundation

/// The rewrites AI Rewrite can do to the text in a text box, like
/// Goodnotes' AI typing tools: fix, shorten, expand, re-tone or bulletize
/// the words the owner selected (or the whole box when nothing is
/// selected).
enum AIRewriteMode: String, CaseIterable, Identifiable {
    case fixGrammar, shorter, longer, friendlier, formal, bullets

    var id: Self { self }

    var title: String {
        switch self {
        case .fixGrammar: "Fix Grammar & Spelling"
        case .shorter: "Make Shorter"
        case .longer: "Make Longer"
        case .friendlier: "Friendlier Tone"
        case .formal: "More Formal"
        case .bullets: "Convert to Bullets"
        }
    }

    var systemImage: String {
        switch self {
        case .fixGrammar: "text.badge.checkmark"
        case .shorter: "arrow.down.right.and.arrow.up.left"
        case .longer: "arrow.up.left.and.arrow.down.right"
        case .friendlier: "face.smiling"
        case .formal: "briefcase"
        case .bullets: "list.bullet"
        }
    }

    /// The instruction for the AI, with the text to rewrite.
    func prompt(for text: String) -> String {
        switch self {
        case .fixGrammar:
            "Fix the grammar and spelling of the following text:\n\n\(text)"
        case .shorter:
            "Make the following text shorter, keeping the important content and meaning:\n\n\(text)"
        case .longer:
            "Expand the following text with more detail, keeping the same meaning and voice:\n\n\(text)"
        case .friendlier:
            "Rewrite the following text in a friendlier, warmer tone, keeping the same meaning:\n\n\(text)"
        case .formal:
            "Rewrite the following text in a more formal, professional tone, keeping the same meaning:\n\n\(text)"
        case .bullets:
            "Convert the following text into a concise bulleted list:\n\n\(text)"
        }
    }
}
