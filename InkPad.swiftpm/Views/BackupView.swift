import SwiftUI
import UniformTypeIdentifiers

/// Back up the whole library to one file (saved to iCloud Drive or
/// anywhere in Files), and restore it on this or another iPad.
struct BackupView: View {
    static let lastBackupKey = "lastBackupAt"

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    /// Seconds since 1970; 0 when the library was never backed up.
    @AppStorage(Self.lastBackupKey) private var lastBackupAt: Double = 0

    @State private var progress: String?
    /// The finished backup in the temporary folder, waiting to be saved.
    @State private var backupURL: URL?
    @State private var isSavingBackup = false
    @State private var isPickingBackup = false
    @State private var pendingRestore: PendingRestore?
    @State private var safetyCopies: [SafetyCopy] = []
    @State private var automaticBackups: [SafetyCopy] = []
    @AppStorage(AutoBackupFrequency.storageKey) private var frequency: AutoBackupFrequency = .weekly
    @AppStorage(AutoBackupFrequency.keepKey) private var keep = 5
    @AppStorage(AutoBackupFrequency.lastKey) private var lastAutomaticAt: Double = 0
    @State private var notice: Notice?
    /// The restore picked in the options sheet; run once the sheet closes.
    @State private var chosen: (PendingRestore, RestoreChoice)?
    /// The backup shown in the options sheet (still set after it closes).
    @State private var shownPick: PendingRestore?

