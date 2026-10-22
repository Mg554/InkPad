import AVFoundation
import NaturalLanguage
import SwiftUI

/// Full-screen presentation: tap or swipe between slides, a laser pointer
/// for Apple Pencil or a finger, speaker notes, and narration that reads each
/// slide aloud and moves on by itself, like a NotebookLM video overview.
struct SlidePresenter: View {
    let deck: SlideDeck
    let images: [String: UIImage]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var narrator = SlideNarrator()
    @State private var index: Int
    @State private var usesLaser = false
    @State private var laserPoint: CGPoint?
    @State private var showsNotes = false

    init(deck: SlideDeck, images: [String: UIImage], startIndex: Int) {
        self.deck = deck
        self.images = images
        _index = State(initialValue: min(max(startIndex, 0), max(deck.slides.count - 1, 0)))
    }

    private var currentSlide: Slide? {
        deck.slides.indices.contains(index) ? deck.slides[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                slideArea
                if showsNotes, let slide = currentSlide {
                    notesPanel(slide)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 60)
        }
        .overlay(alignment: .top) { controls }
        .overlay(alignment: .bottom) { progressBar }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onDisappear {
            narrator.onSlideFinished = nil
            narrator.stop()
        }
    }

    // MARK: Slide

    private var slideArea: some View {
        ZStack {
            if let slide = currentSlide {
                SlideView(
                    slide: slide,
                    theme: deck.theme,
                    image: slide.imageFile.flatMap { images[$0] },
                    number: index + 1,
                    total: deck.slides.count
                )
                .id(slide.id)
                .transition(.opacity)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if usesLaser {
                laserLayer
            } else {
                // Tap the left side to go back, anywhere else to go on.
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: proxy.size.width * 0.35)
                            .onTapGesture { go(by: -1) }
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { go(by: 1) }
                    }
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard !usesLaser else { return }
                    if value.translation.width < -60 {
                        go(by: 1)
                    } else if value.translation.width > 60 {
                        go(by: -1)
                    }
                }
        )
    }

    /// Drag to point: a glowing red dot that fades when lifted.
    private var laserLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { laserPoint = $0.location }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.4)) { laserPoint = nil }
                    }
            )
            .overlay(alignment: .topLeading) {
                if let laserPoint {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 18, height: 18)
                        .shadow(color: Color.red, radius: 12)
                        .shadow(color: Color.red.opacity(0.8), radius: 4)
                        .position(laserPoint)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }

    private func notesPanel(_ slide: Slide) -> some View {
        ScrollView {
            Text(SlideNarrator.script(for: slide))
                .font(.title3)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(maxHeight: 150)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 18) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("End Presentation")
            Text("\(index + 1) / \(deck.slides.count)")
                .font(.headline.monospacedDigit())
            Divider()
                .frame(height: 22)
                .overlay(Color.white.opacity(0.3))
            controlButton(
                narrator.isNarrating ? "stop.circle.fill" : "speaker.wave.2.fill",
                label: narrator.isNarrating ? "Stop Narration" : "Narrate",
                isOn: narrator.isNarrating
            ) {
                toggleNarration()
            }
            controlButton("hand.point.up.left.fill", label: "Laser Pointer", isOn: usesLaser) {
                usesLaser.toggle()
            }
            controlButton("text.bubble.fill", label: "Speaker Notes", isOn: showsNotes) {
                withAnimation(.snappy(duration: 0.25)) { showsNotes.toggle() }
            }
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12), in: Capsule())
        .padding(.top, 10)
    }

    private func controlButton(_ systemImage: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 40, height: 34)
                .background(isOn ? deck.theme.accent.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .accessibilityLabel(label)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.white.opacity(0.15))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(deck.theme.accent)
                        .frame(width: proxy.size.width * progress)
                }
        }
        .frame(height: 4)
        .padding(.horizontal, 40)
        .padding(.bottom, 24)
        .animation(.easeInOut(duration: 0.3), value: index)
    }

    private var progress: CGFloat {
        deck.slides.count > 1 ? CGFloat(index) / CGFloat(deck.slides.count - 1) : 1
    }

    // MARK: Moving

    private func go(by offset: Int) {
        let target = index + offset
        guard deck.slides.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.3)) { index = target }
        if narrator.isNarrating { narrate() }
    }

    private func toggleNarration() {
        if narrator.isNarrating {
            narrator.stop()
        } else {
            narrator.onSlideFinished = { narrateNext() }
            narrate()
        }
    }

    private func narrate() {
        guard let slide = currentSlide else { return }
        narrator.speak(SlideNarrator.script(for: slide))
    }

    private func narrateNext() {
        guard index < deck.slides.count - 1 else {
            narrator.stop()
            return
        }
        withAnimation(.easeInOut(duration: 0.4)) { index += 1 }
        narrate()
    }
}

/// Reads slides aloud with the iPad's own voices, in the language of the text.
final class SlideNarrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isNarrating = false
    /// Called on the main thread after each slide has been read.
    var onSlideFinished: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        isNarrating = true
        synthesizer.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: text)
        utterance.postUtteranceDelay = 0.7
        current = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        isNarrating = false
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isNarrating, utterance === self.current else { return }
            self.onSlideFinished?()
        }
    }

    /// The speaker notes, or the slide's own words when it has none.
    static func script(for slide: Slide) -> String {
        let notes = slide.speakerNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if slide.layout == .title {
            return [slide.title, slide.subtitle].filter { !$0.isEmpty }.joined(separator: ". ")
        }
        if !notes.isEmpty { return notes }
        return ([slide.title] + slide.visibleBullets).filter { !$0.isEmpty }.joined(separator: ". ")
    }

    /// The best installed voice for the text's language.
    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "en"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
    }
}
