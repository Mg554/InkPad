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
    @State private var notice: Notice?

    private struct PendingRestore: Identifiable {
        let id = UUID()
        let url: URL
        let manifest: BackupManifest
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
                            .foregroundStyle(Color.accentColor)
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
                    Text("Replaces everything in InkPad with the backup. Your current library is kept below first, so you can go back.")
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
                        Text(progress)
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
        .alert(
            "Replace Your Library?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { cancelRestore() } }
            ),
            presenting: pendingRestore
        ) { pending in
            Button("Replace Library", role: .destructive) {
                // Cleared first, so closing the alert keeps the picked file.
                pendingRestore = nil
                Task { await restore(pending) }
            }
            Button("Cancel", role: .cancel) {
                cancelRestore()
            }
        } message: { pending in
            Text(restoreMessage(pending.manifest))
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
        .interactiveDismissDisabled(progress != nil)
        .onAppear {
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

    private var lastBackupText: String {
        guard lastBackupAt > 0 else { return "Not backed up yet." }
        let date = Date(timeIntervalSince1970: lastBackupAt)
        return "Last backup: \(date.formatted(.relative(presentation: .named)))."
    }

    private func restoreMessage(_ manifest: BackupManifest) -> String {
        let date = manifest.createdAt.formatted(date: .long, time: .shortened)
        let notes = manifest.noteCount == 1 ? "1 note" : "\(manifest.noteCount) notes"
        let folders = manifest.folderCount == 1 ? "1 folder" : "\(manifest.folderCount) folders"
        return [
            "This backup from \(date) has \(notes) in \(folders).",
            "It replaces all notes, folders, planner, expenses, mind maps, slides and study in InkPad now.",
            "A copy of your current library is kept under Copies Kept Before Restoring."
        ].joined(separator: " ")
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
            let manifest = try await store.readBackup(at: url)
            pendingRestore = PendingRestore(url: url, manifest: manifest, isTemporary: isTemporary)
        } catch {
            if isTemporary {
                try? FileManager.default.removeItem(at: url)
            }
            notice = Notice(title: "Cannot Restore", message: error.localizedDescription)
        }
    }

    private func cancelRestore() {
        if let pending = pendingRestore, pending.isTemporary {
            try? FileManager.default.removeItem(at: pending.url)
        }
        pendingRestore = nil
    }

    private func restore(_ pending: PendingRestore) async {
        progress = "Restoring…"
        defer {
            progress = nil
            safetyCopies = LibraryBackup.safetyCopies()
            if pending.isTemporary {
                try? FileManager.default.removeItem(at: pending.url)
            }
        }
        do {
            try await store.restoreBackup(at: pending.url)
            workspace.reload()
            let count = store.notes.count
            notice = Notice(
                title: "Library Restored",
                message: count == 1 ? "1 note was restored." : "\(count) notes were restored."
            )
        } catch {
            notice = Notice(title: "Restore Failed", message: "Nothing was changed. \(error.localizedDescription)")
        }
    }
}