    private struct PendingRestore: Identifiable {
        let id = UUID()
        let url: URL
        let contents: LibraryBackup.Contents
        /// A picked file is a temporary copy; a safety copy is kept.
        let isTemporary: Bool
    }

    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("One file with everything in InkPad")
                                .font(.headline)
                            Text("Notes, PDFs, pictures, recordings, folders, planner, expenses, mind maps, slides, flashcards and study chats. AI keys are not included.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "externaldrive.badge.icloud")
                            .font(.title2)
                            .foregroundStyle(Color.inkAccent)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        Task { await backUp() }
                    } label: {
                        Label("Back Up Library…", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Back Up")
                } footer: {
                    Text(lastBackupText + " Save the file to iCloud Drive to keep it safe if this iPad is lost or InkPad is deleted.")
                }

                Section {
                    Button {
                        isPickingBackup = true
                    } label: {
                        Label("Restore from a Backup…", systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text("Restore")
                } footer: {
                    Text("Add the backup's notes to your library, choose which notes to bring back, or replace the library. Your current library is kept below first, so you can go back.")
                }

                Section {
                    Picker(selection: $frequency) {
                        ForEach(AutoBackupFrequency.allCases) { Text(tr($0.title)).tag($0) }
                    } label: {
                        Label("Automatic Backup", systemImage: "clock.arrow.2.circlepath")
                    }
                    if frequency != .off {
                        Stepper("Keep the Last \(keep)", value: $keep, in: 2...20)
                    }
                    ForEach(automaticBackups) { copy in
                        safetyCopyRow(copy)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            try? LibraryBackup.deleteSafetyCopy(automaticBackups[index])
                        }
                        automaticBackups = LibraryBackup.automaticBackups()
                    }
                } header: {
                    Text("Automatic Backups on This iPad")
                } footer: {
                    Text(trMessage(automaticFooter))
                }

                if !safetyCopies.isEmpty {
                    Section {
                        ForEach(safetyCopies) { copy in
                            safetyCopyRow(copy)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                try? LibraryBackup.deleteSafetyCopy(safetyCopies[index])
                            }
                            safetyCopies = LibraryBackup.safetyCopies()
                        }
                    } header: {
                        Text("Copies Kept Before Restoring")
                    } footer: {
                        Text("The last \(LibraryBackup.keptSafetyCopies) are kept on this iPad.")
                    }
                }
            }
            .disabled(progress != nil)
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(progress != nil)
                }
            }
            .overlay {
                if let progress {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(trMessage(progress))
                            .font(.headline)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        // Moves the backup out of the temporary folder to where the user
        // picks: iCloud Drive, On My iPad, a USB drive ...
        .fileMover(isPresented: $isSavingBackup, file: backupURL) { result in
            if case .success = result {
                lastBackupAt = Date().timeIntervalSince1970
            } else if case let .failure(error) = result {
                notice = Notice(title: "Backup Not Saved", message: error.localizedDescription)
            }
            discardBackupFile()
        } onCancellation: {
            discardBackupFile()
        }
        .fileImporter(isPresented: $isPickingBackup, allowedContentTypes: [.zip]) { result in
            switch result {
            case let .success(url):
                Task { await pick(url) }
            case let .failure(error):
                notice = Notice(title: "Cannot Open the File", message: error.localizedDescription)
            }
        }
        .sheet(item: $pendingRestore, onDismiss: discardUnusedPick) { pending in
            RestoreOptionsView(contents: pending.contents) { choice in
                chosen = (pending, choice)
            }
            .environmentObject(store)
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(tr(notice.title)), message: Text(trMessage(notice.message)))
        }
        .interactiveDismissDisabled(progress != nil)
        .onChange(of: frequency) {
            Task {
                await store.makeAutomaticBackupIfDue(workspace: workspace)
                automaticBackups = LibraryBackup.automaticBackups()
            }
        }
        .onAppear {
            automaticBackups = LibraryBackup.automaticBackups()
            safetyCopies = LibraryBackup.safetyCopies()
        }
    }

    private func safetyCopyRow(_ copy: SafetyCopy) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.date.formatted(date: .abbreviated, time: .shortened))
                Text(ByteCountFormatter.string(fromByteCount: copy.byteCount, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") {
                Task { await check(copy.url, isTemporary: false) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var automaticFooter: String {
        guard frequency != .off else {
            return "Turn on to have InkPad back up the library by itself when you open it. Each backup can be restored like a backup file, and earlier versions of a note can be brought back from its menu."
        }
        let last = lastAutomaticAt > 0
            ? "Last one: \(Date(timeIntervalSince1970: lastAutomaticAt).formatted(.relative(presentation: .named)))."
            : "The first one is made now."
        return "\(last) Kept on this iPad only, so also save a backup to iCloud Drive now and then. Earlier versions of a note can be brought back from its menu (Earlier Versions…)."
    }

    private var lastBackupText: String {
        guard lastBackupAt > 0 else { return "Not backed up yet." }
        let date = Date(timeIntervalSince1970: lastBackupAt)
        return "Last backup: \(date.formatted(.relative(presentation: .named)))."
    }

    // MARK: Actions

    private func backUp() async {
        progress = "Backing Up…"
        defer { progress = nil }
        do {
            backupURL = try await store.makeBackup()
            isSavingBackup = true
        } catch {
            notice = Notice(title: "Backup Failed", message: error.localizedDescription)
        }
    }

    private func discardBackupFile() {
        if let backupURL {
            try? FileManager.default.removeItem(at: backupURL)
        }
        backupURL = nil
    }

    /// Copies the picked file into the temporary folder (downloading it
    /// from iCloud first if needed), then checks it.
    private func pick(_ url: URL) async {
        progress = "Opening Backup…"
        do {
            let copy = try await LibraryBackup.copyPickedFile(url)
            progress = nil
            await check(copy, isTemporary: true)
        } catch {
            progress = nil
            notice = Notice(title: "Cannot Open the File", message: error.localizedDescription)
        }
    }

    private func check(_ url: URL, isTemporary: Bool) async {
        progress = "Checking Backup…"
        defer { progress = nil }
        do {
            let contents = try await store.readBackupContents(at: url)
            let pick = PendingRestore(url: url, contents: contents, isTemporary: isTemporary)
            shownPick = pick
            pendingRestore = pick
        } catch {
            if isTemporary {
                try? FileManager.default.removeItem(at: url)
            }
            notice = Notice(title: "Cannot Restore", message: error.localizedDescription)
        }
    }

    /// After the options sheet closes: runs the chosen restore, or removes
    /// the picked file if nothing was chosen.
    private func discardUnusedPick() {
        if let (pending, choice) = chosen {
            chosen = nil
            Task { await restore(pending, choice) }
        } else if let pending = shownPick, pending.isTemporary {
            try? FileManager.default.removeItem(at: pending.url)
        }
        shownPick = nil
    }

    private func restore(_ pending: PendingRestore, _ choice: RestoreChoice) async {
        progress = "Restoring…"
        defer {
            progress = nil
            safetyCopies = LibraryBackup.safetyCopies()
            if pending.isTemporary {
                try? FileManager.default.removeItem(at: pending.url)
            }
        }
        do {
            switch choice {
            case .replace:
                try await store.restoreBackup(at: pending.url)
                workspace.reload()
                notice = Notice(title: "Library Restored", message: RestoreOptionsView.count(store.notes.count, "note") + " in your library now.")
            case .addEverything:
                let result = try await store.addFromBackup(at: pending.url, mode: .everything)
                workspace.reload()
                notice = Notice(
                    title: "Added from Backup",
                    message: "\(RestoreOptionsView.count(result.added, "note")) added and \(RestoreOptionsView.count(result.updated, "note")) updated. Nothing was removed."
                )
            case let .notes(ids):
                let result = try await store.addFromBackup(at: pending.url, mode: .notes(ids))
                notice = Notice(
                    title: "Notes Restored",
                    message: [
                        result.added > 0 ? "\(RestoreOptionsView.count(result.added, "note")) restored." : nil,
                        result.copied > 0
                            ? "\(RestoreOptionsView.count(result.copied, "note")) you still had came back as a copy, marked \"(from backup)\"; your own stays as it is."
                            : nil,
                    ].compactMap { $0 }.joined(separator: " ")
                )
            }
        } catch {
            notice = Notice(title: "Restore Failed", message: "Nothing was changed. \(error.localizedDescription)")
        }
    }
}
