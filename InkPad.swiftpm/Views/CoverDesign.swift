import SwiftUI

/// A note's cover: a material (color, pattern, old leather, cloth, wood,
/// marble, spiral notebook, kraft paper), decorations and the title.
struct NoteCoverView: View {
    let cover: NoteCover
    let title: String

    private var base: Color { cover.color.color }
    private var second: Color { cover.secondColor.color }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                CoverMaterial(cover: cover)
                CoverDecorations(cover: cover)
                titleBlock(width: size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: titleAlignment)
                    .padding(.vertical, size.height * 0.1)
                    .padding(.leading, cover.style == .spiral ? size.width * 0.12 : 0)
            }
            .overlay(alignment: .leading) {
                if cover.style != .spiral {
                    // A notebook spine.
                    Rectangle()
                        .fill(LinearGradient(colors: [Color.black.opacity(0.25), Color.black.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(size.width * 0.05, 6))
                }
            }
        }
    }

    private var titleAlignment: Alignment {
        switch cover.titlePlace {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }

    @ViewBuilder
    private func titleBlock(width: CGFloat) -> some View {
        let fontSize: CGFloat = max(9, width * 0.11 * CGFloat(cover.titleScale))
        VStack(spacing: width * 0.03) {
            if let emblem = cover.emblem, !emblem.isEmpty {
                emblemView(emblem, size: width * 0.2)
            }
            if !title.isEmpty {
                Text(verbatim: title)
                    .font(CoverFonts.font(cover.font, size: fontSize))
                    // The app's theme font design must not replace the cover's font.
                    .fontDesign(CoverFonts.design(cover.font))
                    .foregroundStyle(titleStyle)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(cover.titlePlate ? 0 : 0.3), radius: 2, y: 1)
                    .padding(.horizontal, cover.titlePlate ? width * 0.06 : 0)
                    .padding(.vertical, cover.titlePlate ? width * 0.035 : 0)
                    .background {
                        if cover.titlePlate {
                            RoundedRectangle(cornerRadius: width * 0.03)
                                .fill(Color(red: 0.96, green: 0.93, blue: 0.84))
                                .overlay(RoundedRectangle(cornerRadius: width * 0.03).stroke(Color.black.opacity(0.35), lineWidth: 1))
                                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        }
                    }
            }
        }
        .padding(.horizontal, width * 0.13)
    }

    @ViewBuilder
    private func emblemView(_ emblem: String, size: CGFloat) -> some View {
        if UIImage(systemName: emblem) != nil {
            Image(systemName: emblem)
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(titleStyle)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        } else {
            Text(verbatim: emblem).font(.system(size: size))
        }
    }

    /// Gold and silver shine like foil stamping.
    private var titleStyle: AnyShapeStyle {
        if cover.titlePlate { return AnyShapeStyle(Color(white: 0.15)) }
        switch cover.titleInk {
        case .white: return AnyShapeStyle(Color.white)
        case .black: return AnyShapeStyle(Color(white: 0.1))
        case .cream: return AnyShapeStyle(Color(red: 0.97, green: 0.93, blue: 0.82))
        case .gold: return AnyShapeStyle(CoverFonts.gold)
        case .silver: return AnyShapeStyle(CoverFonts.silver)
        }
    }
}

enum CoverFonts {
    static let gold = LinearGradient(
        colors: [Color(red: 0.98, green: 0.86, blue: 0.5), Color(red: 0.8, green: 0.6, blue: 0.2), Color(red: 0.96, green: 0.82, blue: 0.45)],
        startPoint: .top, endPoint: .bottom
    )
    static let silver = LinearGradient(
        colors: [Color(white: 0.95), Color(white: 0.65), Color(white: 0.9)],
        startPoint: .top, endPoint: .bottom
    )

    static func font(_ font: NoteCover.TitleFont, size: CGFloat) -> Font {
        if let family = font.family, let uiFont = uiFont(family: family, size: size) {
            return Font(uiFont as CTFont)
        }
        switch font {
        case .serif: return .system(size: size, weight: .semibold, design: .serif)
        case .mono, .typewriter: return .system(size: size * 0.9, weight: .semibold, design: .monospaced)
        default: return .system(size: size, weight: .bold, design: .rounded)
        }
    }
}

