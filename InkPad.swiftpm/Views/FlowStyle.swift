import os
import AVFoundation
import AudioToolbox
import SwiftUI

/// How Flowmodoro and the Planner look and sound. Changed with the
/// paintbrush (Customize) button.
struct FlowLook: StoredLook {
    static let storageKey = "flowLook"

    enum Face: String, Codable, CaseIterable, Identifiable {
        case ring, digits, analog, liquid, plant
        var id: Self { self }
        var title: String {
            switch self {
            case .ring: "Ring"
            case .digits: "Big Digits"
            case .analog: "Analog"
            case .liquid: "Liquid"
            case .plant: "Growing Plant"
            }
        }
    }

    enum Cards: String, Codable, CaseIterable, Identifiable {
        case glass, sticky, minimal, neon
        var id: Self { self }
        var title: String {
            switch self {
            case .glass: "Glass"
            case .sticky: "Sticky Notes"
            case .minimal: "Minimal"
            case .neon: "Neon"
            }
        }
    }

    enum Ambient: String, Codable, CaseIterable, Identifiable {
        case off, rain, ocean, white, pink, brown
        var id: Self { self }
        var title: String {
            switch self {
            case .off: "Off"
            case .rain: "Rain"
            case .ocean: "Ocean"
            case .white: "White Noise"
            case .pink: "Pink Noise"
            case .brown: "Brown Noise"
            }
        }
        var systemImage: String {
            switch self {
            case .off: "speaker.slash"
            case .rain: "cloud.rain"
            case .ocean: "water.waves"
            case .white, .pink, .brown: "waveform"
            }
        }
    }

    enum Chime: String, Codable, CaseIterable, Identifiable {
        case alarm, triTone, tink, off
        var id: Self { self }
        var title: String {
            switch self {
            case .alarm: "Alarm"
            case .triTone: "Tri-tone"
            case .tink: "Tink"
            case .off: "Off"
            }
        }
        var soundID: SystemSoundID? {
            switch self {
            case .alarm: 1005
            case .triTone: 1007
            case .tink: 1057
            case .off: nil
            }
        }
    }

    var face = Face.ring
    var cards = Cards.glass
    var glow = GlowStyle()
    var backdrop = ScreenBackdrop.theme
    var ambient = Ambient.off
    var volume = 0.5
    /// Ambient sound also during breaks.
    var ambientOnBreaks = false
    var chime = Chime.alarm

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        face = container.value(.face, or: face)
        cards = container.value(.cards, or: cards)
        glow = container.value(.glow, or: glow)
        backdrop = container.value(.backdrop, or: backdrop)
        ambient = container.value(.ambient, or: ambient)
        volume = container.value(.volume, or: volume)
        ambientOnBreaks = container.value(.ambientOnBreaks, or: ambientOnBreaks)
        chime = container.value(.chime, or: chime)
    }
}

/// The saved look, shared by Flowmodoro and the Planner.
@MainActor
final class FlowLookStore: ObservableObject {
    static let shared = FlowLookStore()
    @Published var look = FlowLook.load() {
        didSet {
            look.save()
            AmbientSound.shared.volume = Float(look.volume)
        }
    }
}

// MARK: Timer faces

/// The Flowmodoro timer drawn in the chosen face.
struct FlowTimerFace: View {
    let face: FlowLook.Face
    /// Seconds shown (work counting up, or break counting down).
    let seconds: Int
    /// 0...1: the break left, or the work through the current hour.
    let progress: Double
    let tint: Color
    let label: String

