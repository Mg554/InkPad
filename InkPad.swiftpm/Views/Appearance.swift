import SwiftUI

/// Light, dark, or following the iPad's setting. The pages themselves stay
/// paper-colored; this changes everything around them.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Match iPad"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Picks the appearance, and what Apple Pencil does in text fields; shown
/// in the sidebar and in Flowmodoro.
struct AppearanceMenu: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(TextInputMode.defaultsKey) private var textInput: TextInputMode = .keyboard

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            Section("Tapping a Text Field with Apple Pencil") {
                Picker("Apple Pencil in Text Fields", selection: Binding(
                    get: { textInput },
                    set: { TextInputMode.set($0) }
                )) {
                    Label("Opens the Keyboard", systemImage: "keyboard").tag(TextInputMode.keyboard)
                    Label("Handwriting to Text", systemImage: "pencil.and.scribble").tag(TextInputMode.pencil)
                }
            }
        } label: {
            Label("Appearance", systemImage: appearance.symbol)
        }
    }
}
