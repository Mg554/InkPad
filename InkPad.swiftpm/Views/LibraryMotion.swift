import SwiftUI
import UIKit

/// How the Bubbles and Circle library views move. Kept in UserDefaults (and
/// synced); changed from the library's View menu or Settings › Appearance.
enum LibraryMotion {
    static let physics = "bubblePhysics"
    static let floats = "bubbleFloat"
    static let breathes = "bubbleBreathe"
    static let spins = "circleSpin"
    static let pinch = "libraryPinch"
    static let zoom = "libraryZoom"
    static let tidy = "bubbleTidy"
    static let positions = "bubblePositions"
}

// MARK: Physics

/// Bubbles that can be dragged and thrown, bump into each other and come to
/// rest where they stop. Runs only while something moves.
@MainActor
final class BubbleWorld: ObservableObject {
    private struct Body {
        var position: CGPoint
        var velocity: CGVector
        var radius: CGFloat
    }

    @Published private(set) var positions: [UUID: CGPoint] = [:]
    @Published private(set) var height: CGFloat = 420
    private var bodies: [UUID: Body] = [:]
    private var width: CGFloat = 0
    private var held: UUID?
    private var link: CADisplayLink?
    private var proxy: LinkProxy?
    private var lastTick: CFTimeInterval = 0
    private var calmFrames = 0
    private var lastDrag: (point: CGPoint, time: CFTimeInterval)?

    /// Lays the bubbles out: kept where they were, else where they were
    /// left last time, else packed in rows.
    func configure(_ items: [(id: UUID, radius: CGFloat)], width: CGFloat, tidy: Bool = false) {
        guard width > 40 else { return }
        let packed: [UUID: CGPoint] = Self.pack(items, width: width)
        let saved: [String: [Double]] = tidy ? [:] : (UserDefaults.standard.dictionary(forKey: LibraryMotion.positions) as? [String: [Double]] ?? [:])
        var next: [UUID: Body] = [:]
        var bottom: CGFloat = 0
        for item in items {
            var point: CGPoint = packed[item.id] ?? CGPoint(x: width / 2, y: item.radius)
            if !tidy, let body = bodies[item.id], abs(self.width - width) < 1 {
                point = body.position
            } else if let spot = saved[item.id.uuidString], spot.count == 2 {
                point = CGPoint(x: CGFloat(spot[0]) * width, y: CGFloat(spot[1]))
            }
            point.x = min(max(point.x, item.radius), max(width - item.radius, item.radius))
            point.y = max(point.y, item.radius)
            next[item.id] = Body(position: point, velocity: .zero, radius: item.radius)
            bottom = max(bottom, point.y + item.radius)
        }
        let packedBottom: CGFloat = items.reduce(CGFloat(0)) { result, item in
            max(result, (packed[item.id]?.y ?? 0) + item.radius)
        }
        self.width = width
        bodies = next
        height = max(max(bottom, packedBottom) + 160, 420)
        publish()
        if tidy { save() }
        wake()
    }

    func drag(_ id: UUID, to point: CGPoint) {
        guard var body = bodies[id] else { return }
        let now: CFTimeInterval = CACurrentMediaTime()
        if let lastDrag, now - lastDrag.time > 0.001 {
            let dt: CGFloat = CGFloat(now - lastDrag.time)
            body.velocity = CGVector(dx: (point.x - lastDrag.point.x) / dt, dy: (point.y - lastDrag.point.y) / dt)
        }
        lastDrag = (point, now)
        held = id
        body.position = CGPoint(
            x: min(max(point.x, body.radius), width - body.radius),
            y: min(max(point.y, body.radius), height - body.radius)
        )
        bodies[id] = body
        wake()
    }

    func release(_ id: UUID, velocity: CGSize) {
        held = nil
        lastDrag = nil
        guard var body = bodies[id] else { return }
        let speed: CGFloat = Math.distance(velocity.width, velocity.height)
        let scale: CGFloat = speed > 2600 ? 2600 / speed : 1
        body.velocity = CGVector(dx: velocity.width * scale, dy: velocity.height * scale)
        bodies[id] = body
        wake()
    }

