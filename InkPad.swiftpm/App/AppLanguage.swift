import SwiftUI
import ObjectiveC

/// The language of InkPad's own words: English, or Arabic (right to left).
/// Notes and what the owner writes are never translated.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case arabic = "ar"

    static let storageKey = "appLanguage"

    var id: Self { self }

    /// Each language is named in itself.
    var title: String {
        switch self {
        case .english: "English"
        case .arabic: "العربية"
        }
    }

    var shortTitle: String {
        switch self {
        case .english: "EN"
        case .arabic: "ع"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var layoutDirection: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }

    var other: AppLanguage { self == .arabic ? .english : .arabic }
}

/// The chosen language. Changing it rebuilds the views (like a theme
/// change), so every label is looked up again.
@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    @Published private(set) var language: AppLanguage
    @Published private(set) var revision = 0

    private init() {
        let saved = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? ""
        language = AppLanguage(rawValue: saved) ?? .english
        Localizer.setArabic(language == .arabic)
        Localizer.install()
        Self.applyUIKitDirection(language)
    }

    /// UIKit parts (navigation bars, menus) follow this, not SwiftUI.
    private static func applyUIKitDirection(_ language: AppLanguage) {
        let attribute: UISemanticContentAttribute = language == .arabic ? .forceRightToLeft : .forceLeftToRight
        UINavigationBar.appearance().semanticContentAttribute = attribute
        UISearchBar.appearance().semanticContentAttribute = attribute
    }

    func set(_ new: AppLanguage) {
        guard new != language else { return }
        UserDefaults.standard.set(new.rawValue, forKey: AppLanguage.storageKey)
        Localizer.setArabic(new == .arabic)
        Self.applyUIKitDirection(new)
        language = new
        revision += 1
    }
}

/// Translates a label held in a `String` (enum titles and the like), which
/// SwiftUI shows as it is. Literals in `Text("...")` are translated on
/// their own.
func tr(_ english: String) -> String {
    Localizer.translate(english) ?? english
}

/// Like `tr`, for messages built in code with values in them ("12 pages
/// added"): also matches the table's `{}` patterns. Never use it on note
/// titles or anything the owner wrote.
func trMessage(_ english: String) -> String {
    Localizer.translate(english, patterns: true) ?? english
}

/// Looks InkPad's labels up in the Arabic table. `Bundle.main` is given a
/// subclass, so `Text`, `Label`, `Button` and the rest find the Arabic
/// words without a strings file (Swift Playgrounds builds none).
enum Localizer {
    private static let lock = NSRecursiveLock()
    private static var arabic = false
    private static var table: [String: String]?
    private static var cache: [String: String] = [:]

    static func install() {
        guard !(Bundle.main is LocalizedMainBundle) else { return }
        // SwiftUI looks labels up through several methods (for a locale,
        // with Markdown); each answers from the Arabic table first.
        hookString("localizedStringForKey:value:table:localization:")
        hookString("localizedStringForKey:value:table:localizations:")
        hookString("_localizedStringForKey:value:table:localizations:")
        hookAttributed("localizedAttributedStringForKey:value:table:")
        hookAttributed4("localizedAttributedStringForKey:value:table:localization:")
        object_setClass(Bundle.main, LocalizedMainBundle.self)
    }

    private typealias String4 = @convention(c) (AnyObject, Selector, NSString, NSString?, NSString?, AnyObject?) -> NSString
    private typealias Attributed3 = @convention(c) (AnyObject, Selector, NSString, NSString?, NSString?) -> NSAttributedString
    private typealias Attributed4 = @convention(c) (AnyObject, Selector, NSString, NSString?, NSString?, AnyObject?) -> NSAttributedString

