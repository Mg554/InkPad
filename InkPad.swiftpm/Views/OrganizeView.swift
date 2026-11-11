import SwiftUI

/// Messy Mode: write and paste without order, then "Organize This" asks
/// the AI to sort the note into headings, lists and tasks. The result is
/// shown first; replacing keeps the messy version in Recently Deleted.
struct OrganizeView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var ai = AISettings.shared
    @Environment(\.dismiss) private var dismiss

    let noteID: UUID
    let text: String
    let replace: (String) -> Void

    @State private var organized: String?
    @State private var error: String?
    @State private var isWorking = false
    @State private var confirmsReplace = false
    @State private var task: Task<Void, Never>?

    private var noteTitle: String { store.note(noteID)?.title ?? "Note" }
    private var blockedMessage: String? {
        guard !store.mayUseAI(noteID, onDevice: ai.provider.isOnDevice) else { return nil }
        return NoteTexts.firewallMessage(onDevice: ai.provider.isOnDevice)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let blockedMessage {
                        notice("Protected by the AI Firewall", blockedMessage, image: "lock.shield.fill", tint: .green)
                    } else if let problem = ai.problem {
                        notice("Connect an AI service", problem + " (Study with AI › AI Settings)", image: "sparkles", tint: .purple)
                    } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        notice("Nothing to Organize", "Write or paste something in the note first.", image: "doc", tint: .orange)
                    } else if isWorking {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Organizing \"\(noteTitle)\"…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let organized {
                        Text("Organized")
                            .font(.title3.bold())
                        MarkdownPreview(text: organized) { _ in }
                            .padding(18)
                            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.3)))
                    }
                    if let error {
                        Label(trMessage(error), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .navigationTitle("Organize This")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        task?.cancel()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if organized != nil {
                        Button("Try Again") { organize() }
                        Spacer()
                        Button("Save as New Note") { saveAsNew() }
                        Button("Replace Note") { confirmsReplace = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .confirmationDialog("Replace the note with the organized version?", isPresented: $confirmsReplace, titleVisibility: .visible) {
                Button("Replace Note") { replaceNote() }
            } message: {
                Text("The messy version is kept in Recently Deleted for \(LibraryStore.trashDays) days.")
            }
            .task {
                if organized == nil { organize() }
            }
        }
    }

    private func notice(_ title: String, _ message: String, image: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: image)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr(title)).font(.headline)
                Text(trMessage(message))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glowCard(tint)
    }

    // MARK: Actions

    private func organize() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let client = ai.client(),
              // The AI Firewall is checked again for the AI actually used.
              store.mayUseAI(noteID, onDevice: client.kind.isOnDevice)
        else { return }
        let prompt = StudyAI.organizePrompt(text)
        isWorking = true
        error = nil
        task = Task {
            defer { isWorking = false }
            do {
                let reply = try await client.complete(
                    system: "You tidy up messy notes without changing what they say.",
                    messages: [AIMessage(.user, prompt)]
                )
                guard !Task.isCancelled else { return }
                organized = Self.stripFence(reply)
            } catch {
                if !Task.isCancelled {
                    self.error = "Couldn't organize the note: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Some services wrap the whole answer in a ```markdown fence.
    private static func stripFence(_ reply: String) -> String {
        var lines = reply.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true, lines.last?.hasPrefix("```") == true, lines.count >= 2 {
            lines.removeFirst()
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private func replaceNote() {
        guard let organized else { return }
        // Keep the messy version, restorable from Recently Deleted.
        let folderID = store.note(noteID)?.folderID
        if let copy = store.createTextNote(titled: "\(noteTitle) (before organizing)", in: folderID) {
            store.saveMarkdown(text, for: copy.id)
            store.deleteNote(copy.id)
        }
        replace(organized)
        dismiss()
    }

    private func saveAsNew() {
        guard let organized else { return }
        let folderID = store.note(noteID)?.folderID
        if let note = store.createTextNote(titled: "\(noteTitle) (organized)", in: folderID) {
            store.saveMarkdown(organized, for: note.id)
        }
        dismiss()
    }
}
