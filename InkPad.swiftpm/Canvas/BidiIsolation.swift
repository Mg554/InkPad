import Foundation
import UIKit

/// Keeps Arabic paragraphs readable when they contain English terms, numbers
/// or inline formulas. Unicode isolate controls are added only for display;
/// the stored RTF is stripped so search and AI never see them.
enum BidiIsolation {
    static let start = "\u{2068}" // FSI
    static let end = "\u{2069}"   // PDI

    static func hasArabic(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where scalar.value >= 0x0600 && scalar.value <= 0x06FF {
            return true
        }
        return false
    }

    static func stripped(_ text: String) -> String {
        text.replacingOccurrences(of: start, with: "")
            .replacingOccurrences(of: end, with: "")
    }

    /// Wraps runs of LTR letters, digits and formula punctuation in FSI/PDI.
    static func isolated(_ attributed: NSAttributedString) -> NSAttributedString {
        let source = attributed.string
        guard hasArabic(stripped(source)) else { return attributed }
        let ns = source as NSString
        let result = NSMutableAttributedString()
        var run = ""
        var runAttributes: [NSAttributedString.Key: Any] = [:]

        func flush() {
            guard !run.isEmpty else { return }
            if run.count >= 2 {
                result.append(NSAttributedString(string: start, attributes: runAttributes))
                result.append(NSAttributedString(string: run, attributes: runAttributes))
                result.append(NSAttributedString(string: end, attributes: runAttributes))
            } else {
                result.append(NSAttributedString(string: run, attributes: runAttributes))
            }
            run = ""
        }

        for index in 0..<ns.length {
            let scalar = ns.character(at: index)
            let isLTR = (scalar >= 0x41 && scalar <= 0x5A)
                || (scalar >= 0x61 && scalar <= 0x7A)
                || (scalar >= 0x30 && scalar <= 0x39)
                || [0x24, 0x3D, 0x28, 0x29, 0x2B, 0x2D, 0x2A, 0x2F].contains(scalar)
            let attributes = attributed.attributes(at: index, effectiveRange: nil)
            if isLTR {
                if run.isEmpty { runAttributes = attributes }
                run.append(Character(UnicodeScalar(scalar)!))
            } else {
                flush()
                result.append(NSAttributedString(string: String(Character(UnicodeScalar(scalar)!)), attributes: attributes))
            }
        }
        flush()
        return result
    }

    static func displayReady(_ attributed: NSAttributedString) -> NSAttributedString {
        isolated(strippedAttributed(attributed))
    }

    static func strippedAttributed(_ attributed: NSAttributedString) -> NSAttributedString {
        let plain = stripped(attributed.string)
        guard plain != attributed.string else { return attributed }
        let result = NSMutableAttributedString(string: plain)
        guard attributed.length > 0 else { return result }
        let first = attributed.attributes(at: 0, effectiveRange: nil)
        result.addAttributes(first, range: NSRange(location: 0, length: result.length))
        return result
    }
}
