import EventKit
import SwiftUI

/// How Reminders looks: tiles, rows, the done circle, glow, a little
/// celebration, the background, and an icon for each list.
struct ReminderLook: StoredLook {
    static let storageKey = "reminderLook"

    enum Tiles: String, Codable, CaseIterable, Identifiable {
        case glass, gradient, minimal
        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    enum Density: String, Codable, CaseIterable, Identifiable {
        case comfortable, compact
        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    enum Check: String, Codable, CaseIterable, Identifiable {
        case circle, square, ring
        var id: Self { self }
        var title: String { rawValue.capitalized }

        func symbol(done: Bool) -> String {
            switch self {
            case .circle: done ? "checkmark.circle.fill" : "circle"
            case .square: done ? "checkmark.square.fill" : "square"
            case .ring: done ? "largecircle.fill.circle" : "circle.dashed"
            }
        }
    }

    var tiles = Tiles.glass
    var density = Density.comfortable
    var check = Check.circle
    var celebrate = true
    var glow: GlowStyle = {
        var glow = GlowStyle()
        glow.isOn = false
        glow.intensity = 0.4
        glow.radius = 10
        return glow
    }()
    var backdrop = ScreenBackdrop.theme
    /// An SF Symbol name or an emoji for each list (by calendar id).
    var icons: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tiles = container.value(.tiles, or: tiles)
        density = container.value(.density, or: density)
        check = container.value(.check, or: check)
        celebrate = container.value(.celebrate, or: celebrate)
        glow = container.value(.glow, or: glow)
        backdrop = container.value(.backdrop, or: backdrop)
        icons = container.value(.icons, or: icons)
    }

    func icon(for list: EKCalendar) -> String {
        icons[list.calendarIdentifier] ?? "list.bullet"
    }

