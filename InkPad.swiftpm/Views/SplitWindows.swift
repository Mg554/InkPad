import SwiftUI

/// Settings for the split workspace, kept in UserDefaults (and synced).
enum SplitPrefs {
    static let style = "splitWindowStyle"
    static let snaps = "splitSnaps"
    static let spring = "splitSpring"
    static let dots = "splitDots"
}

enum SplitWindowStyle: String, CaseIterable, Identifiable {
    /// Rounded windows with a shadow and a gap, like iPadOS.
    case windows
    /// Flat panes with a thin divider.
    case classic

    var id: Self { self }
    var title: String { self == .windows ? "Windows" : "Classic" }
}

/// Places the main note, the divider and the note beside. The three are
/// always there (a hidden pane waits just off screen), so nothing is
/// rebuilt when the split opens, swaps, goes full screen or floats: the
/// panes only move, and moves animate.
struct SplitLayout: Layout {
    var vertical: Bool
    var fraction: Double
    var swapped: Bool
    /// 1 shows only the first, 2 only the second, nil both.
    var only: Int?
    /// The second view floats here (Slide Over).
    var floatRect: CGRect?
    var gap: CGFloat
    var inset: CGFloat
    /// The second pane carried by its bar, to swap.
    var paneDrag: CGSize

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rects: [CGRect] = frames(in: bounds)
        for index in subviews.indices {
            let rect: CGRect = index < rects.count ? rects[index] : bounds
            subviews[index].place(at: rect.origin, anchor: .topLeading, proposal: ProposedViewSize(rect.size))
        }
    }

    private func frames(in bounds: CGRect) -> [CGRect] {
        guard bounds.minX.isFinite, bounds.minY.isFinite, bounds.width.isFinite, bounds.height.isFinite else {
            return [.zero, .zero, .zero]
        }
        let hiddenHandle = CGRect(x: bounds.minX - 200, y: bounds.minY, width: 1, height: 1)
        if let floatRect {
            return [bounds, hiddenHandle, floatRect.offsetBy(dx: bounds.minX, dy: bounds.minY)]
        }
        // Off the trailing (or bottom) edge, and off the leading (or top) one.
        let after: CGRect = vertical ? bounds.offsetBy(dx: 0, dy: bounds.height + 40) : bounds.offsetBy(dx: bounds.width + 40, dy: 0)
        let before: CGRect = vertical ? bounds.offsetBy(dx: 0, dy: -bounds.height - 40) : bounds.offsetBy(dx: -bounds.width - 40, dy: 0)
        if only == 1 {
            return [bounds, hiddenHandle, swapped ? before : after]
        }
        if only == 2 {
            return [swapped ? after : before, hiddenHandle, bounds]
        }
        // Too small to split yet (the first layout pass can be empty): an
        // inset would give CGRect.null and NaN frames.
        guard bounds.width > inset * 2 + gap + 2, bounds.height > inset * 2 + gap + 2 else {
            return [bounds, hiddenHandle, after]
        }
        let area: CGRect = bounds.insetBy(dx: inset, dy: inset)
        let total: CGFloat = vertical ? area.height : area.width
        let available: CGFloat = max(total - gap, 1)
        let share: Double = fraction.isFinite ? min(max(fraction, 0), 1) : 0.5
        let firstLength: CGFloat = available * CGFloat(share)
        let leadingLength: CGFloat = swapped ? available - firstLength : firstLength
        let trailingLength: CGFloat = available - leadingLength
        let leading: CGRect
        let handle: CGRect
        let trailing: CGRect
        if vertical {
            leading = CGRect(x: area.minX, y: area.minY, width: area.width, height: leadingLength)
            handle = CGRect(x: area.minX, y: area.minY + leadingLength, width: area.width, height: gap)
            trailing = CGRect(x: area.minX, y: area.minY + leadingLength + gap, width: area.width, height: trailingLength)
        } else {
            leading = CGRect(x: area.minX, y: area.minY, width: leadingLength, height: area.height)
            handle = CGRect(x: area.minX + leadingLength, y: area.minY, width: gap, height: area.height)
            trailing = CGRect(x: area.minX + leadingLength + gap, y: area.minY, width: trailingLength, height: area.height)
        }
        let first: CGRect = swapped ? trailing : leading
        let second: CGRect = (swapped ? leading : trailing).offsetBy(dx: paneDrag.width * 0.6, dy: paneDrag.height * 0.6)
        return [first, handle, second]
    }
}

/// The main note and the note beside, in windows that move like iPadOS
/// ones: a divider that snaps to thirds, an edge that closes, Slide Over,
/// and a ••• menu on each window.
struct SplitStack<First: View, Second: View>: View {
    @ObservedObject var split: SplitController
    let close: () -> Void
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second
    @AppStorage(SplitPrefs.style) private var styleRaw = SplitWindowStyle.windows.rawValue
    @AppStorage(SplitPrefs.snaps) private var snaps = true
    @AppStorage(SplitPrefs.dots) private var showsDots = true
    @State private var dragStart: Double?
    @State private var isDragging = false
    @State private var resizeStart: CGSize?

