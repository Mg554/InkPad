import AVFoundation
import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers

/// Nature recordings that come with the app (CC0, Sounds/CREDITS.txt).
enum NatureSound: String, CaseIterable, Identifiable {
    case birds, dawn, river, lightrain, forest, waves, cafe, wind

    var id: Self { self }
    var key: String { "nature:" + rawValue }

    var title: String {
        switch self {
        case .birds: "Birds in a Garden"
        case .dawn: "Birds at Dawn"
        case .river: "River"
        case .lightrain: "Light Rain"
        case .forest: "Forest"
        case .waves: "Waves and Gulls"
        case .cafe: "Café"
        case .wind: "Wind"
        }
    }

    var systemImage: String {
        switch self {
        case .birds, .dawn: "bird"
        case .river: "drop"
        case .lightrain: "cloud.drizzle"
        case .forest: "tree"
        case .waves: "water.waves"
        case .cafe: "cup.and.saucer"
        case .wind: "wind"
        }
    }

    /// The file inside the app. Swift Playgrounds and Xcode put copied
    /// resources in different bundles, so every bundle is searched.
    var url: URL? {
        let name = rawValue
        var bundles: [Bundle] = [Bundle.main]
        if let resources = Bundle.main.resourceURL,
           let items = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil) {
            for item in items where item.pathExtension == "bundle" {
                if let bundle = Bundle(url: item) { bundles.append(bundle) }
            }
        }
        bundles += Bundle.allBundles
        for bundle in bundles {
            if let found = bundle.url(forResource: name, withExtension: "m4a", subdirectory: "Sounds") { return found }
            if let found = bundle.url(forResource: name, withExtension: "m4a") { return found }
        }
        return nil
    }
}

/// A sound the owner added (from Files or the music library).
struct OwnSound: Codable, Identifiable, Hashable {
    let file: String
    var name: String
    var id: String { file }
    var key: String { "mine:" + file }
}

/// What plays while focusing: a nature recording, the owner's own sound,
/// or one made on the iPad (`AmbientSound`).
@MainActor
enum FocusSounds {
    private static var player: AVAudioPlayer?
    private static var playingURL: URL?

    static func url(for key: String) -> URL? {
        if key.hasPrefix("nature:") {
            return NatureSound(rawValue: String(key.dropFirst(7)))?.url
        }
        if key.hasPrefix("mine:") {
            let file = String(key.dropFirst(5))
            guard isPlainFileName(file) else { return nil }
            let url = OwnSoundStore.shared.directory.appendingPathComponent(file)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return nil
    }

    static func play(_ look: FlowLook) {
        if let key = look.soundKey, let url = url(for: key) {
            AmbientSound.shared.stop()
            playFile(url, volume: Float(look.volume))
        } else {
            stopFile()
            AmbientSound.shared.play(look.ambient, volume: Float(look.volume))
        }
    }

    static func stop() {
        stopFile()
        AmbientSound.shared.stop()
    }

    static func setVolume(_ volume: Float) {
        player?.volume = volume
        AmbientSound.shared.volume = volume
    }

    private static func playFile(_ url: URL, volume: Float) {
        if playingURL == url, let player {
            player.volume = volume
            if !player.isPlaying { player.play() }
            return
        }
        stopFile()
        let session = AVAudioSession.sharedInstance()
        // Never take over a recording (it uses play-and-record); just mix in.
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, options: [.mixWithOthers])
        }
        try? session.setActive(true)
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        newPlayer.numberOfLoops = -1
        newPlayer.volume = volume
        newPlayer.prepareToPlay()
        newPlayer.play()
        player = newPlayer
        playingURL = url
    }

    private static func stopFile() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    static func title(of look: FlowLook) -> String {
        if let key = look.soundKey {
            if let nature = NatureSound.allCases.first(where: { $0.key == key }) { return tr(nature.title) }
            if let own = OwnSoundStore.shared.sounds.first(where: { $0.key == key }) { return own.name }
        }
        return tr(look.ambient.title)
    }

    static func systemImage(of look: FlowLook) -> String {
        if let key = look.soundKey {
            if let nature = NatureSound.allCases.first(where: { $0.key == key }) { return nature.systemImage }
            return "music.note"
        }
        return look.ambient.systemImage
    }
}

/// The owner's own focus sounds, kept in `FocusSounds/` next to the library.
@MainActor
final class OwnSoundStore: ObservableObject {
    static let shared = OwnSoundStore()

