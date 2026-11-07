import SwiftUI

/// A background a screen can have of its own (Expenses, Reminders):
/// the theme's, plain, old paper, glass, or a season.
enum ScreenBackdrop: String, Codable, CaseIterable, Identifiable {
    case theme, plain, oldPaper, glass, spring, summer, autumn, winter

    var id: Self { self }

    var title: String {
        switch self {
        case .theme: "Theme"
        case .plain: "Plain"
        case .oldPaper: "Old Paper"
        case .glass: "Glass"
        case .spring: "Spring"
        case .summer: "Summer"
        case .autumn: "Autumn"
        case .winter: "Winter"
        }
    }

    var systemImage: String {
        switch self {
        case .theme: "paintbrush"
        case .plain: "square"
        case .oldPaper: "scroll"
        case .glass: "square.3.layers.3d"
        case .spring: Season.spring.systemImage
        case .summer: Season.summer.systemImage
        case .autumn: Season.autumn.systemImage
        case .winter: Season.winter.systemImage
        }
    }

    var isPaper: Bool { self == .oldPaper }
}

struct ScreenBackdropView: View {
    let backdrop: ScreenBackdrop
    var animated = true

    var body: some View {
        switch backdrop {
        case .theme:
            ThemeBackground(recipe: animated ? ThemeSettings.current : ThemeSettings.current.still)
        case .plain:
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        case .oldPaper:
            OldPaperView().ignoresSafeArea()
        case .glass:
            ThemeBackground(recipe: glassRecipe)
        case .spring, .summer, .autumn, .winter:
            ThemeBackground(recipe: seasonRecipe)
        }
    }

    private var glassRecipe: ThemeRecipe {
        var recipe = ThemeSettings.current
        recipe.backdrop = .glass
        recipe.season = .none
        recipe.glassStrength = max(recipe.glassStrength, 0.45)
        return recipe
    }

    private var seasonRecipe: ThemeRecipe {
        var recipe = ThemeRecipe.preset(.named(backdrop.rawValue))
        recipe.animateSeason = animated && ThemeSettings.current.animateSeason
        return recipe
    }
}

/// Aged paper: warm parchment, darker edges, specks and a few faint stains.
struct OldPaperView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let dark = colorScheme == .dark
            let base = dark ? Color(red: 0.17, green: 0.14, blue: 0.09) : Color(red: 0.95, green: 0.9, blue: 0.77)
            let edge = dark ? Color.black.opacity(0.6) : Color(red: 0.55, green: 0.38, blue: 0.16).opacity(0.35)
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(base))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(size.width, size.height) * 0.75
            context.fill(Path(rect), with: .radialGradient(Gradient(colors: [.clear, .clear, edge]), center: center, startRadius: 0, endRadius: radius))
            // Stains.
            for index in 0..<4 {
                let seed = Double(index) * 3.1
                let spot = CGPoint(x: paperNoise(seed) * size.width, y: paperNoise(seed + 1) * size.height)
                let r = 60 + paperNoise(seed + 2) * 120
                context.fill(
                    Path(ellipseIn: CGRect(x: spot.x - r, y: spot.y - r * 0.8, width: r * 2, height: r * 1.6)),
                    with: .radialGradient(Gradient(colors: [edge.opacity(0.25), .clear]), center: spot, startRadius: 0, endRadius: r)
                )
            }
            // Fibers and specks.
            let specks = Int(size.width * size.height / 2500)
            for index in 0..<min(specks, 1200) {
                let seed = Double(index) + 40
                let x = paperNoise(seed) * size.width
                let y = paperNoise(seed + 0.5) * size.height
                let r = 0.4 + paperNoise(seed + 0.9) * 1.1
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(edge.opacity(0.5)))
            }
        }
    }
}

private func paperNoise(_ seed: Double) -> CGFloat {
    let value = sin(seed * 91.345 + 47.853) * 24_634.6345
    return CGFloat(value - floor(value))
}

extension View {
    /// Shows a screen's own background (lists and forms let it through).
    func screenBackdrop(_ backdrop: ScreenBackdrop) -> some View {
        scrollContentBackground(.hidden)
            .background { ScreenBackdropView(backdrop: backdrop) }
    }
}

// MARK: Glow