    private var isOpen: Bool { split.session != nil }
    private var floats: Bool { isOpen && split.floating && split.maximized == nil }

    private var only: Int? {
        guard isOpen else { return 1 }
        if split.maximized == .main { return 1 }
        if split.maximized == .other { return 2 }
        return nil
    }

    private var windowed: Bool {
        SplitWindowStyle(rawValue: styleRaw) != .classic && isOpen && !floats && only == nil
    }

    var body: some View {
        GeometryReader { proxy in
            SplitLayout(
                vertical: split.vertical,
                fraction: split.fraction,
                swapped: split.swapped,
                only: floats ? nil : only,
                floatRect: floats ? split.floatRect(in: proxy.size) : nil,
                gap: windowed ? 12 : (only == nil && !floats ? 14 : 0),
                inset: windowed ? 8 : 0,
                paneDrag: floats ? .zero : split.windowDrag
            ) {
                firstPane
                handle(total: windowed ? proxy.size.width - 16 : proxy.size.width, height: proxy.size.height)
                secondPane
            }
            .background(windowed ? Color(uiColor: .systemGray5) : Color.clear)
            .overlay { tuckTab }
            .clipped()
            .onAppear { split.container = proxy.size }
            .onChange(of: proxy.size) { _, size in split.container = size }
        }
    }

    // MARK: Panes

    private var firstPane: some View {
        first()
            .overlay(alignment: .top) {
                if showsDots, isOpen, only != 2 {
                    WindowDots(split: split, side: .main, close: close).padding(.top, 2)
                }
            }
            .modifier(WindowChrome(rounded: windowed, floating: false, active: windowed && split.active == .main))
            .allowsHitTesting(only != 2)
    }

    private var secondPane: some View {
        second()
            .overlay(alignment: .top) {
                if showsDots, isOpen, only != 1 || floats {
                    WindowDots(split: split, side: .other, close: close)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if floats { resizeCorner }
            }
            .modifier(WindowChrome(rounded: windowed || floats, floating: floats, active: windowed && split.active == .other))
            .scaleEffect(!floats && split.windowDrag != .zero ? 0.97 : 1)
            .allowsHitTesting(isOpen && (floats || only != 1))
    }

    // MARK: Divider

    private func handle(total: CGFloat, height: CGFloat) -> some View {
        let along: CGFloat = split.vertical ? height : total
        let long: CGFloat = isDragging ? 70 : 44
        let thick: CGFloat = isDragging ? 7 : 5
        return ZStack {
            if !windowed {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: split.vertical ? nil : 1, height: split.vertical ? 1 : nil)
            }
            Capsule()
                .fill(isDragging ? Color.inkAccent : Color(uiColor: windowed ? .systemGray2 : .tertiaryLabel))
                .frame(width: split.vertical ? long : thick, height: split.vertical ? thick : long)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(windowed ? Color.clear : Color(uiColor: .systemBackground))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start: Double = dragStart ?? split.fraction
                dragStart = start
                if !isDragging { isDragging = true }
                let moved: CGFloat = split.vertical ? value.translation.height : value.translation.width
                let delta = Double(moved / max(along, 1))
                let next: Double = split.swapped ? start - delta : start + delta
                split.fraction = min(max(next, 0.06), 0.94)
            }
            .onEnded { value in
                let start: Double = dragStart ?? split.fraction
                dragStart = nil
                isDragging = false
                let moved: CGFloat = split.vertical ? value.predictedEndTranslation.height : value.predictedEndTranslation.width
                let delta = Double(moved / max(along, 1))
                settle(split.swapped ? start - delta : start + delta)
            })
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        .accessibilityLabel("Resize")
    }

    /// Lets go of the divider: near an edge that side closes, otherwise it
    /// snaps to a third or a half.
    private func settle(_ landing: Double) {
        withAnimation(SplitController.motion) {
            if landing < 0.14 {
                split.fraction = 0.5
                split.maximized = .other
            } else if landing > 0.86 {
                split.fraction = 0.5
                close()
            } else if snaps {
                let stops: [Double] = [1.0 / 3.0, 0.5, 2.0 / 3.0]
                var best: Double = 0.5
                for stop in stops where abs(stop - landing) < abs(best - landing) { best = stop }
                split.fraction = best
            } else {
                split.fraction = min(max(landing, 0.25), 0.75)
            }
        }
    }

    // MARK: Slide Over

    @ViewBuilder
    private var tuckTab: some View {
        if floats, let edge = split.tucked {
            let alignment: Alignment = edge == .trailing ? .trailing : .leading
            Button {
                split.untuck()
            } label: {
                Image(systemName: edge == .trailing ? "chevron.compact.left" : "chevron.compact.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 96)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .transition(.opacity)
            .accessibilityLabel("Show the Other Note")
        }
    }

    private var resizeCorner: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption.weight(.bold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
            .background(.regularMaterial, in: Circle())
            .padding(6)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    let start: CGSize = resizeStart ?? split.floatRect(in: split.container).size
                    resizeStart = start
                    split.resizeFloat(to: CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height))
                }
                .onEnded { _ in
                    resizeStart = nil
                    split.endFloatDrag(translation: .zero, predicted: .zero)
                })
            .accessibilityLabel("Resize")
    }
}

