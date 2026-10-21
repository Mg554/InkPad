import SwiftUI
import UniformTypeIdentifiers

struct NotesGridView: View {
    @EnvironmentObject private var store: LibraryStore
    let scope: LibraryScope
    let openNote: (UUID) -> Void

    @State private var searchText = ""
    @State private var prompt: NamePrompt?
    @State private var noteToDelete: NoteSummary?
    @State private var isImportingPDF = false

    private var visibleNotes: [NoteSummary] {
        let notes = store.notes(in: scope)
        guard !searchText.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var title: String {
        switch scope {
        case .allNotes: "All Notes"
        case .unfiled: "Unfiled"
        case let .folder(id): store.folder(id)?.name ?? "Folder"
        }
    }

    private var targetFolderID: UUID? {
        switch scope {
        case let .folder(id): return id
        case .allNotes, .unfiled: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack {
                if visibleNotes.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Notes" : "No Results",
                        systemImage: searchText.isEmpty ? "square.and.pencil" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Tap the pencil button to create a note." : "")
                    )
                    .padding(.top, 80)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 24)], spacing: 28) {
                    ForEach(visibleNotes) { note in
                        Button {
                            openNote(note.id)
                        } label: {
                            NoteCard(note: note)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: note) }
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "Search titles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(PageTemplate.allCases) { template in
                        Button {
                            createNote(template)
                        } label: {
                            Label(template.title, systemImage: template.systemImage)
                        }
                    }
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImportingPDF = true
                } label: {
                    Label("Import PDF", systemImage: "doc.badge.arrow.up")
                }
            }
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            switch result {
            case let .success(url):
                if let note = store.importPDF(from: url, into: targetFolderID) {
                    openNote(note.id)
                }
            case let .failure(error):
                store.errorMessage = "Could not open the file: \(error.localizedDescription)"
            }
        }
        .namePrompt($prompt)
        .confirmationDialog(
            "Delete \"\(noteToDelete?.title ?? "")\"?",
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: noteToDelete
        ) { note in
            Button("Delete Note", role: .destructive) {
                store.deleteNote(note.id)
            }
        } message: { _ in
            Text("This cannot be undone.")
        }
    }

    @ViewBuilder
    private func menu(for note: NoteSummary) -> some View {
        Button {
            prompt = NamePrompt(
                title: "Rename Note",
                initialText: note.title,
                confirmTitle: "Rename"
            ) { store.renameNote(note.id, to: $0) }
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Menu {
            Button("Unfiled") { store.moveNote(note.id, to: nil) }
                .disabled(note.folderID == nil)
            ForEach(store.folders) { folder in
                Button(folder.name) { store.moveNote(note.id, to: folder.id) }
                    .disabled(note.folderID == folder.id)
            }
        } label: {
            Label("Move to", systemImage: "folder")
        }

        Button(role: .destructive) {
            noteToDelete = note
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func createNote(_ template: PageTemplate) {
        if let note = store.createNote(in: targetFolderID, template: template) {
            openNote(note.id)
        }
    }
}
