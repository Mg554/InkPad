import SwiftUI

extension GardenPlant {
    init(subject: String, minutes: Int) {
        self.init(subject: subject, seconds: minutes * 60)
    }

    var seed: UInt64 { GardenSeed.of(subject) }
}

/// A plant card: the plant, its stage and time, and how far to the next.
struct GardenPlantCard: View {
    let plant: GardenPlant
    var size: CGFloat = 130
    /// Shown growth, when it is being animated.
    var growth: Double?
    @ObservedObject private var settings = GardenSettings.shared

    var body: some View {
        VStack(spacing: 6) {
            LivingPlant(
                growth: growth ?? plant.growth,
                species: settings.species(for: plant.subject),
                season: PlantPainter.currentSeason,
                seed: plant.seed,
                sways: settings.saved.wind
            )
            .frame(width: size, height: size * 1.15)
            Text(verbatim: plant.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("\(tr(plant.stageName)) · \(PlannerInsights.duration(plant.seconds))").font(.caption).foregroundStyle(.secondary)
            if let next = plant.minutesToNext {
                ProgressView(value: plant.growth)
                    .tint(.green)
                    .frame(width: size * 0.8)
                Text("\(next) min to grow").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: size + 30)
        .themedCard()
    }
}

// MARK: The garden

/// Every subject's plant, growing with focus time: one garden under a sky
/// that follows the clock, or cards. Plants grow before your eyes since
/// you last looked.
struct FocusGardenView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = GardenSettings.shared
    @State private var shown: [String: Double] = [:]
    @State private var news: [String] = []
    @State private var picked: GardenPlant?

    var body: some View {
        let plants = GardenPlant.garden(sessions: workspace.flowSessions, tasks: workspace.tasks)
        NavigationStack {
            Group {
                if plants.isEmpty {
                    ContentUnavailableView("Nothing Planted Yet", systemImage: "leaf", description: Text("Finish a Flowmodoro session to plant your first seed."))
                } else if settings.saved.scene {
                    GardenSceneView(plants: plants, shown: shown) { picked = $0 }
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    cards(plants)
                }
            }
            .overlay(alignment: .top) { newsBanner }
            .themedBackground()
            .navigationTitle("Focus Garden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        GardenOptions()
                    } label: {
                        Label("Garden Options", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(item: $picked) { plant in
                PlantDetailView(plant: plant)
            }
        }
        .task { await reveal(plants) }
        .modifier(PageSizedSheet())
    }

    private func cards(_ plants: [GardenPlant]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Each subject grows a plant as you focus on it: a planner task's first tag is its subject. Tap a plant to choose its kind.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    ForEach(plants) { plant in
                        GardenPlantCard(plant: plant, size: 140, growth: shown[plant.subject])
                            .onTapGesture { picked = plant }
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var newsBanner: some View {
        if !news.isEmpty {
            VStack(spacing: 4) {
                ForEach(news, id: \.self) { line in
                    Text(verbatim: line).font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Starts each plant where it was last seen and grows it to now.
    private func reveal(_ plants: [GardenPlant]) async {
        var start: [String: Double] = [:]
        var end: [String: Double] = [:]
        var lines: [String] = []
        for plant in plants {
            end[plant.subject] = plant.growth
            if settings.saved.celebrate, let seen = settings.saved.seen[plant.subject], seen < plant.minutes {
                let before = GardenPlant(subject: plant.subject, minutes: seen)
                start[plant.subject] = before.growth
                if before.stage < plant.stage {
                    lines.append(plant.subject + " · " + tr(plant.stageName) + " 🌱")
                }
            } else if settings.saved.celebrate, settings.saved.seen[plant.subject] == nil {
                start[plant.subject] = 0
            } else {
                start[plant.subject] = plant.growth
            }
        }
        shown = start
        var seen = settings.saved.seen
        for plant in plants { seen[plant.subject] = plant.minutes }
        settings.saved.seen = seen
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeInOut(duration: 2.6)) { shown = end }
        guard !lines.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(1800))
        withAnimation(.spring) { news = lines }
        try? await Task.sleep(for: .seconds(5))
        withAnimation(.easeOut) { news = [] }
    }
}

/// All plants on one piece of land, under the sky of the hour and season.
struct GardenSceneView: View {
    let plants: [GardenPlant]
    let shown: [String: Double]
    let pick: (GardenPlant) -> Void
    @ObservedObject private var settings = GardenSettings.shared

    var body: some View {
        let season: Season = PlantPainter.currentSeason
        GeometryReader { proxy in
            let slot: CGFloat = 160
            let width: CGFloat = max(proxy.size.width, CGFloat(plants.count) * slot * 0.75 + 120)
            let height: CGFloat = proxy.size.height
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    SkyBackdrop(season: season, followsClock: settings.saved.sky)
                    GardenLand(season: season)
                    if settings.saved.wind {
                        GardenParticles(season: season, night: SkyBackdrop.isNight(followsClock: settings.saved.sky))
                    }
                    ForEach(Array(plants.enumerated()), id: \.element.id) { index, plant in
                        placed(plant, index: index, width: width, height: height, season: season)
                    }
                }
                .frame(width: width, height: height)
            }
        }
    }

    /// Back row first, then front, staggered like a real bed.
    private func placed(_ plant: GardenPlant, index: Int, width: CGFloat, height: CGFloat, season: Season) -> some View {
        let back: Bool = index % 2 == 1
        let count: CGFloat = CGFloat(max(plants.count, 1))
        let step: CGFloat = (width - 120) / count
        let x: CGFloat = 60 + step * (CGFloat(index) + 0.5)
        let ground: CGFloat = height - (back ? 150 : 96)
        let plantHeight: CGFloat = min(height * 0.62, 340)
        return VStack(spacing: 4) {
            LivingPlant(
                growth: shown[plant.subject] ?? plant.growth,
                species: settings.species(for: plant.subject),
                season: season,
                seed: plant.seed,
                sways: settings.saved.wind
            )
            .frame(width: plantHeight * 0.8, height: plantHeight)
            Text(verbatim: plant.subject)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .scaleEffect(back ? 0.82 : 1, anchor: .bottom)
        .position(x: x, y: ground - plantHeight / 2 + 10)
        .zIndex(back ? 0 : 1)
        .onTapGesture { pick(plant) }
    }
}

/// The sky: dawn, day, dusk or night with stars, or a sunny day.
struct SkyBackdrop: View {
    let season: Season
    let followsClock: Bool

    static func isNight(followsClock: Bool) -> Bool {
        guard followsClock else { return false }
        let hour: Int = Calendar.current.component(.hour, from: Date())
        return hour >= 21 || hour < 5
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { timeline in
            let hour: Int = followsClock ? Calendar.current.component(.hour, from: timeline.date) : 12
            Canvas { context, size in
                draw(in: context, size: size, hour: hour)
            }
        }
        .allowsHitTesting(false)
    }

    private func colors(hour: Int) -> [Color] {
        switch hour {
        case 5..<8: return [Color(red: 0.55, green: 0.68, blue: 0.95), Color(red: 0.98, green: 0.72, blue: 0.58)]
        case 8..<17:
            if season == .winter { return [Color(red: 0.62, green: 0.75, blue: 0.9), Color(red: 0.88, green: 0.92, blue: 0.97)] }
            return [Color(red: 0.36, green: 0.62, blue: 0.96), Color(red: 0.78, green: 0.9, blue: 1)]
        case 17..<21: return [Color(red: 0.3, green: 0.24, blue: 0.52), Color(red: 0.98, green: 0.58, blue: 0.4)]
        default: return [Color(red: 0.03, green: 0.05, blue: 0.16), Color(red: 0.12, green: 0.16, blue: 0.36)]
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, hour: Int) {
        let rect = CGRect(origin: .zero, size: size)
        let gradient = Gradient(colors: colors(hour: hour))
        context.fill(Path(rect), with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.75)))
        let night: Bool = hour >= 21 || hour < 5
        if night {
            var random = GardenRandom(seed: 42)
            for _ in 0..<70 {
                let x: Double = random.next() * Double(size.width)
                let y: Double = random.next() * Double(size.height) * 0.55
                let r: Double = random.range(0.6, 1.8)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(random.range(0.4, 1))))
            }
            let moon = CGRect(x: size.width * 0.78, y: size.height * 0.1, width: 46, height: 46)
            context.fill(Path(ellipseIn: moon), with: .color(Color(red: 0.98, green: 0.96, blue: 0.85)))
            context.fill(Path(ellipseIn: moon.offsetBy(dx: 12, dy: -6)), with: .color(Color(red: 0.05, green: 0.07, blue: 0.2)))
        } else {
            // The sun climbs and sets across the day.
            let day: Double = min(max((Double(hour) - 5) / 16, 0), 1)
            let x: Double = Double(size.width) * (0.1 + 0.8 * day)
            let y: Double = Double(size.height) * (0.42 - 0.32 * Math.sine(day * Double.pi))
            let glow = CGRect(x: x - 60, y: y - 60, width: 120, height: 120)
            context.fill(Path(ellipseIn: glow), with: .radialGradient(Gradient(colors: [Color.yellow.opacity(0.45), Color.yellow.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 10, endRadius: 60))
            context.fill(Path(ellipseIn: CGRect(x: x - 22, y: y - 22, width: 44, height: 44)), with: .color(Color(red: 1, green: 0.88, blue: 0.4)))
            // A few clouds.
            var random = GardenRandom(seed: 7)
            for _ in 0..<4 {
                let cx: Double = random.next() * Double(size.width)
                let cy: Double = random.range(0.08, 0.3) * Double(size.height)
                for puff in 0..<4 {
                    let px: Double = cx + Double(puff) * 22
                    let py: Double = cy - (puff % 2 == 0 ? 0 : 8)
                    context.fill(Path(ellipseIn: CGRect(x: px, y: py, width: 44, height: 28)), with: .color(.white.opacity(0.75)))
                }
            }
        }
    }
}

/// Far hills and the garden bed.
struct GardenLand: View {
    let season: Season

    var body: some View {
        Canvas { context, size in
            let far: Color = season == .winter ? Color(red: 0.82, green: 0.86, blue: 0.92) : (season == .autumn ? Color(red: 0.62, green: 0.55, blue: 0.35) : Color(red: 0.45, green: 0.66, blue: 0.45))
            let near: Color = TreePainter.groundColor(season)
            let w: Double = Double(size.width)
            let h: Double = Double(size.height)
            var hills = Path()
            hills.move(to: CGPoint(x: 0, y: h * 0.62))
            var x: Double = 0
            while x <= w {
                let y: Double = h * 0.6 - 30 * Math.sine(x / 140) - 16 * Math.sine(x / 53)
                hills.addLine(to: CGPoint(x: x, y: y))
                x += 12
            }
            hills.addLine(to: CGPoint(x: w, y: h))
            hills.addLine(to: CGPoint(x: 0, y: h))
            hills.closeSubpath()
            context.fill(hills, with: .color(far))
            var bed = Path()
            bed.move(to: CGPoint(x: 0, y: h - 190))
            x = 0
            while x <= w {
                let y: Double = h - 190 - 10 * Math.sine(x / 90)
                bed.addLine(to: CGPoint(x: x, y: y))
                x += 12
            }
            bed.addLine(to: CGPoint(x: w, y: h))
            bed.addLine(to: CGPoint(x: 0, y: h))
            bed.closeSubpath()
            context.fill(bed, with: .linearGradient(Gradient(colors: [near, near.opacity(0.8)]), startPoint: CGPoint(x: 0, y: h - 200), endPoint: CGPoint(x: 0, y: h)))
            // Tufts of grass.
            if season != .winter {
                var random = GardenRandom(seed: 99)
                for _ in 0..<Int(w / 16) {
                    let gx: Double = random.next() * w
                    let gy: Double = h - random.range(20, 180)
                    var tuft = Path()
                    tuft.move(to: CGPoint(x: gx, y: gy))
                    tuft.addLine(to: CGPoint(x: gx - 3, y: gy - 9))
                    tuft.move(to: CGPoint(x: gx, y: gy))
                    tuft.addLine(to: CGPoint(x: gx + 3, y: gy - 10))
                    context.stroke(tuft, with: .color(Color.black.opacity(0.12)), lineWidth: 1.4)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Snow, falling leaves, petals, pollen or fireflies drifting by.
struct GardenParticles: View {
    let season: Season
    let night: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let time: Double = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(in: context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        var random = GardenRandom(seed: 5)
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        for _ in 0..<40 {
            let startX: Double = random.next() * w
            let startY: Double = random.next() * h
            let speed: Double = random.range(14, 38)
            let sway: Double = random.range(8, 26)
            let phase: Double = random.next() * 6
            switch season {
            case .winter:
                let y: Double = (startY + time * speed).truncatingRemainder(dividingBy: h)
                let x: Double = startX + Math.sine(time * 0.8 + phase) * sway
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 4, height: 4)), with: .color(.white.opacity(0.9)))
            case .autumn, .spring:
                let y: Double = (startY + time * speed * 0.8).truncatingRemainder(dividingBy: h)
                let x: Double = (startX + time * 12 + Math.sine(time + phase) * sway).truncatingRemainder(dividingBy: w)
                let color: Color = season == .autumn ? Color(red: 0.9, green: 0.5, blue: 0.15) : Color(red: 1, green: 0.78, blue: 0.86)
                var leaf = context
                leaf.translateBy(x: x, y: y)
                leaf.rotate(by: .radians(time + phase))
                leaf.fill(Path(ellipseIn: CGRect(x: -4, y: -2, width: 8, height: 4.5)), with: .color(color.opacity(0.9)))
            case .summer, .none:
                if night {
                    let x: Double = startX + Math.sine(time * 0.5 + phase) * sway * 2
                    let y: Double = h * 0.45 + startY * 0.45 + Math.cosine(time * 0.6 + phase) * sway
                    let glow: Double = 0.4 + 0.6 * abs(Math.sine(time * 1.5 + phase))
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 4, height: 4)), with: .color(Color.yellow.opacity(glow)))
                } else {
                    let y: Double = h - (startY + time * speed * 0.4).truncatingRemainder(dividingBy: h)
                    let x: Double = startX + Math.sine(time * 0.7 + phase) * sway
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.5, height: 2.5)), with: .color(.white.opacity(0.7)))
                }
            }
        }
    }
}

