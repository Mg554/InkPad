import Foundation

/// A durable change log beside each note's document: what changed and
/// when, oldest first. It is an append-only JSON-lines file (`ops.jsonl`
/// in the note's folder), so it survives crashes, costs one small write
/// per change, and can later feed per-change undo, autosave diffs and
/// iCloud merging that combines instead of last-write-wins.
///
/// Nothing reads it while InkPad runs: it writes and forgets. Notes saved
/// before the log existed have none, which is fine.
///
/// All file work happens on one serial queue, so entries keep their order
/// no matter which thread asks.
enum NoteOpsLog {
    /// What the record is about. Kinds stay stable: a log keeps decoding
    /// when kinds are added (an unknown kind reads as `.other`).
    enum Kind: String, Codable, Equatable {
        /// The editor opened the note.
        case opened
        /// The document was saved (ink, text and elements together).
        case inkSaved
        /// A text note's Markdown was saved.
        case textSaved
        case pageInserted
        case pageRemoved
        case pdfImported
        /// Kinds added by a newer version, or lines damaged on disk.
        case other
    }

    /// One change: what, when, and a short summary.
    struct Entry: Codable, Equatable {
        var kind: Kind
        var at: Date
        /// A short summary, e.g. "124 strokes, 3 elements", under 120 chars.
        var detail: String?

        init(kind: Kind, at: Date = Date(), detail: String? = nil) {
            self.kind = kind
            self.at = at
            self.detail = detail.map { String($0.prefix(120)) }
        }

        private enum CodingKeys: String, CodingKey {
            case kind, at, detail
        }

        /// A kind a newer InkPad writes, or a damaged line, reads as
        /// `.other` instead of dropping the whole log's record.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try values.decodeIfPresent(String.self, forKey: .kind) ?? ""
            kind = Kind(rawValue: raw) ?? .other
            at = try values.decodeIfPresent(Date.self, forKey: .at) ?? Date()
            detail = try values.decodeIfPresent(String.self, forKey: .detail)
        }
    }

    /// The log keeps its most recent records; older ones are trimmed on
    /// write, so the file stays a few hundred kilobytes at most.
    static let maxEntries = 400

    /// The file's name, beside the note's document.
    static let fileName = "ops.jsonl"

    private static let queue = DispatchQueue(label: "inkpad.opslog")
    private static var decoder: JSONDecoder { JSONDecoder() }
    private static var encoder: JSONEncoder { JSONEncoder() }

    /// The log's place beside a note's document.
    private static func fileURL(_ directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Records one change. Fire-and-forget: the write cannot fail loudly
    /// (no room, no folder) because a lost record never blocks a save.
    static func append(_ kind: Kind, detail: String? = nil, to directory: URL) {
        guard !directory.path.isEmpty else { return }
        queue.async {
            // We are already on `queue` here. Calling `read(_:)` would do a
            // `queue.sync` onto the queue we own and crash with LIBDISPATCH
            // "dispatch_sync called on queue already owned by current thread".
            var entries = readOnQueue(directory)
            entries.append(Entry(kind: kind, detail: detail))
            let trimmed = Array(entries.suffix(maxEntries))
            let lines = trimmed.compactMap { entry -> String? in
                guard let data = try? encoder.encode(entry) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            guard !lines.isEmpty else { return }
            let body = lines.joined(separator: "\n") + "\n"
            try? body.write(to: fileURL(directory), atomically: true, encoding: .utf8)
        }
    }

    /// The records in the log, oldest first. Missing, empty or damaged
    /// files read as no records.
    private static func read(_ directory: URL) -> [Entry] {
        queue.sync { readOnQueue(directory) }
    }

    /// Must only be called from a closure already running on `queue`.
    private static func readOnQueue(_ directory: URL) -> [Entry] {
        guard let text = try? String(contentsOf: fileURL(directory), encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(Entry.self, from: data)
            }
    }
}