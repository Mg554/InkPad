import Foundation
import UIKit

/// A text box or image placed on the pages, in canvas coordinates.
struct PageElement: Codable, Identifiable, Equatable {
    enum Content: Codable, Equatable {
        /// Rich text stored as RTF.
        case text(rtf: Data)
        /// An image file in the note's `images` folder.
        case image(file: String)
    }

    let id: UUID
    var frame: CGRect
    var content: Content
}

/// Shared text box geometry and defaults, so the editor, thumbnails and
/// PDF export lay text out identically.
enum TextBoxStyle {
    static let padding: CGFloat = 8
    static let minimumWidth: CGFloat = 80
    static let defaultWidth: CGFloat = 320
    static let defaultFontSize: CGFloat = 18

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: defaultFontSize),
            .foregroundColor: UIColor.black,
        ]
    }

    static func rtfData(from text: NSAttributedString) -> Data? {
        try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func attributedString(fromRTF data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }
}

/// Accepts only a plain file name, so stored references cannot point
/// outside the note's folder.
func isPlainFileName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && (name as NSString).lastPathComponent == name
}

/// A title made safe to use as an exported file's name.
func exportFileName(_ title: String, fallback: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? fallback : cleaned
}
