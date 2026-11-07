import Foundation

/// Describes a backup file; stored as `backup.json` at the top of the ZIP.
struct BackupManifest: Codable, Equatable {
    static let currentFormat = 1
    static let appName = "InkPad"

    var format: Int
    var app: String
    var createdAt: Date
    var noteCount: Int
    var folderCount: Int
}

/// A copy of the library InkPad kept by itself just before a restore
/// replaced it, so a restore can always be undone.
struct SafetyCopy: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let date: Date
    let byteCount: Int64
}

/// Backs up the whole library folder (`Documents/InkPad/`: notes, PDFs,
/// images, audio, folders, planner, expenses, mind maps, slides and study)
/// into one ZIP file, and restores it.
///
/// The ZIP holds `backup.json` and an `InkPad/` folder with the files
/// exactly as they are on the iPad. API keys stay in the keychain and are
/// never part of a backup.
enum LibraryBackup {
    static let manifestPath = "backup.json"
    static let folderPrefix = "InkPad/"
    /// How many safety copies are kept; older ones are removed.
    static let keptSafetyCopies = 3

    /// `Documents/InkPad Safety Copies/`, outside the library so a restore
    /// never replaces it.
    static var safetyCopiesURL: URL {
        LibraryStore.defaultRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("InkPad Safety Copies", isDirectory: true)
    }

