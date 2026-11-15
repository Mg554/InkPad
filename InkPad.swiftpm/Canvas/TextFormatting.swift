import UIKit

/// The fonts InkPad offers for typed text, from plain to handwriting.
enum TextFont: String, CaseIterable, Identifiable {
    case system, georgia, avenir, helvetica, bradleyHand, markerFelt, menlo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .georgia: "Georgia"
        case .avenir: "Avenir Next"
        case .helvetica: "Helvetica Neue"
        case .bradleyHand: "Bradley Hand"
        case .markerFelt: "Marker Felt"
        case .menlo: "Menlo"
        }
    }

    /// The font at `size`, falling back to the system font when the iPad
    /// doesn't have it.
    func font(size: CGFloat) -> UIFont {
        let name: String?
        switch self {
        case .system: name = nil
        case .georgia: name = "Georgia"
        case .avenir: name = "AvenirNext-Regular"
        case .helvetica: name = "HelveticaNeue"
        case .bradleyHand: name = "BradleyHand-Regular"
        case .markerFelt: name = "MarkerFelt-Wide"
        case .menlo: name = "Menlo-Regular"
        }
        guard let name, let font = UIFont(name: name, size: size) else { return .systemFont(ofSize: size) }
        return font
    }

    /// The font name behind the family (nil for the system font), to tell
    /// which family the text is in.
    var fontName: String? {
        if self == .system { return nil }
        return font(size: 12).fontName
    }
}

/// How far typed lines sit apart: 1 is normal, 2 is double spacing.
enum TextLineSpacing: CaseIterable, Identifiable {
    case tight, normal, loose, double

    var id: Self { self }

    var multiple: CGFloat {
        switch self {
        case .tight: 0.85
        case .normal: 1
        case .loose: 1.3
        case .double: 2
        }
    }

    var title: String {
        switch self {
        case .tight: "Tight"
        case .normal: "Normal"
        case .loose: "Loose"
        case .double: "Double"
        }
    }
}

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

    // MARK: Paragraph style (alignment and line spacing)

    /// The alignment of the selected text, or of what is typed next.
    var currentTextAlignment: NSTextAlignment {
        (currentAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
    }

    /// Sets the alignment of the selected paragraphs, and of what is typed next.
    func applyTextAlignment(_ alignment: NSTextAlignment) {
        updateParagraphStyle { style in style.alignment = alignment }
    }

    /// The line spacing of the selected text, or of what is typed next
    /// (1 is normal spacing).
    var currentLineSpacingMultiple: CGFloat {
        (currentAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple ?? 1
    }

    /// Sets how far the selected lines sit apart, and what is typed next.
    func applyLineSpacing(multiple: CGFloat) {
        updateParagraphStyle { style in style.lineHeightMultiple = multiple }
    }

    /// Changes one thing about the paragraph style of the selected text, and
    /// of what is typed next, keeping the rest as it is.
    private func updateParagraphStyle(_ update: (NSMutableParagraphStyle) -> Void) {
        let range = selectedRange
        if range.length > 0 {
            textStorage.beginEditing()
            textStorage.enumerateAttributes(in: range) { attributes, subrange, _ in
                let style = Self.mutableStyle(of: attributes[.paragraphStyle] as? NSParagraphStyle ?? .default)
                update(style)
                var changed = attributes
                changed[.paragraphStyle] = style
                textStorage.setAttributes(changed, range: subrange)
            }
            textStorage.endEditing()
            selectedRange = range
            delegate?.textViewDidChange?(self)
        }
        var typing = typingAttributes
        let style = Self.mutableStyle(of: typing[.paragraphStyle] as? NSParagraphStyle ?? .default)
        update(style)
        typing[.paragraphStyle] = style
        typingAttributes = typing
    }

    /// A mutable copy of `style`, so one thing can change and the rest stays.
    private static func mutableStyle(of style: NSParagraphStyle) -> NSMutableParagraphStyle {
        let copy = NSMutableParagraphStyle()
        copy.alignment = style.alignment
        copy.baseWritingDirection = style.baseWritingDirection
        copy.firstLineHeadIndent = style.firstLineHeadIndent
        copy.headIndent = style.headIndent
        copy.hyphenationFactor = style.hyphenationFactor
        copy.lineBreakMode = style.lineBreakMode
        copy.lineHeightMultiple = style.lineHeightMultiple
        copy.lineSpacing = style.lineSpacing
        copy.maximumLineHeight = style.maximumLineHeight
        copy.minimumLineHeight = style.minimumLineHeight
        copy.paragraphSpacing = style.paragraphSpacing
        copy.paragraphSpacingBefore = style.paragraphSpacingBefore
        copy.tabStops = style.tabStops
        return copy
    }

    // MARK: Font family

    /// The font family of the selected text, or of what is typed next.
    var currentTextFont: TextFont {
        let name = currentFont.fontName
        return TextFont.allCases.first { $0.fontName == name } ?? .system
    }

    /// Switches the selected text to `family`, keeping its size and style.
    func applyTextFont(_ family: TextFont) {
        updateAttributes { attributes in
            let current = attributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: TextBoxStyle.defaultFontSize)
            let traits = current.fontDescriptor.symbolicTraits
            let base = family.font(size: current.pointSize)
            guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
                attributes[.font] = base
                return
            }
            attributes[.font] = UIFont(descriptor: descriptor, size: current.pointSize)
        }
    }
}