extension CoverFonts {
    /// The design to keep: the cover's own for system fonts, none for named fonts.
    static func design(_ font: NoteCover.TitleFont) -> Font.Design? {
        switch font {
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        default: nil
        }
    }

    /// The family's boldest face when it has one.
    static func uiFont(family: String, size: CGFloat) -> UIFont? {
        let names = UIFont.fontNames(forFamilyName: family)
        guard !names.isEmpty else { return nil }
        let bold = UIFontDescriptor(fontAttributes: [.family: family]).withSymbolicTraits(.traitBold)
        if let bold {
            let font = UIFont(descriptor: bold, size: size)
            if font.familyName == family { return font }
        }
        return UIFont(name: names[0], size: size)
    }
}

/// A repeatable random sequence, so textures look the same every time.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let value = (state >> 33) & 0xFFFFFF
        return Double(value) / Double(0xFFFFFF)
    }
}

/// The cover's surface.
private struct CoverMaterial: View {
    let cover: NoteCover

    var body: some View {
        switch cover.style {
        case .solid:
            cover.color.color
        case .gradient:
            LinearGradient(colors: [cover.color.color, cover.secondColor.color], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .stripes:
            ZStack {
                cover.color.color
                Canvas { context, size in
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 6)
                        x += 18
                    }
                }
            }
        case .dots:
            ZStack {
                cover.color.color
                Canvas { context, size in
                    var y: CGFloat = 8
                    while y < size.height {
                        var x: CGFloat = 8
                        while x < size.width {
                            context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.3)))
                            x += 16
                        }
                        y += 16
                    }
                }
            }
        case .grid:
            ZStack {
                LinearGradient(colors: [cover.color.color, cover.secondColor.color], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    var path = Path()
                    var x: CGFloat = 0
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += 20
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += 20
                    }
                    context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 1)
                }
            }
        case .leather:
            leather
        case .cloth:
            ZStack {
                cover.color.color
                Canvas { context, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.07)))
                        y += 3
                    }
                    var x: CGFloat = 0
                    while x < size.width {
                        context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.07)))
                        x += 3
                    }
                }
            }
        case .wood:
            wood
        case .marble:
            marble
        case .spiral:
            spiral
        case .kraft:
            ZStack {
                Color(red: 0.78, green: 0.64, blue: 0.45)
                cover.color.color.opacity(0.12)
                speckles(count: 260, dark: 0.12, light: 0.1, seed: 7)
            }
        }
    }

    /// Old leather: a warm brown tinted by the color, grain, and worn edges.
    private var leather: some View {
        let brown = Color(red: 0.36, green: 0.2, blue: 0.11)
        return ZStack {
            brown
            cover.color.color.opacity(0.22)
            speckles(count: 900, dark: 0.18, light: 0.06, seed: 11)
            Canvas { context, size in
                // Creases.
                var random = SeededRandom(seed: 3)
                for _ in 0..<14 {
                    let start = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
                    var path = Path()
                    path.move(to: start)
                    path.addQuadCurve(
                        to: CGPoint(x: start.x + (random.next() - 0.5) * 60, y: start.y + (random.next() - 0.5) * 30),
                        control: CGPoint(x: start.x + (random.next() - 0.5) * 40, y: start.y + (random.next() - 0.5) * 40)
                    )
                    context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: 0.8)
                }
            }
            // Darker, worn edges.
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 40, endRadius: 220)
        }
    }

    private var wood: some View {
        ZStack {
            Color(red: 0.55, green: 0.36, blue: 0.2)
            cover.color.color.opacity(0.15)
            Canvas { context, size in
                var random = SeededRandom(seed: 5)
                var y: CGFloat = 0
                while y < size.height {
                    var path = Path()
                    let phase: Double = random.next() * 6
                    let wave: Double = 2 + random.next() * 4
                    path.move(to: CGPoint(x: 0, y: y))
                    var x: CGFloat = 0
                    while x <= size.width {
                        let offset: Double = Math.sine(Double(x) / 30 + phase) * wave
                        path.addLine(to: CGPoint(x: x, y: y + CGFloat(offset)))
                        x += 6
                    }
                    context.stroke(path, with: .color(.black.opacity(0.08 + random.next() * 0.1)), lineWidth: 1 + random.next() * 1.5)
                    y += 5 + CGFloat(random.next()) * 6
                }
            }
        }
    }

    private var marble: some View {
        ZStack {
            Color(red: 0.95, green: 0.94, blue: 0.92)
            Canvas { context, size in
                var random = SeededRandom(seed: 9)
                for index in 0..<9 {
                    var path = Path()
                    var point = CGPoint(x: random.next() * size.width, y: 0)
                    path.move(to: point)
                    while point.y < size.height {
                        let next = CGPoint(x: point.x + (random.next() - 0.5) * 40, y: point.y + 12 + random.next() * 18)
                        path.addQuadCurve(to: next, control: CGPoint(x: point.x + (random.next() - 0.5) * 30, y: (point.y + next.y) / 2))
                        point = next
                    }
                    let tint: Color = index % 2 == 0 ? cover.color.color : cover.secondColor.color
                    context.stroke(path, with: .color(tint.opacity(0.35)), lineWidth: 0.6 + random.next() * 1.8)
                }
            }
        }
    }

    private var spiral: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .leading) {
                cover.color.color
                Canvas { context, canvasSize in
                    let step: CGFloat = max(canvasSize.height / 16, 10)
                    var y: CGFloat = step / 2
                    while y < canvasSize.height {
                        let hole = CGRect(x: canvasSize.width * 0.07, y: y - 3, width: 6, height: 6)
                        context.fill(Path(ellipseIn: hole), with: .color(.black.opacity(0.45)))
                        var ring = Path()
                        ring.addEllipse(in: CGRect(x: -6, y: y - 4, width: canvasSize.width * 0.07 + 12, height: 8))
                        context.stroke(ring, with: .color(Color(white: 0.75)), lineWidth: 2)
                        y += step
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    private func speckles(count: Int, dark: Double, light: Double, seed: UInt64) -> some View {
        Canvas { context, size in
            var random = SeededRandom(seed: seed)
            for index in 0..<count {
                let x = random.next() * size.width
                let y = random.next() * size.height
                let radius = 0.4 + random.next() * 1.2
                let opacity = index % 3 == 0 ? light : dark
                let color: Color = index % 3 == 0 ? .white : .black
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)), with: .color(color.opacity(opacity * random.next())))
            }
        }
    }
}

