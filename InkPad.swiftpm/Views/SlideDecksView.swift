import SwiftUI

/// All slide decks, newest first, with "New Slide Deck" to make one from notes.
struct SlideDecksView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var store: LibraryStore
    @State private var path: [UUID] = []
    @State private var isCreating = false
    @State private var deckToDelete: SlideDeck?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 22)], spacing: 22) {
                    ForEach(workspace.decks.sorted { $0.modifiedAt > $1.modifiedAt }) { deck in
                        Button {
                            path.append(deck.id)
                        } label: {
                            DeckCard(deck: deck)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                deckToDelete = deck
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(24)
            }
            .overlay {
                if workspace.decks.isEmpty {
                    ContentUnavailableView {
                        Label("No Slide Decks", systemImage: "rectangle.on.rectangle.angled")
                    } description: {
                        Text("Turn your notes into a presentation, like NotebookLM. Your notes stay on this iPad.")
                    } actions: {
                        Button("Create Slides") { isCreating = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Slides")
            .toolbar {
                Button {
                    isCreating = true
                } label: {
                    Label("New Slide Deck", systemImage: "plus.circle.fill")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                SlideDeckView(deckID: id)
            }
            .confirmationDialog(
                "Delete \"\(deckToDelete?.title ?? "")\"?",
                isPresented: Binding(get: { deckToDelete != nil }, set: { if !$0 { deckToDelete = nil } }),
                titleVisibility: .visible,
                presenting: deckToDelete
            ) { deck in
                Button("Delete Slide Deck", role: .destructive) {
                    workspace.deleteDeck(deck.id)
                }
            } message: { _ in
                Text("The notes it was made from are not changed.")
            }
        }
        .fullScreenCover(isPresented: $isCreating) {
            DeckGeneratorView(sources: [])
                .environmentObject(store)
                .environmentObject(workspace)
        }
    }
}

private struct DeckCard: View {
    let deck: SlideDeck

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let first = deck.slides.first {
                SlideView(slide: first, theme: deck.theme, image: nil, number: 1, total: deck.slides.count)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            Text(deck.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                if deck.isAIWritten {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .accessibilityLabel("Written by Apple Intelligence")
                }
                Text("\(deck.slides.count) slides · \(deck.format.title)")
                Spacer(minLength: 0)
                Text(deck.modifiedAt, format: .dateTime.day().month())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
