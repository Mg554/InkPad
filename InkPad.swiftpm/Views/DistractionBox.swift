import PencilKit
import SwiftUI

/// Catches a stray thought in a second, by typing or with the pen, so focus
/// can go on. It waits in the Distraction Box.
struct DistractionCapture: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var drawing = PKDrawing()
    @State private var way: Way = .write
    @StateObject private var voice = VoiceCommandListener()
    @FocusState private var isTyping: Bool

    enum Way: Hashable { case write, type, speak }

    private var writes: Bool { way == .write }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let timer = workspace.flowTimer, timer.phase == .working {
                    Label("While focusing on “\(timer.taskTitle)”", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Picker("How", selection: $way) {
                    Label("Write", systemImage: "pencil.tip").tag(Way.write)
                    Label("Type", systemImage: "keyboard").tag(Way.type)
                    Label("Speak", systemImage: "mic").tag(Way.speak)
                }
                .pickerStyle(.segmented)
                .onChange(of: way) { if way != .speak { voice.stop() } }
                if way == .speak {
                    speakArea
                } else if writes {
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
            .onDisappear { voice.stop() }
            .navigationTitle("Catch a Distraction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(writes ? drawing.strokes.isEmpty : text.trimmingCharacters(in: .whitespaces).isEmpty && voice.text.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Say the thought; it is written out on the iPad as you speak.
    private var speakArea: some View {
        VStack(spacing: 14) {
            Button {
                if voice.isListening {
                    voice.stop()
                } else {
                    voice.start(language: VoiceCommandListener.Language.preferred) { spoken in text = spoken }
                }
            } label: {
                Image(systemName: voice.isListening ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(voice.isListening ? Color.red : Color.inkAccent)
                    .symbolEffect(.pulse, isActive: voice.isListening)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isListening ? "Stop" : "Speak")
            let heard: String = voice.isListening ? voice.text : text
            Text(heard.isEmpty ? tr("Tap the microphone and say the thought.") : heard)
                .foregroundStyle(heard.isEmpty ? Color.secondary : Color.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 60)
            if let problem = voice.problem {
                Text(trMessage(problem)).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func save() {
        if voice.isListening {
            if !voice.text.isEmpty { text = voice.text }
            voice.stop()
        }
        let during: String? = workspace.flowTimer?.phase == .working ? workspace.flowTimer?.taskTitle : nil
        if writes {
            let ink = drawing.dataRepresentation()
            let item = Distraction(text: "", ink: ink, duringTask: during)
            workspace.addDistraction(item)
            let picture = InkSnapshot.onWhite(of: drawing, from: drawing.bounds.insetBy(dx: -12, dy: -12), scale: 2)
            // The handwriting is read on the iPad, so it can become a reminder.
            Task {
                guard let cgImage = picture.cgImage else { return }
                let lines = await Task.detached(priority: .utility) { InkOCR.lines(in: cgImage) }.value
                let read = InkOCR.text(of: lines).replacingOccurrences(of: "\n", with: " ")
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
struct DistractionInkThumbnail: View {
    let id: UUID
    let data: Data
    var height: CGFloat = 70
    @State private var picture: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if let picture {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: height, alignment: .leading)
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
                guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
                return InkSnapshot.onWhite(of: drawing, from: drawing.bounds.insetBy(dx: -12, dy: -12), scale: 2)
            }.value
            if let made { Self.cache.setObject(made, forKey: key) }
            picture = made
        }
    }
}

