import UIKit

/// Formatting commands for the selected text, or for what is typed next when
/// nothing is selected.
extension UITextView {
    private var currentAttributes: [NSAttributedString.Key: Any] {
        selectedRange.length > 0 && selectedRange.location < attributedText.length
            ? attributedText.attributes(at: selectedRange.location, effectiveRange: nil)
            : typingAttributes
    }

    private var currentFont: UIFont {
        currentAttributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: TextBoxStyle.defaultFontSize)
    }

    func hasFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> Bool {
        currentFont.fontDescriptor.symbolicTraits.contains(trait)
    }

    func hasAttribute(_ key: NSAttributedString.Key) -> Bool {
        (currentAttributes[key] as? Int ?? 0) != 0
    }

    func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        let enable = !hasFontTrait(trait)
        updateAttributes { attributes in
            let font = attributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: TextBoxStyle.defaultFontSize)
            var traits = font.fontDescriptor.symbolicTraits
            if enable { traits.insert(trait) } else { traits.remove(trait) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                attributes[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
            }
        }
    }

    /// Toggles `.underlineStyle` or `.strikethroughStyle`.
    func toggleLineStyle(_ key: NSAttributedString.Key) {
        let enable = !hasAttribute(key)
        updateAttributes { attributes in
            if enable {
                attributes[key] = NSUnderlineStyle.single.rawValue
            } else {
                attributes.removeValue(forKey: key)
            }
        }
    }

    func adjustFontSize(by delta: CGFloat) {
        updateAttributes { attributes in
            let font = attributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: TextBoxStyle.defaultFontSize)
            attributes[.font] = font.withSize(min(max(font.pointSize + delta, 8), 96))
        }
    }

    func applyTextColor(_ color: UIColor) {
        updateAttributes { $0[.foregroundColor] = color }
    }

    /// Adds "• " to every selected paragraph, or removes it when all have it.
    func toggleBulletList() {
        let bullet = "• "
        let string = textStorage.string as NSString
        let paragraphs = string.paragraphRange(for: selectedRange)
        var starts: [Int] = []
        string.enumerateSubstrings(in: paragraphs, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            starts.append(range.location)
        }
        if starts.isEmpty { starts = [paragraphs.location] }
        let removing = starts.allSatisfy { string.length >= $0 + 2 && string.substring(with: NSRange(location: $0, length: 2)) == bullet }

        textStorage.beginEditing()
        for start in starts.reversed() {
            if removing {
                textStorage.deleteCharacters(in: NSRange(location: start, length: 2))
            } else {
                let attributes = start < textStorage.length
                    ? textStorage.attributes(at: start, effectiveRange: nil)
                    : typingAttributes
                textStorage.insert(NSAttributedString(string: bullet, attributes: attributes), at: start)
            }
        }
        textStorage.endEditing()
        let shift = removing ? -2 * starts.count : 2 * starts.count
        selectedRange = NSRange(location: min(max(paragraphs.location + paragraphs.length + shift, 0), textStorage.length), length: 0)
        delegate?.textViewDidChange?(self)
    }

    private func updateAttributes(_ update: (inout [NSAttributedString.Key: Any]) -> Void) {
        let range = selectedRange
        if range.length > 0 {
            var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
            textStorage.enumerateAttributes(in: range) { attributes, subrange, _ in
                runs.append((subrange, attributes))
            }
            textStorage.beginEditing()
            for (subrange, attributes) in runs {
                var changed = attributes
                update(&changed)
                textStorage.setAttributes(changed, range: subrange)
            }
            textStorage.endEditing()
            selectedRange = range
            delegate?.textViewDidChange?(self)
        }
        var typing = typingAttributes
        update(&typing)
        typingAttributes = typing
    }
}
