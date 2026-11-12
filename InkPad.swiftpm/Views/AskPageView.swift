import PDFKit
import SwiftUI

/// Ask This Page: a chat beside the note. Answers cite the page and
/// paragraph ([p3¶2]); tapping a citation shows and lights up that
/// paragraph. Anything the AI adds from outside the note is marked.
struct AskPageView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var ai = AISettings.shared
    let noteID: UUID
    @ObservedObject var session: EditorSession
    @ObservedObject var canvas: CanvasController
    /// Puts text on the page: (text, near this rect, as a sticky note).
    let place: (String, CGRect?, Bool) -> Void

    enum Scope: String, CaseIterable, Identifiable {
        case page, chapter, note
        var id: Self { self }
        var title: String {
            switch self {
            case .page: "This Page"
            case .chapter: "This Chapter"
            case .note: "Whole Note"
            }
        }
    }

    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var answer: String?
        var error: String?
        /// The paragraphs the answer could cite, by label.
        var paragraphs: [String: PageParagraph] = [:]
    }

    @State private var scope: Scope = .page
    @State private var question = ""
    @State private var turns: [Turn] = []
    @State private var isAsking = false
    @State private var status: String?
    @State private var task: Task<Void, Never>?
    @State private var showsSettings = false

    private var blocked: String? {
        if let problem = ai.problem { return problem }
        if !store.mayUseAI(noteID, onDevice: ai.provider.isOnDevice) {
            return NoteTexts.firewallMessage(onDevice: ai.provider.isOnDevice)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if turns.isEmpty { intro }
                        ForEach(turns) { turn in
                            turnView(turn).id(turn.id)
                        }
                        if let status {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(trMessage(status)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                }
                .onChange(of: turns.count) {
                    if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .top) } }
                }
            }
            Divider()
            inputBar
        }
        .sheet(isPresented: $showsSettings) { AISettingsView() }
        .onDisappear { task?.cancel() }
        .environment(\.openURL, OpenURLAction { url in
            openCitation(url)
            return .handled
        })
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ask This Page", systemImage: "sparkles").font(.headline)
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { Text(tr($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
    }

    @ViewBuilder
    private var intro: some View {
        if let blocked {
            VStack(alignment: .leading, spacing: 8) {
                Label("AI can't read this note yet", systemImage: "lock.shield").font(.subheadline.weight(.semibold))
                Text(trMessage(blocked)).font(.caption).foregroundStyle(.secondary)
                Button("Open AI Settings") { showsSettings = true }.buttonStyle(.bordered)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ask about what is on the page. Answers point to the page and paragraph; tap one to see it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        question = tr(suggestion)
                        ask()
                    } label: {
                        Label(tr(suggestion), systemImage: "text.bubble")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var suggestions: [String] {
        ["What are the key points here?", "Explain the hardest idea simply", "Quiz me on this", "What should I remember for the exam?"]
    }

    private func turnView(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: turn.question)
                .padding(10)
                .background(Color.inkAccent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
            if let answer = turn.answer {
                Text(CitedAnswer.attributed(answer, paragraphs: turn.paragraphs))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 10) {
                    Button {
                        let first = CitedAnswer.citations(in: answer).compactMap { turn.paragraphs[$0] }.first
                        place(CitedAnswer.plain(answer), first?.rect, false)
                    } label: {
                        Label("Add to Page", systemImage: "text.below.photo")
                    }
                    Button {
                        let first = CitedAnswer.citations(in: answer).compactMap { turn.paragraphs[$0] }.first
                        place(CitedAnswer.plain(answer), first?.rect, true)
                    } label: {
                        Label("As Sticky", systemImage: "note.text")
                    }
                    Button {
                        UIPasteboard.general.string = CitedAnswer.plain(answer)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            if let error = turn.error {
                Label(trMessage(error), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this page", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit(ask)
            Button {
                if isAsking { task?.cancel() } else { ask() }
            } label: {
                Image(systemName: isAsking ? "stop.circle.fill" : "arrow.up.circle.fill").font(.title2)
            }
            .disabled(!isAsking && (question.trimmingCharacters(in: .whitespaces).isEmpty || blocked != nil))
        }
        .padding(12)
    }

    // MARK: Asking

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAsking, let client = ai.client(),
              store.mayUseAI(noteID, onDevice: client.kind.isOnDevice),
              let content = session.currentContent()
        else { return }
        question = ""
        turns.append(Turn(question: text))
        let index = turns.count - 1
        let history = turns.dropLast().compactMap { turn -> [AIMessage]? in
            guard let answer = turn.answer else { return nil }
            return [AIMessage(.user, turn.question), AIMessage(.assistant, answer)]
        }.flatMap { $0 }
        isAsking = true
        task = Task {
            defer {
                isAsking = false
                status = nil
            }
            let pages = pagesInScope(content)
            var paragraphs: [PageParagraph] = []
            var used = 0
            let budget = client.kind.contextBudget
            for (position, page) in pages.enumerated() {
                if Task.isCancelled { return }
                status = trMessage("Reading page \(page + 1) (\(position + 1) of \(pages.count))…")
                let found = await PageParagraphs.paragraphs(onPage: page, of: content)
                for paragraph in found where used < budget {
                    paragraphs.append(paragraph)
                    used += paragraph.text.count + 12
                }
                if used >= budget { break }
            }
            guard !paragraphs.isEmpty else {
                turns[index].error = "Nothing could be read on these pages."
                return
            }
            var map: [String: PageParagraph] = [:]
            for paragraph in paragraphs { map[paragraph.label] = paragraph }
            turns[index].paragraphs = map
            status = trMessage("\(client.kind.title) is answering…")
            let context = paragraphs.map { $0.label + " " + $0.text }.joined(separator: "\n")
            do {
                let reply = try await client.complete(system: CitedAnswer.system(context: context, title: store.note(noteID)?.title ?? ""),
                                                      messages: history + [AIMessage(.user, text)])
                if Task.isCancelled { return }
                turns[index].answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                if !Task.isCancelled { turns[index].error = error.localizedDescription }
            }
        }
    }

    /// The layout pages the question covers.
    private func pagesInScope(_ content: NoteContent) -> [Int] {
        let count = session.background?.layout.pageRects.count ?? 1
        let current = min(canvas.currentPage, max(count - 1, 0))
        switch scope {
        case .page:
            return [current]
        case .note:
            return Array(0..<min(count, NoteTexts.maxPages))
        case .chapter:
            guard let document = content.pdf?.pdfDocument, let metadata = session.metadata else {
                return Array(max(current - 2, 0)...min(current + 2, count - 1))
            }
            let sources = metadata.resolvedPages(pdfPageCount: document.pageCount)
            var pdfCurrent: Int?
            if sources.indices.contains(current), case let .pdf(index) = sources[current] { pdfCurrent = index }
            let chapters = PDFToolKit.chapters(of: document, maxDepth: 0)
            guard let pdfCurrent, let chapter = chapters.first(where: { $0.firstPage <= pdfCurrent && pdfCurrent <= $0.lastPage }) else {
                return Array(max(current - 2, 0)...min(current + 2, count - 1))
            }
            var result: [Int] = []
            for (layout, source) in sources.enumerated() {
                if case let .pdf(index) = source, index >= chapter.firstPage, index <= chapter.lastPage { result.append(layout) }
            }
            return Array(result.prefix(NoteTexts.maxPages))
        }
    }

    private func openCitation(_ url: URL) {
        guard url.scheme == "inkpad-cite" else { return }
        let parts = url.absoluteString.dropFirst("inkpad-cite:".count).split(separator: "-")
        guard parts.count == 2, let page = Int(parts[0]), let index = Int(parts[1]) else { return }
        let label = "[p\(page + 1)¶\(index + 1)]"
        let paragraph = turns.reversed().compactMap { $0.paragraphs[label] }.first
        canvas.scrollToPage(page)
        guard let rect = paragraph?.rect else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            canvas.flash(rect)
        }
    }
}

/// Reading and showing answers with [p3¶2] citations and outside knowledge
/// marked ⟦outside⟧…⟦/outside⟧.
enum CitedAnswer {
    static func system(context: String, title: String) -> String {
        [
            "You answer questions about the note \"\(title)\" using the numbered paragraphs below.",
            "After every sentence that uses the note, cite the paragraphs like [p3¶2] (several are fine: [p3¶2][p4¶1]).",
            "If you add anything that is NOT in these paragraphs (general knowledge), wrap it in ⟦outside⟧ and ⟦/outside⟧.",
            "Never invent citations. Answer in the language of the question. Be clear and concise; use short Markdown.",
            "",
            "Paragraphs (they were read from the page; fix obvious recognition mistakes silently):",
            context,
        ].joined(separator: "\n")
    }

    /// The labels cited, in order.
    static func citations(in answer: String) -> [String] {
        var found: [String] = []
        var rest = Substring(answer)
        while let open = rest.range(of: "[p") {
            guard let close = rest[open.upperBound...].firstIndex(of: "]") else { break }
            let label = "[" + String(rest[rest.index(after: open.lowerBound)..<close]).replacingOccurrences(of: " ", with: "") + "]"
            if label.contains("¶"), !found.contains(label) { found.append(label) }
            rest = rest[rest.index(after: close)...]
        }
        return found
    }

    /// The answer without citations or markers (for the page).
    static func plain(_ answer: String) -> String {
        var text = answer.replacingOccurrences(of: "⟦outside⟧", with: "").replacingOccurrences(of: "⟦/outside⟧", with: "")
        for label in citations(in: answer) {
            text = text.replacingOccurrences(of: label, with: "")
        }
        return text
    }

    static func attributed(_ answer: String, paragraphs: [String: PageParagraph]) -> AttributedString {
        var result = AttributedString()
        var outside = false
        var rest = Substring(answer)
        while !rest.isEmpty {
            let marker: String = outside ? "⟦/outside⟧" : "⟦outside⟧"
            let cut = rest.range(of: marker)
            let piece = cut.map { rest[..<$0.lowerBound] } ?? rest
            result += styled(String(piece), outside: outside, paragraphs: paragraphs)
            guard let cut else { break }
            outside.toggle()
            if outside {
                var badge = AttributedString(" 🌐 ")
                badge.foregroundColor = .orange
                result += badge
            }
            rest = rest[cut.upperBound...]
        }
        return result
    }

    /// One stretch of the answer, with its citations as links.
    private static func styled(_ text: String, outside: Bool, paragraphs: [String: PageParagraph]) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(text)
        while let open = rest.range(of: "[p"), let close = rest[open.upperBound...].firstIndex(of: "]") {
            result += markdown(String(rest[..<open.lowerBound]), outside: outside)
            let raw = String(rest[open.lowerBound...close])
            let label = raw.replacingOccurrences(of: " ", with: "")
            if let paragraph = paragraphs[label], let url = URL(string: "inkpad-cite:\(paragraph.page)-\(paragraph.index)") {
                var chip = AttributedString(" " + tr("p.") + " \(paragraph.page + 1)·\(paragraph.index + 1) ")
                chip.link = url
                chip.foregroundColor = Color.inkAccent
                chip.backgroundColor = Color.inkAccent.opacity(0.12)
                chip.font = .caption.weight(.semibold)
                result += chip
            } else {
                result += markdown(raw, outside: outside)
            }
            rest = rest[rest.index(after: close)...]
        }
        result += markdown(String(rest), outside: outside)
        return result
    }

    private static func markdown(_ text: String, outside: Bool) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var piece = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        if outside {
            piece.foregroundColor = .orange
            piece.font = .body.italic()
        }
        return piece
    }
}