/// Frame, metal corners, ribbon and band.
private struct CoverDecorations: View {
    let cover: NoteCover

    private var lineColor: AnyShapeStyle {
        switch cover.titleInk {
        case .gold: AnyShapeStyle(CoverFonts.gold)
        case .silver: AnyShapeStyle(CoverFonts.silver)
        case .black: AnyShapeStyle(Color.black.opacity(0.7))
        case .white, .cream: AnyShapeStyle(Color.white.opacity(0.8))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let inset: CGFloat = size.width * 0.08
            ZStack {
                switch cover.frame {
                case .none:
                    EmptyView()
                case .line:
                    Rectangle().stroke(lineColor, lineWidth: 1.2).padding(inset)
                case .double:
                    Rectangle().stroke(lineColor, lineWidth: 1.2).padding(inset)
                    Rectangle().stroke(lineColor, lineWidth: 0.8).padding(inset + 4)
                case .ornate:
                    Rectangle().stroke(lineColor, lineWidth: 1.5).padding(inset)
                    Rectangle().stroke(lineColor, lineWidth: 0.7).padding(inset + 5)
                    ornaments(size: size, inset: inset)
                }
                if cover.metalCorners { corners(size: size) }
                if cover.ribbon { ribbon(size: size) }
                if cover.band { band(size: size) }
            }
        }
    }

    private func ornaments(size: CGSize, inset: CGFloat) -> some View {
        let points: [CGPoint] = [
            CGPoint(x: inset, y: inset), CGPoint(x: size.width - inset, y: inset),
            CGPoint(x: inset, y: size.height - inset), CGPoint(x: size.width - inset, y: size.height - inset),
            CGPoint(x: size.width / 2, y: inset), CGPoint(x: size.width / 2, y: size.height - inset),
        ]
        let side: CGFloat = max(size.width * 0.05, 6)
        return ZStack {
            ForEach(Array(points.enumerated()), id: \.offset) { item in
                Image(systemName: "suit.diamond.fill")
                    .font(.system(size: side))
                    .foregroundStyle(lineColor)
                    .position(item.element)
            }
        }
    }