/// A glow the user can tune: on or off, its color, strength and size.
struct GlowStyle: Codable, Equatable {
    enum Source: String, Codable, CaseIterable, Identifiable {
        /// Each item glows in its own color.
        case matching
        case accent
        case custom
        var id: Self { self }
        var title: String {
            switch self {
            case .matching: "Each Item's Color"
            case .accent: "Theme Accent"
            case .custom: "Custom"
            }
        }
    }

    var isOn = true
    var source = Source.matching
    /// For a custom color (0...1 around the color wheel).
    var hue = 0.55
    var intensity = 0.5
    var radius = 12.0

    /// The glow color for an item whose own color is `own`.
    func color(for own: Color) -> Color {
        switch source {
        case .matching: own
        case .accent: .inkAccent
        case .custom: Color(hue: hue, saturation: 0.85, brightness: 1)
        }
    }
}

private struct StyledGlow: ViewModifier {
    let glow: GlowStyle
    let color: Color

    func body(content: Content) -> some View {
        if glow.isOn {
            let tint = glow.color(for: color)
            content
                .shadow(color: tint.opacity(glow.intensity), radius: glow.radius)
                .shadow(color: tint.opacity(glow.intensity * 0.4), radius: glow.radius * 2.2)
        } else {
            content
        }
    }
}

extension View {
    /// A glow around this view, tuned by the user's glow settings.
    func styledGlow(_ glow: GlowStyle, color: Color) -> some View {
        modifier(StyledGlow(glow: glow, color: color))
    }
}

/// The glow settings, for a Form.
struct GlowSettingsSection: View {
    @Binding var glow: GlowStyle
    var footer = "Glow lights up cards, charts and buttons softly."

    var body: some View {
        Section {
            Toggle(isOn: $glow.isOn.animation()) {
                Label("Glow", systemImage: "sparkles")
            }
            if glow.isOn {
                Picker(selection: $glow.source) {
                    ForEach(GlowStyle.Source.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Color", systemImage: "paintpalette")
                }
                if glow.source == .custom {
                    HStack {
                        Slider(value: $glow.hue, in: 0...1)
                            .background(
                                LinearGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 0.8, brightness: 1) }, startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 6)
                                    .clipShape(Capsule())
                                    .opacity(0.6)
                            )
                        Circle()
                            .fill(Color(hue: glow.hue, saturation: 0.85, brightness: 1))
                            .frame(width: 22, height: 22)
                            .shadow(color: Color(hue: glow.hue, saturation: 0.85, brightness: 1), radius: 6)
                    }
                }
                LabeledSlider(title: "Strength", systemImage: "sun.max", value: $glow.intensity, range: 0.1...1, text: "\(Int(glow.intensity * 100))%")
                LabeledSlider(title: "Size", systemImage: "circle.dashed", value: $glow.radius, range: 4...30, text: "\(Int(glow.radius))")
            }
        } header: {
            Text("Glow")
        } footer: {
            Text(footer)
        }
    }
}

struct LabeledSlider: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(text).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}

/// Pick a screen background, with a small picture of each.
struct BackdropPicker: View {
    @Binding var backdrop: ScreenBackdrop

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 12) {
            ForEach(ScreenBackdrop.allCases) { option in
                Button {
                    withAnimation { backdrop = option }
                } label: {
                    VStack(spacing: 5) {
                        ScreenBackdropView(backdrop: option, animated: false)
                            .frame(height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(backdrop == option ? Color.inkAccent : Color.secondary.opacity(0.3), lineWidth: backdrop == option ? 3 : 1)
                            )
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .label))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: Saved looks

/// A screen's look, saved on the iPad as JSON in UserDefaults.
protocol StoredLook: Codable, Equatable {
    static var storageKey: String { get }
    init()
}

extension StoredLook {
    static func load() -> Self {
        UserDefaults.standard.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.storageKey)
    }
}

extension KeyedDecodingContainer {
    /// A saved value, or `fallback` when it is missing (older saves).
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

extension GlowStyle {
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOn = container.value(.isOn, or: isOn)
        source = container.value(.source, or: source)
        hue = container.value(.hue, or: hue)
        intensity = container.value(.intensity, or: intensity)
        radius = container.value(.radius, or: radius)
    }
}