    var body: some View {
        // Every face takes the same height, so switching doesn't jump.
        Group {
            switch face {
            case .ring: ring
            case .digits: digits
            case .analog: AnalogFace(seconds: seconds, tint: tint, label: label)
            case .liquid: LiquidFace(progress: max(progress, 0.08), tint: tint, text: Flowmodoro.clock(seconds), label: label)
            case .plant: PlantFace(seconds: seconds, tint: tint, text: Flowmodoro.clock(seconds), label: label)
            }
        }
        .frame(height: 250)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0.001))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            VStack(spacing: 4) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(Flowmodoro.clock(seconds))
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 210, height: 210)
    }

    private var digits: some View {
        VStack(spacing: 2) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(Flowmodoro.clock(seconds, forceHours: seconds >= 3600))
                .font(.system(size: 88, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(tint.gradient)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(height: 160)
    }
}

private struct AnalogFace: View {
    let seconds: Int
    let tint: Color
    let label: String

    var body: some View {
        Canvas { context, size in
            let radius: Double = Double(min(size.width, size.height)) / 2 - 6
            let r = CGFloat(radius)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                           with: .color(tint.opacity(0.4)), lineWidth: 3)
            for tick in 0..<60 {
                let angle: Double = Double(tick) / 60 * 2 * Double.pi
                let long: Bool = tick % 5 == 0
                let inner: Double = radius - (long ? 14 : 6)
                var path = Path()
                path.move(to: point(center, inner, angle))
                path.addLine(to: point(center, radius - 2, angle))
                context.stroke(path, with: .color(tint.opacity(long ? 0.8 : 0.3)), lineWidth: long ? 2.5 : 1)
            }
            let minuteAngle: Double = Double(seconds % 3600) / 3600 * 2 * Double.pi
            let secondAngle: Double = Double(seconds % 60) / 60 * 2 * Double.pi
            hand(&context, center, radius * 0.62, minuteAngle, 5, tint)
            hand(&context, center, radius * 0.85, secondAngle, 2, Color.red)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(tint))
        }
        .frame(width: 190, height: 190)
        .overlay(alignment: .bottom) {
            HStack(spacing: 6) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(Flowmodoro.clock(seconds)).font(.headline.monospacedDigit()).foregroundStyle(tint)
            }
            .fixedSize()
            .offset(y: 34)
        }
        .padding(.bottom, 34)
    }

    private func point(_ center: CGPoint, _ distance: Double, _ angle: Double) -> CGPoint {
        let x: Double = Double(center.x) + Math.sine(angle) * distance
        let y: Double = Double(center.y) - Math.cosine(angle) * distance
        return CGPoint(x: x, y: y)
    }

    private func hand(_ context: inout GraphicsContext, _ center: CGPoint, _ length: Double, _ angle: Double, _ width: CGFloat, _ color: Color) {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center, length, angle))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

private struct LiquidFace: View {
    let progress: Double
    let tint: Color
    let text: String
    let label: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            let phase: Double = timeline.date.timeIntervalSinceReferenceDate * 2
            Canvas { context, size in
                let level: Double = Double(size.height) * (1 - max(min(progress, 1), 0.02))
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: size.height))
                var x: Double = 0
                while x <= Double(size.width) {
                    let y: Double = level + Math.sine(x / 28 + phase) * 6
                    wave.addLine(to: CGPoint(x: x, y: y))
                    x += 4
                }
                wave.addLine(to: CGPoint(x: size.width, y: size.height))
                wave.closeSubpath()
                context.fill(wave, with: .linearGradient(Gradient(colors: [tint.opacity(0.55), tint]), startPoint: CGPoint(x: 0, y: level), endPoint: CGPoint(x: 0, y: size.height)))
            }
        }
        .frame(width: 180, height: 210)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).stroke(tint.opacity(0.4), lineWidth: 2))
        .overlay {
            VStack(spacing: 2) {
                Text(label).font(.caption.weight(.semibold))
                Text(text).font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(Color(uiColor: .label))
        }
    }
}

private struct PlantFace: View {
    let seconds: Int
    let tint: Color
    let text: String
    let label: String

