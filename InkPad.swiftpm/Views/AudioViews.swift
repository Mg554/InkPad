import SwiftUI

/// The editor's record button: a microphone, or the running time and a stop
/// button while recording.
struct RecordButton: View {
    @ObservedObject var audio: AudioController
    let start: () -> Void

    var body: some View {
        if audio.isRecording {
            Button {
                audio.stopRecording()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .symbolEffect(.pulse)
                    Text(AudioClock.string(audio.recordingTime))
                        .monospacedDigit()
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.12), in: Capsule())
            }
            .accessibilityLabel("Stop Recording")
        } else {
            Button(action: start) {
                Label("Record Audio", systemImage: "mic")
            }
        }
    }
}

/// Notability-style playback bar for a note's recordings: play, skip, scrub,
/// speed, and the list of recordings. While it is open the ink replays with
/// the audio, and tapping writing plays from when it was written.
struct AudioPlaybackBar: View {
    @ObservedObject var audio: AudioController
    let recordings: [AudioRecording]
    let open: (AudioRecording) -> Void
    let rename: (AudioRecording) -> Void
    let share: (AudioRecording) -> Void
    let delete: (AudioRecording) -> Void

    private static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    /// 1×, 1.25×, 0.75×.
    private static func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate)×"
    }

    var body: some View {
        if let current = audio.current {
            bar(current)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func bar(_ current: AudioRecording) -> some View {
        let title = recordings.first(where: { $0.id == current.id })?.title ?? current.title
        return HStack(spacing: 12) {
            recordingMenu(current, title: title)
            Button {
                audio.skip(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
            }
            .accessibilityLabel("Back 15 Seconds")
            Button {
                audio.togglePlayback()
            } label: {
                Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
            Button {
                audio.skip(by: 15)
            } label: {
                Image(systemName: "goforward.15")
            }
            .accessibilityLabel("Forward 15 Seconds")
            Slider(
                value: Binding(get: { audio.playbackTime }, set: { audio.seek(to: $0) }),
                in: 0...max(audio.duration, 0.1)
            )
            .frame(minWidth: 120)
            Text("\(AudioClock.string(audio.playbackTime)) / \(AudioClock.string(audio.duration))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            speedMenu
            Button {
                withAnimation(.snappy(duration: 0.25)) { audio.closePlayer() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Close Player")
        }
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: 700)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func recordingMenu(_ current: AudioRecording, title: String) -> some View {
        Menu {
            Section("Recordings") {
                ForEach(recordings) { recording in
                    Button {
                        open(recording)
                    } label: {
                        Label(
                            "\(recording.title) · \(AudioClock.string(recording.duration))",
                            systemImage: recording.id == current.id ? "checkmark" : "waveform"
                        )
                    }
                }
            }
            Section {
                Toggle(isOn: $audio.replaysInk) {
                    Label("Replay Writing with Audio", systemImage: "scribble.variable")
                }
                Button {
                    rename(current)
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button {
                    share(current)
                } label: {
                    Label("Share Audio…", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    delete(current)
                } label: {
                    Label("Delete Recording", systemImage: "trash")
                }
            }
            Section {
                Text("Tap your writing to hear what was said as you wrote it (with finger drawing off).")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
        }
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: $audio.rate) {
                ForEach(Self.rates, id: \.self) { rate in
                    Text(Self.rateLabel(rate)).tag(rate)
                }
            }
        } label: {
            Text(Self.rateLabel(audio.rate))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .frame(minWidth: 40)
        }
        .accessibilityLabel("Playback Speed")
    }
}