    var rowPadding: CGFloat { density == .compact ? 2 : 8 }
}

/// The saved look, shared by every Reminders screen.
@MainActor
final class ReminderLookStore: ObservableObject {
    static let shared = ReminderLookStore()
    @Published var look = ReminderLook.load() {
        didSet { look.save() }
    }
}

/// A list's icon: a symbol on a colored circle, or an emoji.
struct ListIcon: View {
    let icon: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            if UIImage(systemName: icon) == nil {
                Text(tr(icon)).font(.system(size: size * 0.55))
            } else {
                Image(systemName: icon)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The background of a tile or card in the chosen style.
struct ReminderTileBackground: ViewModifier {
    let tiles: ReminderLook.Tiles
    let tint: Color
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch tiles {
        case .glass:
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        case .gradient:
            content
                .background(LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
        case .minimal:
            content
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        }
    }
}

/// Customize Reminders.
struct ReminderStyleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ReminderLookStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Tiles") {
                    Picker("Tiles", selection: $store.look.tiles) {
                        ForEach(ReminderLook.Tiles.allCases) { Text(tr($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        ForEach([ReminderCenter.SmartList.today, .scheduled, .priority], id: \.self) { smart in
                            HStack {
                                Image(systemName: smart.systemImage)
                                    .foregroundStyle(store.look.tiles == .gradient ? .white : smart.tint)
                                    .styledGlow(store.look.glow, color: smart.tint)
                                Text(tr(smart.title))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(store.look.tiles == .gradient ? Color.white : Color(uiColor: .label))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .modifier(ReminderTileBackground(tiles: store.look.tiles, tint: smart.tint, cornerRadius: 12))
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(ScreenBackdropView(backdrop: store.look.backdrop, animated: false))
                }

                Section("Rows") {
                    Picker(selection: $store.look.density) {
                        ForEach(ReminderLook.Density.allCases) { Text(tr($0.title)).tag($0) }
                    } label: {
                        Label("Spacing", systemImage: "line.3.horizontal")
                    }
                    Picker(selection: $store.look.check) {
                        ForEach(ReminderLook.Check.allCases) { check in
                            Label(tr(check.title), systemImage: check.symbol(done: true)).tag(check)
                        }
                    } label: {
                        Label("Done Button", systemImage: store.look.check.symbol(done: false))
                    }
                    Toggle(isOn: $store.look.celebrate) {
                        Label("Celebrate When Done", systemImage: "party.popper")
                    }
                }

                GlowSettingsSection(glow: $store.look.glow, footer: "Tiles, list icons and done buttons glow softly.")

                Section("Background") {
                    BackdropPicker(backdrop: $store.look.backdrop)
                }

                Section {
                    Button("Reset to Default", role: .destructive) {
                        let icons = store.look.icons
                        store.look = ReminderLook()
                        store.look.icons = icons
                    }
                } footer: {
                    Text("Each list's icon and color: touch and hold a list, then Edit List.")
                }
            }
            .navigationTitle("Customize Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Rename a list, and choose its color and icon.
struct ReminderListEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ReminderLookStore.shared
    @ObservedObject private var center = ReminderCenter.shared
    let list: EKCalendar
    @State private var name = ""
    @State private var color = Color.blue
    @State private var icon = "list.bullet"
    @State private var emoji = ""

    private static let symbols = [
        "list.bullet", "bookmark.fill", "star.fill", "heart.fill", "flag.fill", "bell.fill",
        "cart.fill", "bag.fill", "gift.fill", "graduationcap.fill", "book.fill", "pencil",
        "stethoscope", "cross.case.fill", "pills.fill", "heart.text.square.fill", "brain.head.profile", "figure.run",
        "house.fill", "briefcase.fill", "airplane", "car.fill", "fork.knife", "cup.and.saucer.fill",
        "leaf.fill", "pawprint.fill", "music.note", "gamecontroller.fill", "creditcard.fill", "lightbulb.fill",
    ]
    private static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown, .gray]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ListIcon(icon: icon, color: color, size: 72)
                            .styledGlow(store.look.glow, color: color)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    TextField("List Name", text: $name)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(Self.colors, id: \.self) { option in
                            colorDot(option)
                        }
                        ColorPicker("", selection: $color, supportsOpacity: false)
                            .labelsHidden()
                    }
                    .padding(.vertical, 6)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(icon == symbol ? color.opacity(0.25) : Color.secondary.opacity(0.1), in: Circle())
                                .onTapGesture { icon = symbol }
                        }
                    }
                    .padding(.vertical, 6)
                    HStack {
                        Text("Or an emoji")
                        TextField("😀", text: $emoji)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: emoji) {
                                if let first = emoji.last {
                                    emoji = String(first)
                                    icon = emoji
                                }
                            }
                    }
                }
            }
            .navigationTitle("Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.look.icons[list.calendarIdentifier] = icon
                        center.updateList(list, name: name, color: color)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = list.title
                color = Color(cgColor: list.cgColor)
                icon = store.look.icon(for: list)
            }
        }
    }
}

extension ReminderListEditor {
    private func colorDot(_ option: Color) -> some View {
        let isChosen: Bool = UIColor(option) == UIColor(color)
        let ring = Circle().stroke(Color.primary.opacity(isChosen ? 0.7 : 0), lineWidth: 3).padding(-4)
        return Circle()
            .fill(option)
            .frame(width: 32, height: 32)
            .overlay(ring)
            .onTapGesture { color = option }
    }
}

/// A small burst of color when a reminder is done.
struct CelebrationBurst: View {
    let color: Color
    @State private var flying = false

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                let angle: Double = Double(index) / 12 * 2 * Double.pi
                let dx: CGFloat = CGFloat(Math.cosine(angle)) * 30
                let dy: CGFloat = CGFloat(Math.sine(angle)) * 30
                Circle()
                    .fill(index.isMultiple(of: 3) ? Color.yellow : index.isMultiple(of: 2) ? color : .pink)
                    .frame(width: 6, height: 6)
                    .offset(x: flying ? dx : 0, y: flying ? dy : 0)
                    .opacity(flying ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { flying = true }
        }
    }
}