    var body: some View {
        // Grows over the first hour, then blooms.
        let growth: Double = min(Double(seconds) / 3600, 1)
        VStack(spacing: 6) {
            Canvas { context, size in
                PlantPainter.draw(in: &context, size: size, growth: growth, season: PlantPainter.currentSeason, tint: tint)
            }
            .frame(width: 200, height: 180)
            Text(text).font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Draws a plant at a growth from 0 (a seed) to 1 (a tree in bloom), dressed for a season.
enum PlantPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, growth: Double, season: Season, tint: Color) {
        let width = Double(size.width)
        let height = Double(size.height)
        let groundY = height - 12
        // Pot of earth.
        let soil = Path(roundedRect: CGRect(x: width * 0.3, y: groundY - 4, width: width * 0.4, height: 16), cornerRadius: 6)
        context.fill(soil, with: .color(Color(red: 0.45, green: 0.3, blue: 0.2)))
        guard growth > 0.01 else {
            let seed = Path(ellipseIn: CGRect(x: width / 2 - 5, y: groundY - 10, width: 10, height: 7))
            context.fill(seed, with: .color(Color(red: 0.55, green: 0.38, blue: 0.2)))
            return
        }
        let stemHeight: Double = (height - 30) * (0.15 + 0.85 * growth)
        let topY = groundY - stemHeight
        var stem = Path()
        stem.move(to: CGPoint(x: width / 2, y: groundY))
        stem.addQuadCurve(to: CGPoint(x: width / 2, y: topY), control: CGPoint(x: width / 2 + 8, y: groundY - stemHeight / 2))
        let trunkWidth: Double = 2 + 6 * growth
        context.stroke(stem, with: .color(Color(red: 0.42, green: 0.28, blue: 0.16)), style: StrokeStyle(lineWidth: trunkWidth, lineCap: .round))
        let leafColor: Color = leafColor(for: season)
        let leaves = Int(2 + growth * 14)
        for index in 0..<leaves {
            let t: Double = Double(index) / Double(max(leaves - 1, 1))
            let y: Double = groundY - stemHeight * (0.35 + 0.65 * t)
            let spread: Double = (12 + 42 * growth) * (1 - t * 0.5)
            let side: Double = index % 2 == 0 ? -1 : 1
            let x: Double = width / 2 + side * spread * 0.6
            let leaf = Path(ellipseIn: CGRect(x: x - 9, y: y - 6, width: 18 + 8 * growth, height: 12))
            if season == .winter {
                context.fill(leaf, with: .color(Color.white.opacity(0.9)))
            } else {
                context.fill(leaf, with: .color(leafColor.opacity(0.75 + 0.25 * t)))
            }
        }
        // A full crown and flowers once grown.
        if growth > 0.6 {
            let crown: Double = 30 + 40 * growth
            let rect = CGRect(x: width / 2 - crown / 2, y: topY - crown * 0.55, width: crown, height: crown * 0.8)
            context.fill(Path(ellipseIn: rect), with: .color(season == .winter ? Color.white.opacity(0.85) : leafColor.opacity(0.85)))
            if season == .spring || season == .summer || season == .none {
                for index in 0..<Int(growth * 8) {
                    let angle: Double = Double(index) * 0.9
                    let fx: Double = Double(rect.midX) + Math.cosine(angle) * Double(rect.width) * 0.32
                    let fy: Double = Double(rect.midY) + Math.sine(angle) * Double(rect.height) * 0.3
                    context.fill(Path(ellipseIn: CGRect(x: fx - 4, y: fy - 4, width: 8, height: 8)), with: .color(season == .spring ? Color.pink : tint))
                }
            }
        }
    }

    private static func leafColor(for season: Season) -> Color {
        switch season {
        case .autumn: return Color(red: 0.9, green: 0.5, blue: 0.12)
        case .spring: return Color(red: 0.45, green: 0.78, blue: 0.35)
        case .winter: return .white
        case .summer, .none: return Color(red: 0.22, green: 0.62, blue: 0.3)
        }
    }

    /// The season now, from the theme or the month.
    static var currentSeason: Season {
        let themed = ThemeSettings.current.season
        if themed != .none { return themed }
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }
}

// MARK: Card styles

extension View {
    /// A Planner card in the chosen style.
    func flowCard(_ look: FlowLook, tint: Color, isActive: Bool) -> some View {
        modifier(FlowCardStyle(look: look, tint: tint, isActive: isActive))
    }
}

private struct FlowCardStyle: ViewModifier {
    let look: FlowLook
    let tint: Color
    let isActive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        switch look.cards {
        case .glass:
            content
                .foregroundStyle(Color.primary)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.3), lineWidth: 0.8))
                .styledGlow(isActive ? look.glow : .off, color: tint)
        case .sticky:
            content
                .environment(\.colorScheme, .light)
                .foregroundStyle(Color.black.opacity(0.85))
                .background(Color(red: 1, green: 0.93, blue: 0.55), in: RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.18), radius: 4, x: 2, y: 3)
                .rotationEffect(.degrees(isActive ? -1.2 : 0.8))
        case .minimal:
            content
                .foregroundStyle(Color.primary)
                .background(Color(uiColor: .systemBackground), in: shape)
                .overlay(shape.stroke(Color.secondary.opacity(0.25)))
        case .neon:
            content
                .environment(\.colorScheme, .dark)
                .foregroundStyle(Color.white)
                .background(Color.black.opacity(0.88), in: shape)
                .overlay(shape.stroke(tint, lineWidth: 1.5))
                .styledGlow(look.glow.isOn ? look.glow : GlowStyle(), color: tint)
        }
    }
}

