import SwiftUI

/// How to restore a backup: add what's missing, pick notes, or replace.
enum RestoreChoice {
    case addEverything
    case notes(Set<UUID>)
    case replace
}

/// Shown after a backup file is picked: what it holds compared with the
/// library now, and the ways to restore it.
struct RestoreOptionsView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let contents: LibraryBackup.Contents
    let choose: (RestoreChoice) -> Void

    @State private var confirmsReplace = false

    private enum Status {
        case new, newer, same
    }

    private func status(of note: NoteSummary) -> Status {
        let mine = store.note(note.id) ?? store.trashedNotes.first { $0.id == note.id }
        guard let mine else { return .new }
        return note.modifiedAt > mine.modifiedAt ? .newer : .same
    }

    var body: some View {
        let statuses = contents.notes.map { status(of: $0) }
        let newCount = statuses.filter { $0 == .new }.count
        let newerCount = statuses.filter { $0 == .newer }.count
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Backup from \(contents.manifest.createdAt.formatted(date: .long, time: .shortened))")
                            .font(.headline)
                        Text(Self.count(contents.notes.count, "note") + " in " + Self.count(contents.folders.count, "folder"))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            badge("\(newCount) new", color: .green)
                            badge("\(newerCount) newer", color: .orange)
                            badge("\(contents.notes.count - newCount - newerCount) same", color: .secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("New: not in your library now. Newer: changed in the backup after your copy.")
                }

                Section {
                    Button {
                        dismiss()
                        choose(.addEverything)
                    } label: {
                        option(
                            "Add to My Library",
                            detail: "Adds \(Self.count(newCount, "new note")) and updates \(Self.count(newerCount, "note")) that are newer in the backup, with missing folders, planner, mind maps, slides and flashcards. Nothing in your library is removed.",
                            image: "plus.square.on.square",
                            tint: .green,
                            recommended: true
                        )
                    }
                    NavigationLink {
                        BackupNotePicker(contents: contents, status: { status(of: $0) == .new }) { ids in
                            dismiss()
                            choose(.notes(ids))
                        }
                    } label: {
                        option(
                            "Choose Notes…",
                            detail: "Look through the backup and bring back only the notes you pick. A note you still have comes back as a copy, so both are kept.",
                            image: "checklist",
                            tint: .blue
                        )
                    }
                    Button {
                        confirmsReplace = true
                    } label: {
                        option(
                            "Replace Library",
                            detail: "Makes InkPad exactly like the backup. Notes made after it are removed from the library (a copy is kept first).",
                            image: "arrow.triangle.2.circlepath",
                            tint: .red
                        )
                    }
                } footer: {
                    Text("Before any restore, your current library is kept under Copies Kept Before Restoring, so it can always be undone.")
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Replace your whole library with this backup?", isPresented: $confirmsReplace, titleVisibility: .visible) {
                Button("Replace Library", role: .destructive) {
                    dismiss()
                    choose(.replace)
                }
            } message: {
                Text("Notes, folders, planner and everything else in InkPad now are replaced. A copy is kept under Copies Kept Before Restoring.")
            }
        }
    }

    private func option(_ title: String, detail: String, image: String, tint: Color, recommended: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: image)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(tint == .red ? Color.red : Color(uiColor: .label))
                    if recommended {
                        Text("Recommended")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 6)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }

    static func count(_ number: Int, _ word: String) -> String {
        number == 1 ? "1 \(word)" : "\(number) \(word)s"
    }
}

/// The backup's notes, to pick which to bring back.
private struct BackupNotePicker: View {
    let contents: LibraryBackup.Contents
    /// True for notes the library doesn't have now.
    let status: (NoteSummary) -> Bool
    let restore: (Set<UUID>) -> Void

    @State private var selection: Set<UUID> = []
    @State private var search = ""

    private var notes: [NoteSummary] {
        let sorted = contents.notes.sorted { $0.modifiedAt > $1.modifiedAt }
        guard !search.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func folderName(_ id: UUID?) -> String {
        id.flatMap { id in contents.folders.first { $0.id == id }?.name } ?? "Unfiled"
    }

    var body: some View {
        List(notes) { note in
            Button {
                if selection.contains(note.id) {
                    selection.remove(note.id)
                } else {
                    selection.insert(note.id)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selection.contains(note.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(note.id) ? Color.inkAccent : Color.secondary)
                    Image(systemName: note.isText ? "doc.text" : "pencil.and.scribble")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .foregroundStyle(Color(uiColor: .label))
                        Text("\(folderName(note.folderID)) · \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    Spacer()
                    Text(status(note) ? "Not in library" : "In library")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status(note) ? Color.green : Color.secondary)
                }
            }
        }
        .searchable(text: $search, prompt: "Search the backup")
        .navigationTitle("Choose Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selection.count == contents.notes.count ? "Select None" : "Select All") {
                    selection = selection.count == contents.notes.count ? [] : Set(contents.notes.map(\.id))
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    restore(selection)
                } label: {
                    Text(selection.isEmpty ? "Choose Notes to Restore" : "Restore \(RestoreOptionsView.count(selection.count, "Note"))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
            }
        }
    }
}
