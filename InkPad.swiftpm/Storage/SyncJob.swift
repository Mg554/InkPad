import Foundation

/// What can be synced, each chosen by the owner.
enum SyncPart: String, Codable, CaseIterable, Identifiable, Sendable {
    case library, workspace, media, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .library: "Notes, Folders and Recently Deleted"
        case .workspace: "Planner, Flashcards, Maps and Focus"
        case .media: "My Stickers and Focus Sounds"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "doc.on.doc"
        case .workspace: "checklist"
        case .media: "seal"
        case .settings: "gearshape"
        }
    }
}

/// What each side looked like after the last sync, to tell which side
/// changed: per note its date and a fingerprint of its library entry, per
/// list item a fingerprint, and the files that existed.
struct SyncBase: Codable, Sendable {
    var notes: [String: NoteStamp] = [:]
    /// "file.key" → item id → fingerprint (library.json, workspace.json, ...).
    var items: [String: [String: UInt64]] = [:]
    /// Media files that existed (relative paths).
    var files: Set<String> = []
    var settings: UInt64?

    struct NoteStamp: Codable, Sendable {
        var modified: Date
        var print: UInt64
    }
}

/// Two copies of a note both changed: the other copy was kept as a new note.
struct SyncConflict: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { copyID }
    let originalID: UUID
    let copyID: UUID
    let title: String
    let device: String
    let date: Date
}

struct SyncReport: Sendable {
    var base: SyncBase
    var log: [String] = []
    var conflicts: [SyncConflict] = []
    var libraryChanged = false
    var workspaceChanged = false
    var mediaChanged = false
    /// Settings from the other copy, to apply here.
    var settings: Data?
}

/// One sync run between the library on this iPad and the sync folder.
/// Pure file work, run off the main thread.
enum SyncJob {
    static let remoteName = "InkPad Sync"
    static let settingsFile = "settings.plist"

    struct Input: Sendable {
        let local: URL
        let remote: URL
        let parts: Set<SyncPart>
        let base: SyncBase
        /// Notes open in an editor: left for the next sync.
        let openNotes: Set<UUID>
        let device: String
        /// This copy's settings (a property list), when settings sync.
        let settings: Data?
    }