    func position(of id: UUID) -> CGPoint? { bodies[id]?.position }

    // MARK: Simulation

    private func wake() {
        calmFrames = 0
        guard link == nil else { return }
        let proxy = LinkProxy { [weak self] in self?.tick() }
        let link = CADisplayLink(target: proxy, selector: #selector(LinkProxy.fire))
        link.add(to: .main, forMode: .common)
        self.proxy = proxy
        self.link = link
        lastTick = CACurrentMediaTime()
    }

    private func sleep() {
        link?.invalidate()
        link = nil
        proxy = nil
        save()
    }

    private func tick() {
        let now: CFTimeInterval = CACurrentMediaTime()
        let dt: CGFloat = CGFloat(min(max(now - lastTick, 1.0 / 240.0), 1.0 / 30.0))
        lastTick = now
        let moving: Bool = step(dt)
        publish()
        if moving || held != nil {
            calmFrames = 0
        } else {
            calmFrames += 1
            if calmFrames > 12 { sleep() }
        }
    }

    /// One step: glide with friction, bounce off the edges, push apart.
    /// Returns whether anything still moves.
    private func step(_ dt: CGFloat) -> Bool {
        let friction: CGFloat = CGFloat(Math.power(0.08, Double(dt)))
        var fastest: CGFloat = 0
        for (id, var body) in bodies where id != held {
            body.velocity.dx *= friction
            body.velocity.dy *= friction
            body.position.x += body.velocity.dx * dt
            body.position.y += body.velocity.dy * dt
            bounce(&body)
            fastest = max(fastest, abs(body.velocity.dx) + abs(body.velocity.dy))
            bodies[id] = body
        }
        let pushed: Bool = separate()
        return fastest > 12 || pushed
    }

    private func bounce(_ body: inout Body) {
        let r: CGFloat = body.radius
        if body.position.x < r {
            body.position.x = r
            body.velocity.dx = abs(body.velocity.dx) * 0.55
        } else if body.position.x > width - r {
            body.position.x = width - r
            body.velocity.dx = -abs(body.velocity.dx) * 0.55
        }
        if body.position.y < r {
            body.position.y = r
            body.velocity.dy = abs(body.velocity.dy) * 0.55
        } else if body.position.y > height - r {
            body.position.y = height - r
            body.velocity.dy = -abs(body.velocity.dy) * 0.55
        }
    }

    /// Overlapping bubbles push each other apart and trade momentum, like
    /// soap bubbles. The held one doesn't give way.
    private func separate() -> Bool {
        let ids: [UUID] = Array(bodies.keys)
        var pushed = false
        for _ in 0..<2 {
            for i in 0..<ids.count {
                for j in (i + 1)..<ids.count {
                    guard var a = bodies[ids[i]], var b = bodies[ids[j]] else { continue }
                    let dx: CGFloat = b.position.x - a.position.x
                    let dy: CGFloat = b.position.y - a.position.y
                    let reach: CGFloat = a.radius + b.radius
                    guard abs(dx) < reach, abs(dy) < reach else { continue }
                    var distance: CGFloat = Math.distance(dx, dy)
                    guard distance < reach - 0.5 else { continue }
                    if distance < 0.01 { distance = 0.01 }
                    let nx: CGFloat = distance > 0.01 ? dx / distance : 1
                    let ny: CGFloat = distance > 0.01 ? dy / distance : 0
                    let overlap: CGFloat = reach - distance
                    let aHeld: Bool = ids[i] == held
                    let bHeld: Bool = ids[j] == held
                    let aShare: CGFloat = aHeld ? 0 : (bHeld ? 1 : 0.5)
                    let bShare: CGFloat = bHeld ? 0 : (aHeld ? 1 : 0.5)
                    a.position.x -= nx * overlap * aShare
                    a.position.y -= ny * overlap * aShare
                    b.position.x += nx * overlap * bShare
                    b.position.y += ny * overlap * bShare
                    // Equal bubbles trade the speed along the line between them.
                    let approach: CGFloat = (a.velocity.dx - b.velocity.dx) * nx + (a.velocity.dy - b.velocity.dy) * ny
                    if approach > 0 {
                        let impulse: CGFloat = approach * 0.85
                        if !aHeld {
                            a.velocity.dx -= nx * impulse * (bHeld ? 2 : 1)
                            a.velocity.dy -= ny * impulse * (bHeld ? 2 : 1)
                        }
                        if !bHeld {
                            b.velocity.dx += nx * impulse * (aHeld ? 2 : 1)
                            b.velocity.dy += ny * impulse * (aHeld ? 2 : 1)
                        }
                    }
                    bounce(&a)
                    bounce(&b)
                    bodies[ids[i]] = a
                    bodies[ids[j]] = b
                    if overlap > 0.8 { pushed = true }
                }
            }
        }
        return pushed
    }

    private func publish() {
        var next: [UUID: CGPoint] = [:]
        for (id, body) in bodies { next[id] = body.position }
        positions = next
    }

    /// Where each bubble came to rest, for next time.
    private func save() {
        guard width > 40 else { return }
        var saved: [String: [Double]] = UserDefaults.standard.dictionary(forKey: LibraryMotion.positions) as? [String: [Double]] ?? [:]
        for (id, body) in bodies {
            saved[id.uuidString] = [Double(body.position.x / width), Double(body.position.y)]
        }
        UserDefaults.standard.set(saved, forKey: LibraryMotion.positions)
    }

    /// Rows of bubbles, centered, every other one a little lower.
    private static func pack(_ items: [(id: UUID, radius: CGFloat)], width: CGFloat) -> [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        var row: [(id: UUID, radius: CGFloat)] = []
        var rowWidth: CGFloat = 0
        var top: CGFloat = 12
        func flush() {
            guard !row.isEmpty else { return }
            let tallest: CGFloat = row.map(\.radius).max() ?? 0
            var x: CGFloat = (width - rowWidth) / 2
            for (index, item) in row.enumerated() {
                let lower: CGFloat = index % 2 == 0 ? 0 : 12
                result[item.id] = CGPoint(x: x + item.radius, y: top + tallest + lower)
                x += item.radius * 2
            }
            top += tallest * 2 + 14
            row = []
            rowWidth = 0
        }
        for item in items {
            if rowWidth + item.radius * 2 > width - 8, !row.isEmpty { flush() }
            row.append(item)
            rowWidth += item.radius * 2
        }
        flush()
        return result
    }
}

/// CADisplayLink needs an Objective-C target.
private final class LinkProxy: NSObject {
    let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func fire() {
        MainActor.assumeIsolated { action() }
    }
}

// MARK: Views

/// The Bubbles library view: bubbles float and breathe, can be dragged,
/// thrown and pinched.
struct BubbleField<Content: View>: View {
    let notes: [NoteSummary]
    @ViewBuilder let content: (NoteSummary) -> Content
    @StateObject private var world = BubbleWorld()
    @AppStorage(LibraryMotion.physics) private var physics = true
    @AppStorage(LibraryMotion.floats) private var floats = true
    @AppStorage(LibraryMotion.breathes) private var breathes = true
    @AppStorage(LibraryMotion.tidy) private var tidyCount = 0
    @State private var width: CGFloat = 0
    @State private var grab: CGSize?