/// One plant, opened: its stage and time, and the kind it grows into.
struct PlantDetailView: View {
    let plant: GardenPlant
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = GardenSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LivingPlant(
                        growth: plant.growth,
                        species: settings.species(for: plant.subject),
                        season: PlantPainter.currentSeason,
                        seed: plant.seed,
                        sways: settings.saved.wind
                    )
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    LabeledContent("Stage", value: tr(plant.stageName))
                    LabeledContent("Focused", value: PlannerInsights.duration(plant.seconds))
                    if let next = plant.minutesToNext {
                        LabeledContent("Next Stage In", value: "\(next) min")
                    }
                }
                Section("Kind of Plant") {
                    SpeciesPicker(subject: plant.subject)
                }
            }
            .navigationTitle(plant.subject)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Automatic, or a chosen species, for one subject.
struct SpeciesPicker: View {
    let subject: String
    @ObservedObject private var settings = GardenSettings.shared

    var body: some View {
        Picker(selection: Binding(
            get: { settings.saved.species[subject] },
            set: { settings.setSpecies($0, for: subject) }
        )) {
            Text("Automatic (\(tr(PlantSpecies.automatic(for: subject).title)))").tag(PlantSpecies?.none)
            ForEach(PlantSpecies.allCases) { species in
                Label(tr(species.title), systemImage: species.systemImage).tag(PlantSpecies?.some(species))
            }
        } label: {
            Text(verbatim: subject)
        }
    }
}

