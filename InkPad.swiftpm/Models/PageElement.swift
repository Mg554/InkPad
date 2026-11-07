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
            .font: ThemeSettings.current.typingUIFont(),
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

extension TextBoxStyle {
    /// Simple Markdown (headings, bullets, **bold**) as text-box text, for
    /// placing an AI answer on the page.
    static func attributed(markdown: String, title: String? = nil, tint: UIColor = .systemPurple) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let body = UIFont.systemFont(ofSize: 16)
        let bold = UIFont.boldSystemFont(ofSize: 16)
        if let title {
            result.append(NSAttributedString(string: title + "\n", attributes: [
                .font: UIFont.boldSystemFont(ofSize: 19), .foregroundColor: tint,
            ]))
        }
        let lines = markdown.components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            var font = body
            if line.hasPrefix("#") {
                line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                font = UIFont.boldSystemFont(ofSize: 18)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
            }
            // **bold** spans: every other piece between the markers.
            for (part, piece) in line.components(separatedBy: "**").enumerated() where !piece.isEmpty {
                let isBold = part % 2 == 1 || font != body
                result.append(NSAttributedString(string: piece, attributes: [
                    .font: isBold && font == body ? bold : font, .foregroundColor: UIColor.black,
                ]))
            }
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: body, .foregroundColor: UIColor.black]))
            }
        }
        return result
    }
}
