import PencilKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Picks a sticker to put on the page: favorites, recently used, the
/// built-in packs, and the owner's own (pictures and saved handwriting) in
/// folders. Pictures from Photos or Files can have their background cut out.
struct StickerStudioView: View {
    @ObservedObject private var store = StickerStore.shared
    @Environment(\.dismiss) private var dismiss
    /// Places a picture sticker on the page.
    let insertImage: (UIImage) -> Void
    /// Places handwriting back as ink.
    let insertInk: (PKDrawing) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case favorites, recent, packs, mine
        var id: Self { self }
        var title: String {
            switch self {
            case .favorites: "Favorites"
            case .recent: "Recent"
            case .packs: "Packs"
            case .mine: "My Stickers"
            }
        }
    }

    @AppStorage("stickerTab") private var tab: Tab = .packs
    @AppStorage("stickerCutsOut") private var cutsOut = true
    @State private var folder: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var isPickingPhoto = false
    @State private var isPickingFile = false
    @State private var isWorking = false
    @State private var isNamingFolder = false
    @State private var newFolder = ""
    @State private var renaming: Sticker?
    @State private var newName = ""

    private let columns = [GridItem(.adaptive(minimum: 86, maximum: 120), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases) { Text(tr($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    content
                }
                .padding()
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .overlay {
                if isWorking {
                    ProgressView("Making the sticker…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { await makeSticker(from: data) }
            }
        }
        .sheet(isPresented: $isPickingFile) {
            DocumentPicker(contentTypes: [.image]) { urls in
                Task {
                    for url in urls {
                        if let data = try? Data(contentsOf: url) { await makeSticker(from: data) }
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Folder name", text: $newFolder)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                store.addFolder(newFolder)
                folder = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        .alert("Rename Sticker", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let renaming { store.rename(renaming.id, to: newName) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isPickingPhoto = true
                } label: {
                    Label("From Photos", systemImage: "photo")
                }
                Button {
                    isPickingFile = true
                } label: {
                    Label("From Files", systemImage: "folder")
                }
                Toggle(isOn: $cutsOut) {
                    Label("Remove Background", systemImage: "person.crop.rectangle")
                }
                Divider()
                Button {
                    newFolder = ""
                    isNamingFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } label: {
                Label("New Sticker", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .favorites:
            keyedGrid(store.favorites, empty: "Long-press a sticker and choose Favorite.")
        case .recent:
            keyedGrid(store.recents, empty: "Stickers you use show up here.")
        case .packs:
            ForEach(StickerPack.all) { pack in
                Text(tr(pack.name)).font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(pack.stickers) { sticker in
                        builtInCell(sticker)
                    }
                }
            }
        case .mine:
            folderBar
            let mine = store.stickers.filter { folder == nil || $0.folder == folder }
            if mine.isEmpty {
                emptyText("Add a picture with +, or circle handwriting with the lasso and choose Save as Sticker.")
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(mine) { sticker in
                        ownCell(sticker)
                    }
                }
            }
        }
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderChip(nil, title: tr("All"))
                ForEach(store.folders, id: \.self) { name in
                    folderChip(name, title: name)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.deleteFolder(name)
                                if folder == name { folder = nil }
                            } label: {
                                Label("Delete Folder", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func folderChip(_ name: String?, title: String) -> some View {
        Button {
            folder = name
        } label: {
            Label { Text(verbatim: title) } icon: { Image(systemName: name == nil ? "square.grid.2x2" : "folder") }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(folder == name ? Color.inkAccent.opacity(0.25) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func keyedGrid(_ keys: [String], empty: LocalizedStringKey) -> some View {
        if keys.isEmpty {
            emptyText(empty)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(keys, id: \.self) { key in
                    if let builtIn = StickerPack.sticker(forKey: key) {
                        builtInCell(builtIn)
                    } else if let own = store.sticker(forKey: key) {
                        ownCell(own)
                    }
                }
            }
        }
    }

    private func emptyText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    // MARK: Cells

    private func builtInCell(_ sticker: BuiltInSticker) -> some View {
        Button {
            store.markUsed(sticker.key)
            insertImage(sticker.image(side: 200))
            dismiss()
        } label: {
            cell(StickerThumbnails.image(for: sticker), isFavorite: store.isFavorite(sticker.key))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tr(sticker.name)))
        .contextMenu {
            favoriteButton(sticker.key)
        }
    }

    private func ownCell(_ sticker: Sticker) -> some View {
        Button {
            store.markUsed(sticker.key)
            switch sticker.kind {
            case .image:
                if let image = store.image(of: sticker) { insertImage(image) }
            case .ink:
                if let drawing = store.drawing(of: sticker) { insertInk(drawing) }
            }
            dismiss()
        } label: {
            cell(StickerThumbnails.image(for: sticker, store: store), isFavorite: store.isFavorite(sticker.key), isInk: sticker.kind == .ink)
        }
        .buttonStyle(.plain)
        .contextMenu {
            favoriteButton(sticker.key)
            Menu {
                Button("No Folder") { store.move(sticker.id, toFolder: nil) }
                ForEach(store.folders, id: \.self) { name in
                    Button {
                        store.move(sticker.id, toFolder: name)
                    } label: {
                        Text(verbatim: name)
                    }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
            Button {
                newName = sticker.name
                renaming = sticker
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                store.delete(sticker.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func favoriteButton(_ key: String) -> some View {
        Button {
            store.toggleFavorite(key)
        } label: {
            if store.isFavorite(key) {
                Label("Remove from Favorites", systemImage: "star.slash")
            } else {
                Label("Favorite", systemImage: "star")
            }
        }
    }

    private func cell(_ image: UIImage?, isFavorite: Bool, isInk: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.05))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            }
            HStack(spacing: 2) {
                if isInk { Image(systemName: "scribble") }
                if isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            }
            .font(.caption2)
            .padding(6)
        }
        .frame(height: 96)
        .contentShape(Rectangle())
    }

    // MARK: Making stickers

    private func makeSticker(from data: Data) async {
        guard let image = UIImage(data: data) else { return }
        isWorking = true
        let final: UIImage = cutsOut ? await StickerCutout.cutOut(image) : image
        let target: String? = folder
        store.add(image: final, name: tr("Sticker"), folder: target)
        isWorking = false
        tab = .mine
    }
}

/// Small pictures of stickers for the grid, made once.
@MainActor
enum StickerThumbnails {
    private static var cache: [String: UIImage] = [:]

    static func image(for sticker: BuiltInSticker) -> UIImage {
        if let cached = cache[sticker.key] { return cached }
        let image = sticker.image(side: 90)
        cache[sticker.key] = image
        return image
    }

    static func image(for sticker: Sticker, store: StickerStore) -> UIImage? {
        if let cached = cache[sticker.key] { return cached }
        guard let full = store.image(of: sticker) else { return nil }
        let side: CGFloat = 180
        let factor: CGFloat = min(1, side / max(full.size.width, full.size.height, 1))
        let size = CGSize(width: full.size.width * factor, height: full.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            full.draw(in: CGRect(origin: .zero, size: size))
        }
        cache[sticker.key] = small
        return small
    }
}
