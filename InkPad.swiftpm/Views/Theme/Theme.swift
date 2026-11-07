import SwiftUI
import UIKit

/// A ready-made theme: colors for the background, cards and sidebar (light
/// and dark), an accent, glass colors and a paper for new notes.
struct ThemePreset: Identifiable, Equatable {
    let id: String
    let name: String
    /// nil: the system's own background colors.
    let background: (light: UIColor, dark: UIColor)?
    let sidebar: (light: UIColor, dark: UIColor)?
    let accent: Color
    /// Colors blended behind the cards in the glass style.
    let glass: [Color]
    let paper: PaperColor
    /// Nature drawn over the background (the season themes).
    var season: Season = .none

    static func == (lhs: ThemePreset, rhs: ThemePreset) -> Bool { lhs.id == rhs.id }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func pair(_ light: UInt32, _ dark: UInt32) -> (light: UIColor, dark: UIColor) {
        (rgb(light), rgb(dark))
    }

    static let all: [ThemePreset] = [
        ThemePreset(id: "classic", name: "Classic", background: nil, sidebar: nil,
                    accent: .indigo, glass: [.indigo, .purple, .blue, .cyan], paper: .white),
        ThemePreset(id: "paper", name: "Paper", background: pair(0xF6F1E7, 0x1E1B16), sidebar: pair(0xEFE7D6, 0x26221B),
                    accent: Color(uiColor: rgb(0xB5651D)), glass: [.orange, .brown, .yellow, .red], paper: .ivory),
        ThemePreset(id: "midnight", name: "Midnight", background: pair(0xF2F2F7, 0x000000), sidebar: pair(0xE9E9EF, 0x0B0B0D),
                    accent: .cyan, glass: [.blue, .indigo, .cyan, .black], paper: .black),
        ThemePreset(id: "ocean", name: "Ocean", background: pair(0xEAF4FB, 0x0B1A2A), sidebar: pair(0xDCEBF6, 0x0F2236),
                    accent: .blue, glass: [.blue, .cyan, .teal, .indigo], paper: .mist),
        ThemePreset(id: "forest", name: "Forest", background: pair(0xEEF5EC, 0x0F1A12), sidebar: pair(0xE1EDDD, 0x142218),
                    accent: .green, glass: [.green, .mint, .teal, .yellow], paper: .ivory),
        ThemePreset(id: "sepia", name: "Sepia", background: pair(0xF4ECD8, 0x2A2218), sidebar: pair(0xEADFC4, 0x322819),
                    accent: .brown, glass: [.brown, .orange, .yellow, .red], paper: .sand),
        ThemePreset(id: "rose", name: "Rose", background: pair(0xFBEFF3, 0x22141A), sidebar: pair(0xF6E1E9, 0x2B1820),
                    accent: .pink, glass: [.pink, .purple, .red, .orange], paper: .white),
        ThemePreset(id: "nord", name: "Nord", background: pair(0xECEFF4, 0x2E3440), sidebar: pair(0xE5E9F0, 0x3B4252),
                    accent: Color(uiColor: rgb(0x5E81AC)), glass: [Color(uiColor: rgb(0x88C0D0)), Color(uiColor: rgb(0x81A1C1)), Color(uiColor: rgb(0xB48EAD)), Color(uiColor: rgb(0xA3BE8C))], paper: .mist),
        ThemePreset(id: "sunset", name: "Sunset", background: pair(0xFFF3EA, 0x1F1220), sidebar: pair(0xFBE6DA, 0x2A1729),
                    accent: .orange, glass: [.orange, .pink, .purple, .yellow], paper: .ivory),
        ThemePreset(id: "spring", name: "Spring", background: pair(0xF1F8EC, 0x111C12), sidebar: pair(0xE4F1DC, 0x162317),
                    accent: Color(uiColor: rgb(0x3FA34D)), glass: [.green, .pink, .mint, .yellow], paper: .white, season: .spring),
        ThemePreset(id: "summer", name: "Summer", background: pair(0xFFF8E6, 0x1C1A10), sidebar: pair(0xFDEFC8, 0x252114),
                    accent: Color(uiColor: rgb(0x00A3A3)), glass: [.yellow, .orange, .cyan, .teal], paper: .ivory, season: .summer),
        ThemePreset(id: "autumn", name: "Autumn", background: pair(0xFBF1E2, 0x1E150D), sidebar: pair(0xF4E2C6, 0x281C11),
                    accent: Color(uiColor: rgb(0xC8741A)), glass: [.orange, .yellow, .red, .brown], paper: .sand, season: .autumn),
        ThemePreset(id: "winter", name: "Winter", background: pair(0xEEF4FA, 0x0E1520), sidebar: pair(0xE2ECF6, 0x131C2A),
                    accent: Color(uiColor: rgb(0x4A8FD9)), glass: [.cyan, .blue, .white, .indigo], paper: .mist, season: .winter),
    ]

