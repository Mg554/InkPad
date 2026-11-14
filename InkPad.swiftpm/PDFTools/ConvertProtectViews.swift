import PDFKit
import PencilKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// The Convert and Protect tools of PDF Tools.
enum PDFExtraTool: String, CaseIterable, Identifiable {
    case imagesToPDF, scan, webPage, pdfToImages, extractImages
    case compress, password, unlock, redact, watermark, pageNumbers, sign

    var id: Self { self }

    static let convert: [PDFExtraTool] = [.imagesToPDF, .scan, .webPage, .pdfToImages, .extractImages]
    static let protect: [PDFExtraTool] = [.compress, .password, .unlock, .redact, .watermark, .pageNumbers, .sign]

    var title: String {
        switch self {
        case .imagesToPDF: "Images to PDF"
        case .scan: "Scan with Camera"
        case .webPage: "Web Page to PDF"
        case .pdfToImages: "PDF to Images"
        case .extractImages: "Extract Images"
        case .compress: "Compress PDF"
        case .password: "Protect with Password"
        case .unlock: "Unlock PDF"
        case .redact: "Redact PDF"
        case .watermark: "Add Watermark"
        case .pageNumbers: "Add Page Numbers"
        case .sign: "Sign PDF"
        }
    }

    var detail: String {
        switch self {
        case .imagesToPDF: "Photos or pictures from Files, one page each."
        case .scan: "Scan papers with the camera into a searchable note."
        case .webPage: "Save a web page as pages (needs the internet)."
        case .pdfToImages: "Pages as pictures to share or save."
        case .extractImages: "The pictures stored inside a PDF."
        case .compress: "A smaller file, for sharing big scans."
        case .password: "A copy that needs a password to open."
        case .unlock: "Open a locked PDF with its password."
        case .redact: "Black out words or areas for good."
        case .watermark: "Text across every page, like CONFIDENTIAL."
        case .pageNumbers: "Numbers on every page."
        case .sign: "Write your signature and place it."
        }
    }

    var systemImage: String {
        switch self {
        case .imagesToPDF: "photo.on.rectangle"
        case .scan: "doc.viewfinder"
        case .webPage: "globe"
        case .pdfToImages: "photo.stack"
        case .extractImages: "photo.badge.arrow.down"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .password: "lock"
        case .unlock: "lock.open"
        case .redact: "rectangle.fill.badge.xmark"
        case .watermark: "drop"
        case .pageNumbers: "number"
        case .sign: "signature"
        }
    }

    var tint: Color {
        switch self {
        case .imagesToPDF, .pdfToImages, .extractImages: .pink
        case .scan: .indigo
        case .webPage: .cyan
        case .compress: .mint
        case .password, .unlock: .gray
        case .redact: .black
        case .watermark: .blue
        case .pageNumbers: .orange
        case .sign: .purple
        }
    }

    /// Tools that take one PDF.
    var takesPDF: Bool {
        switch self {
        case .imagesToPDF, .scan, .webPage: false
        default: true
        }
    }
}

