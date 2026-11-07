import SwiftUI

/// Pick a theme, or mix one: colors, accent, glass and paper can each come
/// from a different theme. Fonts for the app and for typing, and card size.
/// Changes show in the preview and apply when you tap Apply.
struct ThemeView: View {
    @ObservedObject private var settings = ThemeSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ThemeSettings.current
    @State private var prompt: NamePrompt?
    /// Called with the theme to apply, once this sheet has closed.
    let apply: (ThemeRecipe) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ThemePreview(recipe: draft)
                        .listRowInsets(EdgeInsets())
                }

                Section("Themes") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 14) {
                        ForEach(ThemePreset.all) { preset in
                            swatch(ThemeRecipe.preset(preset), title: preset.name)
                        }
                        ForEach(settings.saved, id: \.name) { mix in
                            swatch(mix, title: mix.name)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        settings.deleteSaved(mix.name)
                                    } label: {
                                        Label("Delete Mix", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    presetPicker("Colors", systemImage: "paintpalette", selection: $draft.colorsFrom)
                    presetPicker("Accent", systemImage: "drop", selection: $draft.accentFrom)
                    Picker(selection: $draft.backdrop) {
                        ForEach(ThemeRecipe.Backdrop.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Background", systemImage: "square.3.layers.3d")
                    }
                    presetPicker("Paper", systemImage: "doc", selection: $draft.paperFrom)
                    Toggle(isOn: $draft.paperForNewNotes) {
                        Label("New Notes Use This Paper", systemImage: "doc.badge.plus")
                    }
                } header: {
                    Text("Theme Mixer")
                } footer: {
                    Text("Take each part from any theme. Paper: new notes start on the theme's paper, and each note can still change its own (\(draft.paper.title) now).")
                }

                Section {
                    Picker(selection: $draft.season) {
                        ForEach(Season.allCases) { season in
                            Label(season.title, systemImage: season.systemImage).tag(season)
                        }
                    } label: {
                        Label("Scenery", systemImage: "tree")
                    }
                    if draft.season != .none {
                        Toggle(isOn: $draft.animateSeason) {
                            Label(draft.season == .winter ? "Falling Snow" : draft.season == .summer ? "Floating Light" : draft.season == .autumn ? "Falling Leaves" : "Falling Petals",
                                  systemImage: "wind")
                        }
                    }
                } header: {
                    Text("Seasons")
                } footer: {
                    Text("Grass, flowers, leaves or snow at the edges of each screen. Turn the motion off to save battery; it also stops when Reduce Motion is on.")
                }

                Section {
                    if draft.backdrop == .glass {
                        presetPicker("Glass Colors", systemImage: "sparkles", selection: $draft.glassFrom)
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Hue", systemImage: "paintpalette")
                            Slider(value: $draft.glassHue, in: -180...180, step: 5)
                                .background(
                                    LinearGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 0.7, brightness: 1) }, startPoint: .leading, endPoint: .trailing)
                                        .frame(height: 6)
                                        .clipShape(Capsule())
                                        .opacity(0.6)
                                )
                        }
                        sliderRow("Strength", systemImage: "circle.lefthalf.filled", value: $draft.glassStrength, range: 0.1...1, step: 0.05, text: "\(Int(draft.glassStrength * 100))%")
                        sliderRow("Blur", systemImage: "aqi.medium", value: $draft.glassBlur, range: 0...80, step: 2, text: "\(Int(draft.glassBlur))")
                    }
                    Toggle(isOn: $draft.glassCards) {
                        Label("Glass Cards", systemImage: "rectangle.on.rectangle")
                    }
                } header: {
                    Text("Glass")
                } footer: {
                    Text(draft.backdrop == .glass
                         ? "Hue turns the glass colors around the color wheel. Glass Cards makes tiles and cards frosted, letting the colors show through."
                         : "Choose the Glass background in the Theme Mixer for colors, hue, strength and blur. Glass Cards makes tiles and cards frosted.")
                }

                Section {
                    Picker(selection: $draft.appFont) {
                        ForEach(ThemeRecipe.FontStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    } label: {
                        Label("App Font", systemImage: "textformat")
                    }
                    Picker(selection: $draft.typingFont) {
                        ForEach(ThemeRecipe.FontStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    } label: {
                        Label("Typing Font", systemImage: "keyboard")
                    }
                    Stepper(value: $draft.typingSize, in: 12...32, step: 1) {
                        Label("Typing Size: \(Int(draft.typingSize))", systemImage: "textformat.size")
                    }
                    Text("The quick brown fox — النص المكتوب بلوحة المفاتيح")
                        .font(Font(draft.typingUIFont()))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Text")
                } footer: {
                    Text("The typing font is for text you type with the keyboard: text boxes on pages and text notes.")
                }

                Section("Layout") {
                    Picker(selection: $draft.cardSize) {
                        ForEach(ThemeRecipe.CardSize.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Note Cards", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    Button {
                        prompt = NamePrompt(title: "Save Mix", initialText: "My Theme", confirmTitle: "Save") {
                            settings.save(draft, named: $0)
                            draft.name = $0
                        }
                    } label: {
                        Label("Save This Mix…", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        apply(draft)
                        dismiss()
                    }
                    .disabled(draft == settings.recipe)
                }
            }
            .namePrompt($prompt)
        }
    }

    private func sliderRow(_ title: String, systemImage: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(text).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func presetPicker(_ title: String, systemImage: String, selection: Binding<String>) -> some View {
        Picker(selection: selection) {
            ForEach(ThemePreset.all) { preset in
                Text(preset.name).tag(preset.id)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func swatch(_ recipe: ThemeRecipe, title: String) -> some View {
        let isChosen = recipe == draft || (recipe.name == draft.name && recipe.colorsFrom == draft.colorsFrom)
        return Button {
            var chosen = recipe
            // Fonts and card size stay as chosen; a theme changes colors.
            chosen.appFont = draft.appFont
            chosen.typingFont = draft.typingFont
            chosen.typingSize = draft.typingSize
            chosen.cardSize = draft.cardSize
            chosen.animateSeason = draft.animateSeason
            chosen.glassCards = draft.glassCards
            draft = chosen
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    ThemeBackground(recipe: recipe.still)
                        .frame(height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Circle()
                        .fill(recipe.accent)
                        .frame(width: 18, height: 18)
                        .padding(6)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isChosen ? recipe.accent : Color.secondary.opacity(0.3), lineWidth: isChosen ? 3 : 1)
                )
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A small picture of the app in the theme being made.
struct ThemePreview: View {
    let recipe: ThemeRecipe

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("InkPad").font(.headline)
                ForEach(["All Notes", "Study", "Reminders"], id: \.self) { item in
                    Label(item, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(item == "All Notes" ? recipe.accent : Color.primary)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 130, alignment: .leading)
            .background { ThemeBackground(recipe: recipe, isSidebar: true) }

            ZStack(alignment: .topLeading) {
                ThemeBackground(recipe: recipe)
                VStack(alignment: .leading, spacing: 10) {
                    Text("All Notes").font(.title3.bold())
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: recipe.paper.rgb.red, green: recipe.paper.rgb.green, blue: recipe.paper.rgb.blue))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                                .frame(width: index == 0 ? 60 : 50, height: 72)
                        }
                    }
                    Text("Typed text looks like this")
                        .font(Font(recipe.typingUIFont(size: 14)))
                    Capsule()
                        .fill(recipe.accent)
                        .frame(width: 90, height: 26)
                        .overlay(Text("Button").font(.caption.bold()).foregroundStyle(.white))
                }
                .padding(14)
            }
        }
        .fontDesign(recipe.appFont.design)
        .frame(height: 210)
        .clipped()
    }
}
