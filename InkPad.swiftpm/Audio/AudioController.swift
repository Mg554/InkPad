import AVFoundation
import SwiftUI

/// Records audio with a note and plays it back, like Notability.
///
/// The recorder writes straight into the note's `audio` folder. Each
/// recording keeps the moment it started, so ink written while recording can
/// be matched to the moment it was written: playback reports its position
/// for the ink replay, and tapping ink plays from when it was written.
@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingTime: TimeInterval = 0
    /// The recording open in the playback bar.
    @Published private(set) var current: AudioRecording?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published var rate: Float = 1 {
        didSet { player?.rate = rate }
    }
    /// Fades the ink still to come while a recording is open.
    @Published var replaysInk = true {
        didSet { reportPosition() }
    }

    /// Receives each finished recording, to store it with the note.
    var onRecordingFinished: ((AudioRecording) -> Void)?
    /// Receives the open recording (`nil` when closed or with ink replay
    /// off) and the playback position in it.
    var onPlaybackPosition: ((AudioRecording?, TimeInterval) -> Void)?
    var onError: ((String) -> Void)?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStart = Date()
    private var isStarting = false
    /// Changes when everything stops, so a start still waiting for
    /// microphone permission is dropped.
    private var startToken = 0
    private var player: AVAudioPlayer?
    private var isTicking = false

    var duration: TimeInterval { player?.duration ?? current?.duration ?? 0 }

    // MARK: Recording

    func startRecording(into directory: URL) async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        closePlayer()
        let token = startToken
        let granted = await AVAudioApplication.requestRecordPermission()
        // The note was closed while asking.
        guard token == startToken else { return }
        guard granted else {
            onError?("InkPad can't use the microphone. Allow it in Settings › Privacy & Security › Microphone.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString + ".m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else { throw AudioError.couldNotStart }
            self.recorder = recorder
            recordingURL = url
            recordingStart = Date()
            recordingTime = 0
            isRecording = true
            scheduleTick()
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false)
            onError?("Could not start recording: \(error.localizedDescription)")
        }
    }

    /// Stops recording and hands the recording to `onRecordingFinished`.
    func stopRecording() {
        guard isRecording, let recorder, let url = recordingURL else { return }
        recorder.stop()
        self.recorder = nil
        recordingURL = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        // The file's own length: the recorder reports none once stopped.
        let length = (try? AVAudioPlayer(contentsOf: url))?.duration ?? recordingTime
        guard length >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        onRecordingFinished?(AudioRecording(
            id: UUID(),
            title: "Recording",
            file: url.lastPathComponent,
            startTime: recordingStart.timeIntervalSinceReferenceDate,
            duration: length
        ))
    }

    // MARK: Playback

    func open(_ recording: AudioRecording, in directory: URL) {
        guard !isRecording, isPlainFileName(recording.file) else { return }
        closePlayer()
        do {
            let player = try AVAudioPlayer(contentsOf: directory.appendingPathComponent(recording.file))
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            self.player = player
            current = recording
            playbackTime = 0
            reportPosition()
        } catch {
            onError?("Could not open \(recording.title): \(error.localizedDescription)")
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        if player.currentTime >= player.duration - 0.05 {
            player.currentTime = 0
        }
        player.rate = rate
        isPlaying = player.play()
        scheduleTick()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(time, 0), player.duration)
        playbackTime = player.currentTime
        reportPosition()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: playbackTime + seconds)
    }

    /// Plays from just before `date`, the moment some ink was written.
    func play(from date: Date) {
        guard let current else { return }
        seek(to: date.timeIntervalSince(current.startDate) - 1)
        if !isPlaying { togglePlayback() }
    }

    func closePlayer() {
        player?.stop()
        player = nil
        isPlaying = false
        playbackTime = 0
        guard current != nil else { return }
        current = nil
        reportPosition()
    }

    func pause() {
        guard isPlaying else { return }
        togglePlayback()
    }

    /// Stops recording and playback, e.g. when leaving the note.
    func stopAll() {
        startToken += 1
        stopRecording()
        closePlayer()
    }

    private func reportPosition() {
        onPlaybackPosition?(replaysInk ? current : nil, playbackTime)
    }

    // MARK: Updates

    private func scheduleTick() {
        guard !isTicking else { return }
        isTicking = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            self?.tick()
        }
    }

    private func tick() {
        isTicking = false
        if isRecording, let recorder {
            if recorder.isRecording {
                recordingTime = recorder.currentTime
            } else {
                // Interrupted, e.g. by a call: keep what was recorded.
                stopRecording()
            }
        }
        if isPlaying, let player {
            if player.isPlaying {
                playbackTime = player.currentTime
            } else {
                // Finished, or interrupted.
                isPlaying = false
                if playbackTime > player.duration - 0.5 {
                    playbackTime = player.duration
                }
            }
            reportPosition()
        }
        if isRecording || isPlaying {
            scheduleTick()
        }
    }
}

private enum AudioError: LocalizedError {
    case couldNotStart

    var errorDescription: String? {
        "The microphone could not start."
    }
}

/// Times as 0:42, 12:05 or 1:02:09.
enum AudioClock {
    static func string(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let total = max(Int(time), 0)
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