/// One Convert or Protect tool.
struct PDFExtraToolSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let tool: PDFExtraTool

    // Source
    @State private var source: PDFSourceItem?
    @State private var lockedURL: URL?
    @State private var document: PDFDocument?
    @State private var isPickingFile = false
    @State private var isPickingNote = false
    // Images
    @State private var images: [UIImage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isPickingImageFiles = false
    @State private var isScanning = false
    @State private var scanSearchable = true
    // Options
    @State private var selection: Set<Int> = []
    @State private var address = "https://"
    @State private var quality = 1
    @State private var keepsText = false
    @State private var password = ""
    @State private var redactWords = ""
    @State private var redactBoxes: [Int: [CGRect]] = [:]
    @State private var redactPage = 0
    @State private var watermark = "CONFIDENTIAL"
    @State private var watermarkSize: Double = 64
    @State private var watermarkOpacity: Double = 0.18
    @State private var numberPlace = PDFEdit.NumberPlace.bottomCenter
    @State private var numberStyle = 0
    @State private var signature = PKDrawing()
    @State private var signPage = 1
    @State private var signPlace = PDFEdit.NumberPlace.bottomRight
    @State private var signWidth: Double = 160
    // Running
    @State private var working: String?
    @State private var problem: String?
    @State private var done: String?
    @State private var shared: ExportedFile?

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                optionsSection
                if let done {
                    Section { Label(tr(done), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle(tr(tool.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(done == nil ? "Cancel" : "Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Make") { run() }.disabled(!canRun || working != nil)
                }
            }
            .overlay {
                if let working {
                    ProgressView(working)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert(tool.title, isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .sheet(isPresented: $isPickingFile) {
                DocumentPicker(contentTypes: [.pdf]) { urls in
                    isPickingFile = false
                    if let url = urls.first { pickedFile(url) }
                }
            }
            .sheet(isPresented: $isPickingImageFiles) {
                DocumentPicker(contentTypes: [.image]) { urls in
                    isPickingImageFiles = false
                    images += urls.compactMap { UIImage(contentsOfFile: $0.path) }
                }
            }
            .sheet(isPresented: $isPickingNote) {
                PDFNotePicker { notes in
                    isPickingNote = false
                    if let note = notes.first { load(PDFSourceItem(kind: .note(note.id), title: note.title)) }
                }
                .environmentObject(store)
            }
            .fullScreenCover(isPresented: $isScanning) {
                DocumentScanner { scanned in
                    isScanning = false
                    images += scanned
                }
                .ignoresSafeArea()
            }
            .sheet(item: $shared) { file in
                ShareSheet(items: file.urls)
            }
            .onChange(of: photoItems) { loadPhotos() }
        }
    }

    // MARK: Input

    @ViewBuilder
    private var inputSection: some View {
        switch tool {
        case .imagesToPDF, .scan:
            Section {
                if !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(images.enumerated()), id: \.offset) { item in
                                Image(uiImage: item.element).resizable().scaledToFit().frame(height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    Button("Remove All", role: .destructive) { images = [] }
                }
                if tool == .scan {
                    Button {
                        isScanning = true
                    } label: {
                        Label(images.isEmpty ? "Scan Pages…" : "Scan More…", systemImage: "doc.viewfinder")
                    }
                    .disabled(!VNDocumentCameraViewController.isSupported)
                    Toggle("Make the Text Searchable", isOn: $scanSearchable)
                } else {
                    PhotosPicker(selection: $photoItems, matching: .images) {
                        Label("From Photos…", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        isPickingImageFiles = true
                    } label: {
                        Label("From Files…", systemImage: "folder")
                    }
                }
            } header: {
                Text("\(images.count) pictures")
            } footer: {
                if tool == .scan && !VNDocumentCameraViewController.isSupported {
                    Text("This iPad can't scan here (the camera isn't available).")
                }
            }
        case .webPage:
            Section {
                TextField("https://…", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Address")
            } footer: {
                Text("This is the one tool that uses the internet: it loads the page.")
            }
        default:
            Section {
                if let source { Label(tr(source.title), systemImage: "doc.richtext") }
                if tool != .unlock {
                    Button {
                        isPickingNote = true
                    } label: {
                        Label("From the Library…", systemImage: "books.vertical")
                    }
                }
                Button {
                    isPickingFile = true
                } label: {
                    Label("From Files…", systemImage: "folder")
                }
                if tool == .unlock, lockedURL != nil {
                    SecureField("Password", text: $password)
                }
            } header: {
                Text("PDF")
            }
        }
    }

    // MARK: Options

    @ViewBuilder
    private var optionsSection: some View {
        switch tool {
        case .pdfToImages:
            if let document {
                Section("Pages") {
                    HStack {
                        Text("\(selection.count) selected").foregroundStyle(.secondary)
                        Spacer()
                        Button("All") { selection = Set(0..<document.pageCount) }.buttonStyle(.borderless)
                    }
                    PageThumbnailGrid(document: document, selection: $selection)
                }
            }
        case .compress:
            Section {
                Picker("Size", selection: $quality) {
                    Text("Smallest").tag(0)
                    Text("Balanced").tag(1)
                    Text("Good Quality").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("Keep Text Searchable (slower)", isOn: $keepsText)
            } footer: {
                Text("Pages become pictures; text stays searchable only with Keep Text, which reads every page on this iPad.")
            }
        case .password:
            Section {
                SecureField("Password", text: $password)
            } footer: {
                Text("The protected copy is shared or saved to Files. The library keeps notes unlocked.")
            }
        case .redact:
            redactOptions
        case .watermark:
            Section("Watermark") {
                TextField("Text", text: $watermark)
                LabeledSlider(title: "Size", systemImage: "textformat.size", value: $watermarkSize, range: 24...140, text: "\(Int(watermarkSize))")
                LabeledSlider(title: "Strength", systemImage: "circle.lefthalf.filled", value: $watermarkOpacity, range: 0.05...0.6, text: "\(Int(watermarkOpacity * 100))%")
            }
        case .pageNumbers:
            Section("Numbers") {
                Picker("Where", selection: $numberPlace) {
                    ForEach(PDFEdit.NumberPlace.allCases) { Text(tr($0.title)).tag($0) }
                }
                Picker("Style", selection: $numberStyle) {
                    Text("1").tag(0)
                    Text("Page 1 of 12").tag(1)
                    Text("— 1 —").tag(2)
                }
            }
        case .sign:
            Section {
                InkCanvas(drawing: $signature, showsToolPicker: false)
                    .frame(height: 150)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        if signature.strokes.isEmpty {
                            Text("Sign here").foregroundStyle(.tertiary).padding(10).allowsHitTesting(false)
                        }
                    }
                Button("Clear", role: .destructive) { signature = PKDrawing() }
            } header: {
                Text("Signature")
            }
            if let document {
                Section("Where") {
                    Stepper("Page \(signPage) of \(document.pageCount)", value: $signPage, in: 1...max(document.pageCount, 1))
                    Picker("Place", selection: $signPlace) {
                        ForEach(PDFEdit.NumberPlace.allCases) { Text(tr($0.title)).tag($0) }
                    }
                    LabeledSlider(title: "Width", systemImage: "arrow.left.and.right", value: $signWidth, range: 80...300, text: "\(Int(signWidth)) pt")
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var redactOptions: some View {
        Section {
            TextField("Words to hide, separated by commas", text: $redactWords)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Hide Words")
        } footer: {
            Text("Every place they appear is blacked out. Redacted pages become pictures, so the hidden text is really gone.")
        }
        if let document {
            Section {
                Stepper("Page \(redactPage + 1) of \(document.pageCount)", value: $redactPage, in: 0...max(document.pageCount - 1, 0))
                RedactPageView(document: document, page: redactPage, boxes: Binding(
                    get: { redactBoxes[redactPage] ?? [] },
                    set: { redactBoxes[redactPage] = $0 }
                ))
                .frame(height: 420)
                if !(redactBoxes[redactPage] ?? []).isEmpty {
                    Button("Clear This Page's Boxes", role: .destructive) { redactBoxes[redactPage] = [] }
                }
            } header: {
                Text("Hide Areas")
            } footer: {
                Text("Drag on the page to draw black boxes.")
            }
        }
    }

    // MARK: Loading

    private var canRun: Bool {
        switch tool {
        case .imagesToPDF, .scan: return !images.isEmpty
        case .webPage: return URL(string: address)?.host != nil
        case .unlock: return lockedURL != nil && !password.isEmpty
        case .password: return document != nil && !password.isEmpty
        case .pdfToImages: return document != nil && !selection.isEmpty
        case .sign: return document != nil && !signature.strokes.isEmpty
        case .redact: return document != nil && (!redactWords.isEmpty || redactBoxes.values.contains { !$0.isEmpty })
        default: return document != nil
        }
    }

    private func pickedFile(_ url: URL) {
        let item = PDFSourceItem(kind: .file(url), title: url.deletingPathExtension().lastPathComponent)
        if tool == .unlock {
            source = item
            lockedURL = url
        } else {
            load(item)
        }
    }

    private func load(_ item: PDFSourceItem) {
        source = item
        working = "Opening…"
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

    private func loadPhotos() {
        let items = photoItems
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            photoItems = []
        }
    }

    // MARK: Making

    private var baseTitle: String { source?.title ?? "PDF" }

    private func run() {
        working = "Making…"
        Task {
            defer { working = nil }
            do {
                try await make()
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func make() async throws {
        switch tool {
        case .imagesToPDF, .scan:
            let title = tool == .scan ? "Scan \(Date().formatted(date: .abbreviated, time: .shortened))" : "Pictures"
            let url = PDFToolKit.temporaryURL(named: title)
            let pictures = images
            try await Task.detached(priority: .userInitiated) { try PDFEdit.pdf(from: pictures, to: url) }.value
            var final = url
            if tool == .scan && scanSearchable, let scanned = PDFDocument(url: url) {
                working = "Reading the pages…"
                let searchable = PDFToolKit.temporaryURL(named: title)
                _ = try await Task.detached(priority: .userInitiated) {
                    try BookOCR.searchable(scanned, onlyScans: false, to: searchable, progress: { _ in }, isCancelled: { false })
                }.value
                final = searchable
            }
            try importNote(final, "“\(title)” is a new note")
        case .webPage:
            guard let address = URL(string: address) else { return }
            let url = PDFToolKit.temporaryURL(named: address.host ?? "Web Page")
            working = "Loading the page…"
            try await PDFEdit.webPage(address, to: url)
            try importNote(url, "The page is a new note")
        case .pdfToImages:
            guard let document else { return }
            let pages = selection.sorted()
            let title = baseTitle
            let urls = await Task.detached(priority: .userInitiated) { PDFEdit.pageImages(document, pages: pages, title: title) }.value
            shared = ExportedFile(urls: urls)
            done = "\(urls.count) pictures ready to share or save"
        case .extractImages:
            guard let document else { return }
            let title = baseTitle
            let urls = await Task.detached(priority: .userInitiated) { PDFEdit.extractImages(document, title: title) }.value
            guard !urls.isEmpty else {
                problem = "No pictures are stored in this PDF (scans may be single page pictures: use PDF to Images)."
                return
            }
            shared = ExportedFile(urls: urls)
            done = "\(urls.count) pictures found"
        case .compress:
            guard let document else { return }
            let url = PDFToolKit.temporaryURL(named: "\(baseTitle) (smaller)")
            let settings: (CGFloat, CGFloat) = quality == 0 ? (1.2, 0.45) : quality == 1 ? (1.6, 0.6) : (2.2, 0.75)
            let keeps = keepsText
            try await Task.detached(priority: .userInitiated) {
                try PDFEdit.rasterize(document, to: url, resolution: settings.0, quality: settings.1, keepsText: keeps, progress: { done, total in
                    Task { @MainActor in working = "Page \(done) of \(total)…" }
                })
            }.value
            let before = document.documentURL.map(PDFEdit.fileSize) ?? 0
            let after = PDFEdit.fileSize(url)
            let formatter = ByteCountFormatter()
            try importNote(url, before > 0
                           ? "Smaller copy: \(formatter.string(fromByteCount: before)) → \(formatter.string(fromByteCount: after))"
                           : "Smaller copy: \(formatter.string(fromByteCount: after))")
            shared = ExportedFile(url: url)
        case .password:
            guard let document else { return }
            let url = PDFToolKit.temporaryURL(named: "\(baseTitle) (protected)")
            try PDFEdit.protect(document, password: password, to: url)
            shared = ExportedFile(url: url)
            done = "Protected copy ready to share or save"
        case .unlock:
            guard let lockedURL else { return }
            let opened = try PDFEdit.unlocked(lockedURL, password: password)
            let url = try PDFToolKit.write(opened, title: "\(baseTitle) (unlocked)")
            try importNote(url, "Unlocked copy is a new note")
        case .redact:
            guard let document else { return }
            let words = redactWords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let found = PDFEdit.places(of: words, in: document)
            let boxes = redactBoxes.filter { !$0.value.isEmpty }
            let pages = Set(found.keys).union(boxes.keys)
            let url = PDFToolKit.temporaryURL(named: "\(baseTitle) (redacted)")
            try await Task.detached(priority: .userInitiated) {
                try PDFEdit.rasterize(document, to: url, pages: pages, resolution: 2, quality: 0.85, marks: { index, context, size in
                    context.setFillColor(UIColor.black.cgColor)
                    if let rects = found[index], let page = document.page(at: index) {
                        context.saveGState()
                        context.concatenate(page.transform(for: .cropBox))
                        for rect in rects { context.fill(rect) }
                        context.restoreGState()
                    }
                    for box in boxes[index] ?? [] {
                        context.fill(CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height, width: box.width * size.width, height: box.height * size.height))
                    }
                })
            }.value
            try importNote(url, "Redacted copy: \(pages.count) pages changed")
        case .watermark:
            guard let document else { return }
            let url = PDFToolKit.temporaryURL(named: "\(baseTitle) (watermark)")
            let text = watermark
            let size = CGFloat(watermarkSize)
            let color = UIColor.gray.withAlphaComponent(CGFloat(watermarkOpacity))
            try await Task.detached(priority: .userInitiated) {
                try PDFEdit.rewrite(document, to: url) { _, context, pageSize in
                    PDFEdit.drawText(text, size: size, color: color, at: CGPoint(x: pageSize.width / 2, y: pageSize.height / 2), degrees: 45, in: context)
                }
            }.value
            try importNote(url, "Watermarked copy is a new note")
        case .pageNumbers:
            guard let document else { return }
            let url = PDFToolKit.temporaryURL(named: "\(baseTitle) (numbered)")
            let place = numberPlace
            let style = numberStyle
            let total = document.pageCount
            try await Task.detached(priority: .userInitiated) {
                try PDFEdit.rewrite(document, to: url) { index, context, pageSize in
                    let number = index + 1
                    let text: String = style == 1 ? "Page \(number) of \(total)" : style == 2 ? "— \(number) —" : "\(number)"
                    PDFEdit.drawText(text, size: 11, color: .darkGray, at: place.point(in: pageSize), in: context)
                }
            }.value
            try importNote(url, "Numbered copy is a new note")
        case .sign:
            guard let document else { return }
            let url = PDFToolKit.temporaryURL(named: "\(baseTitle) (signed)")
            let picture = InkSnapshot.snapshot(of: signature, from: signature.bounds.insetBy(dx: -4, dy: -4), scale: 3)
            guard let cg = picture.cgImage else { return }
            let pageIndex = signPage - 1
            let place = signPlace
            let width = CGFloat(signWidth)
            let height = width * CGFloat(cg.height) / CGFloat(max(cg.width, 1))
            try await Task.detached(priority: .userInitiated) {
                try PDFEdit.rewrite(document, to: url) { index, context, pageSize in
                    guard index == pageIndex else { return }
                    let anchor = place.point(in: pageSize)
                    let rect = CGRect(x: anchor.x - width / 2, y: anchor.y - 6, width: width, height: height)
                    context.draw(cg, in: rect)
                }
            }.value
            try importNote(url, "Signed copy is a new note")
        }
    }

    private func importNote(_ url: URL, _ message: String) throws {
        guard store.importPDF(from: url, into: nil) != nil else { throw PDFToolError.cannotWrite }
        done = message
        CommandCenter.shared.say(message)
    }
}

/// A page to draw black boxes on (positions kept from 0 to 1, y down).
private struct RedactPageView: View {
    let document: PDFDocument
    let page: Int
    @Binding var boxes: [CGRect]
    @State private var image: UIImage?
    @State private var dragStart: CGPoint?
    @State private var dragNow: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let fitted = fittedRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(uiImage: image).resizable().frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                }
                ForEach(Array(boxes.enumerated()), id: \.offset) { item in
                    Rectangle().fill(Color.black)
                        .frame(width: item.element.width * fitted.width, height: item.element.height * fitted.height)
                        .offset(x: fitted.minX + item.element.minX * fitted.width, y: fitted.minY + item.element.minY * fitted.height)
                }
                if let start = dragStart, let now = dragNow {
                    Rectangle().fill(Color.black.opacity(0.5))
                        .frame(width: abs(now.x - start.x), height: abs(now.y - start.y))
                        .offset(x: min(start.x, now.x), y: min(start.y, now.y))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragStart == nil { dragStart = value.startLocation }
                    dragNow = value.location
                }
                .onEnded { value in
                    let a = value.startLocation
                    let b = value.location
                    let rect = CGRect(
                        x: (min(a.x, b.x) - fitted.minX) / max(fitted.width, 1),
                        y: (min(a.y, b.y) - fitted.minY) / max(fitted.height, 1),
                        width: abs(b.x - a.x) / max(fitted.width, 1),
                        height: abs(b.y - a.y) / max(fitted.height, 1)
                    ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                    if !rect.isNull, rect.width > 0.01, rect.height > 0.005 { boxes.append(rect) }
                    dragStart = nil
                    dragNow = nil
                })
        }
        .task(id: page) {
            guard let pdfPage = document.page(at: page) else { return }
            let size = PDFEdit.shownSize(of: pdfPage)
            image = pdfPage.thumbnail(of: CGSize(width: size.width * 1.5, height: size.height * 1.5), for: .cropBox)
        }
    }

    private func fittedRect(in space: CGSize) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return CGRect(origin: .zero, size: space) }
        let factor: CGFloat = min(space.width / image.size.width, space.height / image.size.height)
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        return CGRect(x: (space.width - size.width) / 2, y: (space.height - size.height) / 2, width: size.width, height: size.height)
    }
}

/// The system document scanner (camera).
private struct DocumentScanner: UIViewControllerRepresentable {
    let done: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([UIImage]) -> Void
        init(done: @escaping ([UIImage]) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            done([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            done([])
        }
    }
}
