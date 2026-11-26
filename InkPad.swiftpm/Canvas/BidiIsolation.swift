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

        var index = 0
        while index < ns.length {
            // Whole characters only: an emoji or an accented letter is more
            // than one UTF-16 unit, and half of one is not a valid String.
            let range = ns.rangeOfComposedCharacterSequences(for: NSRange(location: index, length: 1))
            let piece = ns.substring(with: range)
            let attributes = attributed.attributes(at: index, effectiveRange: nil)
            if isLeftToRight(piece) {
                if run.isEmpty { runAttributes = attributes }
                run += piece
            } else {
                flush()
                result.append(NSAttributedString(string: piece, attributes: attributes))
            }
            index = NSMaxRange(range)
        }
        flush()
        return result
    }

    /// Latin letters, digits and formula signs: the runs that read left to
    /// right inside Arabic writing.
    private static let leftToRightSigns: Set<UInt32> = [0x24, 0x3D, 0x28, 0x29, 0x2B, 0x2D, 0x2A, 0x2F]

    private static func isLeftToRight(_ piece: String) -> Bool {
        let scalars = piece.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return false }
        let value = scalar.value
        if value >= 0x41, value <= 0x5A { return true }
        if value >= 0x61, value <= 0x7A { return true }
        if value >= 0x30, value <= 0x39 { return true }
        return leftToRightSigns.contains(value)
    }

    static func hasControls(_ text: String) -> Bool {
        text.contains(start) || text.contains(end)
    }

    static func displayReady(_ attributed: NSAttributedString) -> NSAttributedString {
        isolated(strippedAttributed(attributed))
    }

    static func strippedAttributed(_ attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0, hasControls(attributed.string) else { return attributed }
        let ns = attributed.string as NSString
        let result = NSMutableAttributedString()
        // Run by run, so each piece keeps its own font and weight.
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let plain = stripped(ns.substring(with: range))
            guard !plain.isEmpty else { return }
            result.append(NSAttributedString(string: plain, attributes: attributes))
        }
        return result
    }

    /// The text as the caret and handwriting should see it: the invisible
    /// controls removed, with `selection` moved back to match. Writing beside
    /// them makes Scribble, the caret and Delete behave oddly, so this runs
    /// when a text box starts editing.
    static func editingReady(_ attributed: NSAttributedString, selection: NSRange) -> (text: NSAttributedString, selection: NSRange) {
        guard attributed.length > 0, hasControls(attributed.string) else { return (attributed, selection) }
        let ns = attributed.string as NSString

        func withoutControls(_ offset: Int) -> Int {
            let limit = min(max(offset, 0), ns.length)
            var removed = 0
            for index in 0..<limit {
                let unit = ns.character(at: index)
                if unit == 0x2068 || unit == 0x2069 { removed += 1 }
            }
            return limit - removed
        }

        let location = withoutControls(selection.location)
        let upper = withoutControls(NSMaxRange(selection))
        return (strippedAttributed(attributed), NSRange(location: location, length: max(upper - location, 0)))
    }
}
