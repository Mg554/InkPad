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
    @State private var isShowingTemplates = false

    private var visibleNotes: [NoteSummary] {
        let notes = store.notes(in: scope)
        guard !searchText.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var title: String {
        switch scope {
        case .allNotes: "All Notes"
        case .unfiled: "Unfiled"
        case .planner: "Planner"
        case .expenses: "Expenses"
        case let .folder(id): store.folder(id)?.name ?? "Folder"
        }
    }

    private var targetFolderID: UUID? {
        switch scope {
        case let .folder(id): return id
        case .allNotes, .unfiled, .planner, .expenses: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if searchText.isEmpty {
                    quickActions
                        .padding([.horizontal, .top], 24)
                }
                if visibleNotes.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Notes" : "No Results",
                        systemImage: searchText.isEmpty ? "square.and.pencil" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Create a note or import a PDF." : "")
                    )
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
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
                    templateButtons
                    Button {
                        isShowingTemplates = true
                    } label: {
                        Label("More Templates…", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button {
                        isImportingPDF = true
                    } label: {
                        Label("Import PDF", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("New", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $isShowingTemplates) {
            TemplateGallery(title: "New Note", applyTitle: "Create") { template, paper in
                if let note = store.createNote(in: targetFolderID, template: template, paper: paper) {
                    openNote(note.id)
                }
            }
        }
        .sheet(isPresented: $isImportingPDF) {
            DocumentPicker(contentTypes: [.pdf]) { urls in
                importPDFs(urls)
            }
            .ignoresSafeArea()
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
            ForEach(store.folderTree()) { row in
                Button(String(repeating: "    ", count: row.depth) + row.folder.name) {
                    store.moveNote(note.id, to: row.folder.id)
                }
                .disabled(note.folderID == row.folder.id)
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

    /// Notability-style shortcut cards above the notes.
    private var quickActions: some View {
        HStack(spacing: 16) {
            QuickActionCard(title: "New Note", systemImage: "square.and.pencil", tint: .indigo) {
                createNote(.lined)
            }
            QuickActionCard(title: "Import a File", systemImage: "square.and.arrow.down", tint: .teal) {
                isImportingPDF = true
            }
            QuickActionCard(title: "Find a Template", systemImage: "doc.on.doc", tint: .orange) {
                isShowingTemplates = true
            }
        }
    }

    @ViewBuilder
    private var templateButtons: some View {
        ForEach(PageTemplate.allCases.filter { $0.section == .basic }) { template in
            Button {
                createNote(template)
            } label: {
                Label("\(template.title) Note", systemImage: template.systemImage)
            }
        }
    }

    private func importPDFs(_ urls: [URL]) {
        var lastImported: NoteSummary?
        for url in urls {
            if let note = store.importPDF(from: url, into: targetFolderID) {
                lastImported = note
            }
            // The picker handed us a temporary copy; the store has its own now.
            try? FileManager.default.removeItem(at: url)
        }
        if urls.count == 1, let lastImported {
            openNote(lastImported.id)
        }
    }

    private func createNote(_ template: PageTemplate) {
        if let note = store.createNote(in: targetFolderID, template: template) {
            openNote(note.id)
        }
    }
}


private struct QuickActionCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

private struct QuickActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.35)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
