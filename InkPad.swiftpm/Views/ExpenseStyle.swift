import SwiftUI

/// How the Expenses screen looks: a chart style, which charts show, the
/// glow and the background. Changed in Customize (paintbrush button).
struct ExpenseLook: StoredLook {
    static let storageKey = "expenseLook"

    enum Style: String, Codable, CaseIterable, Identifiable {
        case glass, neon, minimal, paper
        var id: Self { self }

        var title: String {
            switch self {
            case .glass: "Glass"
            case .neon: "Neon"
            case .minimal: "Minimal"
            case .paper: "Paper"
            }
        }

        var detail: String {
            switch self {
            case .glass: "Frosted cards, soft gradients, a light sheen."
            case .neon: "Dark cards with bright, glowing lines."
            case .minimal: "Calm shades of one color, no glow."
            case .paper: "Muted inks on paper, like a notebook."
            }
        }
    }

    var style = Style.glass
    var showsDonut = true
    var showsBars = false
    var showsDaily = true
    var showsRings = true
    var glow = GlowStyle()
    var backdrop = ScreenBackdrop.theme

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = container.value(.style, or: style)
        showsDonut = container.value(.showsDonut, or: showsDonut)
        showsBars = container.value(.showsBars, or: showsBars)
        showsDaily = container.value(.showsDaily, or: showsDaily)
        showsRings = container.value(.showsRings, or: showsRings)
        glow = container.value(.glow, or: glow)
        backdrop = container.value(.backdrop, or: backdrop)
    }

    /// The glow, which the Minimal style never has.
    var activeGlow: GlowStyle {
        var glow = glow
        if style == .minimal { glow.isOn = false }
        return glow
    }

    /// The color of a category in this style.
    func color(_ category: Expense.Category) -> Color {
        let index = Expense.Category.allCases.firstIndex(of: category) ?? 0
        switch style {
        case .glass:
            return [Color.orange, .blue, .pink, .purple, .red, .teal, .indigo, .green, .gray][index]
        case .neon:
            return [Color(red: 1, green: 0.55, blue: 0.1), Color(red: 0.2, green: 0.8, blue: 1), Color(red: 1, green: 0.2, blue: 0.7),
                    Color(red: 0.7, green: 0.4, blue: 1), Color(red: 1, green: 0.25, blue: 0.3), Color(red: 0.1, green: 1, blue: 0.8),
                    Color(red: 0.45, green: 0.5, blue: 1), Color(red: 0.4, green: 1, blue: 0.3), Color(white: 0.8)][index]
        case .minimal:
            return Color.inkAccent.opacity(1 - Double(index) * 0.09)
        case .paper:
            return [Color(red: 0.72, green: 0.42, blue: 0.2), Color(red: 0.3, green: 0.42, blue: 0.55), Color(red: 0.6, green: 0.3, blue: 0.35),
                    Color(red: 0.45, green: 0.35, blue: 0.55), Color(red: 0.65, green: 0.22, blue: 0.18), Color(red: 0.3, green: 0.5, blue: 0.45),
                    Color(red: 0.35, green: 0.32, blue: 0.5), Color(red: 0.42, green: 0.52, blue: 0.25), Color(red: 0.5, green: 0.47, blue: 0.42)][index]
        }
    }

    /// The fill of a chart mark in this style.
    func fill(_ color: Color) -> AnyShapeStyle {
        switch style {
        case .glass:
            AnyShapeStyle(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
        case .neon:
            AnyShapeStyle(color.opacity(0.55))
        case .minimal, .paper:
            AnyShapeStyle(color)
        }
    }

    /// Behind each row and card of the list.
    @ViewBuilder
    var rowBackground: some View {
        switch style {
        case .glass:
            Rectangle().fill(.ultraThinMaterial)
        case .neon:
            Color(red: 0.06, green: 0.06, blue: 0.1).opacity(0.85)
        case .minimal:
            Color(uiColor: .secondarySystemGroupedBackground)
        case .paper:
            Color(red: 0.98, green: 0.95, blue: 0.86).opacity(0.85)
        }
    }

    /// Neon cards are dark, so their text is light.
    var colorScheme: ColorScheme? {
        switch style {
        case .neon: .dark
        case .paper: .light
        case .glass, .minimal: nil
        }
    }

    var fontDesign: Font.Design? { style == .paper ? .serif : nil }
}

