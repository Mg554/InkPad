import PhotosUI
import PencilKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var palette: ToolPalette
    @Environment(\.scenePhase) private var scenePhase
    let noteID: UUID

    @StateObject private var session = EditorSession()
    @State private var exportedFile: ExportedFile?
    @State private var isExporting = false
    @State private var isShowingExportOptions = false
    @State private var isShowingTemplates = false
    @AppStorage("showPageSidebar") private var isShowingPages = false
    @State private var isPickingPhoto = false
    @State private var isPickingImageFile = false
    @State private var photoItem: PhotosPickerItem?
    @State private var prompt: NamePrompt?
    @AppStorage("pencilOnly") private var pencilOnly = true

    private var canvas: CanvasController { session.canvas }
    private var title: String { store.note(noteID)?.title ?? "Note" }

    var body: some View {
        Group {
            if let content = session.initialContent, let background = session.background {
                HStack(spacing: 0) {
                    canvasArea(content: content, background: background)
                    if isShowingPages, let snapshot = session.snapshot {
                        Divider()
                        PageSidebar(
                            canvas: canvas,
                            content: snapshot,
                            revision: session.snapshotRevision,
                            background: background,
                            insertPage: { session.insertPage(after: $0) },
                            deletePage: { session.deletePage(at: $0) }
                        )
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(.snappy(duration: 0.25), value: isShowingPages)
            } else if let loadError = session.loadError {
                ContentUnavailableView(
                    "Could Not Open Note",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .overlay {
            if isExporting {
                ProgressView("Exporting…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .namePrompt($prompt)
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url])
        }
        .sheet(isPresented: $isShowingExportOptions) {
            ExportOptionsView(pageCount: canvas.pageCount, currentPage: canvas.currentPage) { options in
                export(options)
            }
        }
        .sheet(isPresented: $isShowingTemplates) {
            TemplateGallery(
                template: session.metadata?.template ?? .lined,
                paper: session.metadata?.paperColor ?? .white
            ) { template, paper in
                session.updateMetadata {
                    $0.template = template
                    $0.paperColor = paper == .white ? nil : paper
                }
            }
        }
        .sheet(isPresented: $isPickingImageFile) {
            DocumentPicker(contentTypes: [.image]) { urls in
                for url in urls {
                    if let data = try? Data(contentsOf: url) { insertImage(data) }
                    try? FileManager.default.removeItem(at: url)
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    insertImage(data)
                }
            }
        }
        .task { session.load(noteID: noteID, store: store) }
        .onDisappear { session.save(thumbnail: true) }
        .onChange(of: scenePhase) {
            if scenePhase != .active { session.save(thumbnail: true) }
        }
    }

    private func canvasArea(content: NoteContent, background: NoteBackground) -> some View {
        NoteCanvas(
            initialContent: content,
            background: background,
            pencilOnly: pencilOnly,
            controller: canvas,
            palette: palette
        )
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .top) {
            DrawingToolbar(canvas: canvas, pencilOnly: $pencilOnly) {
                insertMenu
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .overlay(alignment: .bottomTrailing) {
            PageNavigator(canvas: canvas) { isShowingPages.toggle() }
                .padding(16)
        }
    }

    // MARK: Menus

    @ViewBuilder
    private var insertMenu: some View {
        Button {
            isPickingPhoto = true
        } label: {
            Label("Photo", systemImage: "photo")
        }
        Button {
            isPickingImageFile = true
        } label: {
            Label("Image from Files", systemImage: "folder")
        }
        Button {
            palette.select(.text)
            canvas.applyTool()
        } label: {
            Label("Text Box", systemImage: "textformat")
        }
        Divider()
        Button {
            session.insertPage(after: canvas.currentPage)
        } label: {
            Label("Add Page", systemImage: "doc.badge.plus")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            UndoRedoButtons(canvas: canvas)

            Button {
                export(PDFExportOptions())
            } label: {
                Label("Quick Export", systemImage: "square.and.arrow.up")
            }
            .disabled(session.metadata == nil || isExporting)

            Menu {
                Section {
                    Button {
                        export(PDFExportOptions())
                    } label: {
                        Label("Quick Export (PDF, All Pages)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isShowingExportOptions = true
                    } label: {
                        Label("Export as…", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                Section {
                    Button {
                        isShowingTemplates = true
                    } label: {
                        Label("Template Settings", systemImage: "doc.richtext")
                    }
                    Button {
                        session.insertPage(after: canvas.currentPage)
                    } label: {
                        Label("Add Page After This One", systemImage: "doc.badge.plus")
                    }
                }
                Section {
                    Button {
                        prompt = NamePrompt(
                            title: "Rename Note",
                            initialText: title,
                            confirmTitle: "Rename"
                        ) { store.renameNote(noteID, to: $0) }
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    if let note = store.note(noteID) {
                        Text("Edited \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(session.metadata == nil)

            Button {
                isShowingPages.toggle()
            } label: {
                Label("Pages", systemImage: "sidebar.right")
            }
            .disabled(session.metadata == nil)
        }
    }

    // MARK: Actions

    private func export(_ options: PDFExportOptions) {
        guard !isExporting, let content = session.currentContent() else { return }
        session.save(thumbnail: false)
        isExporting = true
        let noteTitle = title
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try PDFExporter.export(content, title: noteTitle, options: options) }
            }.value
            isExporting = false
            switch result {
            case let .success(url):
                exportedFile = ExportedFile(url: url)
            case let .failure(error):
                store.errorMessage = "Could not export the PDF: \(error.localizedDescription)"
            }
        }
    }

    private func insertImage(_ data: Data) {
        Task {
            guard let added = await store.addImage(data, to: noteID),
                  let directory = session.imageDirectory,
                  let image = UIImage(contentsOfFile: directory.appendingPathComponent(added.file).path)
            else { return }
            canvas.insertImage(file: added.file, image: image, pixelSize: added.size)
        }
    }
}

/// Observes the canvas directly so undo state updates without re-rendering the editor.
private struct UndoRedoButtons: View {
    @ObservedObject var canvas: CanvasController

    var body: some View {
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
    }
}
