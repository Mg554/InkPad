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
        let reader = try ZipFileReader(url: url)
        _ = try manifest(in: reader)

        let staging = root.deletingLastPathComponent()
            .appendingPathComponent(".InkPad Restore \(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let unpacked = staging.appendingPathComponent("InkPad", isDirectory: true)
        try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        for entry in reader.entries where entry.path != manifestPath {
            guard let relative = safeRelativePath(entry.path) else { throw ZipArchiveError.unsafePath(entry.path) }
            try reader.extract(entry, to: unpacked.appendingPathComponent(relative))
        }
        try checkVersion(of: unpacked.appendingPathComponent("library.json"), current: LibraryIndex.currentVersion)
        try checkVersion(of: unpacked.appendingPathComponent("workspace.json"), current: WorkspaceFile.currentVersion)

        if fileManager.fileExists(atPath: root.path), !(try files(in: root)).isEmpty {
            try fileManager.createDirectory(at: safetyCopiesURL, withIntermediateDirectories: true)
            try writeArchive(of: root, to: safetyCopiesURL.appendingPathComponent(fileName("Before Restore")))
            pruneSafetyCopies()
        }

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
