import SwiftUI

extension FolderColor {
    var color: Color {
        switch self {
        case .gray: .gray
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

extension Optional where Wrapped == FolderColor {
    /// Folder tint, with the app accent color as the default.
    var tint: Color { self?.color ?? .accentColor }
}
