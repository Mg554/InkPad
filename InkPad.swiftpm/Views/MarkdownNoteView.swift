import SwiftUI
import UIKit

/// An Obsidian-style text note: Markdown with [[links]] and #tags, edited
/// with live highlighting, previewed with working links, and showing the
/// notes that link here.
struct MarkdownNoteView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case edit = "Edit"
        case split = "Split"
        case preview = "Preview"
        var id: Self { self }
    }

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.noteNavigation) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    let noteID: UUID

    @AppStorage("markdownMode") private var mode: Mode = .split
    @StateObject private var editor = MarkdownEditorController()
    @State private var text = ""
    @State private var loaded = false
    @State private var loadError: String?
    @State private var isDirty = false
    @State private var saveTask: Task<Void, Never>?
    @State private var prompt: NamePrompt?
    @State private var isCreatingSlides = false

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("Could Not Open Note", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                switch mode {
                case .edit:
                    editorPane
                case .preview:
                    previewPane
                case .split:
                    HStack(spacing: 0) {
                        editorPane
                        Divider()
                        previewPane
                    }
                }
            }
        }
        .navigationTitle(store.note(noteID)?.title ?? "Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        prompt = NamePrompt(title: "Rename Note", initialText: store.note(noteID)?.title ?? "", confirmTitle: "Rename") {
                            store.renameNote(noteID, to: $0)
                        }
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        prompt = NamePrompt(title: "Save as Template", initialText: store.note(noteID)?.title ?? "", confirmTitle: "Save") {
                            store.saveTemplate(named: $0, body: text)
                        }
                    } label: {
                        Label("Save as Template", systemImage: "doc.badge.plus")
                    }
                    Button {
                        save()
                        isCreatingSlides = true
                    } label: {
                        Label("Create Slides…", systemImage: "rectangle.on.rectangle.angled")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .namePrompt($prompt)
        .fullScreenCover(isPresented: $isCreatingSlides) {
            DeckGeneratorView(sources: [noteID])
                .environmentObject(store)
                .environmentObject(workspace)
        }
        .environment(\.openURL, OpenURLAction { InkPadLink.handle($0, with: navigation) })
        .task { load() }
        .onChange(of: text) {
            guard loaded else { return }
            isDirty = true
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                save()
            }
        }
        .onDisappear { save() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { save() }
        }
    }

    // MARK: Panes

    private var editorPane: some View {
        VStack(spacing: 0) {
            formattingBar
            Divider()
            MarkdownTextView(text: $text, controller: editor)
        }
        .frame(maxWidth: .infinity)
    }

    private var previewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let tags = NoteLinks.tags(in: text)
                if !tags.isEmpty {
                    TagChips(tags: tags) { navigation.openTag($0) }
                }
                MarkdownPreview(text: text) { line in toggleCheckbox(onLine: line) }
                BacklinksSection(backlinks: store.backlinks(to: noteID)) { navigation.openNote($0) }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .secondarySystemBackground).opacity(mode == .split ? 0.5 : 0))
    }

    private var formattingBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                barButton("Heading", "number") { editor.toggleLinePrefix("# ") }
                barButton("Subheading", "textformat.size") { editor.toggleLinePrefix("## ") }
                barButton("Bold", "bold") { editor.wrapSelection("**", "**") }
                barButton("Italic", "italic") { editor.wrapSelection("*", "*") }
                barButton("Highlight", "highlighter") { editor.wrapSelection("==", "==") }
                Divider().frame(height: 22)
                barButton("Bulleted List", "list.bullet") { editor.toggleLinePrefix("- ") }
                barButton("Checklist", "checklist") { editor.toggleLinePrefix("- [ ] ") }
                barButton("Quote", "text.quote") { editor.toggleLinePrefix("> ") }
                Divider().frame(height: 22)
                barButton("Link to Note", "link") { editor.wrapSelection("[[", "]]") }
                barButton("Tag", "tag") { editor.wrapSelection("#", "") }
                barButton("Divider", "minus") { editor.insertLine("---") }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private func barButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 36, height: 32)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        do {
            text = try store.loadMarkdown(for: noteID)
        } catch {
            loadError = error.localizedDescription
        }
        // Set after the first text change so loading is not saved back.
        DispatchQueue.main.async { loaded = true }
    }

    private func save() {
        saveTask?.cancel()
        guard isDirty, loaded else { return }
        if store.saveMarkdown(text, for: noteID) { isDirty = false }
    }

    private func toggleCheckbox(onLine index: Int) {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(index) else { return }
        let line = lines[index]
        if let range = line.range(of: "- [ ]") {
            lines[index] = line.replacingCharacters(in: range, with: "- [x]")
        } else if let range = line.range(of: "- [x]") ?? line.range(of: "- [X]") {
            lines[index] = line.replacingCharacters(in: range, with: "- [ ]")
        }
        text = lines.joined(separator: "\n")
    }
}