/// Customize the Expenses screen.
struct ExpenseStyleView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var look: ExpenseLook

    var body: some View {
        NavigationStack {
            Form {
                Section("Style") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(ExpenseLook.Style.allCases) { style in
                            styleCard(style)
                        }
                    }
                    .padding(.vertical, 6)
                    Text(trMessage(look.style.detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Charts") {
                    Toggle(isOn: $look.showsRings) {
                        Label("Budget Rings", systemImage: "circle.circle")
                    }
                    Toggle(isOn: $look.showsDonut) {
                        Label("Spending by Category", systemImage: "chart.pie")
                    }
                    Toggle(isOn: $look.showsBars) {
                        Label("Category Bars", systemImage: "chart.bar")
                    }
                    Toggle(isOn: $look.showsDaily) {
                        Label("This Month Day by Day", systemImage: "chart.xyaxis.line")
                    }
                }

                if look.style == .minimal {
                    Section {
                        Text("The Minimal style has no glow.")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Glow")
                    }
                } else {
                    GlowSettingsSection(glow: $look.glow, footer: "The glow around cards, rings and chart marks.")
                }

                Section("Background") {
                    BackdropPicker(backdrop: $look.backdrop)
                }

                Section {
                    Button("Reset to Default", role: .destructive) {
                        withAnimation { look = ExpenseLook() }
                    }
                }
            }
            .navigationTitle("Customize Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func styleCard(_ style: ExpenseLook.Style) -> some View {
        var sample = look
        sample.style = style
        let isOn = look.style == style
        return Button {
            withAnimation(.snappy) { look.style = style }
        } label: {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array([0.5, 0.8, 0.35, 1, 0.65].enumerated()), id: \.offset) { item in
                        let category = Expense.Category.allCases[item.offset]
                        RoundedRectangle(cornerRadius: 3)
                            .fill(sample.fill(sample.color(category)))
                            .frame(width: 12, height: 44 * item.element)
                            .styledGlow(sample.activeGlow, color: sample.color(category))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .background { sample.rowBackground }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isOn ? Color.inkAccent : Color.secondary.opacity(0.3), lineWidth: isOn ? 3 : 1))
                Text(tr(style.title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
            }
        }
        .buttonStyle(.plain)
    }
}

/// Apple Watch–style rings: budget used, money kept, and the month passed.
struct BudgetRings: View {
    struct Ring: Identifiable {
        let id: String
        let title: String
        let value: Double
        let detail: String
        let color: Color
    }

    let rings: [Ring]
    let look: ExpenseLook
    @State private var shown = false

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                    let size = 170 - CGFloat(index) * 44
                    Circle()
                        .stroke(ring.color.opacity(0.18), lineWidth: 18)
                        .frame(width: size, height: size)
                    Circle()
                        .trim(from: 0, to: shown ? min(max(ring.value, 0.001), 1) : 0.001)
                        .stroke(
                            AngularGradient(colors: [ring.color.opacity(0.7), ring.color], center: .center),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: size, height: size)
                        .styledGlow(look.activeGlow, color: ring.color)
                    if ring.value > 1 {
                        // A second lap shows going over, as on the Watch.
                        Circle()
                            .trim(from: 0, to: shown ? min(ring.value - 1, 1) : 0)
                            .stroke(ring.color.opacity(0.75), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: size, height: size)
                            .shadow(color: .black.opacity(0.35), radius: 3)
                    }
                }
            }
            .frame(width: 180, height: 180)
            .animation(.spring(response: 1, dampingFraction: 0.8), value: shown)
            .onAppear { shown = true }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(rings) { ring in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr(ring.title))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ring.color)
                        Text(trMessage(ring.detail))
                            .font(.title3.bold())
                            .contentTransition(.numericText())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}