    var body: some View {
        Group {
            if physics {
                field
            } else {
                BubbleFlow {
                    ForEach(notes) { note in
                        content(note).modifier(BubbleLife(id: note.id, floats: floats, breathes: breathes))
                    }
                }
                .padding(24)
            }
        }
        .modifier(PinchZoom())
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(notes) { note in
                content(note)
                    .modifier(BubbleLife(id: note.id, floats: floats, breathes: breathes))
                    .position(world.positions[note.id] ?? CGPoint(x: width / 2, y: 60))
                    .highPriorityGesture(drag(note.id))
            }
        }
        .frame(height: world.height)
        .frame(maxWidth: .infinity)
        .coordinateSpace(.named("bubbles"))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width - 32
        } action: { value in
            width = value
            configure(tidy: false)
        }
        .onChange(of: notes.map(\.id)) { configure(tidy: false) }
        .onChange(of: tidyCount) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { configure(tidy: true) }
        }
    }

    private func configure(tidy: Bool) {
        let items: [(id: UUID, radius: CGFloat)] = notes.map { note in
            (note.id, NoteBubble.diameter(note) / 2 + 14)
        }
        world.configure(items, width: width, tidy: tidy)
    }

    private func drag(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("bubbles"))
            .onChanged { value in
                if grab == nil {
                    let center: CGPoint = world.position(of: id) ?? value.startLocation
                    grab = CGSize(width: value.startLocation.x - center.x, height: value.startLocation.y - center.y)
                }
                let offset: CGSize = grab ?? .zero
                world.drag(id, to: CGPoint(x: value.location.x - offset.width, y: value.location.y - offset.height))
            }
            .onEnded { value in
                grab = nil
                world.release(id, velocity: value.velocity)
            }
    }
}