    static func fileName(_ prefix: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).zip"
    }

    // MARK: Writing

    /// Writes the library at `root` into a new ZIP at `destination`.
    static func writeArchive(of root: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let date = Date()
        var writer = try ZipFileWriter(creating: destination, date: date)
        do {
            try writer.add(manifestPath, data: JSONEncoder.inkpad.encode(manifest(for: root, date: date)))
            for (file, path) in try files(in: root) {
                try writer.addFile(at: file, as: folderPrefix + path)
            }
            try writer.finish()
        } catch {
            writer.cancel()
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    /// Every regular file under `root`, with its path relative to it.
    private static func files(in root: URL) throws -> [(URL, String)] {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        var found: [(URL, String)] = []
        for case let file as URL in enumerator {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = file.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(basePath) else { continue }
            found.append((file, String(path.dropFirst(basePath.count))))
        }
        return found.sorted { $0.1 < $1.1 }
    }

    private struct IndexCounts: Decodable {
        struct Item: Decodable {}
        var folders: [Item]
        var notes: [Item]
    }

    private static func manifest(for root: URL, date: Date) -> BackupManifest {
        let counts = (try? Data(contentsOf: root.appendingPathComponent("library.json")))
            .flatMap { try? JSONDecoder.inkpad.decode(IndexCounts.self, from: $0) }
        return BackupManifest(
            format: BackupManifest.currentFormat,
            app: BackupManifest.appName,
            createdAt: date,
            noteCount: counts?.notes.count ?? 0,
            folderCount: counts?.folders.count ?? 0
        )
    }

    // MARK: Reading

    /// Checks that the file is an InkPad backup this version can restore.
    static func readManifest(at url: URL) throws -> BackupManifest {
        try manifest(in: ZipFileReader(url: url))
    }

    private static func manifest(in reader: ZipFileReader) throws -> BackupManifest {
        guard let entry = reader.entries.first(where: { $0.path == manifestPath }),
              let manifest = try? JSONDecoder.inkpad.decode(BackupManifest.self, from: reader.data(of: entry)),
              manifest.app == BackupManifest.appName
        else { throw ZipArchiveError.notAnArchive }
        guard manifest.format <= BackupManifest.currentFormat else {
            throw StoreError.newerFormat(file: manifestPath, version: manifest.format)
        }
        return manifest
    }

    /// Replaces the library at `root` with the backup. The backup is fully
    /// unpacked and checked first, and the current library is saved as a
    /// safety copy, so nothing is lost if any step fails.
    static func restore(from url: URL, into root: URL) throws {
        let fileManager = FileManager.default
        let unpacked = try unpack(url, beside: root)
        let staging = unpacked.deletingLastPathComponent()
        defer { try? fileManager.removeItem(at: staging) }
        try keepSafetyCopy(of: root)

        let previous = staging.appendingPathComponent("Previous", isDirectory: true)
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.moveItem(at: root, to: previous)
        }
        do {
            try fileManager.moveItem(at: unpacked, to: root)
        } catch {
            if fileManager.fileExists(atPath: previous.path) {
                try? fileManager.moveItem(at: previous, to: root)
            }
            throw error
        }
    }

    /// Unpacks and checks a backup into a staging folder next to `root`;
    /// returns its `InkPad` folder. The caller removes the staging folder.
    private static func unpack(_ url: URL, beside root: URL) throws -> URL {
        let fileManager = FileManager.default
        let reader = try ZipFileReader(url: url)
        _ = try manifest(in: reader)
        let staging = root.deletingLastPathComponent()
            .appendingPathComponent(".InkPad Restore \(UUID().uuidString)", isDirectory: true)
        let unpacked = staging.appendingPathComponent("InkPad", isDirectory: true)
        do {
            try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
            for entry in reader.entries where entry.path != manifestPath {
                guard let relative = safeRelativePath(entry.path) else { throw ZipArchiveError.unsafePath(entry.path) }
                try reader.extract(entry, to: unpacked.appendingPathComponent(relative))
            }
            try checkVersion(of: unpacked.appendingPathComponent("library.json"), current: LibraryIndex.currentVersion)
            try checkVersion(of: unpacked.appendingPathComponent("workspace.json"), current: WorkspaceFile.currentVersion)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        return unpacked
    }

    /// Saves the current library as a safety copy, if it has anything in it.
    private static func keepSafetyCopy(of root: URL) throws {
        guard FileManager.default.fileExists(atPath: root.path), !(try files(in: root)).isEmpty else { return }
        try FileManager.default.createDirectory(at: safetyCopiesURL, withIntermediateDirectories: true)
        try writeArchive(of: root, to: safetyCopiesURL.appendingPathComponent(fileName("Before Restore")))
        pruneSafetyCopies()
    }

    // MARK: Adding from a backup

    /// What a backup holds, for choosing what to restore.
    struct Contents {
        var manifest: BackupManifest
        var folders: [Folder]
        var notes: [NoteSummary]
    }

    /// Reads the backup's manifest and its list of notes and folders.
    static func readContents(at url: URL) throws -> Contents {
        let reader = try ZipFileReader(url: url)
        let manifest = try manifest(in: reader)
        guard let entry = reader.entries.first(where: { $0.path == folderPrefix + "library.json" }) else {
            return Contents(manifest: manifest, folders: [], notes: [])
        }
        let index = try JSONDecoder.inkpad.decode(LibraryIndex.self, from: reader.data(of: entry))
        return Contents(manifest: manifest, folders: index.folders, notes: index.notes)
    }

    enum AddMode {
        /// Every note and item the library is missing; notes in both are
        /// updated when the backup's copy is newer.
        case everything
        /// Only these notes; ones already in the library come back as copies.
        case notes(Set<UUID>)
    }

    struct AddResult {
        var added = 0
        var updated = 0
        var copied = 0
    }

    /// Adds notes (and, for `.everything`, folders, templates, planner,
    /// decks and the rest of the workspace) from the backup to the library
    /// at `root`, removing nothing. A safety copy is kept first.
    static func add(from url: URL, into root: URL, mode: AddMode) throws -> AddResult {
        let fileManager = FileManager.default
        let unpacked = try unpack(url, beside: root)
        defer { try? fileManager.removeItem(at: unpacked.deletingLastPathComponent()) }
        try keepSafetyCopy(of: root)
        try fileManager.createDirectory(at: root.appendingPathComponent("notes", isDirectory: true), withIntermediateDirectories: true)

        let indexURL = root.appendingPathComponent("library.json")
        var index = (try? JSONDecoder.inkpad.decode(LibraryIndex.self, from: Data(contentsOf: indexURL)))
            ?? LibraryIndex(version: LibraryIndex.currentVersion, folders: [], notes: [])
        let backup = (try? JSONDecoder.inkpad.decode(
            LibraryIndex.self,
            from: Data(contentsOf: unpacked.appendingPathComponent("library.json"))
        )) ?? LibraryIndex(version: LibraryIndex.currentVersion, folders: [], notes: [])

        var result = AddResult()
        let chosen: [NoteSummary]
        switch mode {
        case .everything: chosen = backup.notes
        case let .notes(ids): chosen = backup.notes.filter { ids.contains($0.id) }
        }

        func noteFolder(_ id: UUID, in base: URL) -> URL {
            base.appendingPathComponent("notes", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        }
        /// Brings in the note's folder (and its parents) from the backup if
        /// the library doesn't have it; nil if the backup doesn't either.
        func ensureFolder(_ id: UUID?) -> UUID? {
            guard let id else { return nil }
            if index.folders.contains(where: { $0.id == id }) { return id }
            guard var folder = backup.folders.first(where: { $0.id == id }) else { return nil }
            folder.parentID = folder.parentID == id ? nil : ensureFolder(folder.parentID)
            index.folders.append(folder)
            return id
        }

        for var note in chosen {
            let source = noteFolder(note.id, in: unpacked)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            note.folderID = ensureFolder(note.folderID)
            note.deletedAt = nil
            let existing = index.notes.first { $0.id == note.id } ?? index.trash?.first { $0.id == note.id }
            if let existing {
                switch mode {
                case .everything:
                    // Kept as is unless the backup's copy is newer.
                    guard note.modifiedAt > existing.modifiedAt else { continue }
                    let target = noteFolder(note.id, in: root)
                    if fileManager.fileExists(atPath: target.path) {
                        _ = try fileManager.replaceItemAt(target, withItemAt: source)
                    } else {
                        try fileManager.moveItem(at: source, to: target)
                    }
                    index.notes.removeAll { $0.id == note.id }
                    index.trash?.removeAll { $0.id == note.id }
                    index.notes.append(note)
                    result.updated += 1
                case .notes:
                    // Both versions are kept: the backup's comes back as a copy.
                    var copy = NoteSummary(
                        id: UUID(),
                        title: note.title + " (from backup)",
                        folderID: note.folderID,
                        createdAt: note.createdAt,
                        modifiedAt: note.modifiedAt,
                        kind: note.kind
                    )
                    copy.tags = note.tags
                    copy.hiddenFromAI = note.hiddenFromAI
                    copy.aiOnDeviceOnly = note.aiOnDeviceOnly
                    try fileManager.moveItem(at: source, to: noteFolder(copy.id, in: root))
                    index.notes.append(copy)
                    result.copied += 1
                }
            } else {
                try fileManager.moveItem(at: source, to: noteFolder(note.id, in: root))
                index.notes.append(note)
                result.added += 1
            }
        }

        if case .everything = mode {
            for folder in backup.folders where !index.folders.contains(where: { $0.id == folder.id }) {
                _ = ensureFolder(folder.id)
            }
            let templateIDs = Set((index.textTemplates ?? []).map(\.id))
            let newTemplates = (backup.textTemplates ?? []).filter { !templateIDs.contains($0.id) }
            if !newTemplates.isEmpty {
                index.textTemplates = (index.textTemplates ?? []) + newTemplates
            }
            try mergeWorkspace(from: unpacked, into: root)
        }

        index.version = LibraryIndex.currentVersion
        try JSONEncoder.inkpad.encode(index).write(to: indexURL, options: .atomic)
        return result
    }

    /// Adds every planner task, expense, mind map, deck, flashcard deck,
    /// quiz, chat and Flowmodoro item the library is missing (matched by id);
    /// settings stay as they are. Slide pictures come along.
    private static func mergeWorkspace(from unpacked: URL, into root: URL) throws {
        let fileManager = FileManager.default
        let backupURL = unpacked.appendingPathComponent("workspace.json")
        guard let backupData = try? Data(contentsOf: backupURL),
              let backup = try JSONSerialization.jsonObject(with: backupData) as? [String: Any]
        else { return }
        let currentURL = root.appendingPathComponent("workspace.json")
        guard let currentData = try? Data(contentsOf: currentURL),
              var current = try JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        else {
            try fileManager.copyItem(at: backupURL, to: currentURL)
            try copyMissingItems(in: "decks", from: unpacked, to: root)
            return
        }
        for (key, value) in backup {
            guard let items = value as? [[String: Any]] else {
                if current[key] == nil { current[key] = value }
                continue
            }
            var mine = current[key] as? [[String: Any]] ?? []
            let ids = Set(mine.compactMap { $0["id"] as? String })
            mine += items.filter { item in (item["id"] as? String).map { !ids.contains($0) } ?? false }
            current[key] = mine
        }
        let merged = try JSONSerialization.data(withJSONObject: current, options: [.prettyPrinted, .sortedKeys])
        try merged.write(to: currentURL, options: .atomic)
        try copyMissingItems(in: "decks", from: unpacked, to: root)
    }

    /// Copies the backup's `folder/<item>` entries the library doesn't have.
    private static func copyMissingItems(in folder: String, from unpacked: URL, to root: URL) throws {
        let fileManager = FileManager.default
        let source = unpacked.appendingPathComponent(folder, isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        let target = root.appendingPathComponent(folder, isDirectory: true)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for item in items where !fileManager.fileExists(atPath: target.appendingPathComponent(item.lastPathComponent).path) {
            try fileManager.moveItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
        }
    }

    /// `InkPad/notes/<id>/note.json` → `notes/<id>/note.json`; nil for
    /// anything outside the library folder or with `..` in it.
    private static func safeRelativePath(_ path: String) -> String? {
        guard path.hasPrefix(folderPrefix), !path.contains("\\") else { return nil }
        let parts = path.dropFirst(folderPrefix.count).split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return parts.joined(separator: "/")
    }

    private struct Versioned: Decodable {
        var version: Int
    }

    private static func checkVersion(of file: URL, current: Int) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let version = try JSONDecoder.inkpad.decode(Versioned.self, from: Data(contentsOf: file)).version
        guard version <= current else {
            throw StoreError.newerFormat(file: file.lastPathComponent, version: version)
        }
    }

    /// Copies a file picked in Files into the temporary folder. Coordinated,
    /// so a backup that is only in iCloud is downloaded first.
    static func copyPickedFile(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try copyPickedFileNow(url) })
            }
        }
    }

    private static func copyPickedFileNow(_ url: URL) throws -> URL {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("Restore \(UUID().uuidString).zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            do {
                try FileManager.default.copyItem(at: readableURL, to: target)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        return target
    }

    // MARK: Safety copies

    /// Newest first.
    static func safetyCopies() -> [SafetyCopy] {
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: safetyCopiesURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension == "zip" }
            .map { file in
                let values = try? file.resourceValues(forKeys: Set(keys))
                return SafetyCopy(
                    url: file,
                    date: values?.creationDate ?? .distantPast,
                    byteCount: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.date > $1.date }
    }

    static func deleteSafetyCopy(_ copy: SafetyCopy) throws {
        try FileManager.default.removeItem(at: copy.url)
    }

    private static func pruneSafetyCopies() {
        for copy in safetyCopies().dropFirst(keptSafetyCopies) {
            try? FileManager.default.removeItem(at: copy.url)
        }
    }
}

