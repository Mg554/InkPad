import SwiftUI

/// Formats money in the workspace currency. Without `showsCents`, whole
/// amounts have no decimals (1,000 instead of 1,000.00).
struct MoneyFormatter {
    let currencyCode: String
    let showsCents: Bool

    func string(_ value: Decimal) -> String {
        value.formatted(style)
    }

    func string(_ value: Double) -> String {
        Decimal(value).formatted(style)
    }

    private var style: Decimal.FormatStyle.Currency {
        .currency(code: currencyCode).precision(showsCents ? .fractionLength(2) : .fractionLength(0...2))
    }
}

/// A softly glowing card used across the workspace.
struct GlowCard: ViewModifier {
    let color: Color
    var isActive = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [color.opacity(0.7), color.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: color.opacity(isActive ? 0.45 : 0), radius: isActive ? 12 : 0)
    }
}

extension View {
    func glowCard(_ color: Color, isActive: Bool = true) -> some View {
        modifier(GlowCard(color: color, isActive: isActive))
    }
}

/// Buttons and cards that shrink slightly and glow while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