/// The Circle library view: the rings turn with a finger and keep turning
/// a little after it lets go.
struct SpinningCircle<Content: View>: View {
    let notes: [NoteSummary]
    let title: String
    @ViewBuilder let content: (NoteSummary) -> Content
    @AppStorage(LibraryMotion.spins) private var spins = true
    @AppStorage(LibraryMotion.floats) private var floats = true
    @AppStorage(LibraryMotion.breathes) private var breathes = true
    @State private var rotation: Double = 0
    @State private var lastAngle: Double?
    @State private var size: CGSize = .zero

    var body: some View {
        ZStack {
            Color.clear
            RadialLayout(rotation: rotation) {
                ForEach(notes) { note in
                    content(note).modifier(BubbleLife(id: note.id, floats: floats, breathes: breathes))
                }
            }
            CircleHub(title: title, count: notes.count)
        }
        .contentShape(Rectangle())
        .coordinateSpace(.named("circle"))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .gesture(spinGesture, including: spins ? .all : .subviews)
        .padding(.horizontal, 24)
        .modifier(PinchZoom())
    }

    private func angle(of point: CGPoint) -> Double {
        Math.angle(y: Double(point.y - size.height / 2), x: Double(point.x - size.width / 2))
    }

    /// The change from one angle to the next, the short way round.
    private func turn(from start: Double, to end: Double) -> Double {
        var delta: Double = end - start
        if delta > Double.pi { delta -= 2 * Double.pi }
        if delta < -Double.pi { delta += 2 * Double.pi }
        return delta
    }

    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("circle"))
            .onChanged { value in
                let now: Double = angle(of: value.location)
                let before: Double = lastAngle ?? angle(of: value.startLocation)
                rotation += turn(from: before, to: now)
                lastAngle = now
            }
            .onEnded { value in
                lastAngle = nil
                let fling: Double = turn(from: angle(of: value.location), to: angle(of: value.predictedEndLocation))
                withAnimation(.spring(response: 1.2, dampingFraction: 0.95)) {
                    rotation += fling * 1.2
                }
            }
    }
}

/// A gentle drift and a slow breath, each bubble at its own pace.
struct BubbleLife: ViewModifier {
    let id: UUID
    let floats: Bool
    let breathes: Bool
    @State private var phase = false

    private var seed: Double {
        let bytes = id.uuid
        return Double(bytes.0) / 255
    }

    func body(content: Content) -> some View {
        let driftX: CGFloat = floats ? CGFloat(3 + seed * 4) * (phase ? 1 : -1) : 0
        let driftY: CGFloat = floats ? CGFloat(4 + seed * 5) * (phase ? -1 : 1) : 0
        let breath: CGFloat = breathes && phase ? 1.035 : 1
        content
            .scaleEffect(breath)
            .offset(x: driftX, y: driftY)
            .onAppear { start() }
            .onChange(of: floats) { start() }
            .onChange(of: breathes) { start() }
    }

