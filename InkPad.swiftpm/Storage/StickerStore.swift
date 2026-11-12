import CoreImage
import PencilKit
import UIKit
import Vision

/// A sticker the owner made: a picture (with a see-through background) or
/// saved handwriting that is placed back as editable ink.
struct Sticker: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case image, ink
    }

    let id: UUID
    var name: String
    var kind: Kind
    /// A file in the Stickers folder: PNG for pictures, PKDrawing data for ink.
    var file: String
    var folder: String?
    let createdAt: Date

    init(name: String, kind: Kind, file: String, folder: String?) {
        id = UUID()
        self.name = name
        self.kind = kind
        self.file = file
        self.folder = folder
        createdAt = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = container.value(.name, or: "")
        kind = container.value(.kind, or: Kind.image)
        file = try container.decode(String.self, forKey: .file)
        folder = container.value(.folder, or: nil)
        createdAt = container.value(.createdAt, or: Date())
    }

    var key: String { "mine:" + id.uuidString }
}

/// A sticker that comes with the app, drawn when it is used.
struct BuiltInSticker: Identifiable, Hashable {
    enum Look: Hashable {
        case symbol(String, UIColor)
        case emoji(String)
        case label(String, UIColor)
    }

    let id: String
    let name: String
    let look: Look

    var key: String { "pack:" + id }

    /// A picture of the sticker, `side` points on its longer side.
    func image(side: CGFloat = 160) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        switch look {
        case let .symbol(name, color):
            let size = CGSize(width: side, height: side)
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let config = UIImage.SymbolConfiguration(pointSize: side * 0.62, weight: .semibold)
                guard let symbol = UIImage(systemName: name, withConfiguration: config)?
                    .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
                let fit = symbol.size
                symbol.draw(in: CGRect(x: (side - fit.width) / 2, y: (side - fit.height) / 2, width: fit.width, height: fit.height))
            }
        case let .emoji(text):
            let size = CGSize(width: side, height: side)
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let font = UIFont.systemFont(ofSize: side * 0.72)
                let string = NSAttributedString(string: text, attributes: [.font: font])
                let fit = string.size()
                string.draw(at: CGPoint(x: (side - fit.width) / 2, y: (side - fit.height) / 2))
            }
        case let .label(text, color):
            let font = UIFont.systemFont(ofSize: side * 0.2, weight: .heavy)
            let string = NSAttributedString(string: tr(text).uppercased(), attributes: [.font: font, .foregroundColor: UIColor.white])
            let textSize = string.size()
            let padding: CGFloat = side * 0.1
            let size = CGSize(width: textSize.width + padding * 2.4, height: textSize.height + padding * 1.4)
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                color.setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
                string.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
            }
        }
    }
}

/// A set of built-in stickers.
struct StickerPack: Identifiable {
    let id: String
    let name: String
    let stickers: [BuiltInSticker]

    static let all: [StickerPack] = [study, marks, emoji, arrows]

    private static func symbols(_ pack: String, _ items: [(String, String, UIColor)]) -> [BuiltInSticker] {
        items.map { BuiltInSticker(id: pack + "." + $0.0, name: $0.1, look: .symbol($0.0, $0.2)) }
    }

    private static func labels(_ items: [(String, UIColor)]) -> [BuiltInSticker] {
        items.map { BuiltInSticker(id: "study." + $0.0, name: $0.0, look: .label($0.0, $0.1)) }
    }

    static let study = StickerPack(id: "study", name: "Study Labels", stickers: labels([
        ("Important", .systemRed), ("Definition", .systemBlue), ("Example", .systemGreen),
        ("Exam", .systemOrange), ("Review", .systemPurple), ("Formula", .systemTeal),
        ("Remember", .systemPink), ("Question", .systemIndigo), ("Summary", .systemBrown),
        ("To Do", .systemGray),
    ]))

    static let marks = StickerPack(id: "marks", name: "Marks", stickers: symbols("marks", [
        ("star.fill", "Star", .systemYellow), ("checkmark.seal.fill", "Done", .systemGreen),
        ("exclamationmark.triangle.fill", "Warning", .systemOrange), ("questionmark.circle.fill", "Question", .systemBlue),
        ("lightbulb.fill", "Idea", .systemYellow), ("flag.fill", "Flag", .systemRed),
        ("bookmark.fill", "Bookmark", .systemPurple), ("heart.fill", "Heart", .systemPink),
        ("pin.fill", "Pin", .systemRed), ("clock.fill", "Time", .systemTeal),
        ("brain.head.profile", "Brain", .systemPink), ("target", "Target", .systemRed),
        ("xmark.circle.fill", "Wrong", .systemRed), ("checkmark.circle.fill", "Right", .systemGreen),
    ]))

    static let arrows = StickerPack(id: "arrows", name: "Arrows & Shapes", stickers: symbols("arrows", [
        ("arrow.right", "Right Arrow", .label), ("arrow.left", "Left Arrow", .label),
        ("arrow.up", "Up Arrow", .label), ("arrow.down", "Down Arrow", .label),
        ("arrow.turn.down.right", "Turn Arrow", .label), ("arrow.triangle.2.circlepath", "Cycle", .systemBlue),
        ("circle", "Circle", .systemRed), ("square", "Square", .systemBlue),
        ("triangle", "Triangle", .systemGreen), ("seal", "Seal", .systemOrange),
        ("bubble.left.fill", "Speech Bubble", .systemBlue), ("cloud.fill", "Cloud", .systemTeal),
    ]))

    private static let emojiList: [String] = [
        "📌", "✅", "⭐️", "💡", "❗️", "❓", "🔥", "🎯", "📚", "🧠", "✏️", "📝", "⏰", "💯", "🚀", "❤️", "👀", "🎉",
    ]

