import SwiftUI

/// Memory Heatmap: how well each flashcard deck (topic) is remembered right
/// now, as a colored tile from red (forgotten) to green (strong), with a
/// warning for the topic that is fading most.
struct MemoryHeatmap: View {
    let decks: [FlashcardDeck]
    let review: (UUID) -> Void

    /// Below this, a studied topic is "being forgotten".
    static let fadingThreshold = 0.6

    private var ranked: [(deck: FlashcardDeck, strength: Double?)] {
        let now = Date()
        return decks
            .filter { !$0.cards.isEmpty }
            .map { ($0, $0.memoryStrength(now: now)) }
            .sorted { lhs, rhs in
                // Weakest first; topics not started yet at the end.
                switch (lhs.strength, rhs.strength) {
                case let (left?, right?): left < right
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): lhs.deck.title.localizedStandardCompare(rhs.deck.title) == .orderedAscending
                }
            }
    }

    var body: some View {
        let items = ranked
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Memory")
                    .font(.title3.bold())
                Spacer()
                legend
            }
            if let fading = items.first(where: { ($0.strength ?? 1) < Self.fadingThreshold }) {
                Button {
                    review(fading.deck.id)
                } label: {
                    Label {
                        Text("You're forgetting \"\(fading.deck.title)\". Review it now.")
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(items, id: \.deck.id) { item in
                    Button {
                        review(item.deck.id)
                    } label: {
                        tile(item.deck, strength: item.strength)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func tile(_ deck: FlashcardDeck, strength: Double?) -> some View {
        let color = Self.color(for: strength)
        return VStack(alignment: .leading, spacing: 6) {
            Text(deck.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
            Text(strength.map { "\(Int(($0 * 100).rounded()))%" } ?? "New")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text("\(deck.studiedCount) of \(deck.cards.count) cards studied")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.45)))
        .accessibilityElement(children: .combine)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Weak").font(.caption2).foregroundStyle(.secondary)
            ForEach([0.1, 0.4, 0.7, 0.95], id: \.self) { value in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Self.color(for: value))
                    .frame(width: 14, height: 10)
            }
            Text("Strong").font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Red up to 40%, through orange and yellow, to green at 100%: anything
    /// under the 90% a card has when it falls due already shows as fading.
    static func color(for strength: Double?) -> Color {
        guard let strength else { return .gray }
        let scaled = min(max((strength - 0.4) / 0.6, 0), 1)
        return Color(hue: 0.33 * scaled, saturation: 0.8, brightness: 0.85)
    }
}
