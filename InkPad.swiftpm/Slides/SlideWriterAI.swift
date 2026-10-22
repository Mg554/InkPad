import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes slides with Apple Intelligence's on-device model (iPadOS 26 and
/// later, on iPads that support it). Nothing leaves the iPad.
@MainActor
enum SlideWriterAI {
    /// `nil` when Apple Intelligence can write slides; otherwise why not.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return OnDeviceSlideWriter.unavailableReason
        }
        return "Apple Intelligence needs iPadOS 26 or later."
        #else
        return "This version of Swift Playgrounds can't use Apple Intelligence."
        #endif
    }

    /// The deck's words written by the model; `nil` if it wrote nothing usable.
    static func outline(
        _ sources: [SlideSource],
        format: DeckFormat,
        length: DeckLength,
        focus: String,
        progress: (String) -> Void
    ) async throws -> DeckOutline? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await OnDeviceSlideWriter.outline(sources, format: format, length: length, focus: focus, progress: progress)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@MainActor
private enum OnDeviceSlideWriter {
    /// Characters of notes given to the model at once: it reads only a few
    /// thousand words in one go.
    static var budget: Int { 5000 }
    static var chunkSize: Int { 3500 }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This iPad doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to have it write your slides."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready on this iPad. Try again later."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        }
    }

    static func outline(
        _ sources: [SlideSource],
        format: DeckFormat,
        length: DeckLength,
        focus: String,
        progress: (String) -> Void
    ) async throws -> DeckOutline? {
        var material = sources
            .map { "# \($0.title)\n\($0.text)" }
            .joined(separator: "\n\n")
        if material.count > budget {
            progress("Apple Intelligence is reading your long notes…")
            material = try await keyPoints(of: material)
        }
        progress("Apple Intelligence is writing your slides…")
        let reply: String
        do {
            reply = try await respond(to: prompt(material: material, format: format, length: length, focus: focus))
        } catch {
            // Usually the notes were too long for the model: try with less of them.
            let shorter = String(material.prefix(material.count / 2))
            reply = try await respond(to: prompt(material: shorter, format: format, length: length, focus: focus))
        }
        return DeckReplyParser.outline(from: reply, format: format, length: length)
    }

    private static func respond(to prompt: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }

    /// For long notes: the key points of each part, to write the slides from.
    private static func keyPoints(of material: String) async throws -> String {
        var points: [String] = []
        for chunk in chunks(of: material).prefix(4) {
            let reply = try await respond(to: """
                List the 6 most important facts or ideas in these notes, one per line, each starting with "- ". \
                Write them in the same language as the notes.

                Notes:
                \(chunk)
                """)
            points.append(reply)
        }
        return points.joined(separator: "\n")
    }

    private static func chunks(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentLength = 0
        for line in text.components(separatedBy: "\n") {
            let piece = String(line.prefix(chunkSize))
            if currentLength + piece.count > chunkSize, !current.isEmpty {
                result.append(current)
                current = ""
                currentLength = 0
            }
            current += piece + "\n"
            currentLength += piece.count + 1
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func prompt(material: String, format: DeckFormat, length: DeckLength, focus: String) -> String {
        let style: String
        switch format {
        case .detailed:
            style = "Each slide has 3 to 5 bullets written as complete, informative sentences."
        case .presenter:
            style = "Each slide has at most 3 very short bullets of under 8 words. Put the explanation in NOTES."
        }
        let trimmedFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusLine = trimmedFocus.isEmpty ? "" : "Focus on: \(trimmedFocus).\n"
        return """
            You turn notes into a presentation, like NotebookLM's slide decks.
            Write \(length.contentSlides) content slides. \(style)
            \(focusLine)Use only facts from the notes. Write in the same language as the notes.
            Answer in exactly this format, with nothing before or after it:
            TITLE: <title of the presentation>
            SUBTITLE: <one short line>
            SLIDE: <slide title>
            ICON: <one of: idea, data, time, people, goal, process, problem, question, money, science, health, technology, book, world, law, math, summary>
            - <bullet>
            - <bullet>
            NOTES: <what the presenter says, 2 or 3 sentences>
            (more SLIDE blocks)
            TAKEAWAYS:
            - <key takeaway>
            - <key takeaway>
            - <key takeaway>

            Notes:
            \(material)
            """
    }
}
#endif

/// Reads a deck written in the TITLE / SLIDE / NOTES format, forgiving small
/// departures from it.
enum DeckReplyParser {
    static func outline(from reply: String, format: DeckFormat, length: DeckLength) -> DeckOutline? {
        var title = ""
        var subtitle = ""
        var slides: [Slide] = []
        var takeaways: [String] = []
        var inTakeaways = false
        var inNotes = false

        for rawLine in reply.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let text = value(of: "SUBTITLE", in: line) {
                subtitle = text
            } else if let text = value(of: "TITLE", in: line) {
                title = text
            } else if let text = value(of: "SLIDE", in: line) {
                inTakeaways = false
                inNotes = false
                slides.append(Slide(layout: .bullets, title: text))
            } else if value(of: "TAKEAWAYS", in: line) != nil {
                inTakeaways = true
                inNotes = false
            } else if let text = value(of: "ICON", in: line) {
                if !slides.isEmpty {
                    slides[slides.count - 1].symbol = SlideSymbols.symbol(forKeyword: text)
                }
            } else if let text = value(of: "NOTES", in: line) {
                if !slides.isEmpty, !inTakeaways {
                    slides[slides.count - 1].speakerNotes = text
                    inNotes = true
                }
            } else if let bullet = bulletText(in: line) {
                inNotes = false
                if inTakeaways {
                    takeaways.append(bullet)
                } else if !slides.isEmpty {
                    slides[slides.count - 1].bullets.append(bullet)
                }
            } else if inNotes, !slides.isEmpty {
                slides[slides.count - 1].speakerNotes += " " + line
            }
        }

        let perSlide = format.bulletsPerSlide
        let tidied = slides.compactMap { original -> Slide? in
            var slide = original
            slide.bullets = Array(slide.bullets.prefix(perSlide + 1))
            if slide.symbol == "sparkles" {
                slide.symbol = SlideSymbols.symbol(for: ([slide.title] + slide.bullets).joined(separator: " "))
            }
            return slide.title.isEmpty && slide.bullets.isEmpty ? nil : slide
        }
        guard !tidied.isEmpty else { return nil }
        return DeckOutline(
            title: title,
            subtitle: subtitle,
            slides: Array(tidied.prefix(length.contentSlides + 3)),
            takeaways: Array(takeaways.prefix(5))
        )
    }

    /// The text after `KEY:` (or `KEY 2:`), in any letter case.
    private static func value(of key: String, in line: String) -> String? {
        guard line.uppercased().hasPrefix(key) else { return nil }
        let rest = line.dropFirst(key.count).drop { $0.isNumber || $0 == " " }
        guard let mark = rest.first, mark == ":" || mark == "-" || mark == "–" else { return nil }
        return rest.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private static func bulletText(in line: String) -> String? {
        guard let first = line.first, "-•*–".contains(first) || first.isNumber else { return nil }
        var rest = Substring(line)
        if first.isNumber {
            rest = rest.drop { $0.isNumber }
            guard let mark = rest.first, mark == "." || mark == ")" else { return nil }
        }
        let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
