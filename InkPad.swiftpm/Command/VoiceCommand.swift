import AVFoundation
import Speech
import SwiftUI

/// Listens for a spoken command and writes it out as you speak, on the
/// iPad only (nothing is sent anywhere).
@MainActor
final class VoiceCommandListener: ObservableObject {
    enum Language: String, CaseIterable, Identifiable {
        case english = "en-US"
        case arabic = "ar-SA"
        var id: Self { self }
        var title: String { self == .english ? "English" : "العربية" }

        static var preferred: Language {
            Locale.preferredLanguages.first?.hasPrefix("ar") == true ? .arabic : .english
        }
    }

    @Published private(set) var isListening = false
    @Published private(set) var text = ""
    @Published var problem: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?

    func start(language: Language, onFinish: @escaping (String) -> Void) {
        guard !isListening else { return }
        problem = nil
        text = ""
        Task {
            guard await Self.authorize() else {
                problem = "Allow Speech Recognition and the Microphone for InkPad in Settings."
                return
            }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue)), recognizer.isAvailable else {
                problem = "Speech recognition for \(language.title) isn't available on this iPad."
                return
            }
            guard recognizer.supportsOnDeviceRecognition else {
                problem = "\(language.title) can't be recognized on this iPad without the internet. Download it in Settings › General › Keyboard › Dictation."
                return
            }
            do {
                try begin(with: recognizer, onFinish: onFinish)
            } catch {
                problem = "The microphone couldn't start: \(error.localizedDescription)"
                stop()
            }
        }
    }

    private func begin(with recognizer: SFSpeechRecognizer, onFinish: @escaping (String) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = false
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.text = result.bestTranscription.formattedString
                    self.restartSilenceTimer(onFinish: onFinish)
                    if result.isFinal { self.finish(onFinish) }
                } else if error != nil, self.isListening {
                    self.finish(onFinish)
                }
            }
        }
        restartSilenceTimer(onFinish: onFinish)
    }

    /// Stops by itself after a short silence.
    private func restartSilenceTimer(onFinish: @escaping (String) -> Void) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.finish(onFinish)
        }
    }

    private func finish(_ onFinish: (String) -> Void) {
        guard isListening else { return }
        let spoken = text
        stop()
        if !spoken.isEmpty { onFinish(spoken) }
    }

    func stop() {
        silenceTask?.cancel()
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
