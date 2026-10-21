import PencilKit
import SwiftUI

struct NoteEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    let noteID: UUID

    @StateObject private var canvas = CanvasController()
    @State private var content: NoteContent?
    /// Derived from `content`; rebuilt only when pages or paper change.
    @State private var background: NoteBackground?
    @State private var exportedFile: ExportedFile?
    @State private var loadError: String?
    @State private var isDirty = false
    @State private var saveTask: Task<Void, Never>?
    @State private var prompt: NamePrompt?
    @AppStorage("pencilOnly") private var pencilOnly = true

    var body: some View {
        Group {
            if let content, let background {
                NoteCanvas(
                    initialDrawing: content.drawing,
                    background: background,
                    pencilOnly: pencilOnly,
                    controller: canvas,
                    onDrawingChange: drawingChanged
                )
                .ignoresSafeArea(edges: .bottom)
            } else if let loadError {
                ContentUnavailableView(
                    "Could Not Open Note",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(store.note(noteID)?.title ?? "Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .namePrompt($prompt)
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url])
        }
        .task { load() }
        .onDisappear { saveNow() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { saveNow() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                canvas.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canvas.canUndo)

            Button {
                canvas.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!canvas.canRedo)

            Toggle(isOn: $pencilOnly) {
                Label("Pencil Only", systemImage: "applepencil")
            }
            .toggleStyle(.button)

            Button {
                addPage()
            } label: {
                Label("Add Page", systemImage: "doc.badge.plus")
            }
            .disabled(content == nil)

            Menu {
                Picker(selection: templateBinding) {
                    ForEach(PageTemplate.allCases) { template in
                        Label(template.title, systemImage: template.systemImage)
                            .tag(template)
                    }
                } label: {
                    Label("Paper", systemImage: "doc.richtext")
                }
                .pickerStyle(.menu)

                Toggle(isOn: $canvas.isToolPickerVisible) {
                    Label("Tool Palette", systemImage: "paintpalette")
                }

                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }

                Button {
                    prompt = NamePrompt(
                        title: "Rename Note",
                        initialText: store.note(noteID)?.title ?? "",
                        confirmTitle: "Rename"
                    ) { store.renameNote(noteID, to: $0) }
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(content == nil)
        }
    }

    private var templateBinding: Binding<PageTemplate> {
        Binding(
            get: { content?.metadata.template ?? .blank },
            set: { template in
                guard content?.metadata.template != template else { return }
                content?.metadata.template = template
                pagesChanged()
            }
        )
    }

    private func load() {
        guard content == nil, loadError == nil else { return }
        do {
            content = try store.loadContent(for: noteID)
            background = content?.makeBackground()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func drawingChanged(_ drawing: PKDrawing) {
        content?.drawing = drawing
        markDirty()
    }

    private func addPage() {
        content?.metadata.pageCount += 1
        pagesChanged()
    }

    private func pagesChanged() {
        background = content?.makeBackground()
        markDirty()
    }

    private func exportPDF() {
        guard let content else { return }
        saveNow()
        do {
            let url = try PDFExporter.export(content, title: store.note(noteID)?.title ?? "Note")
            exportedFile = ExportedFile(url: url)
        } catch {
            store.errorMessage = "Could not export the PDF: \(error.localizedDescription)"
        }
    }

    /// Saves shortly after the last change so fast writing is not slowed by disk I/O.
    private func markDirty() {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty, let content else { return }
        if store.saveContent(content, for: noteID) {
            isDirty = false
        }
    }
}
