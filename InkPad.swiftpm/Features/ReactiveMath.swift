import Foundation

/// Live math on the canvas, without a network call. Reads lines the owner
/// writes as `name = expression` (Arabic or English names), evaluates them in
/// order and keeps the results beside the handwriting.
struct MathLine: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let expression: String
    var value: Double?
    var problem: String?
}

enum ReactiveMath {
    /// Reads `a = 3`, `b = a * 2`, `total = a + b` from the note's words.
    static func lines(in text: String) -> [MathLine] {
        var results: [MathLine] = []
        var values: [String: Double] = [:]

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mark = line.firstIndex(of: "=") else { continue }
            let name = String(line[line.startIndex..<mark])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let expression = String(line[line.index(after: mark)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !expression.isEmpty, isName(name) else { continue }

            var resolved = expression
            // Longest names first so `a` cannot eat `area`.
            for key in values.keys.sorted(by: { $0.count > $1.count }) {
                resolved = replaceWholeWord(key, in: resolved, with: format(values[key]!))
            }
            do {
                let value = try MathExpression.value(of: resolved)
                values[name] = value
                results.append(MathLine(name: name, expression: expression, value: value))
            } catch {
                results.append(MathLine(name: name, expression: expression,
                                        problem: String(describing: error)))
            }
        }
        return results
    }

    private static func isName(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        guard first.isLetter else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Replaces a standalone name, never a part of another word.
    private static func replaceWholeWord(_ word: String, in text: String, with number: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix(word),
               isBoundary(text, before: index),
               isBoundary(text, after: text.index(index, offsetBy: word.count)) {
                result += "(" + number + ")"
                index = text.index(index, offsetBy: word.count)
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func isBoundary(_ text: String, before index: String.Index) -> Bool {
        index == text.startIndex || !isNameCharacter(text[text.index(before: index)])
    }

    private static func isBoundary(_ text: String, after index: String.Index) -> Bool {
        index == text.endIndex || !isNameCharacter(text[index])
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.4g", value)
    }
}
