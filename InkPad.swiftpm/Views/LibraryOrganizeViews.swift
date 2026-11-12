import SwiftUI

/// A note's cover: a color, gradient or pattern with the title.
struct NoteCoverView: View {
    let cover: NoteCover
    let title: String

    private var base: Color { cover.color.color }
    private var second: Color { cover.secondColor.color }

    var body: some View {
        ZStack {
            background
            Text(verbatim: title)
                .font(titleFont)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .padding(16)
        }
        .overlay(alignment: .leading) {
            // A notebook spine.
            Rectangle()
                .fill(Color.black.opacity(0.14))
                .frame(width: 10)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch cover.style {
        case .solid:
            base
        case .gradient:
            LinearGradient(colors: [base, second], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .stripes:
            ZStack {
                base
                Canvas { context, size in
                    let step: CGFloat = 18
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 6)
                        x += step
                    }
                }
            }
        case .dots:
            ZStack {
                base
                Canvas { context, size in
                    let step: CGFloat = 16
                    var y: CGFloat = step / 2
                    while y < size.height {
                        var x: CGFloat = step / 2
                        while x < size.width {
                            context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.3)))
                            x += step
                        }
                        y += step
                    }
                }
            }
        case .grid:
            ZStack {
                LinearGradient(colors: [base, second], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    let step: CGFloat = 20
                    var path = Path()
                    var x: CGFloat = 0
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += step
                    }
                    context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 1)
                }
            }
        }
    }

    private var titleFont: Font {
        switch cover.font {
        case .rounded: return .system(.title3, design: .rounded).weight(.bold)
        case .serif: return .system(.title3, design: .serif).weight(.semibold)
        case .mono: return .system(.headline, design: .monospaced).weight(.semibold)
        case .handwritten: return .custom("Noteworthy-Bold", size: 22)
        }
    }
}

/// Picks or removes a note's cover.
struct CoverEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let note: NoteSummary
    @State private var cover: NoteCover = .standard

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NoteCoverView(cover: cover, title: note.title)
                        .aspectRatio(0.72, contentMode: .fit)
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section("Style") {
                    Picker("Style", selection: $cover.style) {
                        ForEach(NoteCover.Style.allCases) { Text(tr($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Colors") {
                    colorRow(selection: $cover.color)
                    if cover.style == .gradient || cover.style == .grid {
                        colorRow(selection: $cover.secondColor)
                    }
                }
                Section("Font") {
                    Picker("Font", selection: $cover.font) {
                        ForEach(NoteCover.TitleFont.allCases) { Text(tr($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if note.cover != nil {
                    Section {
                        Button("Show the First Page Instead", role: .destructive) {
                            store.setCover(nil, for: note.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.setCover(cover, for: note.id)
                        dismiss()
                    }
                }
            }
            .onAppear { cover = note.cover ?? .standard }
        }
    }

    private func colorRow(selection: Binding<FolderColor>) -> some View {
        HStack(spacing: 10) {
            ForEach(FolderColor.allCases) { color in
                Button {
                    selection.wrappedValue = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.primary, lineWidth: selection.wrappedValue == color ? 3 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tr(color.title)))
            }
        }
        .padding(.vertical, 4)
    }
}

/// A detailed row for the list view.
struct NoteRow: View {
    @EnvironmentObject private var store: LibraryStore
    let note: NoteSummary
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            preview
                .frame(width: 44, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if note.isPinned {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
                    }
                    Text(verbatim: note.title)
                        .font(.headline)
                        .lineLimit(1)
                    if note.favorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 8) {
                    if let folderID = note.folderID, let folder = store.folder(folderID) {
                        Label { Text(verbatim: folder.name) } icon: { Image(systemName: "folder") }
                    }
                    let tags = store.tags(of: note)
                    if !tags.isEmpty {
                        Text(verbatim: tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                            .foregroundStyle(.teal)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            if note.hasAudio == true {
                Image(systemName: "waveform").foregroundStyle(.secondary)
            }
            Text(pagesText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(note.modifiedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .task(id: note.modifiedAt) {
            if !note.isText, note.cover == nil {
                thumbnail = await store.cardThumbnail(for: note.id, modifiedAt: note.modifiedAt)
            }
        }
    }

    private var pagesText: String {
        if note.isText { return tr("Text") }
        let count: Int = note.pageCount ?? 1
        return count == 1 ? tr("1 page") : trMessage("\(count) pages")
    }

    @ViewBuilder
    private var preview: some View {
        if let cover = note.cover {
            NoteCoverView(cover: cover, title: "")
        } else if note.isText {
            ZStack {
                Color.white
                Image(systemName: "doc.text").foregroundStyle(.purple)
            }
        } else if let thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFill()
        } else {
            Color.white
        }
    }
}

/// The column titles of the list view; tapping one sorts by it.
struct NoteListHeader: View {
    @Binding var sort: NoteSort

    var body: some View {
        HStack(spacing: 14) {
            column("Name", sortsBy: .name)
                .padding(.leading, 58)
            Spacer()
            column("Pages", sortsBy: .pages)
                .frame(width: 64, alignment: .trailing)
            column("Edited", sortsBy: .edited)
                .frame(width: 150, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func column(_ title: LocalizedStringKey, sortsBy option: NoteSort) -> some View {
        Button {
            sort = option
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if sort == option {
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .foregroundStyle(sort == option ? Color.inkAccent : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

/// Makes or edits a smart collection.
struct CollectionEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State var collection: SmartCollection
    @State private var limitDays = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Collection name", text: $collection.name)
                }
                Section {
                    Picker("Kind", selection: $collection.kind) {
                        ForEach(SmartCollection.Kind.allCases) { Text(tr($0.title)).tag($0) }
                    }
                    Picker("Tag", selection: Binding(
                        get: { collection.tag ?? "" },
                        set: { collection.tag = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Any Tag").tag("")
                        ForEach(store.allTags, id: \.self) { tag in
                            Text(verbatim: "#" + tag).tag(tag)
                        }
                    }
                    Toggle("Edited Recently", isOn: $limitDays)
                    if limitDays {
                        Stepper(value: Binding(
                            get: { collection.editedWithinDays ?? 7 },
                            set: { collection.editedWithinDays = $0 }
                        ), in: 1...365) {
                            Text("In the last \(collection.editedWithinDays ?? 7) days")
                        }
                    }
                    Toggle("Has Audio", isOn: $collection.needsAudio)
                    Toggle("Has Unfinished Tasks", isOn: $collection.needsOpenTasks)
                    Toggle("Favorites Only", isOn: $collection.onlyFavorites)
                } header: {
                    Text("Rules")
                } footer: {
                    Text("A note joins when it matches every rule you set. The collection updates itself.")
                }
                Section {
                    Text("\(matchingCount) notes match now")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Smart Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !limitDays { collection.editedWithinDays = nil }
                        if collection.name.trimmingCharacters(in: .whitespaces).isEmpty { collection.name = tr("Collection") }
                        store.saveCollection(collection)
                        dismiss()
                    }
                }
            }
            .onAppear { limitDays = collection.editedWithinDays != nil }
        }
    }

    private var matchingCount: Int {
        var rules = collection
        if !limitDays { rules.editedWithinDays = nil }
        return store.notes.filter { store.matches($0, collection: rules) }.count
    }
}