    @Published private(set) var sounds: [OwnSound] = []
    let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("sounds.json") }

    private init() {
        directory = LibraryStore.defaultRootURL.appendingPathComponent("FocusSounds", isDirectory: true)
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([OwnSound].self, from: data) {
            sounds = saved
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(sounds) { try? data.write(to: indexURL, options: .atomic) }
    }

    /// Reads the list again (after a sync).
    func reload() {
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder().decode([OwnSound].self, from: data) {
            sounds = saved
        }
    }

    /// Copies an audio file in; returns the new sound.
    @discardableResult
    func add(fileAt url: URL, name: String) -> OwnSound? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let file = UUID().uuidString + "." + ext
        do {
            try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(file))
        } catch {
            return nil
        }
        let sound = OwnSound(file: file, name: name)
        sounds.append(sound)
        save()
        return sound
    }

    /// A song from the music library, exported to a file. Songs from Apple
    /// Music that are protected or not downloaded can't be used.
    func add(_ item: MPMediaItem) async -> String? {
        guard let assetURL = item.assetURL else {
            return tr("This song is protected or not downloaded to the iPad, so it can't be played here. Choose a song you own that is on the iPad.")
        }
        let name = item.title ?? tr("Song")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = UUID().uuidString + ".m4a"
        let out = directory.appendingPathComponent(file)
        let asset = AVURLAsset(url: assetURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return tr("The song couldn't be read.")
        }
        session.outputURL = out
        session.outputFileType = .m4a
        let box = SoundExportBox(session)
        let done: Bool = await withCheckedContinuation { continuation in
            box.session.exportAsynchronously {
                continuation.resume(returning: box.session.status == .completed)
            }
        }
        guard done else { return tr("The song couldn't be read.") }
        sounds.append(OwnSound(file: file, name: name))
        save()
        return nil
    }

    func rename(_ sound: OwnSound, to name: String) {
        guard let index = sounds.firstIndex(of: sound) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { sounds[index].name = trimmed }
        save()
    }

    func delete(_ sound: OwnSound) {
        if isPlainFileName(sound.file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(sound.file))
        }
        sounds.removeAll { $0 == sound }
        save()
    }
}

private final class SoundExportBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

/// Picks the focus sound: off, nature, made on the iPad, or the owner's own.
struct FocusSoundPicker: View {
    @ObservedObject private var looks = FlowLookStore.shared
    @ObservedObject private var own = OwnSoundStore.shared
    @State private var isPickingFile = false
    @State private var isPickingSong = false
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        List {
            Section {
                row(title: tr("Off"), systemImage: "speaker.slash", isOn: looks.look.soundKey == nil && looks.look.ambient == .off) {
                    looks.look.soundKey = nil
                    looks.look.ambient = .off
                }
            }
            Section("Nature") {
                ForEach(NatureSound.allCases) { sound in
                    row(title: tr(sound.title), systemImage: sound.systemImage, isOn: looks.look.soundKey == sound.key) {
                        looks.look.soundKey = sound.key
                        preview()
                    }
                }
            }
            Section("Made on This iPad") {
                ForEach(FlowLook.Ambient.allCases.filter { $0 != .off }) { ambient in
                    row(title: tr(ambient.title), systemImage: ambient.systemImage, isOn: looks.look.soundKey == nil && looks.look.ambient == ambient) {
                        looks.look.soundKey = nil
                        looks.look.ambient = ambient
                        preview()
                    }
                }
            }
            Section {
                ForEach(own.sounds) { sound in
                    row(title: sound.name, systemImage: "music.note", isOn: looks.look.soundKey == sound.key) {
                        looks.look.soundKey = sound.key
                        preview()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            if looks.look.soundKey == sound.key { looks.look.soundKey = nil }
                            own.delete(sound)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Button {
                    isPickingSong = true
                } label: {
                    Label("Add from Music Library", systemImage: "music.note.list")
                }
                Button {
                    isPickingFile = true
                } label: {
                    Label("Add from Files", systemImage: "folder")
                }
            } header: {
                Text("My Sounds")
            } footer: {
                Text("Songs must be on the iPad and not protected (Apple Music downloads can't be used). Any audio file from Files works.")
            }
        }
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
        }
        .sheet(isPresented: $isPickingFile) {
            DocumentPicker(contentTypes: [.audio]) { urls in
                for url in urls {
                    let name = url.deletingPathExtension().lastPathComponent
                    if let sound = own.add(fileAt: url, name: name) { looks.look.soundKey = sound.key }
                    try? FileManager.default.removeItem(at: url)
                }
                preview()
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isPickingSong) {
            MusicPicker { item in
                isWorking = true
                Task {
                    let problem = await own.add(item)
                    isWorking = false
                    if let problem {
                        message = problem
                    } else if let last = own.sounds.last {
                        looks.look.soundKey = last.key
                        preview()
                    }
                }
            }
            .ignoresSafeArea()
        }
        .alert("Sound", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .onDisappear { FocusSoundController.update() }
    }

    private func row(title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label { Text(verbatim: title) } icon: { Image(systemName: systemImage) }
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(Color.inkAccent) }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(Color.primary)
    }

    /// Plays the choice for a few seconds, then goes back to what the timer wants.
    private func preview() {
        FocusSounds.play(looks.look)
        Task {
            try? await Task.sleep(for: .seconds(5))
            FocusSoundController.update()
        }
    }
}

/// The music library picker (one song).
struct MusicPicker: UIViewControllerRepresentable {
    let picked: (MPMediaItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.prompt = tr("Choose a song to play while focusing")
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let picked: (MPMediaItem) -> Void

        init(picked: @escaping (MPMediaItem) -> Void) {
            self.picked = picked
        }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems collection: MPMediaItemCollection) {
            if let item = collection.items.first { picked(item) }
            mediaPicker.dismiss(animated: true)
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            mediaPicker.dismiss(animated: true)
        }
    }
}