    private static func hookString(_ name: String) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(Bundle.self, selector) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: String4.self)
        let block: @convention(block) (AnyObject, NSString, NSString?, NSString?, AnyObject?) -> NSString = { bundle, key, value, table, extra in
            if let arabic = translate(key as String) { return arabic as NSString }
            return original(bundle, selector, key, value, table, extra)
        }
        class_addMethod(LocalizedMainBundle.self, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }

    private static func hookAttributed(_ name: String) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(Bundle.self, selector) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: Attributed3.self)
        let block: @convention(block) (AnyObject, NSString, NSString?, NSString?) -> NSAttributedString = { bundle, key, value, table in
            if let arabic = translate(key as String) { return LocalizedMainBundle.attributed(arabic) }
            return original(bundle, selector, key, value, table)
        }
        class_addMethod(LocalizedMainBundle.self, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }

    private static func hookAttributed4(_ name: String) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(Bundle.self, selector) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: Attributed4.self)
        let block: @convention(block) (AnyObject, NSString, NSString?, NSString?, AnyObject?) -> NSAttributedString = { bundle, key, value, table, extra in
            if let arabic = translate(key as String) { return LocalizedMainBundle.attributed(arabic) }
            return original(bundle, selector, key, value, table, extra)
        }
        class_addMethod(LocalizedMainBundle.self, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }

    static func setArabic(_ on: Bool) {
        lock.lock()
        arabic = on
        cache = [:]
        lock.unlock()
    }

    static var isArabic: Bool {
        lock.lock()
        defer { lock.unlock() }
        return arabic
    }

    /// The Arabic for a key, or nil (English, or not in the table). Keys
    /// with format specifiers (`%lld`, `%@`) match table entries written
    /// with `{}` in their place.
    static func translate(_ key: String, patterns: Bool = false) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard arabic, !key.isEmpty else { return nil }
        let cacheKey = patterns ? "\u{1}" + key : key
        if let hit = cache[cacheKey] { return hit }
        if table == nil { table = ArabicTable.load() }
        guard let table else { return nil }
        let parsed = FormatKey(key)
        var result: String?
        if let value = table[parsed.normalized] {
            result = parsed.fill(value)
        } else if patterns, parsed.specifiers.isEmpty, key.count < 400 {
            result = matchTemplate(key, in: table)
        }
        if let result { cache[cacheKey] = result }
        return result
    }

    /// A message built in code ("12 pages added") matched against the
    /// table's patterns ("{} pages added"), its values put into the Arabic.
    private static var templates: [(regex: NSRegularExpression, value: String)]?

    private static func matchTemplate(_ text: String, in table: [String: String]) -> String? {
        if templates == nil { templates = makeTemplates(table) }
        guard let templates else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for template in templates {
            guard let match = template.regex.firstMatch(in: text, range: whole) else { continue }
            var values: [String] = []
            for group in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: group), in: text) {
                    values.append(translate(String(text[range])) ?? String(text[range]))
                }
            }
            return fillValues(template.value, values)
        }
        return nil
    }

    private static func makeTemplates(_ table: [String: String]) -> [(regex: NSRegularExpression, value: String)] {
        var list: [(regex: NSRegularExpression, value: String, weight: Int)] = []
        for (key, value) in table where key.contains("{}") {
            let parts = key.components(separatedBy: "{}")
            let fixed: Int = parts.reduce(0) { $0 + $1.count }
            // A pattern that is mostly blanks would match anything.
            guard fixed >= 3 else { continue }
            let escaped = parts.map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = "^" + escaped.joined(separator: "(.+?)") + "$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                list.append((regex, value, fixed))
            }
        }
        // The most specific patterns are tried first.
        list.sort { $0.weight > $1.weight }
        return list.map { ($0.regex, $0.value) }
    }

    private static func fillValues(_ value: String, _ values: [String]) -> String {
        var result = ""
        var next = 0
        var rest = Substring(value)
        while let open = rest.firstIndex(of: "{") {
            result += rest[rest.startIndex..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { break }
            let inside = String(rest[rest.index(after: open)..<close])
            if inside.isEmpty, next < values.count {
                result += values[next]
                next += 1
            } else if let number = Int(inside), number >= 1, number <= values.count {
                result += values[number - 1]
            } else {
                result += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }
}

final class LocalizedMainBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let arabic = Localizer.translate(key) { return arabic }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }

    static func attributed(_ text: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return NSAttributedString(parsed)
        }
        return NSAttributedString(string: text)
    }
}

/// A localization key split into its text and its format specifiers.
struct FormatKey {
    /// The key with each specifier written as `{}`.
    let normalized: String
    /// The specifiers in order, without the `%` and any position.
    let specifiers: [String]

    init(_ key: String) {
        var text = ""
        var found: [String] = []
        let chars = Array(key)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            guard char == "%", index + 1 < chars.count else {
                text.append(char)
                index += 1
                continue
            }
            if chars[index + 1] == "%" {
                text.append("%")
                index += 2
                continue
            }
            // %[n$][flags][width][.precision][length]conversion
            var end = index + 1
            var spec = ""
            while end < chars.count {
                let next = chars[end]
                spec.append(next)
                end += 1
                if next.isLetter && !"hlqLzjt".contains(next) { break }
                if next == "@" { break }
            }
            if let dollar = spec.firstIndex(of: "$") {
                spec = String(spec[spec.index(after: dollar)...])
            }
            found.append(spec)
            text.append("{}")
            index = end
        }
        normalized = text
        specifiers = found
    }

    /// Puts the specifiers back into a translation: `{}` takes the next one
    /// in order, `{2}` the second (as a positional `%2$`).
    func fill(_ value: String) -> String {
        if specifiers.isEmpty { return value }
        var result = ""
        var next = 0
        let chars = Array(value)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "{", let close = chars[index...].firstIndex(of: "}") {
                let inside = String(chars[(index + 1)..<close])
                if inside.isEmpty, next < specifiers.count {
                    result += "%\(next + 1)$" + specifiers[next]
                    next += 1
                    index = close + 1
                    continue
                }
                if let number = Int(inside), number >= 1, number <= specifiers.count {
                    result += "%\(number)$" + specifiers[number - 1]
                    index = close + 1
                    continue
                }
            }
            // The result is a format string again: a plain % is doubled.
            if char == "%" {
                result += "%%"
            } else {
                result.append(char)
            }
            index += 1
        }
        return result
    }
}

enum ArabicTable {
    /// Parses the `english => arabic` lines of the tables.
    static func load() -> [String: String] {
        var table: [String: String] = [:]
        for source in ArabicStrings.parts {
            for line in source.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let range = line.range(of: " => ") else { continue }
                let key = unescape(String(line[line.startIndex..<range.lowerBound]))
                let value = unescape(String(line[range.upperBound...]))
                if !key.isEmpty, !value.isEmpty { table[key] = value }
            }
        }
        return table
    }

    private static func unescape(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        var result = ""
        var escaped = false
        for char in text {
            if escaped {
                switch char {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(char)
                }
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else {
                result.append(char)
            }
        }
        return result
    }
}

/// A small AR/EN switch for toolbars.
struct LanguageButton: View {
    @ObservedObject private var settings = LanguageSettings.shared

    var body: some View {
        Button {
            let next = settings.language.other
            // Let the tap finish before the whole app is rebuilt.
            DispatchQueue.main.async { LanguageSettings.shared.set(next) }
        } label: {
            Text(verbatim: settings.language.other.shortTitle)
                .font(.callout.weight(.bold))
                .frame(minWidth: 26)
        }
        .accessibilityLabel(Text(verbatim: settings.language.other.title))
    }
}