extension LibraryStore {
    /// Writes a backup of the whole library into the temporary folder.
    /// Runs on the note write queue, after any save in progress.
    func makeBackup() async throws -> URL {
        let root = rootURL
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(LibraryBackup.fileName("InkPad Backup"))
        return try await withCheckedThrowingContinuation { continuation in
            writeQueue.async {
                continuation.resume(with: Result {
                    try LibraryBackup.writeArchive(of: root, to: url)
                    return url
                })
            }
        }
    }

    func readBackup(at url: URL) async throws -> BackupManifest {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try LibraryBackup.readManifest(at: url) })
            }
        }
    }

    func readBackupContents(at url: URL) async throws -> LibraryBackup.Contents {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try LibraryBackup.readContents(at: url) })
            }
        }
    }

    /// Adds notes (or everything) from the backup without removing anything,
    /// then reads the library again.
    func addFromBackup(at url: URL, mode: LibraryBackup.AddMode) async throws -> LibraryBackup.AddResult {
        let root = rootURL
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LibraryBackup.AddResult, Error>) in
            writeQueue.async {
                continuation.resume(with: Result { try LibraryBackup.add(from: url, into: root, mode: mode) })
            }
        }
        reload()
        return result
    }

    /// Replaces the library with the backup and reads it again. Allowed
    /// even when the library opened read-only: restoring is the way out.
    func restoreBackup(at url: URL) async throws {
        let root = rootURL
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writeQueue.async {
                continuation.resume(with: Result { try LibraryBackup.restore(from: url, into: root) })
            }
        }
        reload()
    }
}
