import SwiftUI

/// Reviews flashcards one at a time: tap to turn the card over, then rate
/// how well you knew it. Cards you missed come back later in the session.
struct FlashcardReviewView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    /// `nil` reviews the cards due in every deck.
    let deckID: UUID?

    private struct Item: Equatable {
        let deckID: UUID
        let cardID: UUID
    }

    @State private var queue: [Item] = []
    @State private var position = 0
    @State private var showsBack = false
    @State private var reviewed = 0
    @State private var didLoad = false

    private var current: Flashcard? {
        guard queue.indices.contains(position) else { return nil }
        let item = queue[position]
        let deck = workspace.flashcardDecks.first(where: { $0.id == item.deckID })
        return deck?.cards.first(where: { $0.id == item.cardID })
    }

    var body: some View {
        VStack(spacing: 24) {
            if let card = current {
                Text("\(position + 1) of \(queue.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                cardView(card)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showsBack.toggle() }
                    }
                if showsBack {
                    ratingButtons
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text("Tap the card to see the answer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if didLoad {
                ContentUnavailableView {
                    Label(reviewed > 0 ? "Session Complete" : "Nothing to Review", systemImage: "checkmark.seal.fill")
                } description: {
                    Text(reviewed > 0
                        ? "You reviewed \(reviewed) cards. They'll come back when it's time to review them again."
                        : "No cards are due right now.")
                } actions: {
                    if let deckID, workspace.flashcardDecks.contains(where: { $0.id == deckID }) {
                        Button("Study All Cards Again") { load(all: true) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(workspace.flashcardDecks.first(where: { $0.id == deckID })?.title ?? "Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didLoad { load(all: false) }
        }
    }

    private func cardView(_ card: Flashcard) -> some View {
        ZStack {
            face(card.front, label: "Question", tint: .orange)
                .opacity(showsBack ? 0 : 1)
            face(card.back, label: "Answer", tint: .green)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(showsBack ? 1 : 0)
        }
        .rotation3DEffect(.degrees(showsBack ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func face(_ text: String, label: String, tint: Color) -> some View {
        VStack(spacing: 18) {
            Text(label.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.title2.weight(.medium))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glowCard(tint)
    }

    private var ratingButtons: some View {
        HStack(spacing: 12) {
            ForEach(Flashcard.Rating.allCases, id: \.self) { rating in
                Button {
                    rate(rating)
                } label: {
                    Text(rating.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .tint(ratingColor(rating))
            }
        }
    }

    private func ratingColor(_ rating: Flashcard.Rating) -> Color {
        switch rating {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }

    private func load(all: Bool) {
        didLoad = true
        let decks = workspace.flashcardDecks.filter { deckID == nil || $0.id == deckID }
        var items: [Item] = []
        for deck in decks {
            let cards = deck.cards.filter { all || $0.isDue }
            // A deck opened by itself with nothing due is studied in full.
            let chosen = cards.isEmpty && deckID != nil && !all ? deck.cards : cards
            items += chosen.map { Item(deckID: deck.id, cardID: $0.id) }
        }
        queue = items.shuffled()
        position = 0
        reviewed = 0
        showsBack = false
    }

    private func rate(_ rating: Flashcard.Rating) {
        guard queue.indices.contains(position) else { return }
        let item = queue[position]
        workspace.review(card: item.cardID, in: item.deckID, rating: rating)
        reviewed += 1
        if rating == .again {
            queue.append(item)
        }
        showsBack = false
        withAnimation(.snappy(duration: 0.25)) { position += 1 }
    }
}

/// A multiple-choice quiz: pick an answer, see why it's right, and get a
/// score at the end.
struct QuizView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    let quizID: UUID

    @State private var position = 0
    @State private var picked: Int?
    @State private var score = 0

    private var quiz: Quiz? {
        workspace.quizzes.first { $0.id == quizID }
    }

    var body: some View {
        Group {
            if let quiz {
                if quiz.questions.indices.contains(position) {
                    questionView(quiz.questions[position], count: quiz.questions.count)
                } else {
                    resultView(quiz)
                }
            } else {
                ContentUnavailableView("Quiz Not Found", systemImage: "questionmark.circle")
            }
        }
        .padding(28)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(quiz?.title ?? "Quiz")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func questionView(_ question: QuizQuestion, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView(value: Double(position), total: Double(count))
            Text("Question \(position + 1) of \(count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(question.question)
                .font(.title2.weight(.semibold))
            ForEach(Array(question.choices.enumerated()), id: \.offset) { item in
                Button {
                    guard picked == nil else { return }
                    picked = item.offset
                    if item.offset == question.answer { score += 1 }
                } label: {
                    HStack {
                        Text(item.element)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                        Spacer()
                        if let picked, item.offset == question.answer || item.offset == picked {
                            Image(systemName: item.offset == question.answer ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(item.offset == question.answer ? Color.green : Color.red)
                                .opacity(picked == item.offset || item.offset == question.answer ? 1 : 0)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(choiceColor(item.offset, answer: question.answer), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
            if picked != nil {
                if !question.explanation.isEmpty {
                    Text(question.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .glowCard(.indigo, isActive: false)
                }
                Button {
                    picked = nil
                    withAnimation(.snappy(duration: 0.25)) { position += 1 }
                } label: {
                    Text(position + 1 < count ? "Next Question" : "See Score")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 0)
        }
    }

    private func choiceColor(_ index: Int, answer: Int) -> Color {
        guard let picked else { return Color(uiColor: .secondarySystemBackground) }
        if index == answer { return Color.green.opacity(0.2) }
        if index == picked { return Color.red.opacity(0.2) }
        return Color(uiColor: .secondarySystemBackground)
    }

    private func resultView(_ quiz: Quiz) -> some View {
        VStack(spacing: 18) {
            Image(systemName: score * 2 >= quiz.questions.count ? "star.circle.fill" : "arrow.clockwise.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(score * 2 >= quiz.questions.count ? Color.yellow : Color.orange)
            Text("\(score) of \(quiz.questions.count) right")
                .font(.largeTitle.bold())
            if let best = quiz.bestScore {
                Text("Your best: \(max(best, score)) of \(quiz.questions.count)")
                    .foregroundStyle(.secondary)
            }
            Button("Try Again") {
                position = 0
                score = 0
                picked = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            var updated = quiz
            updated.bestScore = max(quiz.bestScore ?? 0, score)
            if updated != quiz { workspace.save(updated) }
        }
    }
}