    static func named(_ id: String) -> ThemePreset {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Everything the user chose, mixed from different themes (Theme Mixer).
struct ThemeRecipe: Codable, Equatable {
    enum Backdrop: String, Codable, CaseIterable, Identifiable {
        case plain, glass
        var id: Self { self }
        var title: String { self == .plain ? "Plain" : "Glass" }
    }

    enum FontStyle: String, Codable, CaseIterable, Identifiable {
        case standard, rounded, serif, mono
        var id: Self { self }

        var title: String {
            switch self {
            case .standard: "Standard"
            case .rounded: "Rounded"
            case .serif: "Serif"
            case .mono: "Mono"
            }
        }

        var design: Font.Design {
            switch self {
            case .standard: .default
            case .rounded: .rounded
            case .serif: .serif
            case .mono: .monospaced
            }
        }

        var uiDesign: UIFontDescriptor.SystemDesign {
            switch self {
            case .standard: .default
            case .rounded: .rounded
            case .serif: .serif
            case .mono: .monospaced
            }
        }
    }

    enum CardSize: String, Codable, CaseIterable, Identifiable {
        case compact, regular, large
        var id: Self { self }
        var title: String { rawValue.capitalized }

        var range: (min: CGFloat, max: CGFloat) {
            switch self {
            case .compact: (140, 190)
            case .regular: (170, 240)
            case .large: (220, 310)
            }
        }
    }

    var name = "Classic"
    /// Backgrounds and sidebar come from this theme.
    var colorsFrom = "classic"
    var accentFrom = "classic"
    var backdrop = Backdrop.plain
    var glassFrom = "classic"
    var paperFrom = "classic"
    /// New notes start on the theme's paper (each note can still change it).
    var paperForNewNotes = true
    var appFont = FontStyle.standard
    var cardSize = CardSize.regular
    /// The font used when typing with the keyboard (text boxes, text notes).
    var typingFont = FontStyle.standard
    var typingSize: Double = 18
    /// Glass: turns its colors around the color wheel (degrees).
    var glassHue: Double = 0
    /// Glass: how strongly its colors show (0.1 faint ... 1 deep).
    var glassStrength: Double = 0.4
    /// Glass: how softly its colors blur together.
    var glassBlur: Double = 30
    /// Cards and tiles become frosted glass instead of solid.
    var glassCards = false
    /// Nature drawn over the background.
    var season = Season.none
    /// Falling leaves, petals or snow.
    var animateSeason = true

    /// A whole preset, unmixed.
    static func preset(_ preset: ThemePreset) -> ThemeRecipe {
        var recipe = ThemeRecipe()
        recipe.name = preset.name
        recipe.colorsFrom = preset.id
        recipe.accentFrom = preset.id
        recipe.glassFrom = preset.id
        recipe.paperFrom = preset.id
        recipe.backdrop = preset.id == "sunset" || preset.season != .none ? .glass : .plain
        recipe.glassStrength = preset.season != .none ? 0.3 : 0.4
        recipe.season = preset.season
        return recipe
    }

    /// The same theme without falling leaves or snow (small previews).
    var still: ThemeRecipe {
        var recipe = self
        recipe.animateSeason = false
        return recipe
    }

    var colors: ThemePreset { .named(colorsFrom) }
    var accent: Color { ThemePreset.named(accentFrom).accent }
    var glass: [Color] { ThemePreset.named(glassFrom).glass }
    var paper: PaperColor { ThemePreset.named(paperFrom).paper }

    var background: Color {
        guard let pair = colors.background else { return Color(uiColor: .systemBackground) }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? pair.dark : pair.light })
    }

    var sidebar: Color? {
        guard let pair = colors.sidebar else { return nil }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? pair.dark : pair.light })
    }

    func typingUIFont(size: CGFloat? = nil, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size ?? CGFloat(typingSize), weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(typingFont.uiDesign) else { return base }
        return UIFont(descriptor: descriptor, size: size ?? CGFloat(typingSize))
    }
}