    private func corners(size: CGSize) -> some View {
        let side: CGFloat = size.width * 0.16
        let metal = LinearGradient(colors: [Color(red: 0.95, green: 0.82, blue: 0.5), Color(red: 0.6, green: 0.45, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        return ZStack {
            CornerShape().fill(metal).frame(width: side, height: side).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            CornerShape().fill(metal).rotationEffect(.degrees(90)).frame(width: side, height: side).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
    }

    private func ribbon(size: CGSize) -> some View {
        RibbonShape()
            .fill(LinearGradient(colors: [Color(red: 0.7, green: 0.1, blue: 0.15), Color(red: 0.5, green: 0.05, blue: 0.1)], startPoint: .leading, endPoint: .trailing))
            .frame(width: size.width * 0.08, height: size.height * 0.3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, size.width * 0.18)
            .shadow(color: .black.opacity(0.3), radius: 1, x: 1)
    }

    private func band(size: CGSize) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.75))
            .frame(width: size.width * 0.05)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, size.width * 0.1)
            .shadow(color: .black.opacity(0.35), radius: 2, x: -1)
    }
}

/// A triangle in the top right corner.
private struct CornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A bookmark ribbon with a V cut at its end.
private struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.6))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Tilts a cover in 3D as a finger drags over it.
struct CoverTilt: ViewModifier {
    @State private var tilt: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(Double(tilt.width) / 6), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(Double(-tilt.height) / 6), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let width: CGFloat = min(max(value.translation.width, -120), 120)
                    let height: CGFloat = min(max(value.translation.height, -120), 120)
                    tilt = CGSize(width: width, height: height)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { tilt = .zero }
                })
    }
}

/// The cover swings open on its spine before the note opens.
struct CoverOpening: ViewModifier {
    let isOpening: Bool

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(isOpening ? -75 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
            .opacity(isOpening ? 0.3 : 1)
            .animation(.easeIn(duration: 0.35), value: isOpening)
    }
}