    private func start() {
        guard floats || breathes else {
            phase = false
            return
        }
        phase = false
        let duration: Double = 2.4 + seed * 2.2
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(seed)) {
            phase = true
        }
    }
}

/// Two fingers zoom the bubbles or the circle in and out.
private struct PinchZoom: ViewModifier {
    @AppStorage(LibraryMotion.pinch) private var pinches = true
    @AppStorage(LibraryMotion.zoom) private var zoom = 1.0
    @GestureState private var pinch: CGFloat = 1

    func body(content: Content) -> some View {
        let scale: CGFloat = pinches ? CGFloat(zoom) * pinch : 1
        content
            .scaleEffect(scale, anchor: .top)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        let next: Double = zoom * Double(value.magnification)
                        withAnimation(.spring(response: 0.35)) { zoom = min(max(next, 0.5), 2) }
                    },
                including: pinches ? .all : .subviews
            )
    }
}

/// The library View menu's motion choices, for Bubbles and Circle.
struct LibraryMotionMenu: View {
    @AppStorage(LibraryMotion.physics) private var physics = true
    @AppStorage(LibraryMotion.floats) private var floats = true
    @AppStorage(LibraryMotion.breathes) private var breathes = true
    @AppStorage(LibraryMotion.spins) private var spins = true
    @AppStorage(LibraryMotion.pinch) private var pinch = true
    @AppStorage(LibraryMotion.zoom) private var zoom = 1.0
    @AppStorage(LibraryMotion.tidy) private var tidyCount = 0
    let isCircle: Bool

    var body: some View {
        Menu {
            if isCircle {
                Toggle(isOn: $spins) { Label("Spin with a Finger", systemImage: "arrow.clockwise.circle") }
            } else {
                Toggle(isOn: $physics) { Label("Drag and Throw", systemImage: "hand.draw") }
            }
            Toggle(isOn: $floats) { Label("Floating", systemImage: "wind") }
            Toggle(isOn: $breathes) { Label("Breathing", systemImage: "lungs") }
            Toggle(isOn: $pinch) { Label("Pinch to Zoom", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
            Section {
                if !isCircle, physics {
                    Button {
                        tidyCount += 1
                    } label: {
                        Label("Tidy Up", systemImage: "circle.grid.3x3")
                    }
                }
                if zoom != 1 {
                    Button {
                        withAnimation(.spring(response: 0.35)) { zoom = 1 }
                    } label: {
                        Label("Actual Size", systemImage: "1.magnifyingglass")
                    }
                }
            }
        } label: {
            Label("Motion", systemImage: "sparkles")
        }
    }
}

/// Settings › Appearance › Library Motion.
struct LibraryMotionSettingsView: View {
    @AppStorage(LibraryMotion.physics) private var physics = true
    @AppStorage(LibraryMotion.floats) private var floats = true
    @AppStorage(LibraryMotion.breathes) private var breathes = true
    @AppStorage(LibraryMotion.spins) private var spins = true
    @AppStorage(LibraryMotion.pinch) private var pinch = true

    var body: some View {
        Form {
            Section {
                Toggle("Drag and Throw Bubbles", isOn: $physics)
                Toggle("Spin the Circle with a Finger", isOn: $spins)
            } footer: {
                Text("Bubbles bump into each other and stay where you leave them. Tidy Up in the View menu puts them back in rows.")
            }
            Section {
                Toggle("Floating", isOn: $floats)
                Toggle("Breathing", isOn: $breathes)
                Toggle("Pinch to Zoom", isOn: $pinch)
            } footer: {
                Text("For the Bubbles and Circle views of the library.")
            }
        }
        .navigationTitle("Library Motion")
        .navigationBarTitleDisplayMode(.inline)
    }
}
