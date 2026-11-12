import SwiftUI

/// Settings: AI services, appearance and language, writing, focus sound,
/// transcription, storage and backups, InkPad Pro, and About.
struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var palette: ToolPalette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = AISettings.shared
    @ObservedObject private var looks = FlowLookStore.shared
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(TextInputMode.defaultsKey) private var textInput: TextInputMode = .keyboard
    @AppStorage("pencilOnly") private var pencilOnly = true
    @AppStorage("transcriptionMethod") private var transcription: TranscriptionMethod = .automatic

    @State private var showsAI = false
    @State private var showsBackup = false
    @State private var showsDeleted = false
    @State private var showsThemes = false
    @State private var themeToApply: ThemeRecipe?
    @State private var librarySize: Int64?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ProView()
                    } label: {
                        proBanner
                    }
                }
                aiSection
                appearanceSection
                writingSection
                Section("Focus") {
                    NavigationLink {
                        FocusSoundPicker()
                    } label: {
                        LabeledContent {
                            Text(FocusSounds.title(of: looks.look))
                        } label: {
                            Label("Focus Sound", systemImage: FocusSounds.systemImage(of: looks.look))
                        }
                    }
                }
                Section {
                    Picker(selection: $transcription) {
                        ForEach(TranscriptionMethod.allCases) { Text(tr($0.title)).tag($0) }
                    } label: {
                        Label("Recordings to Text", systemImage: "waveform.badge.magnifyingglass")
                    }
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("Automatic tries this iPad, then Apple's free speech service, then your AI service if the AI Firewall allows the note.")
                }
                storageSection
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About InkPad", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsAI) { AISettingsView() }
            .sheet(isPresented: $showsBackup) { BackupView() }
            .sheet(isPresented: $showsDeleted) { RecentlyDeletedView() }
            .sheet(isPresented: $showsThemes, onDismiss: applyTheme) {
                ThemeView { themeToApply = $0 }
            }
            .task { await measureLibrary() }
        }
    }

    // MARK: Sections

    private var proBanner: some View {
        HStack(spacing: 14) {
            AppBadge(size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("InkPad Pro").font(.headline)
                Text("Every feature is free for now. See what Pro will include.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var aiSection: some View {
        Section {
            Button {
                showsAI = true
            } label: {
                LabeledContent {
                    Text(ai.isReady ? ai.summary : tr("Not connected"))
                        .foregroundStyle(ai.isReady ? Color.secondary : Color.orange)
                } label: {
                    Label("AI Services", systemImage: "sparkles")
                }
            }
            .foregroundStyle(Color.primary)
            NavigationLink {
                AIFirewallView()
            } label: {
                Label("AI Firewall", systemImage: "lock.shield")
            }
        } header: {
            Text("AI")
        } footer: {
            Text("Connect Claude, ChatGPT, Gemini, OpenRouter, Groq, DeepSeek, Mistral or Apple Intelligence once; every AI feature in the app uses it. The AI Firewall decides which notes AI may read.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker(selection: $appearance) {
                ForEach(AppAppearance.allCases) { Label(tr($0.title), systemImage: $0.symbol).tag($0) }
            } label: {
                Label("Appearance", systemImage: appearance.symbol)
            }
            Picker(selection: Binding(
                get: { LanguageSettings.shared.language },
                set: { new in DispatchQueue.main.async { LanguageSettings.shared.set(new) } }
            )) {
                ForEach(AppLanguage.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Label("Language", systemImage: "globe")
            }
            Button {
                showsThemes = true
            } label: {
                Label("Themes", systemImage: "paintbrush")
            }
        }
    }

    private var writingSection: some View {
        Section("Writing") {
            Toggle(isOn: Binding(get: { !pencilOnly }, set: { pencilOnly = !$0 })) {
                Label("Draw with Finger", systemImage: "hand.draw")
            }
            Picker(selection: Binding(get: { textInput }, set: { TextInputMode.set($0) })) {
                Text("Opens the Keyboard").tag(TextInputMode.keyboard)
                Text("Handwriting to Text").tag(TextInputMode.pencil)
            } label: {
                Label("Pencil in Text Fields", systemImage: "pencil.and.scribble")
            }
            NavigationLink {
                PenPresetsEditor()
            } label: {
                Label("Pens & Palettes", systemImage: "swatchpalette")
            }
            NavigationLink {
                GestureSettingsView()
            } label: {
                Label("Gestures", systemImage: "hand.tap")
            }
            NavigationLink {
                HandwritingSettingsView()
            } label: {
                Label("Refine Handwriting", systemImage: "wand.and.stars")
            }
        }
    }

    private var storageSection: some View {
        Section {
            LabeledContent {
                if let librarySize {
                    Text(ByteCountFormatter.string(fromByteCount: librarySize, countStyle: .file))
                } else {
                    ProgressView()
                }
            } label: {
                Label("Library", systemImage: "internaldrive")
            }
            LabeledContent {
                Text("\(store.notes.count)")
            } label: {
                Label("Notes", systemImage: "doc.on.doc")
            }
            Button {
                showsBackup = true
            } label: {
                Label("Backup & Restore", systemImage: "externaldrive.badge.icloud")
            }
            Button {
                showsDeleted = true
            } label: {
                Label("Recently Deleted", systemImage: "trash")
            }
        } header: {
            Text("Storage")
        }
    }

    // MARK: Actions

    private func applyTheme() {
        guard let recipe = themeToApply else { return }
        themeToApply = nil
        DispatchQueue.main.async { ThemeSettings.shared.apply(recipe) }
    }

    private func measureLibrary() async {
        let root = LibraryStore.defaultRootURL
        librarySize = await Task.detached(priority: .utility) { Self.size(of: root) }.value
    }

    private nonisolated static func size(of folder: URL) -> Int64 {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in items {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}

/// The app's mark: a pen nib on the accent gradient.
struct AppBadge: View {
    var size: CGFloat = 80

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color.inkAccent, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .shadow(color: .black.opacity(0.15), radius: size * 0.08, y: size * 0.04)
    }
}

/// About InkPad: version, what it is, privacy, and credits.
struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return short + " (" + build + ")"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    AppBadge(size: 96)
                    Text("InkPad").font(.title.bold())
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("A free, private note app for iPad: handwriting, PDFs, audio, study tools and focus, all on your iPad.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
            Section("Privacy") {
                Label("Your notes stay on this iPad. Nothing is uploaded unless you choose an AI service or a backup location.", systemImage: "hand.raised")
                Label("AI only reads what the AI Firewall allows, with your own key.", systemImage: "lock.shield")
                Label("No accounts, no ads, no tracking.", systemImage: "eye.slash")
            }
            Section("Made With") {
                Label("SwiftUI, PencilKit, PDFKit, Vision and Speech", systemImage: "swift")
                Label("Focus sounds: CC0 recordings from Wikimedia Commons (Sounds/CREDITS.txt)", systemImage: "music.note")
            }
            Section {
                Link(destination: URL(string: "https://github.com/Mg554/InkPad")!) {
                    Label("InkPad on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// InkPad Pro: the plans, shown for later. Payments need Apple's paid
/// developer program, so every feature stays free for now.
struct ProView: View {
    private struct Plan: Identifiable {
        let id: String
        let name: String
        let price: String
        let note: String
        let tint: Color
    }

    private let plans: [Plan] = [
        Plan(id: "free", name: "Free", price: "0", note: "Everything you use today", tint: .gray),
        Plan(id: "monthly", name: "Pro Monthly", price: "$2.99", note: "Per month", tint: .blue),
        Plan(id: "yearly", name: "Pro Yearly", price: "$19.99", note: "Per year · 2 months free", tint: .purple),
        Plan(id: "lifetime", name: "Lifetime", price: "$49.99", note: "Once", tint: .orange),
    ]

    private let features: [(String, String)] = [
        ("Sync between your devices", "arrow.triangle.2.circlepath"),
        ("Unlimited sticker and sound packs", "seal"),
        ("Premium covers and themes", "paintpalette"),
        ("Priority AI tools for study", "sparkles"),
        ("Early access to new features", "star"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    AppBadge(size: 84)
                    Text("InkPad Pro").font(.largeTitle.bold())
                    Text("Support InkPad and get more when Pro arrives.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(features, id: \.0) { feature in
                        Label(tr(feature.0), systemImage: feature.1)
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    ForEach(plans) { plan in
                        VStack(spacing: 6) {
                            Text(tr(plan.name)).font(.headline)
                            Text(verbatim: plan.price).font(.title.bold()).foregroundStyle(plan.tint)
                            Text(tr(plan.note)).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 18).fill(plan.tint.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(plan.tint.opacity(0.4), lineWidth: plan.id == "free" ? 2 : 1))
                    }
                }
                .frame(maxWidth: 760)
                Button {} label: {
                    Label("Every Feature Is Free Right Now", systemImage: "gift")
                        .frame(maxWidth: 360)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)
                Text("Paying inside the app needs Apple's paid developer program, which InkPad doesn't use yet. Until then you have everything for free.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("InkPad Pro")
        .navigationBarTitleDisplayMode(.inline)
    }
}
