import SwiftUI

/// Voice → Timeline: a recording's chapters and transcript. Tap a chapter or
/// a line to play from there; search for a word (like "PEEP") to jump to
/// where it was said.
struct RecordingTimelineView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject var audio: AudioController
    @ObservedObject private var ai = AISettings.shared
    let recording: AudioRecording
    let noteID: UUID

    @State private var transcript: AudioTranscript?
    @State private var language = Transcriber.languages.first?.identifier ?? Locale.current.identifier
    @State private var stage: String?
    @State private var error: String?
    @State private var search = ""
    @State private var showsTranscript = false
    @State private var task: Task<Void, Never>?

    private var audioURL: URL {
        store.audioDirectory(for: noteID).appendingPathComponent(recording.file)
    }

    /// Whether the connected AI may write chapters for this note (AI Firewall).
    private var aiMayWriteChapters: Bool {
        ai.isReady && store.mayUseAI(noteID, onDevice: ai.provider.isOnDevice)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let transcript {
                    timeline(transcript)
                } else {
                    start
                }
            }
            .navigationTitle(recording.title)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if let stage {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(stage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 480, idealHeight: 600)
        .onAppear { transcript = store.transcript(of: recording, in: noteID) }
        .onDisappear { task?.cancel() }
    }

    // MARK: Before transcribing

    private var start: some View {
        Form {
            Section {
                Label {
                    Text("Turn this recording into text on this iPad, with chapters you can jump to. The audio never leaves the iPad.")
                } icon: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .foregroundStyle(.purple)
                }
            }
            Section("Language Spoken") {
                let languages = Transcriber.languages
                if languages.isEmpty {
                    Text("No language can be recognized on this iPad yet. Add one in Settings › General › Keyboard › Dictation Languages.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Language", selection: $language) {
                        ForEach(languages, id: \.identifier) { locale in
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                .tag(locale.identifier)
                        }
                    }
                }
            }
            Section {
                Button {
                    transcribe()
                } label: {
                    Label("Make Timeline", systemImage: "list.bullet.below.rectangle")
                }
                .disabled(stage != nil || Transcriber.languages.isEmpty)
            } footer: {
                Text(aiMayWriteChapters
                    ? "Chapters are named by \(ai.provider.title)."
                    : "Chapters are outlined on this iPad. Connect an AI service (allowed by the AI Firewall) for named topics.")
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Timeline

    private func timeline(_ transcript: AudioTranscript) -> some View {
        let isCurrent = audio.current?.id == recording.id
        let playing = isCurrent ? transcript.chapter(at: audio.playbackTime) : nil
        return List {
            if search.isEmpty {
                Section {
                    ForEach(transcript.chapters) { chapter in
                        Button {
                            jump(to: chapter.start)
                        } label: {
                            HStack(spacing: 12) {
                                Text(AudioClock.string(chapter.start))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(chapter.title)
                                    .font(.body.weight(chapter == playing ? .bold : .regular))
                                    .foregroundStyle(chapter == playing ? Color.accentColor : Color.primary)
                                Spacer()
                                if chapter == playing {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Chapters")
                        Spacer()
                        Text(transcript.chaptersByAI ? "Named by AI" : "Outlined on this iPad")
                            .textCase(nil)
                    }
                } footer: {
                    if aiMayWriteChapters {
                        Button {
                            writeChapters(for: transcript)
                        } label: {
                            Label(transcript.chaptersByAI ? "Name Chapters Again" : "Name Chapters with AI", systemImage: "sparkles")
                                .font(.footnote.weight(.semibold))
                        }
                        .disabled(stage != nil)
                    }
                }

                Section {
                    DisclosureGroup("Transcript", isExpanded: $showsTranscript) {
                        ForEach(transcript.phrases) { phrase in
                            phraseRow(phrase)
                        }
                    }
                }
            } else {
                let found = transcript.phrases(matching: search)
                Section(found.isEmpty ? "Not said in this recording" : "\(found.count) found") {
                    ForEach(found) { phrase in
                        phraseRow(phrase)
                    }
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Jump to a word")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        self.transcript = nil
                    } label: {
                        Label("Transcribe Again…", systemImage: "arrow.clockwise")
                    }
                    Button {
                        UIPasteboard.general.string = transcript.text
                    } label: {
                        Label("Copy Transcript", systemImage: "doc.on.doc")
                    }
                    Button {
                        saveAsNote(transcript)
                    } label: {
                        Label("Save as Text Note", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func phraseRow(_ phrase: AudioTranscript.Phrase) -> some View {
        Button {
            jump(to: phrase.start)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(AudioClock.string(phrase.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                Text(phrase.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .tint(.primary)
    }

    // MARK: Actions

    private func jump(to time: TimeInterval) {
        if audio.current?.id != recording.id {
            audio.open(recording, in: store.audioDirectory(for: noteID))
        }
        audio.seek(to: max(time - 0.5, 0))
        if !audio.isPlaying { audio.togglePlayback() }
    }

    private func transcribe() {
        error = nil
        stage = "Listening to the recording…"
        let url = audioURL
        let locale = Locale(identifier: language)
        task = Task {
            do {
                let phrases = try await Transcriber.transcribe(url, locale: locale)
                var made = AudioTranscript(
                    language: locale.identifier,
                    phrases: phrases,
                    chapters: Transcriber.outlineChapters(phrases, duration: recording.duration),
                    chaptersByAI: false
                )
                store.saveTranscript(made, of: recording, in: noteID)
                transcript = made
                if aiMayWriteChapters, let named = await namedChapters(for: made) {
                    made.chapters = named
                    made.chaptersByAI = true
                    store.saveTranscript(made, of: recording, in: noteID)
                    transcript = made
                }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            stage = nil
        }
    }

    private func writeChapters(for current: AudioTranscript) {
        error = nil
        task = Task {
            if let named = await namedChapters(for: current) {
                var updated = current
                updated.chapters = named
                updated.chaptersByAI = true
                store.saveTranscript(updated, of: recording, in: noteID)
                transcript = updated
            }
        }
    }

    /// Chapters named by the connected AI, if the AI Firewall allows it.
    private func namedChapters(for transcript: AudioTranscript) async -> [AudioTranscript.Chapter]? {
        guard let client = ai.client(), store.mayUseAI(noteID, onDevice: client.kind.isOnDevice) else { return nil }
        stage = "\(client.kind.title) is naming the chapters…"
        defer { stage = nil }
        do {
            let reply = try await client.complete(
                system: "You split lecture and meeting transcripts into clear, well named chapters.",
                messages: [AIMessage(.user, StudyAI.chaptersPrompt(transcript, title: recording.title))]
            )
            return try StudyAI.chapters(from: reply)
        } catch {
            if !Task.isCancelled {
                self.error = "The AI couldn't name the chapters (\(error.localizedDescription)), so they are outlined on this iPad."
            }
            return nil
        }
    }

    private func saveAsNote(_ transcript: AudioTranscript) {
        let noteTitle = store.note(noteID)?.title ?? "Note"
        let lines = transcript.chapters.map { chapter -> String in
            let phrases = transcript.phrases.filter { phrase in
                phrase.start >= chapter.start
                    && phrase.start < (transcript.chapters.first { $0.start > chapter.start }?.start ?? .infinity)
            }
            return "## \(AudioClock.string(chapter.start)) \(chapter.title)\n\n" + phrases.map(\.text).joined(separator: " ")
        }
        let body = ["# \(recording.title)", "From [[\(noteTitle)]] #transcript", ""] + lines
        let folderID = store.note(noteID)?.folderID
        if let note = store.createTextNote(titled: "\(recording.title) (transcript)", in: folderID) {
            store.saveMarkdown(body.joined(separator: "\n\n"), for: note.id)
        }
    }
}
