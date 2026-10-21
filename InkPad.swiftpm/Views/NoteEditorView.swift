import PencilKit
import SwiftUI

struct NoteEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var palette: ToolPalette
    @Environment(\.scenePhase) private var scenePhase
    let noteID: UUID

    @StateObject private var canvas = CanvasController()
    @State private var content: NoteContent?
    /// Derived from `content`; rebuilt only when pages or paper change.
    @State private var background: NoteBackground?
    @State private var exportedFile: ExportedFile?
    @State private var isShowingPages = false
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
                    palette: palette,
                    onDrawingChange: drawingChanged
                )
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .top) {
                    DrawingToolbar(canvas: canvas, pencilOnly: $pencilOnly)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                }
                .overlay(alignment: .bottomTrailing) {
                    PageNavigator(canvas: canvas) { isShowingPages = true }
                        .padding(16)
                }
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
        .sheet(isPresented: $isShowingPages) {
            if let content, let background {
                PageOverview(
                    drawing: canvas.drawing ?? content.drawing,
                    background: background,
                    currentPage: canvas.currentPage
                ) { canvas.scrollToPage($0) }
            }
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

            Button {
                exportPDF()
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.up")
            }
            .disabled(content == nil)

            Button {
                isShowingPages = true
            } label: {
                Label("Pages", systemImage: "square.on.square")
            }
            .disabled(content == nil)

            Menu {
                Button {
                    addPage()
                } label: {
                    Label("Add Page", systemImage: "doc.badge.plus")
                }

                Picker(selection: templateBinding) {
                    ForEach(PageTemplate.allCases) { template in
                        Label(template.title, systemImage: template.systemImage)
                            .tag(template)
                    }
                } label: {
                    Label("Paper", systemImage: "doc.richtext")
                }
                .pickerStyle(.menu)

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
