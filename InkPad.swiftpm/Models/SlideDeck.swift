import Foundation

/// A presentation made from notes, like NotebookLM's slide decks. Stored in
/// `workspace.json`; pictures of pages live in `decks/<id>/`.
struct SlideDeck: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var slides: [Slide]
    var theme: SlideTheme
    var format: DeckFormat
    /// The notes it was made from.
    var sourceNoteIDs: [UUID]
    /// `true` when Apple Intelligence wrote the slides.
    var isAIWritten: Bool
    let createdAt: Date
    var modifiedAt: Date
}

struct Slide: Codable, Identifiable, Equatable, Sendable {
    enum Layout: String, Codable, CaseIterable, Identifiable, Sendable {
        case title, agenda, bullets, quote, image, summary

        var id: Self { self }

        var title: String {
            switch self {
            case .title: "Title"
            case .agenda: "Overview"
            case .bullets: "Points"
            case .quote: "Quote"
            case .image: "Picture"
            case .summary: "Takeaways"
            }
        }
    }

    let id: UUID
    var layout: Layout
    /// For a quote, the quote itself.
    var title: String
    /// The title slide's subtitle, or who said a quote.
    var subtitle: String
    var bullets: [String]
    /// What to say while the slide is shown; read aloud when narrating.
    var speakerNotes: String
    /// SF Symbol shown on the slide.
    var symbol: String
    /// A picture in the deck's folder.
    var imageFile: String?

    init(
        layout: Layout,
        title: String,
        subtitle: String = "",
        bullets: [String] = [],
        speakerNotes: String = "",
        symbol: String = "sparkles",
        imageFile: String? = nil
    ) {
        id = UUID()
        self.layout = layout
        self.title = title
        self.subtitle = subtitle
        self.bullets = bullets
        self.speakerNotes = speakerNotes
        self.symbol = symbol
        self.imageFile = imageFile
    }

    /// Bullets with blank lines (left while editing) removed.
    var visibleBullets: [String] {
        bullets.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// A copy with a new identity, for duplicating.
    func duplicated() -> Slide {
        Slide(
            layout: layout,
            title: title,
            subtitle: subtitle,
            bullets: bullets,
            speakerNotes: speakerNotes,
            symbol: symbol,
            imageFile: imageFile
        )
    }
}

/// NotebookLM's two kinds of deck.
enum DeckFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Full sentences, to read on its own or share.
    case detailed
    /// A few words per slide, with talking points in the speaker notes.
    case presenter

    var id: Self { self }

    var title: String {
        switch self {
        case .detailed: "Detailed Deck"
        case .presenter: "Presenter Slides"
        }
    }

    var summary: String {
        switch self {
        case .detailed: "Complete sentences on every slide, ready to read or send to someone."
        case .presenter: "Short points to talk over, with what to say in each slide's speaker notes."
        }
    }

    var bulletsPerSlide: Int {
        switch self {
        case .detailed: 5
        case .presenter: 3
        }
    }

    /// The longest bullet, in words.
    var wordsPerBullet: Int {
        switch self {
        case .detailed: 30
        case .presenter: 14
        }
    }
}

enum DeckLength: String, CaseIterable, Identifiable, Sendable {
    case short, standard, long

    var id: Self { self }

    var title: String {
        switch self {
        case .short: "Short"
        case .standard: "Default"
        case .long: "Long"
        }
    }

    /// Content slides, not counting the title, overview, pictures and takeaways.
    var contentSlides: Int {
        switch self {
        case .short: 4
        case .standard: 7
        case .long: 11
        }
    }
}

enum SlideTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case aurora, midnight, paper, sunset, forest, ocean

    var id: Self { self }
    var title: String { rawValue.capitalized }
}