/// The garden's switches, for its menu, the sidebar and Settings.
struct GardenOptions: View {
    @ObservedObject private var settings = GardenSettings.shared

    var body: some View {
        Picker(selection: $settings.saved.scene) {
            Label("Garden Scene", systemImage: "mountain.2").tag(true)
            Label("Cards", systemImage: "square.grid.2x2").tag(false)
        } label: {
            Label("Show As", systemImage: "eye")
        }
        Toggle(isOn: $settings.saved.wind) { Label("Wind and Weather", systemImage: "wind") }
        Toggle(isOn: $settings.saved.sky) { Label("Sky Follows the Clock", systemImage: "sun.and.horizon") }
        Toggle(isOn: $settings.saved.celebrate) { Label("Watch Plants Grow", systemImage: "sparkles") }
    }
}

/// Settings › Focus › Focus Garden.
struct GardenSettingsView: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        let plants = GardenPlant.garden(sessions: workspace.flowSessions, tasks: workspace.tasks)
        Form {
            Section {
                GardenOptions()
            } footer: {
                Text("Watch Plants Grow: after a session, and when you open the garden, plants grow from where you last saw them.")
            }
            if !plants.isEmpty {
                Section("Kind of Plant") {
                    ForEach(plants) { plant in
                        SpeciesPicker(subject: plant.subject)
                    }
                }
            }
        }
        .navigationTitle("Focus Garden")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: After a session

