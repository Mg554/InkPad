import PencilKit
import SwiftUI

/// Catches a stray thought in a second, by typing or with the pen, so focus
/// can go on. It waits in the Distraction Box.
struct DistractionCapture: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var drawing = PKDrawing()
    @State private var writes = true
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let timer = workspace.flowTimer, timer.phase == .working {
                    Label("While focusing on “\(timer.taskTitle)”", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Picker("How", selection: $writes) {
                    Label("Write", systemImage: "pencil.tip").tag(true)
                    Label("Type", systemImage: "keyboard").tag(false)
                }
                .pickerStyle(.segmented)
                if writes {
                    InkCanvas(drawing: $drawing, showsToolPicker: false)
                        .frame(height: 180)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topLeading) {
                            if drawing.strokes.isEmpty {
                                Text("Write the thought here…").foregroundStyle(.tertiary).padding(12).allowsHitTesting(false)
                            }
                        }
                } else {
                    TextField("What popped into your head?", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isTyping)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                Text("It goes into the Distraction Box. Deal with it after your session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Catch a Distraction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(writes ? drawing.strokes.isEmpty : text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let during: String? = workspace.flowTimer?.phase == .working ? workspace.flowTimer?.taskTitle : nil
        if writes {
            let ink = drawing.dataRepresentation()
            let item = Distraction(text: "", ink: ink, duringTask: during)
            workspace.addDistraction(item)
            let picture = DistractionInk.image(of: drawing)
            // The handwriting is read on the iPad, so it can become a reminder.
            Task {
                guard let cgImage = picture?.cgImage else { return }
                let lines = await Task.detached(priority: .utility) { BookOCR.lines(in: cgImage) }.value
                let read = BookOCR.text(of: lines).replacingOccurrences(of: "\n", with: " ")
                guard !read.isEmpty else { return }
                workspace.setDistractionText(read, for: item.id)
            }
        } else {
            workspace.addDistraction(Distraction(text: text.trimmingCharacters(in: .whitespacesAndNewlines), duringTask: during))
        }
        CommandCenter.shared.say("Caught. Back to focus")
        dismiss()
    }
}

/// Handwriting drawn once, off the main thread, and kept.
private struct DistractionInkThumbnail: View {
    let id: UUID
    let data: Data
    @State private var picture: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if let picture {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 70, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Color.clear.frame(height: 40)
            }
        }
        .task(id: id) {
            let key = id.uuidString as NSString
            if let cached = Self.cache.object(forKey: key) {
                picture = cached
                return
            }
            let data = data
            let made: UIImage? = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let drawing = try? PKDrawing(data: data) else { return nil }
                return DistractionInk.image(of: drawing)
            }.value
            if let made { Self.cache.setObject(made, forKey: key) }
            picture = made
        }
    }
}

enum DistractionInk {
    /// The handwriting on white, dark ink, for showing and reading.
    static func image(of drawing: PKDrawing) -> UIImage? {
        guard !drawing.strokes.isEmpty else { return nil }
        var picture: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            let bounds = drawing.bounds.insetBy(dx: -12, dy: -12)
            let ink = drawing.image(from: bounds, scale: 2)
            let renderer = UIGraphicsImageRenderer(size: ink.size)
            picture = renderer.image { _ in
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: ink.size))
                ink.draw(at: .zero)
            }
        }
        return picture
    }
}

/// Every caught distraction: stats, and turning each into a reminder or done.
struct DistractionBoxView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reminders = ReminderCenter.shared
    @State private var isCapturing = false
    @State private var showsDone = false

    private var shown: [Distraction] {
        workspace.distractions.filter { showsDone || !$0.isDone }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    stats
                }
                Section {
                    Toggle("Show Done", isOn: $showsDone)
                    if shown.isEmpty {
                        Text("Nothing here. Catch a thought with + while you focus.").foregroundStyle(.secondary)
                    }
                    ForEach(shown) { item in
                        row(item)
                    }
                }
            }
            .navigationTitle("Distraction Box")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCapturing = true
                    } label: {
                        Label("Catch", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $isCapturing) {
                DistractionCapture().environmentObject(workspace)
            }
        }
    }

    private var stats: some View {
        let calendar = Calendar.current
        let today = workspace.distractions.filter { calendar.isDateInToday($0.createdAt) }.count
        let weekStart = Date().addingTimeInterval(-7 * 24 * 3600)
        let week = workspace.distractions.filter { $0.createdAt >= weekStart }
        var byTask: [String: Int] = [:]
        for item in week {
            if let task = item.duringTask { byTask[task, default: 0] += 1 }
        }
        let worst = byTask.max { $0.value < $1.value }
        var byHour: [Int: Int] = [:]
        for item in week { byHour[calendar.component(.hour, from: item.createdAt), default: 0] += 1 }
        let peak = byHour.max { $0.value < $1.value }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("\(today)").font(.title2.bold()).foregroundStyle(.orange)
                    Text("today").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("\(week.count)").font(.title2.bold())
                    Text("this week").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("\(workspace.distractions.filter { !$0.isDone }.count)").font(.title2.bold())
                    Text("waiting").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let peak {
                Text("Most distractions come around \(PlannerInsights.hourLabel(peak.key)).").font(.caption).foregroundStyle(.secondary)
            }
            if let worst {
                Text("Most while working on “\(worst.key)” (\(worst.value)).").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ item: Distraction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                var changed = item
                changed.isDone.toggle()
                withAnimation(.snappy) { workspace.updateDistraction(changed) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 6) {
                if let data = item.ink {
                    DistractionInkThumbnail(id: item.id, data: data)
                }
                if !item.text.isEmpty {
                    Text(tr(item.text)).strikethrough(item.isDone)
                }
                HStack(spacing: 8) {
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let task = item.duringTask { Text("· \(task)").lineLimit(1) }
                    if item.isReminder { Label("Reminder", systemImage: "bell.fill").foregroundStyle(Color.inkAccent) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    makeReminder(item, due: nil)
                } label: {
                    Label("Make a Reminder", systemImage: "bell")
                }
                Button {
                    makeReminder(item, due: Calendar.current.date(byAdding: .day, value: 1, to: Date()))
                } label: {
                    Label("Remind Me Tomorrow", systemImage: "sunrise")
                }
                Button(role: .destructive) {
                    workspace.deleteDistraction(item.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                workspace.deleteDistraction(item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Sends it to Apple Reminders (shown in InkPad's Reminders too).
    private func makeReminder(_ item: Distraction, due: Date?) {
        let title = item.text.isEmpty ? "Distraction from \(item.createdAt.formatted(date: .abbreviated, time: .shortened))" : item.text
        Task {
            if reminders.access != .granted { await reminders.requestAccess() }
            guard reminders.access == .granted else {
                CommandCenter.shared.say("Allow Reminders in Settings to send it there")
                return
            }
            reminders.quickAdd(title, in: nil, due: due)
            var changed = item
            changed.isReminder = true
            changed.isDone = true
            workspace.updateDistraction(changed)
            CommandCenter.shared.say("Added to Reminders")
        }
    }
}
