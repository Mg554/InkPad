import PDFKit
import SwiftUI

/// Pull pages from another PDF (a note or a file) into the open note,
/// after the page being read.
struct InsertPagesSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let afterPage: Int
    let insert: ([Int], PDFDocument) throws -> Void

    @State private var source: PDFSourceItem?
    @State private var document: PDFDocument?
    @State private var selection: Set<Int> = []
    @State private var rangeText = ""
    @State private var isPickingFile = false
    @State private var isPickingNote = false
    @State private var working: String?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let source {
                        Label(tr(source.title), systemImage: source.isFile ? "doc" : "doc.richtext")
                    }
                    Button {
                        isPickingNote = true
                    } label: {
                        Label("From the Library…", systemImage: "books.vertical")
                    }
                    Button {
                        isPickingFile = true
                    } label: {
                        Label("From Files…", systemImage: "folder")
                    }
                } header: {
                    Text("Take Pages From")
                } footer: {
                    Text("The pages go after page \(afterPage + 1) of this note, and later pages move down with what is written on them.")
                }
                if let document {
                    Section("Pages") {
                        HStack {
                            TextField("Pages, like 3-7, 12", text: $rangeText)
                            Button("Select") {
                                selection = Set(PDFToolKit.pages(from: rangeText, pageCount: document.pageCount))
                            }
                            .disabled(rangeText.isEmpty)
                        }
                        Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
                        PageThumbnailGrid(document: document, selection: $selection)
                    }
                }
            }
            .navigationTitle("Insert Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") { run() }
                        .disabled(selection.isEmpty || working != nil)
                }
            }
            .overlay {
                if let working {
                    ProgressView(working)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Insert Pages", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .sheet(isPresented: $isPickingFile) {
                DocumentPicker(contentTypes: [.pdf]) { urls in
                    isPickingFile = false
                    if let url = urls.first {
                        load(PDFSourceItem(kind: .file(url), title: url.deletingPathExtension().lastPathComponent))
                    }
                }
            }
            .sheet(isPresented: $isPickingNote) {
                PDFNotePicker { notes in
                    isPickingNote = false
                    if let note = notes.first {
                        load(PDFSourceItem(kind: .note(note.id), title: note.title))
                    }
                }
                .environmentObject(store)
            }
        }
    }

    private func load(_ item: PDFSourceItem) {
        source = item
        working = "Opening “\(item.title)”…"
        Task {
            defer { working = nil }
            do {
                document = try await store.pdfDocument(for: item)
                selection = []
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func run() {
        guard let document else { return }
        working = "Inserting…"
        let pages = selection.sorted()
        do {
            try insert(pages, document)
            CommandCenter.shared.say("\(pages.count) pages added")
            dismiss()
        } catch {
            working = nil
            problem = error.localizedDescription
        }
    }
}

/// Some pages of the open note, with what is written on them, as a new note.
struct SendPagesSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let content: NoteContent
    let title: String
    let folderID: UUID?
    let currentPage: Int

    @State private var rangeText = ""
    @State private var newTitle = ""
    @State private var working = false
    @State private var problem: String?

    private var pageCount: Int { content.makeBackground().layout.pageRects.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pages, like 4-9, 15", text: $rangeText)
                    HStack {
                        Button("This Page") { rangeText = "\(currentPage + 1)" }
                        Button("This and the Next 4") { rangeText = "\(currentPage + 1)-\(min(currentPage + 5, pageCount))" }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text("Pages (of \(pageCount))")
                } footer: {
                    Text("The new note keeps what you wrote on these pages. This note stays as it is.")
                }
                Section("New Note") {
                    TextField("Title", text: $newTitle)
                }
            }
            .navigationTitle("Send Pages to a New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Make") { run() }
                        .disabled(PDFToolKit.pages(from: rangeText, pageCount: pageCount).isEmpty || working)
                }
            }
            .overlay {
                if working {
                    ProgressView("Making the note…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Send Pages", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .onAppear {
                rangeText = "\(currentPage + 1)"
                newTitle = "\(title) (pages)"
            }
        }
    }

    private func run() {
        var options = PDFExportOptions()
        options.pageSet = Set(PDFToolKit.pages(from: rangeText, pageCount: pageCount))
        let content = content
        let name = newTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "\(title) (pages)" : newTitle
        working = true
        Task {
            defer { working = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try PDFExporter.export(content, title: name, options: options)
                }.value
                if store.importPDF(from: url, into: folderID) != nil {
                    CommandCenter.shared.say("“\(name)” is a new note")
                    dismiss()
                }
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