// MARK: - Editor

/// Formatting commands for the Markdown text view, acting at the cursor.
@MainActor
final class MarkdownEditorController: ObservableObject {
    weak var textView: UITextView?

    func wrapSelection(_ prefix: String, _ suffix: String) {
        guard let textView else { return }
        let range = textView.selectedRange
        let selected = (textView.text as NSString).substring(with: range)
        replace(range, with: prefix + selected + suffix, caret: range.location + prefix.count + (selected as NSString).length)
    }

    /// Adds the prefix to the current line, or removes it if already there.
    func toggleLinePrefix(_ prefix: String) {
        guard let textView else { return }
        let string = textView.text as NSString
        let lineRange = string.lineRange(for: NSRange(location: textView.selectedRange.location, length: 0))
        let line = string.substring(with: lineRange)
        if line.hasPrefix(prefix) {
            replace(NSRange(location: lineRange.location, length: (prefix as NSString).length), with: "", caret: max(textView.selectedRange.location - (prefix as NSString).length, lineRange.location))
        } else {
            replace(NSRange(location: lineRange.location, length: 0), with: prefix, caret: textView.selectedRange.location + (prefix as NSString).length)
        }
    }

    func insertLine(_ line: String) {
        guard let textView else { return }
        let location = textView.selectedRange.location
        let insertion = "\n" + line + "\n"
        replace(NSRange(location: location, length: 0), with: insertion, caret: location + (insertion as NSString).length)
    }

    private func replace(_ range: NSRange, with text: String, caret: Int) {
        guard let textView, let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end)
        else { return }
        // Through the text input system so undo works.
        textView.replace(textRange, withText: text)
        textView.selectedRange = NSRange(location: min(caret, (textView.text as NSString).length), length: 0)
        textView.becomeFirstResponder()
    }
}

/// A UITextView that highlights Markdown headings, [[links]] and #tags as you type.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 17)
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 40, right: 20)
        textView.autocorrectionType = .default
        textView.smartDashesType = .no
        textView.delegate = context.coordinator
        textView.text = text
        Coordinator.highlight(textView)
        controller.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        // Only push outside changes (e.g. a checkbox ticked in the preview).
        if textView.text != text {
            let selection = textView.selectedRange
            textView.text = text
            Coordinator.highlight(textView)
            textView.selectedRange = NSRange(location: min(selection.location, (text as NSString).length), length: 0)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            Self.highlight(textView)
            text.wrappedValue = textView.text
        }

        private static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,6}) .*$"#, options: .anchorsMatchLines)
        private static let linkPattern = try! NSRegularExpression(pattern: #"\[\[[^\[\]]+\]\]"#)
        private static let tagPattern = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&/#])#[\p{L}_][\p{L}\p{N}_/-]*"#)
        private static let boldPattern = try! NSRegularExpression(pattern: #"\*\*[^*\n]+\*\*"#)

        /// Restyles the whole text; cheap enough for note-sized documents.
        static func highlight(_ textView: UITextView) {
            let storage = textView.textStorage
            let full = NSRange(location: 0, length: storage.length)
            let string = storage.string
            storage.beginEditing()
            storage.setAttributes([.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label], range: full)
            for match in headingPattern.matches(in: string, range: full) {
                let level = match.range(at: 1).length
                let size: CGFloat = [30, 25, 21, 19, 18, 17][min(level - 1, 5)]
                storage.addAttribute(.font, value: UIFont.systemFont(ofSize: size, weight: .bold), range: match.range)
            }
            for match in boldPattern.matches(in: string, range: full) {
                storage.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 17), range: match.range)
            }
            for match in linkPattern.matches(in: string, range: full) {
                storage.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: match.range)
            }
            for match in tagPattern.matches(in: string, range: full) {
                storage.addAttribute(.foregroundColor, value: UIColor.systemTeal, range: match.range)
            }
            storage.endEditing()
            textView.typingAttributes = [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label]
        }
    }
}