extension ThemeRecipe {
    /// Reads older saved themes too: a missing setting keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        name = value(.name, name)
        colorsFrom = value(.colorsFrom, colorsFrom)
        accentFrom = value(.accentFrom, accentFrom)
        backdrop = value(.backdrop, backdrop)
        glassFrom = value(.glassFrom, glassFrom)
        paperFrom = value(.paperFrom, paperFrom)
        paperForNewNotes = value(.paperForNewNotes, paperForNewNotes)
        appFont = value(.appFont, appFont)
        cardSize = value(.cardSize, cardSize)
        typingFont = value(.typingFont, typingFont)
        typingSize = value(.typingSize, typingSize)
        glassHue = value(.glassHue, glassHue)
        glassStrength = value(.glassStrength, glassStrength)
        glassBlur = value(.glassBlur, glassBlur)
        glassCards = value(.glassCards, glassCards)
        season = value(.season, season)
        animateSeason = value(.animateSeason, animateSeason)
    }
}

/// The current theme, saved on the iPad. `current` is read where views
/// can't observe it (UIKit text, accent colors); the app rebuilds its views
/// when the theme is applied.
@MainActor
final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()
    private static let key = "themeRecipe"
    private static let savedKey = "savedThemes"

    /// Read anywhere; follows `recipe`.
    nonisolated(unsafe) static var current = ThemeRecipe()

    @Published private(set) var recipe: ThemeRecipe
    /// Changes when a theme is applied, so the app rebuilds its views.
    @Published private(set) var revision = 0
    /// The user's own mixes.
    @Published private(set) var saved: [ThemeRecipe]

    private init() {
        let defaults = UserDefaults.standard
        recipe = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ThemeRecipe.self, from: $0) } ?? ThemeRecipe()
        saved = defaults.data(forKey: Self.savedKey).flatMap { try? JSONDecoder().decode([ThemeRecipe].self, from: $0) } ?? []
        Self.current = recipe
    }

    func apply(_ recipe: ThemeRecipe) {
        guard recipe != self.recipe else { return }
        self.recipe = recipe
        Self.current = recipe
        UserDefaults.standard.set(try? JSONEncoder().encode(recipe), forKey: Self.key)
        revision += 1
    }

    func save(_ recipe: ThemeRecipe, named name: String) {
        var mix = recipe
        mix.name = name
        saved.removeAll { $0.name == name }
        saved.append(mix)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
    }

    func deleteSaved(_ name: String) {
        saved.removeAll { $0.name == name }
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
    }
}

extension Color {
    /// The theme's accent color (use instead of `Color.accentColor`).
    static var inkAccent: Color { ThemeSettings.current.accent }
}

/// The theme's background behind a screen: its color, or glass colors
/// blended softly behind the content.
struct ThemeBackground: View {
    var recipe = ThemeSettings.current
    var isSidebar = false

    var body: some View {
        ZStack {
            if isSidebar, let sidebar = recipe.sidebar {
                sidebar
            } else {
                recipe.background
            }
            if recipe.backdrop == .glass {
                GlassBlend(colors: recipe.glass, hue: recipe.glassHue, blur: recipe.glassBlur)
                    .opacity(isSidebar ? recipe.glassStrength * 0.6 : recipe.glassStrength)
            }
            if recipe.season != .none {
                SceneryView(season: recipe.season, animated: recipe.animateSeason && !isSidebar, isSidebar: isSidebar)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct GlassBlend: View {
    let colors: [Color]
    var hue: Double = 0
    var blur: Double = 30

    var body: some View {
        blend
            .hueRotation(.degrees(hue))
            .blur(radius: blur)
    }

    @ViewBuilder
    private var blend: some View {
        if #available(iOS 18.0, *) {
            let c = colors + colors
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.55, 0.45], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [c[0], c[1], c[2], c[3], .clear, c[0], c[2], c[3], c[1]]
            )
        } else {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

extension View {
    /// Shows the theme's background behind a screen (lists and forms let it
    /// through).
    func themedBackground(sidebar: Bool = false) -> some View {
        scrollContentBackground(.hidden)
            .background { ThemeBackground(isSidebar: sidebar) }
    }

    /// The background of a card or tile: solid, or frosted glass when the
    /// theme has Glass Cards on.
    func themedCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(ThemedCard(cornerRadius: cornerRadius))
    }
}

private struct ThemedCard: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if ThemeSettings.current.glassCards {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.25), lineWidth: 0.8))
        } else {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        }
    }
}
