import SwiftUI

/// A lassoed area to read.
struct AreaRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let rect: CGRect
}

/// Lasso › Text from Area: the area read on the iPad (English and
/// Arabic), as text or as a table, to copy, put on the page, or keep as a
/// note. "Clean Up with AI" fixes misreads and formulas when allowed.
struct AreaTextSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AISettings.shared
    let request: AreaRequest
    let noteID: UUID
    let place: (NSAttributedString, CGRect) -> Void

    @State private var lines: [OCRLine] = []
    @State private var text = ""
    @State private var table: String?
    @State private var asTable = false
    @State private var isReading = true
    @State private var isCleaning = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: request.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Section {
                    if isReading {
                        ProgressView("Reading…")
                    } else {
                        if table != nil {
                            Picker("Show", selection: $asTable) {
                                Text("Text").tag(false)
                                Text("Table").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: asTable) { text = asTable ? (table ?? text) : BookOCR.text(of: lines) }
                        }
                        TextEditor(text: $text)
                            .frame(minHeight: 180)
                            .font(asTable ? .system(.body, design: .monospaced) : .body)
                    }
                } header: {
                    Text(lines.isEmpty && !isReading ? "No text was found" : "Text (you can edit it)")
                } footer: {
                    if let problem { Text(problem).foregroundStyle(.red) }
                }
                if !isReading && !text.isEmpty {
                    Section {
                        Button {
                            UIPasteboard.general.string = text
                            CommandCenter.shared.say("Copied")
                            dismiss()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button {
                            place(TextBoxStyle.attributed(markdown: text), request.rect)
                            dismiss()
                        } label: {
                            Label("Put on the Page", systemImage: "textformat")
                        }
                        Button {
                            let title = String(text.split(separator: "\n").first ?? "From the page").prefix(60)
                            if store.createTextNote(titled: String(title), in: store.note(noteID)?.folderID, extraText: text) != nil {
                                CommandCenter.shared.say("Saved as a text note")
                                dismiss()
                            }
                        } label: {
                            Label("Save as a Text Note", systemImage: "doc.text")
                        }
                        if ai.problem == nil {
                            Button {
                                cleanUp()
                            } label: {
                                if isCleaning {
                                    ProgressView()
                                } else {
                                    Label("Clean Up with AI", systemImage: "sparkles")
                                }
                            }
                            .disabled(isCleaning)
                        }
                    } footer: {
                        Text("Clean Up with AI fixes misread words, keeps the layout, and writes formulas clearly. Only this text is sent, if the AI Firewall allows it for this note.")
                    }
                }
            }
            .navigationTitle("Text from Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await read() }
        }
    }

    private func read() async {
        guard let cgImage = request.image.cgImage else {
            isReading = false
            return
        }
        let found = await Task.detached(priority: .userInitiated) { BookOCR.lines(in: cgImage) }.value
        lines = found
        table = BookOCR.table(from: found)
        text = BookOCR.text(of: found)
        isReading = false
    }

    private func cleanUp() {
        guard let client = ai.client() else { return }
        guard store.mayUseAI(noteID, onDevice: client.kind.isOnDevice) else {
            problem = NoteTexts.firewallMessage(onDevice: client.kind.isOnDevice)
            return
        }
        let original = text
        isCleaning = true
        Task {
            defer { isCleaning = false }
            do {
                let prompt = [
                    "This text was read from a page of a book by OCR and may have misread words or broken formulas.",
                    "Fix the misreads, keep the language and the line structure, keep tables as Markdown tables, and write formulas in plain readable form (like FiO2 × PEEP or V̇E = VT × f). Don't add anything new.",
                    "Reply with the fixed text only.",
                    original,
                ].joined(separator: "\n\n")
                let reply = try await client.complete(system: "You correct OCR text faithfully.", messages: [AIMessage(.user, prompt)])
                text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                problem = "Couldn't clean up: \(error.localizedDescription)"
            }
        }
    }
}