/// Designs a note's cover, with a live preview you can tilt.
struct CoverEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let note: NoteSummary
    @State private var cover: NoteCover = .standard
    @State private var emblemText = ""

    private static let emblems: [String] = [
        "book.closed.fill", "graduationcap.fill", "brain.head.profile", "stethoscope", "heart.fill", "leaf.fill",
        "star.fill", "moon.stars.fill", "atom", "function", "globe.europe.africa.fill", "music.note",
        "📚", "🧠", "🩺", "⚗️", "🌿", "✨",
    ]

    private struct Preset: Identifiable {
        let id: String
        let name: String
        let cover: NoteCover
    }

    private var presets: [Preset] {
        var notebook = NoteCover(style: .spiral, color: .teal, secondColor: .blue, font: .handwritten)
        notebook.titlePlate = true
        var modern = NoteCover(style: .gradient, color: .purple, secondColor: .pink, font: .futura)
        modern.titlePlace = .bottom
        var classic = NoteCover(style: .cloth, color: .blue, secondColor: .gray, font: .didot)
        classic.titleInk = .gold
        classic.frame = .double
        var journal = NoteCover(style: .kraft, color: .orange, secondColor: .gray, font: .typewriter)
        journal.titleInk = .black
        journal.band = true
        var arabic = NoteCover(style: .marble, color: .teal, secondColor: .gray, font: .naskh)
        arabic.titleInk = .black
        arabic.frame = .ornate
        return [
            Preset(id: "leather", name: "Old Leather Book", cover: .leatherBook),
            Preset(id: "notebook", name: "Spiral Notebook", cover: notebook),
            Preset(id: "classic", name: "Classic Cloth", cover: classic),
            Preset(id: "journal", name: "Kraft Journal", cover: journal),
            Preset(id: "arabic", name: "Arabic Marble", cover: arabic),
            Preset(id: "modern", name: "Modern", cover: modern),
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NoteCoverView(cover: cover, title: note.title)
                        .aspectRatio(0.72, contentMode: .fit)
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                        .modifier(CoverTilt())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Drag the cover to tilt it.")
                        .frame(maxWidth: .infinity)
                }
                Section("Ready-Made") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(presets) { preset in
                                Button {
                                    withAnimation(.snappy) { cover = preset.cover }
                                } label: {
                                    VStack(spacing: 4) {
                                        NoteCoverView(cover: preset.cover, title: "")
                                            .frame(width: 58, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        Text(tr(preset.name)).font(.caption2).lineLimit(1).frame(width: 74)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Material") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(NoteCover.Style.allCases) { style in
                                Button {
                                    withAnimation(.snappy) { cover.style = style }
                                } label: {
                                    VStack(spacing: 4) {
                                        NoteCoverView(cover: sample(style), title: "")
                                            .frame(width: 46, height: 62)
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.inkAccent, lineWidth: cover.style == style ? 3 : 0))
                                        Text(tr(style.title)).font(.caption2).lineLimit(1).frame(width: 64)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    colorRow(selection: $cover.color)
                    if cover.style.usesSecondColor {
                        colorRow(selection: $cover.secondColor)
                    }
                }
                titleSection
                decorationSection
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
            .onAppear {
                cover = note.cover ?? .standard
                emblemText = cover.emblem ?? ""
            }
        }
    }

    private var titleSection: some View {
        Section("Title") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteCover.TitleFont.allCases) { font in
                        Button {
                            cover.font = font
                        } label: {
                            VStack(spacing: 2) {
                                Text(verbatim: font.isArabic ? "أبجد" : "Aa")
                                    .font(CoverFonts.font(font, size: 22))
                                    .fontDesign(CoverFonts.design(font))
                                    .frame(height: 30)
                                Text(tr(font.title)).font(.caption2).lineLimit(1)
                            }
                            .frame(width: 78, height: 58)
                            .background(RoundedRectangle(cornerRadius: 10).fill(cover.font == font ? Color.inkAccent.opacity(0.2) : Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                Image(systemName: "textformat.size.smaller")
                Slider(value: $cover.titleScale, in: 0.6...1.8)
                Image(systemName: "textformat.size.larger")
            }
            Picker("Place", selection: $cover.titlePlace) {
                ForEach(NoteCover.TitlePlace.allCases) { Text(tr($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Ink", selection: $cover.titleInk) {
                ForEach(NoteCover.TitleInk.allCases) { Text(tr($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("On a Label", isOn: $cover.titlePlate)
        }
    }

    private var decorationSection: some View {
        Section("Decorations") {
            Picker("Frame", selection: $cover.frame) {
                ForEach(NoteCover.Frame.allCases) { Text(tr($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        cover.emblem = nil
                        emblemText = ""
                    } label: {
                        Image(systemName: "nosign").frame(width: 38, height: 38)
                            .background(Circle().fill(cover.emblem == nil ? Color.inkAccent.opacity(0.2) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    ForEach(Self.emblems, id: \.self) { emblem in
                        Button {
                            cover.emblem = emblem
                            emblemText = emblem
                        } label: {
                            Group {
                                if UIImage(systemName: emblem) != nil {
                                    Image(systemName: emblem)
                                } else {
                                    Text(verbatim: emblem)
                                }
                            }
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(cover.emblem == emblem ? Color.inkAccent.opacity(0.2) : Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            TextField("Or type an emoji", text: $emblemText)
                .onChange(of: emblemText) {
                    let trimmed = emblemText.trimmingCharacters(in: .whitespaces)
                    cover.emblem = trimmed.isEmpty ? nil : String(trimmed.prefix(2))
                }
            Toggle("Metal Corners", isOn: $cover.metalCorners)
            Toggle("Bookmark Ribbon", isOn: $cover.ribbon)
            Toggle("Elastic Band", isOn: $cover.band)
        }
    }

    private func sample(_ style: NoteCover.Style) -> NoteCover {
        var copy = cover
        copy.style = style
        copy.frame = .none
        copy.metalCorners = false
        copy.ribbon = false
        copy.band = false
        copy.emblem = nil
        return copy
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