// MARK: - Preview

/// Renders Markdown blocks (headings, lists, checklists, quotes, dividers)
/// with working [[links]] and #tags.
struct MarkdownPreview: View {
    let text: String
    let toggleCheckbox: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { item in
                block(item.element, line: item.offset)
            }
        }
        .tint(.purple)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func block(_ line: String, line index: Int) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Spacer().frame(height: 4)
        } else if trimmed == "---" || trimmed == "***" {
            Divider().padding(.vertical, 6)
        } else if let level = headingLevel(trimmed) {
            Text(Self.inline(String(trimmed.drop(while: { $0 == "#" }).dropFirst())))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 8 : 2)
        } else if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            let done = !trimmed.hasPrefix("- [ ] ")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    toggleCheckbox(index)
                } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(done ? Color.green : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                Text(Self.inline(String(trimmed.dropFirst(6))))
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().frame(width: 6, height: 6).foregroundStyle(.secondary)
                Text(Self.inline(String(trimmed.dropFirst(2))))
            }
            .padding(.leading, CGFloat(line.prefix { $0 == " " }.count) * 6)
        } else if trimmed.hasPrefix(">") {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color.purple.opacity(0.6)).frame(width: 4)
                Text(Self.inline(String(trimmed.dropFirst().drop(while: { $0 == " " }))))
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(Self.inline(trimmed))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .largeTitle.bold()
        case 2: return .title.bold()
        case 3: return .title2.bold()
        case 4: return .title3.bold()
        case 5: return .headline
        default: return .subheadline.bold()
        }
    }

    private func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static let linkPattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]|]+)(?:\|([^\[\]]*))?\]\]"#)
    private static let tagPattern = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&/#\[])#([\p{L}_][\p{L}\p{N}_/-]*)"#)
    private static let highlightPattern = try! NSRegularExpression(pattern: #"==([^=\n]+)=="#)

    /// Inline Markdown with [[links]] and #tags turned into tappable links.
    static func inline(_ line: String) -> AttributedString {
        var markdown = line as NSString
        for match in linkPattern.matches(in: line, range: NSRange(location: 0, length: markdown.length)).reversed() {
            let title = markdown.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let shown = match.range(at: 2).location != NSNotFound ? markdown.substring(with: match.range(at: 2)) : title
            guard let url = InkPadLink.note(title) else { continue }
            markdown = markdown.replacingCharacters(in: match.range, with: "[\(shown)](\(url.absoluteString))") as NSString
        }
        var result = markdown as String
        let tagged = result as NSString
        for match in tagPattern.matches(in: result, range: NSRange(location: 0, length: tagged.length)).reversed() {
            let tag = tagged.substring(with: match.range(at: 1))
            guard let url = InkPadLink.tag(tag) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range, with: "[#\(tag)](\(url.absoluteString))")
        }
        result = highlightPattern.stringByReplacingMatches(
            in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "**$1**"
        )
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: result, options: options)) ?? AttributedString(line)
    }
}

struct TagChips: View {
    let tags: [String]
    let open: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        open(tag)
                    } label: {
                        Text("#\(tag)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(.teal)
                            .glowCard(.teal)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(4)
        }
    }
}

/// "Linked mentions": the notes whose text links to this one.
struct BacklinksSection: View {
    let backlinks: [(note: NoteSummary, line: String)]
    let open: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 8)
            Label("Linked Mentions (\(backlinks.count))", systemImage: "arrow.uturn.backward.circle")
                .font(.headline)
            if backlinks.isEmpty {
                Text("No notes link here yet. Write this note's title in double brackets in another note to link it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(backlinks, id: \.note.id) { item in
                Button {
                    open(item.note.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.note.title)
                            .font(.subheadline.weight(.semibold))
                        if !item.line.isEmpty {
                            Text(MarkdownPreview.inline(item.line))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glowCard(.purple, isActive: false)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}