    static let emoji = StickerPack(id: "emoji", name: "Emoji", stickers: emojiList.enumerated().map { item in
        BuiltInSticker(id: "emoji.\(item.offset)", name: item.element, look: .emoji(item.element))
    })

    static func sticker(forKey key: String) -> BuiltInSticker? {
        guard key.hasPrefix("pack:") else { return nil }
        let id = String(key.dropFirst(5))
        for pack in all {
            if let found = pack.stickers.first(where: { $0.id == id }) { return found }
        }
        return nil
    }
}

/// The owner's stickers, folders, favorites and recently used, kept in
/// `Stickers/` next to the library.
@MainActor
final class StickerStore: ObservableObject {
    static let shared = StickerStore()

    private struct Index: Codable {
        var stickers: [Sticker]
        var folders: [String]
        var favorites: [String]
        var recents: [String]
    }

    @Published private(set) var stickers: [Sticker] = []
    @Published private(set) var folders: [String] = []
    /// Sticker keys (`Sticker.key` or `BuiltInSticker.key`).
    @Published private(set) var favorites: [String] = []
    @Published private(set) var recents: [String] = []

    let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("stickers.json") }

    private init() {
        directory = LibraryStore.defaultRootURL.appendingPathComponent("Stickers", isDirectory: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { return }
        stickers = index.stickers
        folders = index.folders
        favorites = index.favorites
        recents = index.recents
    }

    private func save() {
        let index = Index(stickers: stickers, folders: folders, favorites: favorites, recents: recents)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    func fileURL(_ sticker: Sticker) -> URL? {
        guard isPlainFileName(sticker.file) else { return nil }
        return directory.appendingPathComponent(sticker.file)
    }

    func sticker(forKey key: String) -> Sticker? {
        stickers.first(where: { $0.key == key })
    }

    // MARK: Adding

    /// Saves a picture as a sticker (PNG keeps a see-through background).
    @discardableResult
    func add(image: UIImage, name: String, folder: String?) -> Sticker? {
        let maxSide: CGFloat = 800
        let pixel = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor: CGFloat = min(1, maxSide / max(pixel.width, pixel.height, 1))
        let size = CGSize(width: (pixel.width * factor).rounded(), height: (pixel.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = resized.pngData() else { return nil }
        return add(data: png, kind: .image, extension: "png", name: name, folder: folder)
    }

    /// Saves handwriting as a sticker; it is placed back as ink.
    @discardableResult
    func add(ink drawing: PKDrawing, name: String, folder: String?) -> Sticker? {
        guard !drawing.strokes.isEmpty else { return nil }
        return add(data: drawing.dataRepresentation(), kind: .ink, extension: "drawing", name: name, folder: folder)
    }

    private func add(data: Data, kind: Sticker.Kind, extension ext: String, name: String, folder: String?) -> Sticker? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = UUID().uuidString + "." + ext
        do {
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        } catch {
            return nil
        }
        let sticker = Sticker(name: name, kind: kind, file: file, folder: folder)
        stickers.insert(sticker, at: 0)
        if let folder, !folders.contains(folder) { folders.append(folder) }
        save()
        return sticker
    }

    // MARK: Organizing

    func isFavorite(_ key: String) -> Bool { favorites.contains(key) }

    func toggleFavorite(_ key: String) {
        if let index = favorites.firstIndex(of: key) {
            favorites.remove(at: index)
        } else {
            favorites.insert(key, at: 0)
        }
        save()
    }

    func markUsed(_ key: String) {
        recents.removeAll { $0 == key }
        recents.insert(key, at: 0)
        if recents.count > 24 { recents.removeLast(recents.count - 24) }
        save()
    }

    func addFolder(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !folders.contains(trimmed) else { return }
        folders.append(trimmed)
        save()
    }

    func deleteFolder(_ name: String) {
        folders.removeAll { $0 == name }
        for index in stickers.indices where stickers[index].folder == name {
            stickers[index].folder = nil
        }
        save()
    }

    func move(_ id: UUID, toFolder folder: String?) {
        guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[index].folder = folder
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func delete(_ id: UUID) {
        guard let sticker = stickers.first(where: { $0.id == id }) else { return }
        if let url = fileURL(sticker) { try? FileManager.default.removeItem(at: url) }
        stickers.removeAll { $0.id == id }
        favorites.removeAll { $0 == sticker.key }
        recents.removeAll { $0 == sticker.key }
        save()
    }

    // MARK: Reading

    func image(of sticker: Sticker) -> UIImage? {
        guard let url = fileURL(sticker) else { return nil }
        switch sticker.kind {
        case .image:
            return UIImage(contentsOfFile: url.path)
        case .ink:
            guard let drawing = drawing(of: sticker) else { return nil }
            var image = UIImage()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = drawing.image(from: drawing.bounds.insetBy(dx: -4, dy: -4), scale: 2)
            }
            return image
        }
    }

    func drawing(of sticker: Sticker) -> PKDrawing? {
        guard sticker.kind == .ink, let url = fileURL(sticker), let data = try? Data(contentsOf: url) else { return nil }
        return try? PKDrawing(data: data)
    }
}

/// Cuts the main subject out of a photo, on the device (Vision). Returns
/// the original when nothing is found or the device can't do it.
enum StickerCutout {
    static func cutOut(_ image: UIImage) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            subject(of: image) ?? image
        }.value
    }

    private nonisolated static func subject(of image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(image.imageOrientation))
        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
            let ciImage = CIImage(cvPixelBuffer: buffer)
            let context = CIContext()
            guard let output = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: output)
        } catch {
            return nil
        }
    }

    private nonisolated static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