/// A window's frame: rounded corners and a shadow, a ring on the active one.
private struct WindowChrome: ViewModifier {
    let rounded: Bool
    let floating: Bool
    let active: Bool

    func body(content: Content) -> some View {
        let radius: CGFloat = rounded ? (floating ? 20 : 14) : 0
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let shadow: Double = floating ? 0.32 : (rounded ? 0.12 : 0)
        content
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.inkAccent.opacity(active ? 0.65 : 0), lineWidth: 2).allowsHitTesting(false))
            .shadow(color: .black.opacity(shadow), radius: floating ? 26 : 8, y: floating ? 12 : 3)
    }
}

/// The ••• at the top of a window, like iPadOS: how the two notes share
/// the screen.
struct WindowDots: View {
    @ObservedObject var split: SplitController
    let side: SplitController.Side
    let close: () -> Void

    var body: some View {
        Menu {
            WindowArrangeButtons(split: split, side: side, close: close)
        } label: {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(split.active == side ? Color.inkAccent : Color.secondary)
            .frame(width: 54, height: 18)
            .background(.ultraThinMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .accessibilityLabel("Window Options")
    }
}

/// Split View, Top and Bottom, Slide Over, Full Screen, Swap and Close.
struct WindowArrangeButtons: View {
    @ObservedObject var split: SplitController
    let side: SplitController.Side
    let close: () -> Void

    var body: some View {
        Section {
            Button {
                split.arrange(.sideBySide)
            } label: {
                Label("Split View", systemImage: "rectangle.split.2x1")
            }
            Button {
                split.arrange(.topAndBottom)
            } label: {
                Label("Top and Bottom", systemImage: "rectangle.split.1x2")
            }
            Button {
                split.arrange(.slideOver)
            } label: {
                Label("Slide Over", systemImage: "rectangle.trailinghalf.inset.filled")
            }
        }
        Section {
            let isFull: Bool = split.maximized == side
            Button {
                withAnimation(SplitController.motion) {
                    split.tucked = nil
                    split.maximized = isFull ? nil : side
                }
            } label: {
                Label(isFull ? "Show Both" : "Full Screen", systemImage: isFull ? "rectangle.split.2x1" : "arrow.up.left.and.arrow.down.right")
            }
            if !split.floating {
                Button {
                    withAnimation(SplitController.motion) { split.swapped.toggle() }
                } label: {
                    Label("Swap Sides", systemImage: "arrow.left.arrow.right")
                }
            }
            Button(role: .destructive) {
                withAnimation(SplitController.motion) { close() }
            } label: {
                Label(side == .other ? "Close" : "Close the Other Note", systemImage: "xmark")
            }
        }
    }
}

/// Settings › Split View.
struct SplitSettingsView: View {
    @AppStorage(SplitPrefs.style) private var styleRaw = SplitWindowStyle.windows.rawValue
    @AppStorage(SplitPrefs.snaps) private var snaps = true
    @AppStorage(SplitPrefs.spring) private var spring = true
    @AppStorage(SplitPrefs.dots) private var dots = true
    @AppStorage("splitFloating") private var floating = false
    @AppStorage("splitVertical") private var vertical = false

    private var arrangement: Binding<Int> {
        Binding(
            get: { floating ? 2 : (vertical ? 1 : 0) },
            set: { value in
                floating = value == 2
                if value < 2 { vertical = value == 1 }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Look", selection: $styleRaw) {
                    ForEach(SplitWindowStyle.allCases) { Text(tr($0.title)).tag($0.rawValue) }
                }
                Picker("Open Notes Beside As", selection: arrangement) {
                    Text("Split View").tag(0)
                    Text("Top and Bottom").tag(1)
                    Text("Slide Over").tag(2)
                }
            } footer: {
                Text("Windows have rounded corners and a shadow, like iPadOS. Slide Over floats the other note above the main one.")
            }
            Section {
                Toggle("Snap to Thirds and Halves", isOn: $snaps)
                Toggle("Spring Animations", isOn: $spring)
                Toggle("••• Menu on Each Window", isOn: $dots)
            } footer: {
                Text("Drag the divider to an edge to close that side. Drag a window's bar across to swap sides; in Slide Over, drag it to move the window or throw it off the edge to tuck it away.")
            }
        }
        .navigationTitle("Split View")
        .navigationBarTitleDisplayMode(.inline)
    }
}
