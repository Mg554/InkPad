import SwiftUI

/// A dashboard assembled from signals already on this iPad: what is due in
/// the Planner, cards the spaced-review schedule says are due, and the notes
/// touched most recently. Nothing is uploaded and no calendar access is used.
struct TodayDashboard: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.noteNavigation) private var navigation

    private var openTasks: [PlanTask] {
        workspace.tasks
            .filter { $0.status != .done }
            .sorted { left, right in
                guard let a = left.dueDate else { return right.dueDate == nil }
                guard let b = right.dueDate else { return true }
                return a < b
            }
    }

    private var dueCards: Int {
        workspace.flashcardDecks.reduce(0) { $0 + $1.dueCount }
    }

    private var recentNotes: [NoteSummary] {
        Array(store.notes.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    greeting
                    section(tr("Up Next")) {
                        if openTasks.isEmpty {
                            Text(tr("Nothing is waiting in the Planner."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(openTasks.prefix(8)) { task in
                                HStack {
                                    Image(systemName: task.dueDate.map(Calendar.current.isDateInToday) ?? false
                                          ? "exclamationmark.circle" : "circle")
                                        .foregroundStyle(Color.inkAccent)
                                    Text(verbatim: task.title).font(.subheadline)
                                    Spacer()
                                    if let due = task.dueDate {
                                        Text(due, style: .date).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    section(tr("Study")) {
                        Label(trMessage("{} cards are due for review.").replacingOccurrences(of: "{}", with: String(dueCards)),
                              systemImage: "rectangle.on.rectangle")
                        if !workspace.marginalia.isEmpty {
                            Label(trMessage("{} questions are waiting on your pages.").replacingOccurrences(of: "{}", with: String(workspace.marginalia.count)),
                                  systemImage: "questionmark.bubble")
                        }
                    }
                    section(tr("Recently Edited")) {
                        ForEach(recentNotes) { note in
                            Button {
                                navigation.openNote(note.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: note.isText ? "doc.text" : "pencil.and.scribble")
                                        .foregroundStyle(Color.inkAccent)
                                    Text(verbatim: note.title).font(.subheadline)
                                    Spacer()
                                    Text(note.modifiedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(tr("Today / Up Next"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let text = hour < 12 ? tr("Good morning") : hour < 17 ? tr("Good afternoon") : tr("Good evening")
        return Text(text).font(.title2.weight(.semibold)).foregroundStyle(Color.inkAccent)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
