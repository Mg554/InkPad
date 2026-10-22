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
    /// `true` when an AI service (or Apple Intelligence) wrote the slides.
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
    var isDark: Bool { self != .paper }

    /// The theme's colors, shared by the slides on screen and exported files.
    var palette: SlidePalette {
        let darkText = SlideColor(0.10, 0.10, 0.14)
        let light = SlidePalette(
            background: [], title: SlideColor(1, 1, 1), text: SlideColor(0.90, 0.90, 0.93),
            accent: SlideColor(1, 1, 1), glow: SlideColor(1, 1, 1), onAccent: SlideColor(0.06, 0.07, 0.12)
        )
        switch self {
        case .aurora:
            return light.with(background: [SlideColor(0.07, 0.08, 0.20), SlideColor(0.24, 0.10, 0.40)],
                              accent: SlideColor(0.42, 0.86, 1.00), glow: SlideColor(0.85, 0.35, 0.95))
        case .midnight:
            return light.with(background: [SlideColor(0.05, 0.06, 0.08), SlideColor(0.13, 0.15, 0.20)],
                              accent: SlideColor(0.99, 0.78, 0.30), glow: SlideColor(0.30, 0.40, 0.80))
        case .paper:
            return SlidePalette(
                background: [SlideColor(0.99, 0.98, 0.95), SlideColor(0.93, 0.91, 0.86)],
                title: darkText, text: SlideColor(0.22, 0.22, 0.27),
                accent: SlideColor(0.30, 0.32, 0.86), glow: SlideColor(0.98, 0.80, 0.55), onAccent: SlideColor(1, 1, 1)
            )
        case .sunset:
            return light.with(background: [SlideColor(0.98, 0.47, 0.33), SlideColor(0.62, 0.16, 0.44)],
                              accent: SlideColor(1.00, 0.92, 0.62), glow: SlideColor(1.00, 0.80, 0.40))
        case .forest:
            return light.with(background: [SlideColor(0.05, 0.19, 0.15), SlideColor(0.10, 0.35, 0.27)],
                              accent: SlideColor(0.62, 0.95, 0.58), glow: SlideColor(0.30, 0.80, 0.60))
        case .ocean:
            return light.with(background: [SlideColor(0.02, 0.22, 0.42), SlideColor(0.04, 0.52, 0.66)],
                              accent: SlideColor(0.80, 0.97, 1.00), glow: SlideColor(0.30, 0.90, 0.85))
        }
    }
}

/// A color with red, green and blue from 0 to 1.
struct SlideColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// "RRGGBB", as Office files write colors.
    var hex: String {
        [red, green, blue].map { component -> String in
            let value = String(Int((min(max(component, 0), 1) * 255).rounded()), radix: 16, uppercase: true)
            return value.count == 1 ? "0" + value : value
        }.joined()
    }
}

struct SlidePalette: Sendable {
    var background: [SlideColor]
    var title: SlideColor
    var text: SlideColor
    var accent: SlideColor
    var glow: SlideColor
    var onAccent: SlideColor

    func with(background: [SlideColor], accent: SlideColor, glow: SlideColor) -> SlidePalette {
        var copy = self
        copy.background = background
        copy.accent = accent
        copy.glow = glow
        return copy
    }
}
