import SwiftUI

/// A note's look in small views: its cover, first page, or a text icon.
struct NotePreview: View {
    @EnvironmentObject private var store: LibraryStore
    let note: NoteSummary
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let cover = note.cover {
                NoteCoverView(cover: cover, title: "")
            } else if note.isText {
                Image(systemName: "doc.text").foregroundStyle(.purple)
            } else if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill()
            }
        }
        .task(id: note.modifiedAt) {
            if !note.isText, note.cover == nil {
                thumbnail = await store.cardThumbnail(for: note.id, modifiedAt: note.modifiedAt)
            }
        }
    }
}

/// Small icon with the title under it.
struct NoteIcon: View {
    let note: NoteSummary

    var body: some View {
        VStack(spacing: 6) {
            NotePreview(note: note)
                .frame(width: 64, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
            Text(verbatim: note.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
    }
}

/// One line: icon, title, date.
struct NoteCompactRow: View {
    let note: NoteSummary

    var body: some View {
        HStack(spacing: 10) {
            NotePreview(note: note)
                .frame(width: 20, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(verbatim: note.title).lineLimit(1)
            if note.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
            if note.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
            Spacer()
            Text(note.modifiedAt, format: .dateTime.day().month(.abbreviated))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }
}

/// A round bubble; bigger notes make bigger bubbles.
struct NoteBubble: View {
    let note: NoteSummary

    static func diameter(_ note: NoteSummary) -> CGFloat {
        let pages: Int = note.pageCount ?? 1
        let grow: Double = Math.root(Double(max(pages, 1)))
        return CGFloat(min(70 + grow * 18, 170))
    }

    var body: some View {
        let size = Self.diameter(note)
        VStack(spacing: 4) {
            NotePreview(note: note)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            Text(verbatim: note.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: size + 20)
        }
    }
}

/// Wraps items into rows, centered, like soap bubbles.
struct BubbleFlow: Layout {
    var spacing: CGFloat = 18

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // Every other bubble sits a little lower, for a looser look.
                let offset: CGFloat = index % 2 == 0 ? 0 : 10
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2 + offset), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed: CGFloat = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height + 10)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Places items on rings around the middle; `rotation` turns the rings
/// (each ring a little differently), and animates along the circle.
struct RadialLayout: Layout {
    var rotation: Double = 0

    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let rings = Self.rings(count: subviews.count)
        let radius = Self.radius(ring: rings.count, width: width)
        return CGSize(width: width, height: max(radius * 2 + 140, 420))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rings = Self.rings(count: subviews.count)
        var index = 0
        for (ring, count) in rings.enumerated() {
            let radius = Self.radius(ring: ring + 1, width: bounds.width)
            for slot in 0..<count where index < subviews.count {
                let turn: Double = ring % 2 == 0 ? rotation : -rotation * 0.7
                let angle: Double = Double(slot) / Double(count) * 2 * Double.pi - Double.pi / 2 + Double(ring) * 0.35 + turn
                let x: CGFloat = center.x + radius * CGFloat(Math.cosine(angle))
                let y: CGFloat = center.y + radius * CGFloat(Math.sine(angle))
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .center, proposal: .unspecified)
                index += 1
            }
        }
    }

    /// How many items go on each ring: 8, 14, 20...
    static func rings(count: Int) -> [Int] {
        var result: [Int] = []
        var left = count
        var capacity = 8
        while left > 0 {
            result.append(min(left, capacity))
            left -= capacity
            capacity += 6
        }
        return result
    }

    static func radius(ring: Int, width: CGFloat) -> CGFloat {
        let step: CGFloat = min(max(width / 9, 95), 140)
        return step * CGFloat(ring) + 30
    }
}

/// The middle of the circle view.
struct CircleHub: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "folder.fill").font(.title).foregroundStyle(Color.inkAccent)
            Text(verbatim: title).font(.headline).lineLimit(1)
            Text("\(count) notes").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 130, height: 130)
        .background(Circle().fill(.regularMaterial))
        .overlay(Circle().stroke(Color.inkAccent.opacity(0.4), lineWidth: 2))
    }
}

/// One line of the tree, drawn like `tree` in a terminal.
struct TreeLine<Label: View>: View {
    /// For each level above: whether a line continues down there.
    let ancestors: [Bool]
    let isLast: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: prefix)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
            label()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var prefix: String {
        let lines: [String] = ancestors.map { $0 ? "│   " : "    " }
        return lines.joined() + (isLast ? "└── " : "├── ")
    }
}

/// A wooden shelf under a row of books.
struct ShelfPlank: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.42, blue: 0.24), Color(red: 0.45, green: 0.28, blue: 0.15)], startPoint: .top, endPoint: .bottom))
                .frame(height: 14)
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(height: 6)
                .blur(radius: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// A note standing on the shelf like a book.
struct ShelfBook: View {
    let note: NoteSummary

    var body: some View {
        VStack(spacing: 0) {
            NotePreview(note: note)
                .frame(width: 92, height: 128)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 6, topTrailingRadius: 6))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.2)).frame(width: 6)
                }
                .shadow(color: .black.opacity(0.25), radius: 3, x: 2, y: 2)
            Text(verbatim: note.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .frame(width: 96)
                .padding(.top, 4)
        }
    }
}

/// A dot and the note on the timeline.
struct TimelineEntry: View {
    let note: NoteSummary
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().fill(Color.inkAccent).frame(width: 12, height: 12).padding(.top, 14)
                if !isLast {
                    Rectangle().fill(Color.inkAccent.opacity(0.3)).frame(width: 2)
                }
            }
            .frame(width: 14)
            HStack(spacing: 12) {
                NotePreview(note: note)
                    .frame(width: 34, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: note.title).font(.headline).lineLimit(1)
                    Text(note.modifiedAt, format: .dateTime.weekday(.wide).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 8)
        }
    }
}
