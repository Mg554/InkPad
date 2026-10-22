import SwiftUI

extension SlideTheme {
    var background: LinearGradient {
        LinearGradient(colors: backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var backgroundColors: [Color] {
        switch self {
        case .aurora: return [Color(red: 0.07, green: 0.08, blue: 0.20), Color(red: 0.24, green: 0.10, blue: 0.40)]
        case .midnight: return [Color(red: 0.05, green: 0.06, blue: 0.08), Color(red: 0.13, green: 0.15, blue: 0.20)]
        case .paper: return [Color(red: 0.99, green: 0.98, blue: 0.95), Color(red: 0.93, green: 0.91, blue: 0.86)]
        case .sunset: return [Color(red: 0.98, green: 0.47, blue: 0.33), Color(red: 0.62, green: 0.16, blue: 0.44)]
        case .forest: return [Color(red: 0.05, green: 0.19, blue: 0.15), Color(red: 0.10, green: 0.35, blue: 0.27)]
        case .ocean: return [Color(red: 0.02, green: 0.22, blue: 0.42), Color(red: 0.04, green: 0.52, blue: 0.66)]
        }
    }

    var isDark: Bool { self != .paper }

    var titleColor: Color {
        isDark ? .white : Color(red: 0.10, green: 0.10, blue: 0.14)
    }

    var textColor: Color {
        isDark ? Color.white.opacity(0.88) : Color(red: 0.22, green: 0.22, blue: 0.27)
    }

    var accent: Color {
        switch self {
        case .aurora: return Color(red: 0.42, green: 0.86, blue: 1.00)
        case .midnight: return Color(red: 0.99, green: 0.78, blue: 0.30)
        case .paper: return Color(red: 0.30, green: 0.32, blue: 0.86)
        case .sunset: return Color(red: 1.00, green: 0.92, blue: 0.62)
        case .forest: return Color(red: 0.62, green: 0.95, blue: 0.58)
        case .ocean: return Color(red: 0.80, green: 0.97, blue: 1.00)
        }
    }

    /// The soft light in the corner.
    var glow: Color {
        switch self {
        case .aurora: return Color(red: 0.85, green: 0.35, blue: 0.95)
        case .midnight: return Color(red: 0.30, green: 0.40, blue: 0.80)
        case .paper: return Color(red: 0.98, green: 0.80, blue: 0.55)
        case .sunset: return Color(red: 1.00, green: 0.80, blue: 0.40)
        case .forest: return Color(red: 0.30, green: 0.80, blue: 0.60)
        case .ocean: return Color(red: 0.30, green: 0.90, blue: 0.85)
        }
    }

    /// Text and icons drawn on the accent color.
    var onAccent: Color {
        isDark ? Color(red: 0.06, green: 0.07, blue: 0.12) : .white
    }
}

/// A slide scaled to fit its space, keeping 16:9. Every slide is laid out at
/// `designSize`, so thumbnails, the presentation and PDF export match.
struct SlideView: View {
    static let designSize = CGSize(width: 1280, height: 720)

    let slide: Slide
    let theme: SlideTheme
    let image: UIImage?
    var number = 1
    var total = 1

    var body: some View {
        GeometryReader { proxy in
            SlideCanvas(slide: slide, theme: theme, image: image, number: number, total: total)
                .scaleEffect(proxy.size.width / Self.designSize.width, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipped()
    }
}

/// One slide drawn at `SlideView.designSize`.
struct SlideCanvas: View {
    let slide: Slide
    let theme: SlideTheme
    let image: UIImage?
    let number: Int
    let total: Int

    var body: some View {
        ZStack {
            theme.background
            RadialGradient(colors: [theme.glow.opacity(0.55), .clear], center: .topTrailing, startRadius: 10, endRadius: 760)
            RadialGradient(colors: [theme.accent.opacity(0.20), .clear], center: .bottomLeading, startRadius: 10, endRadius: 640)
            if slide.layout != .image {
                Image(systemName: slide.symbol)
                    .font(.system(size: 300, weight: .bold))
                    .foregroundStyle(theme.accent.opacity(0.07))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 450, y: 190)
            }
            content
                .padding(.horizontal, 90)
                .padding(.top, 70)
                .padding(.bottom, 90)
            footer
        }
        .frame(width: SlideView.designSize.width, height: SlideView.designSize.height)
        .clipped()
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }

    @ViewBuilder
    private var content: some View {
        switch slide.layout {
        case .title:
            titleLayout
        case .agenda:
            agendaLayout
        case .bullets:
            bulletsLayout
        case .quote:
            quoteLayout
        case .image:
            imageLayout
        case .summary:
            summaryLayout
        }
    }

    // MARK: Layouts

    private var titleLayout: some View {
        VStack(alignment: .leading, spacing: 26) {
            Spacer(minLength: 0)
            Image(systemName: slide.symbol)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(theme.accent)
            Text(slide.title)
                .font(.system(size: 76, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.titleColor)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
            if !slide.subtitle.isEmpty {
                Text(slide.subtitle)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            Capsule()
                .fill(theme.accent)
                .frame(width: 120, height: 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Numbered sections, in two columns when there are many. Plain stacks,
    /// not a lazy grid, so PDF export draws every item.
    private var agendaLayout: some View {
        let items = Array(slide.visibleBullets.enumerated())
        let columns = items.count > 4 ? 2 : 1
        let perColumn = max(Int((Double(items.count) / Double(columns)).rounded(.up)), 1)
        return VStack(alignment: .leading, spacing: 40) {
            header
            HStack(alignment: .top, spacing: 40) {
                ForEach(0..<columns, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(items.filter { $0.offset / perColumn == column }, id: \.offset) { item in
                            HStack(spacing: 20) {
                                Text("\(item.offset + 1)")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(theme.onAccent)
                                    .frame(width: 54, height: 54)
                                    .background(theme.accent, in: Circle())
                                Text(item.element)
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(theme.textColor)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bulletsLayout: some View {
        let items = slide.visibleBullets
        let dense = items.joined().count > 260
        return VStack(alignment: .leading, spacing: 36) {
            header
            VStack(alignment: .leading, spacing: dense ? 18 : 26) {
                ForEach(Array(items.enumerated()), id: \.offset) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 22) {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 14, height: 14)
                        Text(item.element)
                            .font(.system(size: dense ? 26 : 32, weight: .medium))
                            .foregroundStyle(theme.textColor)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var quoteLayout: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)
            Image(systemName: "quote.opening")
                .font(.system(size: 70, weight: .bold))
                .foregroundStyle(theme.accent)
            Text(slide.title)
                .font(.system(size: 46, weight: .semibold, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.titleColor)
                .lineLimit(6)
                .minimumScaleFactor(0.5)
            if !slide.subtitle.isEmpty {
                Text("— " + slide.subtitle)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.textColor)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var imageLayout: some View {
        HStack(alignment: .center, spacing: 50) {
            VStack(alignment: .leading, spacing: 26) {
                Text(slide.title)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.titleColor)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                ForEach(Array(slide.visibleBullets.prefix(4).enumerated()), id: \.offset) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 12, height: 12)
                        Text(item.element)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(theme.textColor)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    .frame(maxWidth: 600, maxHeight: 560)
            }
        }
    }

    private var summaryLayout: some View {
        VStack(alignment: .leading, spacing: 32) {
            header
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(slide.visibleBullets.prefix(5).enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(theme.accent)
                        Text(item.element)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(theme.textColor)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 24) {
            Image(systemName: slide.symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 76, height: 76)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(slide.title)
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundStyle(theme.titleColor)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
    }

    private var footer: some View {
        VStack {
            Spacer()
            HStack {
                Text("InkPad")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textColor.opacity(0.4))
                Spacer()
                Text("\(number) / \(total)")
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.textColor.opacity(0.5))
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 30)
        }
    }
}

/// Loads the pictures a deck's slides show.
enum SlideImages {
    static func load(for deck: SlideDeck, from directory: URL) -> [String: UIImage] {
        var images: [String: UIImage] = [:]
        for slide in deck.slides {
            guard let file = slide.imageFile, images[file] == nil, isPlainFileName(file),
                  let image = UIImage(contentsOfFile: directory.appendingPathComponent(file).path)
            else { continue }
            images[file] = image
        }
        return images
    }
}
