import SwiftUI

/// Earlier versions of a note, found in the automatic backups and safety
/// copies kept on this iPad. A version comes back as a copy next to the
/// note, so nothing is overwritten.
struct NoteHistoryView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let note: NoteSummary

    @State private var versions: [LibraryBackup.NoteVersion]?
    @State private var restoring: URL?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if let versions {
                    if versions.isEmpty {
                        ContentUnavailableView(
                            "No Earlier Versions",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Versions come from the automatic backups kept on this iPad. Turn them on in Backup (the drive button at the top of the sidebar).")
                        )
                    } else {
                        List(versions) { version in
                            row(version)
                        }
                    }
                } else {
                    ProgressView("Looking through backups…")
                }
            }
            .navigationTitle("Earlier Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Version Restored", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
        .task {
            let id = note.id
            versions = await Task.detached(priority: .userInitiated) {
                LibraryBackup.versions(of: id)
            }.value
        }
    }

    private func row(_ version: LibraryBackup.NoteVersion) -> some View {
        let isCurrent = version.note.modifiedAt == store.note(note.id)?.modifiedAt
        return HStack(spacing: 14) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Edited \(version.note.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.headline)
                Text(isCurrent ? "Same as now" : "Saved in the backup of \(version.backupDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if restoring == version.archive {
                ProgressView()
            } else if !isCurrent {
                Button("Restore as Copy") { restore(version) }
                    .buttonStyle(.bordered)
                    .disabled(restoring != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func restore(_ version: LibraryBackup.NoteVersion) {
        restoring = version.archive
        Task {
            defer { restoring = nil }
            do {
                _ = try await store.addFromBackup(at: version.archive, mode: .notes([note.id]))
                message = "The version from \(version.note.modifiedAt.formatted(date: .abbreviated, time: .shortened)) is next to the note as \"\(note.title) (from backup)\"."
            } catch {
                message = "Couldn't restore it: \(error.localizedDescription)"
            }
        }
    }
}
