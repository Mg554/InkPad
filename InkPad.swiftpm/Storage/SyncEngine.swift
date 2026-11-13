import SwiftUI
import UIKit

/// Free sync through a folder the owner picks in Files (an iCloud Drive
/// folder): first between the Swift Playgrounds copy and the installed copy
/// on the same iPad, and any other iPad that opens the same folder. No
/// CloudKit or server: each copy reads and writes `InkPad Sync/` there.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case off
        case idle
        case syncing
        case failed(String)
    }

    struct LogEntry: Codable, Identifiable, Hashable {
        var id: Date { date }
        let date: Date
        let text: String
    }

    private struct Saved: Codable {
        var bookmark: Data?
        var folderName: String?
        var parts: Set<SyncPart> = Set(SyncPart.allCases)
        var automatic = true
        var weeklyBackup = true
        var lastSync: Date?
        var lastBackup: Date?
        var deviceName: String?
        var log: [LogEntry] = []
        var conflicts: [SyncConflict] = []
    }

    private static let key = "syncSettings"
    private var saved = Saved()
    @Published private(set) var status: Status = .off
    @Published private(set) var lastSync: Date?
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var conflicts: [SyncConflict] = []
    @Published var parts: Set<SyncPart> = Set(SyncPart.allCases) { didSet { saved.parts = parts; persist() } }
    @Published var automatic = true { didSet { saved.automatic = automatic; persist() } }
    @Published var weeklyBackup = true { didSet { saved.weeklyBackup = weeklyBackup; persist() } }
    @Published var deviceName: String = "" { didSet { saved.deviceName = deviceName; persist() } }

    /// Notes open in an editor; not synced until closed.
    var openNotes: Set<UUID> = []
    weak var store: LibraryStore?
    weak var workspace: WorkspaceStore?
    private var timer: Task<Void, Never>?
    private var pending: Task<Void, Never>?

    var folderName: String? { saved.folderName }
    var isOn: Bool { saved.bookmark != nil }

    private var baseURL: URL { LibraryStore.defaultRootURL.appendingPathComponent("sync-base.json") }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let value = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = value
        }
        parts = saved.parts
        automatic = saved.automatic
        weeklyBackup = saved.weeklyBackup
        lastSync = saved.lastSync
        log = saved.log
        conflicts = saved.conflicts
        deviceName = saved.deviceName ?? Self.defaultDeviceName
        status = saved.bookmark == nil ? .off : .idle
    }

    /// "iPad · Playgrounds" or "iPad · App", so the two copies are told apart.
    static var defaultDeviceName: String {
        let inPlaygrounds = Bundle.main.bundlePath.contains("Playground") || (Bundle.main.bundleIdentifier ?? "").contains("swift-playgrounds")
        return UIDevice.current.name + " · " + (inPlaygrounds ? "Playgrounds" : "App")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    // MARK: Folder

    func choose(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            status = .failed(tr("The folder can't be used for sync. Choose a folder in iCloud Drive."))
            return
        }
        saved.bookmark = bookmark
        saved.folderName = url.lastPathComponent
        persist()
        status = .idle
        addLog("Sync folder: \(url.lastPathComponent)")
        syncNow()
    }

    func stop() {
        saved.bookmark = nil
        saved.folderName = nil
        persist()
        timer?.cancel()
        status = .off
        addLog("Sync turned off")
    }

    private func folderURL() throws -> URL {
        guard let bookmark = saved.bookmark else { throw SyncError.noFolder }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw SyncError.cannotOpenFolder
        }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            saved.bookmark = fresh
            persist()
        }
        return url
    }

    // MARK: Running

    /// Starts the five-minute rhythm while the app is open.
    func start(store: LibraryStore, workspace: WorkspaceStore) {
        self.store = store
        self.workspace = workspace
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self, self.automatic, self.isOn else { continue }
                await self.run()
            }
        }
    }

    /// An automatic sync a moment from now (after leaving a note, going to
    /// the background, opening the app).
    func soon(delay: Double = 2) {
        guard automatic, isOn else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    func syncNow() {
        Task { await run() }
    }

    func run() async {
        guard isOn, status != .syncing, let store, let workspace else { return }
        status = .syncing
        // Pending index and planner changes land on disk before the job
        // reads the library, so nothing is synced half a step behind.
        await store.flushIndex()
        await workspace.flushWorkspace()
        let folder: URL
        do {
            folder = try folderURL()
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let input = SyncJob.Input(
            local: LibraryStore.defaultRootURL,
            remote: folder.appendingPathComponent(SyncJob.remoteName, isDirectory: true),
            parts: parts,
            base: loadBase(),
            openNotes: openNotes,
            device: deviceName,
            settings: parts.contains(.settings) ? Self.exportSettings() : nil
        )
        let result: Result<SyncReport, Error> = await Task.detached(priority: .utility) {
            Result { try SyncJob.run(input) }
        }.value
        switch result {
        case let .success(report):
            saveBase(report.base)
            if report.libraryChanged { store.reload() }
            if report.workspaceChanged { workspace.reload() }
            if report.mediaChanged {
                StickerStore.shared.reload()
                OwnSoundStore.shared.reload()
            }
            if let settings = report.settings { Self.importSettings(settings) }
            for line in report.log { addLog(line) }
            if !report.conflicts.isEmpty {
                conflicts.append(contentsOf: report.conflicts)
                saved.conflicts = conflicts
            }
            lastSync = Date()
            saved.lastSync = lastSync
            persist()
            status = .idle
            await backupIfDue(to: input.remote)
        case let .failure(error):
            status = .failed(error.localizedDescription)
            addLog("Sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: Weekly backup

    private func backupIfDue(to remote: URL) async {
        guard weeklyBackup, Date().timeIntervalSince(saved.lastBackup ?? .distantPast) > 7 * 86_400 else { return }
        let root = LibraryStore.defaultRootURL
        let folder = remote.appendingPathComponent("Backups", isDirectory: true)
        let name = LibraryBackup.fileName("InkPad Sync Backup")
        let ok: Bool = await Task.detached(priority: .background) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try LibraryBackup.writeArchive(of: root, to: folder.appendingPathComponent(name))
                // Keep the four newest.
                let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
                let zips = items.filter { $0.pathExtension == "zip" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
                for old in zips.dropFirst(4) { try? FileManager.default.removeItem(at: old) }
                return true
            } catch {
                return false
            }
        }.value
        if ok {
            saved.lastBackup = Date()
            persist()
            addLog("Weekly backup saved in the sync folder")
        }
    }

    // MARK: Base and log

    private func loadBase() -> SyncBase {
        guard let data = try? Data(contentsOf: baseURL), let base = try? JSONDecoder.inkpad.decode(SyncBase.self, from: data) else { return SyncBase() }
        return base
    }

    private func saveBase(_ base: SyncBase) {
        if let data = try? JSONEncoder.inkpad.encode(base) { try? data.write(to: baseURL, options: .atomic) }
    }

    private func addLog(_ text: String) {
        log.insert(LogEntry(date: Date(), text: text), at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
        saved.log = log
        persist()
    }

    func resolve(_ conflict: SyncConflict) {
        conflicts.removeAll { $0 == conflict }
        saved.conflicts = conflicts
        persist()
    }

    // MARK: Settings

    /// Preferences that belong to this copy only.
    private static let localKeys: [String] = ["syncSettings", "splitMemory", "organizeDismissed", "lastAutoBackupAt", "lastBackupAt"]

    static func exportSettings() -> Data? {
        guard let id = Bundle.main.bundleIdentifier, let domain = UserDefaults.standard.persistentDomain(forName: id) else { return nil }
        var values: [String: Any] = [:]
        for (key, value) in domain {
            if localKeys.contains(key) || key.hasPrefix("NS") || key.hasPrefix("Apple") || key.hasPrefix("com.apple") || key.hasPrefix("AK") { continue }
            values[key] = value
        }
        return try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    static func importSettings(_ data: Data) {
        guard let values = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return }
        for (key, value) in values where !localKeys.contains(key) {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}