/// The plant that just grew, shown for a few seconds after a session.
@MainActor
final class GardenToastCenter: ObservableObject {
    static let shared = GardenToastCenter()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let subject: String
        let from: Int
        let to: Int
    }

    @Published var toast: Toast?

    func sessionEnded(_ workspace: WorkspaceStore) {
        guard GardenSettings.shared.saved.celebrate, let last = workspace.flowSessions.last, last.workSeconds >= 60 else { return }
        let tag: String? = last.planTaskID.flatMap { id in workspace.tasks.first(where: { $0.id == id })?.tags.first }
        let subject: String = tag ?? last.taskTitle
        let plants = GardenPlant.garden(sessions: workspace.flowSessions, tasks: workspace.tasks)
        guard let plant = plants.first(where: { $0.subject == subject }) else { return }
        let before: Int = max(plant.seconds - last.workSeconds, 0) / 60
        let shown = Toast(subject: subject, from: before, to: plant.minutes)
        GardenSettings.shared.saved.seen[subject] = plant.minutes
        withAnimation(.spring) { toast = shown }
        Task {
            try? await Task.sleep(for: .seconds(9))
            if toast?.id == shown.id {
                withAnimation(.easeOut) { toast = nil }
            }
        }
    }
}

struct GardenGrowthToast: View {
    let toast: GardenToastCenter.Toast
    @ObservedObject private var settings = GardenSettings.shared
    @State private var growth: Double = 0

    var body: some View {
        let before = GardenPlant(subject: toast.subject, minutes: toast.from)
        let after = GardenPlant(subject: toast.subject, minutes: toast.to)
        HStack(spacing: 14) {
            LivingPlant(
                growth: growth,
                species: settings.species(for: toast.subject),
                season: PlantPainter.currentSeason,
                seed: after.seed,
                sways: settings.saved.wind
            )
            .frame(width: 80, height: 96)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your \(toast.subject) plant grew").font(.headline)
                if after.stage > before.stage {
                    Text("Now a \(tr(after.stageName))! 🎉").font(.subheadline).foregroundStyle(.green)
                } else {
                    Text("+\(toast.to - toast.from) min · \(tr(after.stageName))").font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Tap to open the garden").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                withAnimation(.easeOut) { GardenToastCenter.shared.toast = nil }
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            GardenToastCenter.shared.toast = nil
            CommandCenter.shared.sheet = .garden
        }
        .onAppear {
            growth = before.growth
            withAnimation(.easeInOut(duration: 2.6).delay(0.4)) { growth = after.growth }
        }
    }
}

/// A sheet as big as a page on iPadOS 18 and later (the garden needs room).
struct PageSizedSheet: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.large])
        }
    }
}
