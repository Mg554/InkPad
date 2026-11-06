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

    /// A dot in this color for menus. Menus draw symbol images in one
    /// color, so the image is colored before it gets there.
    func menuDot(selected: Bool) -> Image {
        let name = selected ? "checkmark.circle.fill" : "circle.fill"
        let image = UIImage(systemName: name)?
            .withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
        return image.map { Image(uiImage: $0) } ?? Image(systemName: name)
    }
}

extension Optional where Wrapped == FolderColor {
    /// Folder tint, with the app accent color as the default.
    var tint: Color { self?.color ?? .accentColor }
}