// MARK: Ambient sound

/// Rain, ocean or noise made on the iPad while focusing (no sound files).
final class AmbientSound: @unchecked Sendable {
    static let shared = AmbientSound()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    /// Read on the audio thread: the kind of sound, as its index.
    private let current = OSAllocatedUnfairLock(initialState: 0)
    private var isObserving = false
    var volume: Float = 0.5 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    /// Starts, changes or stops the sound.
    func play(_ ambient: FlowLook.Ambient, volume: Float) {
        self.volume = volume
        let index = FlowLook.Ambient.allCases.firstIndex(of: ambient) ?? 0
        current.withLock { $0 = index }
        guard ambient != .off else {
            stopEngine()
            return
        }
        observe()
        if source == nil { setUp() }
        guard !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        // Never take over a recording (it uses play-and-record); just mix in.
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, options: [.mixWithOthers])
        }
        try? session.setActive(true)
        try? engine.start()
    }

    func stop() { play(.off, volume: volume) }

    private func stopEngine() {
        guard engine.isRunning else { return }
        engine.stop()
        let session = AVAudioSession.sharedInstance()
        if session.category == .playback {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// After a call, Siri, a recording or a route change the engine stops:
    /// start it again if the timer still wants sound.
    private func observe() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            AVAudioSession.interruptionNotification,
            AVAudioSession.mediaServicesWereResetNotification,
            .AVAudioEngineConfigurationChange,
            UIApplication.didBecomeActiveNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    FocusSoundController.update()
                }
            }
        }
    }

    private func setUp() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 44_100
        var generator = NoiseGenerator(sampleRate: sampleRate)
        let current = current
        let node = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
            let index = current.withLock { $0 }
            let cases = FlowLook.Ambient.allCases
            let ambient = index < cases.count ? cases[index] : .off
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let sample = generator.next(ambient)
                for buffer in buffers {
                    let pointer = buffer.mData?.assumingMemoryBound(to: Float.self)
                    pointer?[frame] = sample
                }
            }
            return noErr
        }
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = volume
        source = node
    }
}

/// Colored noise, shaped into rain or waves. Its own fast random numbers,
/// so the audio thread never waits on a lock.
private struct NoiseGenerator {
    let sampleRate: Double
    private var seed: UInt32 = 0x9E37_79B9
    private var pink: (Float, Float, Float) = (0, 0, 0)
    private var brown: Float = 0
    private var time: Double = 0
    private var drop: Float = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// -1...1 (xorshift).
    private mutating func random() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        let unit: Float = Float(seed) / Float(UInt32.max)
        return unit * 2 - 1
    }

    mutating func next(_ ambient: FlowLook.Ambient) -> Float {
        let white = random()
        time += 1 / sampleRate
        switch ambient {
        case .off:
            return 0
        case .white:
            return white * 0.25
        case .pink:
            pink.0 = 0.997 * pink.0 + white * 0.029591
            pink.1 = 0.985 * pink.1 + white * 0.032534
            pink.2 = 0.950 * pink.2 + white * 0.048056
            return (pink.0 + pink.1 + pink.2 + white * 0.05) * 0.9
        case .brown:
            brown = max(min(brown + white * 0.02, 1), -1) * 0.998
            return brown * 0.9
        case .rain:
            // Soft hiss plus random drops that fade.
            brown = max(min(brown + white * 0.02, 1), -1) * 0.998
            if random() > 0.998 { drop = 0.3 + (random() + 1) * 0.25 }
            drop *= 0.9993
            return (white * 0.08 + brown * 0.35) + white * drop * 0.4
        case .ocean:
            // Brown noise rising and falling like waves (about 9 s).
            brown = max(min(brown + white * 0.02, 1), -1) * 0.998
            let swell = Float(0.35 + 0.65 * (0.5 + 0.5 * Math.sine(time * 2 * Double.pi / 9)))
            return (brown * 0.9 + white * 0.05) * swell
        }
    }
}

