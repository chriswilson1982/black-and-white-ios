import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: GameSettings
    private let onSave: (GameSettings) -> Void
    /// Leaves the game for the title screen. Nil when Settings was opened from the title screen.
    private let onReturnToTitle: (() -> Void)?
    /// The player is signed in to Game Center.
    private let gameCenterAvailable: Bool

    init(settings: GameSettings, onSave: @escaping (GameSettings) -> Void,
         gameCenterAvailable: Bool = false, onReturnToTitle: (() -> Void)? = nil) {
        _draft = State(initialValue: settings)
        self.onSave = onSave
        self.gameCenterAvailable = gameCenterAvailable
        self.onReturnToTitle = onReturnToTitle
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Difficulty", selection: $draft.difficulty) {
                        ForEach(Difficulty.allCases) { level in
                            Text(level.name).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Difficulty")
                } footer: {
                    Text(difficultySummary)
                }

                Section {
                    Picker("Appearance", selection: $draft.appearance) {
                        ForEach(ColorTheme.allCases) { option in
                            Text(option.name).tag(option)
                        }
                    }
                    if draft.appearance == .custom {
                        ColorPicker("Background", selection: colorBinding(\.background), supportsOpacity: false)
                        Picker("Text and icons", selection: $draft.whiteText) {
                            Text("Black").tag(false)
                            Text("White").tag(true)
                        }
                    }
                    PalettePicker(selected: draft.palette) { draft.apply($0) }
                    ColorPicker("Locked squares", selection: colorBinding(\.lockColor), supportsOpacity: false)
                    ColorPicker("Path", selection: colorBinding(\.pathColor), supportsOpacity: false)
                    ColorPicker("Bonus star", selection: colorBinding(\.starColor), supportsOpacity: false)
                    Toggle("Rounded squares", isOn: $draft.roundedSquares)
                    ThemePreview(settings: resolvedDraft)
                    Button("Restore default colours") { draft.resetColors() }
                } header: {
                    Text("Colours")
                } footer: {
                    Text("Pick a colour scheme, then fine-tune any colour if you like.")
                }

                Section {
                    Toggle("Sound effects", isOn: $draft.soundEnabled)
                } footer: {
                    Text("Closing settings starts a new game.")
                }

                if gameCenterAvailable {
                    Section {
                        // Opens the same dashboard as the access point on the title screen.
                        Button("Open Game Center Dashboard") { GameCenter.shared.showDashboard() }
                    } header: {
                        GameCenterHeader()
                    }
                }

                Section {
                    NavigationLink("Tutorial") { TutorialView(settings: resolvedDraft) }
                    NavigationLink("How to play") { HelpView() }
                }

                if let onReturnToTitle = onReturnToTitle {
                    Section {
                        Button {
                            onSave(draft)
                            onReturnToTitle()
                            dismiss()
                        } label: {
                            Label("Return to Title Screen", systemImage: "house.fill")
                        }
                    } footer: {
                        Text("Saves your settings and leaves this game.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }

    /// The draft as the game will draw it (Automatic follows the current light / dark mode).
    private var resolvedDraft: GameSettings {
        draft.resolved(systemIsDark: colorScheme == .dark)
    }

    private var difficultySummary: String {
        let powerups = draft.difficulty.startingPowerups
        let seconds = Int(draft.difficulty.timeAllowed(level: 1))
        return "Start with \(powerups) of each power-up and \(seconds) seconds on the clock. "
            + "The clock gets quicker every level."
    }

    private func colorBinding(_ keyPath: WritableKeyPath<GameSettings, RGBA>) -> Binding<Color> {
        Binding(
            get: { draft[keyPath: keyPath].color },
            set: { draft[keyPath: keyPath] = RGBA($0) }
        )
    }
}

/// A scrolling row of the ready-made colour schemes. Tapping one fills in the colour pickers.
private struct PalettePicker: View {
    /// The scheme the current colours match, if any.
    let selected: ColorPalette?
    let onSelect: (ColorPalette) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ColorPalette.all) { palette in
                    let isSelected = palette == selected
                    Button {
                        onSelect(palette)
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                dot(palette.lockColor)
                                dot(palette.pathColor)
                                dot(palette.starColor)
                            }
                            Text(palette.name)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                              lineWidth: isSelected ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(palette.name) colour scheme")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func dot(_ color: RGBA) -> some View {
        Circle()
            .fill(color.color)
            .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
            .frame(width: 18, height: 18)
    }
}

/// A small sample of the grid in the chosen colours.
private struct ThemePreview: View {
    let settings: GameSettings

    private let side: CGFloat = 34

    var body: some View {
        HStack(spacing: 10) {
            swatch(.black)
            swatch(.white.opacity(0.8))
            swatch(settings.lockColor.color)
            swatch(settings.pathColor.color)
            Spacer(minLength: 0)
            star
        }
        .padding(14)
        .background(settings.background.color, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: side * 0.22)
            .fill(color)
            // A faint edge, so a swatch matching the background (white on light) still shows.
            .overlay(RoundedRectangle(cornerRadius: side * 0.22)
                .strokeBorder(Color(uiColor: settings.textColor).opacity(0.25), lineWidth: 1))
            .frame(width: side, height: side)
    }

    /// The game's own rounded star, drawn the same way as on the grid.
    private var star: some View {
        let art = Art.star(fill: settings.starColor.uiColor, outline: .black, pointSize: side * 0.85)
        let image = UIImage(cgImage: art.texture.cgImage(), scale: Art.displayScale, orientation: .up)
        return Image(uiImage: image)
            .frame(width: side, height: side)
    }
}