    static func run(_ input: Input) throws -> SyncReport {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: input.remote, withIntermediateDirectories: true)
        try materialize(input.remote)
        var report = SyncReport(base: input.base)
        if input.parts.contains(.library) { try syncLibrary(input, &report) }
        if input.parts.contains(.workspace) {
            report.workspaceChanged = try syncJSONFile("workspace.json", input, &report)
        }
        if input.parts.contains(.media) {
            for folder in ["Stickers", "FocusSounds"] {
                let changed = try syncFiles(in: folder, input, &report)
                let index = folder == "Stickers" ? "stickers.json" : "sounds.json"
                let merged = try syncJSONFile(folder + "/" + index, input, &report)
                if changed || merged { report.mediaChanged = true }
            }
        }
        if input.parts.contains(.settings) { try syncSettings(input, &report) }
        return report
    }

    // MARK: Library

    private static func syncLibrary(_ input: Input, _ report: inout SyncReport) throws {
        let fileManager = FileManager.default
        let localURL = input.local.appendingPathComponent("library.json")
        let remoteURL = input.remote.appendingPathComponent("library.json")
        var local = try readIndex(localURL)
        let remote = try readIndex(remoteURL)
        guard local != nil || remote != nil else { return }
        if local == nil { local = LibraryIndex(version: LibraryIndex.currentVersion, folders: [], notes: [], textTemplates: nil, trash: nil, customOrders: nil, collections: nil) }
        var merged = local!

        var localNotes: [UUID: NoteSummary] = [:]
        for note in merged.notes + (merged.trash ?? []) { localNotes[note.id] = note }
        var remoteNotes: [UUID: NoteSummary] = [:]
        for note in (remote?.notes ?? []) + (remote?.trash ?? []) { remoteNotes[note.id] = note }
        var result: [UUID: NoteSummary] = localNotes
        var base = report.base

        let ids = Set(localNotes.keys).union(remoteNotes.keys)
        for id in ids {
            guard !input.openNotes.contains(id) else { continue }
            let key = id.uuidString
            let stamp = base.notes[key]
            let mine = localNotes[id]
            let theirs = remoteNotes[id]
            let localFolder = input.local.appendingPathComponent("notes/" + key, isDirectory: true)
            let remoteFolder = input.remote.appendingPathComponent("notes/" + key, isDirectory: true)

            switch (mine, theirs) {
            case let (mine?, nil):
                if let stamp, !changed(mine, since: stamp) {
                    // Deleted for good in the other copy.
                    result[id] = nil
                    try? fileManager.removeItem(at: localFolder)
                    base.notes[key] = nil
                    report.log.append("Removed “\(mine.title)” (deleted on the other copy)")
                    report.libraryChanged = true
                } else {
                    try copyFolder(localFolder, to: remoteFolder)
                    base.notes[key] = stampOf(mine)
                    report.log.append("Sent “\(mine.title)”")
                }
            case let (nil, theirs?):
                if let stamp, !changed(theirs, since: stamp) {
                    try? fileManager.removeItem(at: remoteFolder)
                    base.notes[key] = nil
                    report.log.append("Removed “\(theirs.title)” from the sync folder (deleted here)")
                } else {
                    try copyFolder(remoteFolder, to: localFolder)
                    result[id] = theirs
                    base.notes[key] = stampOf(theirs)
                    report.log.append("Received “\(theirs.title)”")
                    report.libraryChanged = true
                }
            case let (mine?, theirs?):
                let mineChanged = stamp.map { changed(mine, since: $0) } ?? (fingerprint(mine) != fingerprint(theirs))
                let theirsChanged = stamp.map { changed(theirs, since: $0) } ?? false
                if mineChanged && theirsChanged {
                    let contentMine = stamp.map { mine.modifiedAt > $0.modified } ?? true
                    let contentTheirs = stamp.map { theirs.modifiedAt > $0.modified } ?? (mine.modifiedAt != theirs.modifiedAt)
                    if contentMine && contentTheirs {
                        // Both edited: keep both. The other copy becomes a new note.
                        let copyID = UUID()
                        let copy = try NoteSummary.copy(of: theirs, id: copyID, title: theirs.title + " (" + tr("other copy") + ")")
                        try copyFolder(remoteFolder, to: input.local.appendingPathComponent("notes/" + copyID.uuidString, isDirectory: true))
                        result[copyID] = copy
                        try copyFolder(localFolder, to: remoteFolder)
                        let copyFolderRemote = input.remote.appendingPathComponent("notes/" + copyID.uuidString, isDirectory: true)
                        try copyFolder(input.local.appendingPathComponent("notes/" + copyID.uuidString, isDirectory: true), to: copyFolderRemote)
                        base.notes[copyID.uuidString] = stampOf(copy)
                        base.notes[key] = stampOf(mine)
                        report.conflicts.append(SyncConflict(originalID: id, copyID: copyID, title: mine.title, device: input.device, date: Date()))
                        report.log.append("Both copies of “\(mine.title)” changed: kept both")
                        report.libraryChanged = true
                    } else if contentTheirs {
                        try copyFolder(remoteFolder, to: localFolder)
                        result[id] = theirs
                        base.notes[key] = stampOf(theirs)
                        report.libraryChanged = true
                    } else {
                        if contentMine { try copyFolder(localFolder, to: remoteFolder) }
                        base.notes[key] = stampOf(mine)
                    }
                } else if mineChanged {
                    if mine.modifiedAt != theirs.modifiedAt || !fileManager.fileExists(atPath: remoteFolder.path) {
                        try copyFolder(localFolder, to: remoteFolder)
                        report.log.append("Sent “\(mine.title)”")
                    }
                    base.notes[key] = stampOf(mine)
                } else if theirsChanged {
                    if mine.modifiedAt != theirs.modifiedAt || !fileManager.fileExists(atPath: localFolder.path) {
                        try copyFolder(remoteFolder, to: localFolder)
                        report.log.append("Received “\(theirs.title)”")
                    }
                    result[id] = theirs
                    base.notes[key] = stampOf(theirs)
                    report.libraryChanged = true
                } else {
                    base.notes[key] = stampOf(mine)
                }
            case (nil, nil):
                break
            }
        }
        let all = Array(result.values)
        merged.notes = all.filter { $0.deletedAt == nil }
        let trash = all.filter { $0.deletedAt != nil }
        merged.trash = trash.isEmpty ? nil : trash

        // Folders, templates and collections: merged item by item.
        merged.folders = mergeItems("library.folders", merged.folders, remote?.folders ?? [], base: &base, changed: &report.libraryChanged)
        merged.textTemplates = mergeItems("library.templates", merged.textTemplates ?? [], remote?.textTemplates ?? [], base: &base, changed: &report.libraryChanged)
        merged.collections = mergeItems("library.collections", merged.collections ?? [], remote?.collections ?? [], base: &base, changed: &report.libraryChanged)
        if let theirs = remote?.customOrders {
            var orders = merged.customOrders ?? [:]
            for (key, value) in theirs where orders[key] == nil { orders[key] = value }
            merged.customOrders = orders
        }
        report.base = base
        let data = try JSONEncoder.inkpad.encode(merged)
        if report.libraryChanged { try data.write(to: localURL, options: .atomic) }
        try write(data, to: remoteURL)
    }

    private static func readIndex(_ url: URL) throws -> LibraryIndex? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder.inkpad.decode(LibraryIndex.self, from: Data(contentsOf: url))
    }

    private static func stampOf(_ note: NoteSummary) -> SyncBase.NoteStamp {
        SyncBase.NoteStamp(modified: note.modifiedAt, print: fingerprint(note))
    }

    private static func changed(_ note: NoteSummary, since stamp: SyncBase.NoteStamp) -> Bool {
        note.modifiedAt > stamp.modified || fingerprint(note) != stamp.print
    }

    /// Items with an id, merged: kept on both sides, added on either,
    /// deleted when deleted on one side and unchanged on the other; when
    /// both changed, this copy wins.
    private static func mergeItems<Item: Codable & Identifiable>(_ key: String, _ mine: [Item], _ theirs: [Item], base: inout SyncBase, changed: inout Bool) -> [Item] {
        let known = base.items[key] ?? [:]
        var result: [Item] = []
        var seen: Set<String> = []
        var newBase: [String: UInt64] = [:]
        let theirsByID: [String: Item] = Dictionary(theirs.map { ("\($0.id)", $0) }, uniquingKeysWith: { first, _ in first })
        for item in mine {
            let id = "\(item.id)"
            seen.insert(id)
            let myPrint = fingerprint(item)
            if let other = theirsByID[id] {
                let otherPrint = fingerprint(other)
                if let old = known[id], myPrint == old, otherPrint != old {
                    result.append(other)
                    newBase[id] = otherPrint
                    changed = true
                } else {
                    result.append(item)
                    newBase[id] = myPrint
                }
            } else if let old = known[id], old == myPrint {
                changed = true // deleted on the other copy
            } else {
                result.append(item)
                newBase[id] = myPrint
            }
        }
        for item in theirs where !seen.contains("\(item.id)") {
            let id = "\(item.id)"
            let print = fingerprint(item)
            if let old = known[id], old == print { continue } // deleted here
            result.append(item)
            newBase[id] = print
            changed = true
        }
        base.items[key] = newBase
        return result
    }

    // MARK: Other JSON files (workspace, sticker and sound lists)

    /// Merges a JSON file whose top-level lists hold items with an "id"
    /// (or "file"). Returns whether this copy changed.
    private static func syncJSONFile(_ path: String, _ input: Input, _ report: inout SyncReport) throws -> Bool {
        let localURL = input.local.appendingPathComponent(path)
        let remoteURL = input.remote.appendingPathComponent(path)
        let fileManager = FileManager.default
        let mineData = try? Data(contentsOf: localURL)
        let theirsData = try? Data(contentsOf: remoteURL)
        guard mineData != nil || theirsData != nil else { return false }
        let mine = mineData.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let theirs = theirsData.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        var changed = false
        var base = report.base
        let merged = mergeJSON(path, mine, theirs, base: &base, changed: &changed)
        report.base = base
        guard let merged else { return false }
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        if changed || mineData == nil {
            try fileManager.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: localURL, options: .atomic)
            report.log.append("Updated \(path)")
            changed = true
        }
        try write(data, to: remoteURL)
        return changed
    }

    private static func mergeJSON(_ key: String, _ mine: Any?, _ theirs: Any?, base: inout SyncBase, changed: inout Bool) -> Any? {
        guard let mine else {
            changed = theirs != nil
            return theirs
        }
        guard let theirs else { return mine }
        if let mineList = mine as? [[String: Any]], let theirList = theirs as? [[String: Any]] {
            return mergeList(key, mineList, theirList, base: &base, changed: &changed)
        }
        guard let mineDict = mine as? [String: Any], let theirDict = theirs as? [String: Any] else { return mine }
        var result = mineDict
        for (field, value) in theirDict {
            let path = key + "." + field
            if let list = value as? [[String: Any]], let ours = mineDict[field] as? [[String: Any]] {
                result[field] = mergeList(path, ours, list, base: &base, changed: &changed)
            } else if mineDict[field] == nil {
                result[field] = value
                changed = true
            } else if let stamp = base.items[path]?["value"], let ours = mineDict[field] {
                // A plain value: the side that changed since last time wins.
                if fingerprint(json: ours) == stamp, fingerprint(json: value) != stamp {
                    result[field] = value
                    changed = true
                }
            }
            if let final = result[field] { base.items[path, default: [:]]["value"] = fingerprint(json: final) }
        }
        return result
    }

    private static func mergeList(_ key: String, _ mine: [[String: Any]], _ theirs: [[String: Any]], base: inout SyncBase, changed: inout Bool) -> [[String: Any]] {
        func identity(_ item: [String: Any]) -> String? {
            if let id = item["id"] { return "\(id)" }
            if let file = item["file"] { return "\(file)" }
            return nil
        }
        let known = base.items[key] ?? [:]
        var newBase: [String: UInt64] = [:]
        var result: [[String: Any]] = []
        var seen: Set<String> = []
        var theirsByID: [String: [String: Any]] = [:]
        for item in theirs { if let id = identity(item) { theirsByID[id] = item } }
        for item in mine {
            guard let id = identity(item) else {
                result.append(item)
                continue
            }
            seen.insert(id)
            let myPrint = fingerprint(json: item)
            if let other = theirsByID[id] {
                let otherPrint = fingerprint(json: other)
                if let old = known[id], myPrint == old, otherPrint != old {
                    result.append(other)
                    newBase[id] = otherPrint
                    changed = true
                } else {
                    result.append(item)
                    newBase[id] = myPrint
                }
            } else if let old = known[id], old == myPrint {
                changed = true
            } else {
                result.append(item)
                newBase[id] = myPrint
            }
        }
        for item in theirs {
            guard let id = identity(item), !seen.contains(id) else { continue }
            let print = fingerprint(json: item)
            if let old = known[id], old == print { continue }
            result.append(item)
            newBase[id] = print
            changed = true
        }
        base.items[key] = newBase
        return result
    }

    // MARK: Media files

    /// Files are never edited (each has its own name): add the new, remove
    /// the deleted. Returns whether this copy changed.
    private static func syncFiles(in folder: String, _ input: Input, _ report: inout SyncReport) throws -> Bool {
        let fileManager = FileManager.default
        let localDir = input.local.appendingPathComponent(folder, isDirectory: true)
        let remoteDir = input.remote.appendingPathComponent(folder, isDirectory: true)
        try fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        func names(_ dir: URL) -> Set<String> {
            let items = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
            return Set(items.filter { !$0.hasPrefix(".") && !$0.hasSuffix(".json") })
        }
        let mine = names(localDir)
        let theirs = names(remoteDir)
        var changed = false
        var known = report.base.files
        for name in mine.union(theirs) {
            let path = folder + "/" + name
            let here = localDir.appendingPathComponent(name)
            let there = remoteDir.appendingPathComponent(name)
            switch (mine.contains(name), theirs.contains(name)) {
            case (true, false):
                if known.contains(path) {
                    try? fileManager.removeItem(at: here)
                    known.remove(path)
                    changed = true
                } else {
                    try copyItem(here, to: there)
                    known.insert(path)
                }
            case (false, true):
                if known.contains(path) {
                    try? fileManager.removeItem(at: there)
                    known.remove(path)
                } else {
                    try copyItem(there, to: here)
                    known.insert(path)
                    changed = true
                }
            default:
                known.insert(path)
            }
        }
        report.base.files = known
        return changed
    }

    // MARK: Settings

    private static func syncSettings(_ input: Input, _ report: inout SyncReport) throws {
        let remoteURL = input.remote.appendingPathComponent(settingsFile)
        let theirs = try? Data(contentsOf: remoteURL)
        let mine = input.settings
        let myPrint = mine.map { fingerprint(data: $0) }
        let theirPrint = theirs.map { fingerprint(data: $0) }
        let old = report.base.settings
        if let theirs, let theirPrint, theirPrint != old, myPrint == old || mine == nil {
            report.settings = theirs
            report.base.settings = theirPrint
            report.log.append("Received settings")
        } else if let mine, let myPrint, myPrint != theirPrint {
            try write(mine, to: remoteURL)
            report.base.settings = myPrint
            report.log.append("Sent settings")
        } else {
            report.base.settings = myPrint ?? theirPrint
        }
    }

    // MARK: Files

    /// Replaces `destination` with a copy of `source` (a note's folder).
    static func copyFolder(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        try materialize(source)
        try coordinated(writing: destination) { target in
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let staging = target.deletingLastPathComponent().appendingPathComponent(".incoming-" + UUID().uuidString)
            try fileManager.copyItem(at: source, to: staging)
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.moveItem(at: staging, to: target)
        }
    }

    private static func copyItem(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try coordinated(writing: destination) { target in
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.copyItem(at: source, to: target)
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        try coordinated(writing: url) { target in
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
    }

    private static func coordinated(writing url: URL, _ work: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var workError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try work(target) } catch { workError = error }
        }
        if let coordinationError { throw coordinationError }
        if let workError { throw workError }
    }

    /// Asks iCloud Drive for files only listed so far (".name.icloud") and
    /// waits until they are on the iPad.
    static func materialize(_ folder: URL) throws {
        let fileManager = FileManager.default
        func placeholders() -> [URL] {
            guard let items = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil, options: []) else { return [] }
            var found: [URL] = []
            for case let url as URL in items {
                let name = url.lastPathComponent
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    let real = String(name.dropFirst().dropLast(".icloud".count))
                    found.append(url.deletingLastPathComponent().appendingPathComponent(real))
                }
            }
            return found
        }
        var waiting = placeholders()
        guard !waiting.isEmpty else { return }
        for url in waiting { try? fileManager.startDownloadingUbiquitousItem(at: url) }
        let deadline = Date().addingTimeInterval(120)
        while !waiting.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            waiting = placeholders()
        }
        if !waiting.isEmpty { throw SyncError.notDownloaded(waiting.count) }
    }

    // MARK: Fingerprints

    static func fingerprint<Item: Encodable>(_ item: Item) -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return fingerprint(data: (try? encoder.encode(item)) ?? Data())
    }

    static func fingerprint(json: Any) -> UInt64 {
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
        return fingerprint(data: data)
    }

    /// FNV-1a, the same on every launch and device.
    static func fingerprint(data: Data) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

enum SyncError: LocalizedError {
    case noFolder
    case cannotOpenFolder
    case notDownloaded(Int)

    var errorDescription: String? {
        switch self {
        case .noFolder: tr("Choose a sync folder first.")
        case .cannotOpenFolder: tr("The sync folder can't be opened. Choose it again in Sync settings.")
        case let .notDownloaded(count): trMessage("\(count) files are still downloading from iCloud. Try again in a moment.")
        }
    }
}

extension NoteSummary {
    /// A copy of a note's entry under a new id and title (a sync conflict).
    static func copy(of other: NoteSummary, id: UUID, title: String) throws -> NoteSummary {
        let data = try JSONEncoder.inkpad.encode(other)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SyncError.cannotOpenFolder }
        object["id"] = id.uuidString
        object["title"] = title
        return try JSONDecoder.inkpad.decode(NoteSummary.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
