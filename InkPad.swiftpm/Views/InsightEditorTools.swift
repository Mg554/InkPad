import PencilKit
import SwiftUI

/// All the sheets and overlays the new tools add to a note editor. Kept in
/// one modifier so `NoteEditorView` only needs a single extra line.
struct InsightEditorTools: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var exam = ExamSession.shared
    let noteID: UUID
    let title: String
    let canvas: CanvasController
    let page: Int
    let content: () -> NoteContent?
    @Binding var showsTimeline: Bool
    @Binding var showsConfidence: Bool
    @Binding var showsMacro: Bool
    @Binding var showsExam: Bool
    @Binding var showsMarginalia: Bool
    @Binding var exportedFile: ExportedFile?
    let onMacroAction: (MacroAction) -> Void

    func body(content editor: Content) -> some View {
        editor
            .sheet(isPresented: $showsTimeline) {
                if let noteContent = content() {
                    TimeLapseSheet(title: title, content: noteContent, page: page) { url in
                        exportedFile = ExportedFile(url: url)
                    }
                }
            }
            .sheet(isPresented: $showsConfidence) {
                if let noteContent = content() {
                    ConfidenceSheet(noteID: noteID, content: noteContent, page: page, canvas: canvas)
                        .environmentObject(workspace)
                }
            }
            .sheet(isPresented: $showsMacro) {
                MacroRunnerSheet(macros: InsightSettings.load().macros) { action in
                    onMacroAction(action)
                }
            }
            .sheet(isPresented: $showsExam) {
                ExamSetupSheet(noteID: noteID, title: title)
            }
            .sheet(isPresented: $showsMarginalia) {
                MarginaliaSheet(noteID: noteID, canvas: canvas)
                    .environmentObject(store)
                    .environmentObject(workspace)
            }
            .overlay(alignment: .top) {
                if exam.isActive, exam.noteID == noteID { ExamTimerBar() }
            }
    }
}

// MARK: - Time-lapse

struct TimeLapseSheet: View {
    let title: String
    let content: NoteContent
    let page: Int
    let onExport: (URL) -> Void

    @State private var result: TimelineResult?
    @State private var index = 0
    @State private var isPlaying = false
    @State private var isBusy = true
    @State private var timer: Timer?
    @Environment(\.dismiss) private var dismiss