// MARK: Customize

/// The paintbrush sheet for Flowmodoro and the Planner.
struct FlowStyleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = FlowLookStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Timer Face") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(FlowLook.Face.allCases) { face in
                                facePreview(face)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                Section("Planner Cards") {
                    Picker("Cards", selection: $store.look.cards) {
                        ForEach(FlowLook.Cards.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Sample task")
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .flowCard(store.look, tint: .orange, isActive: true)
                        .padding(.vertical, 6)
                }
                GlowSettingsSection(glow: $store.look.glow, footer: "Glow lights up the timer and active task cards.")
                Section("Background") {
                    BackdropPicker(backdrop: $store.look.backdrop)
                }
                Section {
                    Picker("Ambient Sound", selection: $store.look.ambient) {
                        ForEach(FlowLook.Ambient.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    LabeledSlider(title: "Volume", systemImage: "speaker.wave.2", value: $store.look.volume, range: 0...1, text: "\(Int(store.look.volume * 100))%")
                    Toggle("Also During Breaks", isOn: $store.look.ambientOnBreaks)
                    Button {
                        preview()
                    } label: {
                        Label("Listen for 4 Seconds", systemImage: "play.circle")
                    }
                    .disabled(store.look.ambient == .off)
                } header: {
                    Text("Sound While Focusing")
                } footer: {
                    Text("Made on this iPad: rain, ocean and noise to cover distracting sounds.")
                }
                Section("Break Chime") {
                    Picker("Chime", selection: $store.look.chime) {
                        ForEach(FlowLook.Chime.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.look.chime) {
                        if let sound = store.look.chime.soundID { AudioServicesPlaySystemSound(sound) }
                    }
                }
            }
            .onChange(of: store.look.ambient) { FocusSoundController.update() }
            .onChange(of: store.look.ambientOnBreaks) { FocusSoundController.update() }
            .navigationTitle("Customize Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func facePreview(_ face: FlowLook.Face) -> some View {
        let selected = store.look.face == face
        return Button {
            withAnimation { store.look.face = face }
        } label: {
            VStack(spacing: 6) {
                FlowTimerFace(face: face, seconds: 1525, progress: 0.42, tint: .green, label: "Work")
                    .scaleEffect(0.5)
                    .frame(width: 120, height: 120)
                Text(face.title).font(.caption.weight(.semibold)).foregroundStyle(Color(uiColor: .label))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.inkAccent : Color.secondary.opacity(0.25), lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
    }

    private func preview() {
        let look = store.look
        AmbientSound.shared.play(look.ambient, volume: Float(look.volume))
        Task {
            try? await Task.sleep(for: .seconds(4))
            // Keep playing if a work session started meanwhile.
            await MainActor.run { FocusSoundController.update() }
        }
    }
}

/// Plays the ambient sound while work (or a break, if chosen) runs.
@MainActor
enum FocusSoundController {
    static weak var workspace: WorkspaceStore?
    private static var breakCheck: Task<Void, Never>?

    static func update() {
        let look = FlowLookStore.shared.look
        let timer = workspace?.flowTimer
        let breakEnd: Date? = timer?.breakEndsAt
        let breakRunning: Bool = timer?.phase == .onBreak && (breakEnd ?? .distantPast) > Date()
        let plays: Bool = timer?.phase == .working || (look.ambientOnBreaks && breakRunning)
        if plays {
            AmbientSound.shared.play(look.ambient, volume: Float(look.volume))
        } else {
            AmbientSound.shared.stop()
        }
        // A break can end while Flowmodoro isn't open: stop the sound then.
        breakCheck?.cancel()
        if breakRunning, let breakEnd {
            breakCheck = Task {
                try? await Task.sleep(for: .seconds(max(breakEnd.timeIntervalSinceNow, 0) + 0.5))
                guard !Task.isCancelled else { return }
                update()
            }
        }
    }
}
