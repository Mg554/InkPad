import Foundation

/// Reads a transcript for the way a speaker organised ideas and draws a
/// simple structure from it: a comparison table, a sequence or a hierarchy.
/// Entirely on-device; the optional AI is never called here.
struct DiagramRow: Identifiable, Equatable {
    let id = UUID()
    let group: String
    let text: String
    let time: TimeInterval
}

enum AcousticDiagrammer {
    static func rows(in transcript: AudioTranscript) -> [DiagramRow] {
        var result: [DiagramRow] = []
        for phrase in transcript.phrases {
            let lower = phrase.text.lowercased()
            if containsAny(lower, ["compared with", "on the other hand", "whereas", "difference between", "versus"]) {
                result.append(DiagramRow(group: "Comparison", text: phrase.text, time: phrase.start))
            } else if containsAny(lower, ["first", "then", "next", "after that", "finally", "step "]) {
                result.append(DiagramRow(group: "Sequence", text: phrase.text, time: phrase.start))
            } else if containsAny(lower, ["there are three", "there are two", "such as", "for example", "types of", "kinds of"]) {
                result.append(DiagramRow(group: "Hierarchy", text: phrase.text, time: phrase.start))
            }
        }
        return result
    }

    private static func containsAny(_ text: String, _ words: [String]) -> Bool {
        for word in words where text.contains(word) { return true }
        return false
    }
}