    private var frameCount: Int { result?.frames.count ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    Color.black.opacity(0.05)
                    if isBusy {
                        ProgressView(tr("Reading the ink…"))
                    } else if let result, result.frames.indices.contains(index) {
                        let frame = result.frames[index]
                        Image(decorative: frame.image, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                        Text(frame.date.formatted(date: .abbreviated, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(.regularMaterial, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    } else {
                        Text("Nothing written yet.").foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                if let result {
                    Text(trInsightLocal("{} strokes over {}", String(result.strokeCount), durationText(result)))
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(index) },
                        set: { index = Int($0) }
                    ), in: 0...Double(max(frameCount - 1, 0)))
                    .padding(.horizontal)
                    HStack(spacing: Theme.Spacing.xl) {
                        Button {
                            index = 0
                        } label: {
                            Image(systemName: "backward.end.fill")
                        }
                        Button {
                            isPlaying ? stop() : play()
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36))
                        }
                        Button {
                            index = max(frameCount - 1, 0)
                        } label: {
                            Image(systemName: "forward.end.fill")
                        }
                    }
                    .buttonStyle(.borderless)
                    Button {
                        export()
                    } label: {
                        Label("Export Animated GIF", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer(minLength: 0)
            }
            .navigationTitle("Writing Time-Lapse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { build() }
            .onDisappear { stop() }
        }
    }

    private func build() {
        // Only this page, at a bounded size: a whole note at full resolution
        // would make too many large bitmaps on the iPad.
        let rects = content.makeBackground().layout.pageRects
        let rect = rects.indices.contains(page) ? rects[page] : (rects.first ?? .zero)
        let strokes = content.drawing.strokes.filter { $0.renderBounds.intersects(rect) }
        let drawing = PKDrawing(strokes: strokes)
        let scale = min(1.2, 900 / max(rect.width, rect.height, 1))
        let bounds = rect
        Task {
            let built = await Task.detached(priority: .utility) {
                TimelineEngine.build(drawing: drawing, bounds: bounds, maxFrames: 60, scale: scale)
            }.value
            result = built
            index = max(built.frames.count - 1, 0)
            isBusy = false
        }
    }

    private func durationText(_ result: TimelineResult) -> String {
        let seconds = result.last.timeIntervalSince(result.first)
        if seconds < 90 { return trInsightLocal("{} seconds", String(format: "%.0f", seconds)) }
        return trInsightLocal("{} minutes", String(format: "%.0f", seconds / 60))
    }

    private func play() {
        guard frameCount > 1 else { return }
        if index >= frameCount - 1 { index = 0 }
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { _ in
            Task { @MainActor in
                if self.index < self.frameCount - 1 {
                    self.index += 1
                } else {
                    self.stop()
                }
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }

    private func export() {
        guard let result else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(title + " time-lapse")
            .appendingPathExtension("gif")
        Task {
            let saved = await Task.detached(priority: .utility) {
                TimelineEngine.writeGIF(result, to: url)
            }.value
            if saved { onExport(url) }
        }
    }
}

// MARK: - Confidence Ink

struct ConfidenceSheet: View {
    let noteID: UUID
    let content: NoteContent
    let page: Int
    let canvas: CanvasController
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var marks: [ConfidenceMark] = []
    @State private var picture: UIImage?
    @State private var isReading = true

    private var pageRect: CGRect {
        let rects = content.makeBackground().layout.pageRects
        return rects.indices.contains(page) ? rects[page] : .zero
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let picture {
                        ConfidencePageView(picture: picture, marks: marks, pageRect: pageRect) { rect in
                            canvas.flash(rect)
                        }
                        .frame(height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else if isReading {
                        ProgressView(tr("Reading the page…"))
                    }
                    ForEach(ConfidenceLevel.allCases, id: \.self) { level in
                        let lines = marks.filter { $0.level == level }
                        if !lines.isEmpty {
                            Section {
                                ForEach(lines.prefix(12)) { mark in
                                    Button {
                                        canvas.flash(mark.rect)
                                    } label: {
                                        HStack {
                                            Circle().fill(confidenceColor(level)).frame(width: 9, height: 9)
                                            Text(verbatim: mark.text).lineLimit(2).foregroundStyle(Color.primary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Label(tr(level.title), systemImage: level.symbol)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Confidence Ink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { read() }
        }
    }

    private func confidenceColor(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .weak: .red
        case .learning: .orange
        case .strong: .green
        case .unknown: .secondary
        }
    }

    private func read() {
        let rect = pageRect
        guard rect != .zero, let image = canvas.picture(of: rect), let cg = image.cgImage else {
            isReading = false
            return
        }
        picture = image
        Task {
            let lines = await Task.detached(priority: .utility) {
                InkOCR.lines(in: cg, mappedTo: rect)
            }.value
            marks = ConfidenceEngine.marks(for: lines, workspace: workspace)
            isReading = false
        }
    }
}

private struct ConfidencePageView: View {
    let picture: UIImage
    let marks: [ConfidenceMark]
    let pageRect: CGRect
    let flash: (CGRect) -> Void

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / picture.size.width, geo.size.height / picture.size.height)
            let width = picture.size.width * scale
            let height = picture.size.height * scale
            ZStack {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFit()
                ForEach(marks) { mark in
                    let x = (mark.rect.midX - pageRect.minX) / max(pageRect.width, 1)
                    let y = (mark.rect.midY - pageRect.minY) / max(pageRect.height, 1)
                    let w = mark.rect.width / max(pageRect.width, 1)
                    let h = mark.rect.height / max(pageRect.height, 1)
                    Rectangle()
                        .fill(color(mark.level).opacity(0.3))
                        .frame(width: w * width, height: h * height)
                        .offset(x: (x - 0.5) * width, y: (y - 0.5) * height)
                        .onTapGesture { flash(mark.rect) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func color(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .weak: .red
        case .learning: .orange
        case .strong: .green
        case .unknown: .gray
        }
    }
}

// MARK: - Pencil Macro runner

struct MacroRunnerSheet: View {
    let macros: [PencilMacro]
    let run: (MacroAction) -> Void
    @State private var ink = PKDrawing()
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Text("Draw the shape you saved for a macro.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                CalculatorCanvas(drawing: $ink)
                    .frame(height: 240)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if let message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
                Button {
                    match()
                } label: {
                    Label("Run Macro", systemImage: "command")
                }
                .buttonStyle(.borderedProminent)
                .disabled(ink.strokes.isEmpty)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Pencil Macro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func match() {
        guard let found = MacroEngine.match(ink, against: macros) else {
            message = tr("That shape does not match a saved macro.")
            return
        }
        dismiss()
        run(found.action)
    }
}

// MARK: - Exam

struct ExamSetupSheet: View {
    let noteID: UUID
    let title: String
    @ObservedObject private var exam = ExamSession.shared
    @State private var minutes = InsightSettings.load().examMinutes
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $minutes, in: 5...120, step: 5) {
                        Text("\(minutes) minutes").font(.title3)
                    }
                } header: {
                    Text("Time Allowed")
                }
                Section {
                    Text("The tools hide, search and the command palette stop answering, and AI study tools are closed until the exam ends. When time is up InkPad leaves a review task and a sticky on the page.")
                        .font(.caption)
                }
            }
            .navigationTitle("Closed-Book Exam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        var settings = InsightSettings.load()
                        settings.examMinutes = minutes
                        settings.save()
                        exam.start(noteID: noteID, title: title, minutes: minutes)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExamTimerBar: View {
    @ObservedObject private var exam = ExamSession.shared

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "book.closed")
            Text(Flowmodoro.clock(exam.remaining, forceHours: false))
                .font(.system(.body, design: .monospaced).weight(.semibold))
            Text(verbatim: exam.title).font(.caption).lineLimit(1)
            Spacer()
            Button("End Exam") { exam.finish() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

// MARK: - Marginalia

struct MarginaliaSheet: View {
    let noteID: UUID
    let canvas: CanvasController
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    private var questions: [MarginalQuestion] {
        workspace.marginalia.filter { $0.noteID == noteID && $0.answeredAt == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if questions.isEmpty {
                    ContentUnavailableView("No Questions Yet", systemImage: "clock.badge.questionmark",
                                           description: Text("Leave a question for Future Me from InkPad Insights."))
                }
                ForEach(questions) { item in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(verbatim: item.text).font(.subheadline.weight(.semibold))
                        Text("Asked \(item.due.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button {
                                canvas.placeTextInView(TextBoxStyle.attributed(markdown: item.text, title: ""))
                            } label: {
                                Label("Put on Page", systemImage: "text.bubble")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Mark Answered") {
                                workspace.answerFutureMe(item.id, answer: "Answered on the page")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Margin Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Short local pattern fill for messages built in this file.
private func trInsightLocal(_ pattern: String, _ values: String...) -> String {
    var text = pattern
    for value in values { text = text.replacingOccurrences(of: "{}", with: value) }
    return trMessage(text)
}
