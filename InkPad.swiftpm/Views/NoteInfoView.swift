import SwiftUI

/// The note's details (the `i` in the card menu): when it was made and last
/// changed, its size, where it lives — and a place for the owner's own
/// details.
struct NoteInfoView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let note: NoteSummary
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    row(tr("Title"), note.title)
                    row(tr("Created"), note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    row(tr("Modified"), note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    row(tr("Kind"), tr(kindTitle))
                    if let folder = note.folderID.flatMap({ store.folder($0)?.name }) {
                        row(tr("Folder"), folder)
                    } else {
                        row(tr("Folder"), tr("Unfiled"))
                    }
                    if let pageCount = note.pageCount, pageCount > 0 {
                        row(tr("Pages"), String(pageCount))
                    }
                    if let counts = textCounts {
                        row(tr("Words"), String(counts.words))
                        row(tr("Characters"), String(counts.characters))
                    }
                    if let tags = note.tags, !tags.isEmpty {
                        row(tr("Tags"), tags.joined(separator: ", "))
                    }
                    if note.locked {
                        row(tr("Locked"), tr("Yes"))
                    }
                }
                Section {
                    TextField(tr("Add details…"), text: $details, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text(tr("Details"))
                } footer: {
                    Text(tr("Your own notes about this note — saved with the library."))
                }
            }
            .navigationTitle(tr("Note Info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
            .onAppear { details = store.note(note.id)?.details ?? "" }
            .onChange(of: details) {
                guard details != (store.note(note.id)?.details ?? "") else { return }
                store.setDetails(details, for: note.id)
            }
        }
    }

    private var kindTitle: String {
        switch note.kind {
        case .text: "Text Note"
        case .handwritten, nil: "Handwritten"
        }
    }

    /// The text note's size, from the live index.
    private var textCounts: (words: Int, characters: Int)? {
        guard let text = store.textIndex[note.id]?.text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.isEmpty ? 0 : trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        return (words, text.count)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
