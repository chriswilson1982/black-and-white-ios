import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: GameSettings
    /// The music volume when Settings opened, restored if the player cancels (the slider
    /// changes the music live so it can be judged by ear).
    private let originalMusicVolume: Float
    @State private var saved = false
    private let onSave: (GameSettings) -> Void
    /// Leaves the game for the title screen. Nil when Settings was opened from the title screen.
    private let onReturnToTitle: (() -> Void)?
    /// The player is signed in to Game Center.
    private let gameCenterAvailable: Bool
    /// Opened during a game: the difficulty can't change until the game ends.
    private let difficultyLocked: Bool

    init(settings: GameSettings, onSave: @escaping (GameSettings) -> Void,
         gameCenterAvailable: Bool = false, difficultyLocked: Bool = false,
         onReturnToTitle: (() -> Void)? = nil) {
        _draft = State(initialValue: settings)
        originalMusicVolume = settings.musicVolume
        self.onSave = onSave
        self.gameCenterAvailable = gameCenterAvailable
        self.difficultyLocked = difficultyLocked
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
                    // Taller segments, for more room around the larger labels.
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .disabled(difficultyLocked)
                } header: {
                    Text("Difficulty")
                } footer: {
                    if difficultyLocked {
                        Text("You can change the difficulty once this game is over, or after restarting.")
                    } else {
                        Text(difficultySummary)
                    }
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
                    Button {
                        draft.resetColors()
                    } label: {
                        Label("Restore default colours", systemImage: "paintpalette.fill")
                    }
                } header: {
                    Text("Colours")
                } footer: {
                    Text("Pick a colour scheme, then fine-tune any colour if you like.")
                }

                if UIApplication.shared.supportsAlternateIcons {
                    Section {
                        AppIconPicker()
                    } header: {
                        Text("App Icon")
                    } footer: {
                        Text("Changes the icon on your Home Screen straight away.")
                    }
                }

                Section {
                    Toggle("Sound effects", isOn: $draft.soundEnabled)
                    Toggle("Music", isOn: $draft.musicEnabled)
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $draft.musicVolume, in: 0...1)
                            .accessibilityLabel("Music volume")
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!draft.musicEnabled)
                    .onChange(of: draft.musicVolume) { _, volume in
                        MusicPlayer.shared.level = volume
                    }
                }

                if gameCenterAvailable {
                    Section {
                        // Opens the same dashboard as the access point on the title screen.
                        Button {
                            GameCenter.shared.showDashboard()
                        } label: {
                            Label {
                                Text("Open Game Center Dashboard")
                            } icon: {
                                // A template image, so it takes the button's tint like the other icons.
                                Image("gameCenterBlack")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
                            }
                        }
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
                            saved = true
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

                // Credit for the music (not required by its licence, but deserved).
                Section {
                } footer: {
                    Text("Music: [On Synthwave by Janevo](https://janevo.itch.io/synthwave-retrowave-music-pack)")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
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
                        saved = true
                        onSave(draft)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        // Closed without saving (Cancel or a swipe down): undo the live volume change. On the
        // whole sheet, so opening the tutorial or help from here doesn't count as closing.
        .onDisappear {
            if !saved { MusicPlayer.shared.level = originalMusicVolume }
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

/// A scrolling row of the app icons, one per colour scheme. Tapping one switches the
/// Home Screen icon (iOS confirms with its own short alert).
private struct AppIconPicker: View {
    /// The alternate icon in use; nil for the main one (Classic).
    @State private var current: String? = UIApplication.shared.alternateIconName

    /// Each scheme's icon name: the main icon for Classic, otherwise "AppIcon-<scheme>".
    private func iconName(for palette: ColorPalette) -> String? {
        palette.name == "Classic" ? nil : "AppIcon-\(palette.name)"
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ColorPalette.all) { palette in
                    let name = iconName(for: palette)
                    let isSelected = name == current
                    Button {
                        choose(name)
                    } label: {
                        VStack(spacing: 6) {
                            AppIconPreview(palette: palette)
                                .frame(width: 60, height: 60)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 60 * 0.225, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                                        .padding(-4)
                                }
                            Text(palette.name)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(palette.name) app icon")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func choose(_ name: String?) {
        guard name != current else { return }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                current = name
            } catch {
                print("Couldn't change the app icon: \(error.localizedDescription)")
            }
        }
    }
}

/// The app icon's design drawn in a scheme's colours: a 3×3 grid of rounded squares on white,
/// laid out like AppIcon.icon (path and locked colours, white and black).
private struct AppIconPreview: View {
    let palette: ColorPalette

    private enum Tile { case lock, path, white, black }

    /// Top row first, as in the Icon Composer design.
    private let rows: [[Tile]] = [
        [.lock, .black, .white],
        [.path, .path, .lock],
        [.black, .path, .path],
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let gap = side * 0.06
            let tile = (side * 0.78 - 2 * gap) / 3
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                VStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { c in
                                RoundedRectangle(cornerRadius: tile * 0.25, style: .continuous)
                                    .fill(color(rows[r][c]))
                                    .overlay {
                                        // The white tile needs an edge to show on the white icon.
                                        if rows[r][c] == .white {
                                            RoundedRectangle(cornerRadius: tile * 0.25, style: .continuous)
                                                .strokeBorder(.black.opacity(0.1), lineWidth: 1)
                                        }
                                    }
                                    .frame(width: tile, height: tile)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func color(_ tile: Tile) -> Color {
        switch tile {
        case .lock: return palette.lockColor.color
        case .path: return palette.pathColor.color
        case .white: return .white
        case .black: return .black
        }
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

    /// Rounded like the game's squares when Rounded squares is on (true quarter circles, as in
    /// `Art.square`), otherwise square.
    private var swatchShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: settings.roundedSquares ? side * Art.cornerFraction : 0,
                         style: .circular)
    }

    private func swatch(_ color: Color) -> some View {
        swatchShape
            .fill(color)
            // A faint edge, so a swatch matching the background (white on light) still shows.
            .overlay(swatchShape
                .strokeBorder(Color(uiColor: settings.textColor).opacity(0.25), lineWidth: 1))
            .frame(width: side, height: side)
            .animation(.easeInOut(duration: 0.2), value: settings.roundedSquares)
    }

    /// The game's own rounded star, drawn the same way as on the grid.
    private var star: some View {
        let art = Art.star(fill: settings.starColor.uiColor, outline: .black, pointSize: side * 0.85)
        let image = UIImage(cgImage: art.texture.cgImage(), scale: Art.displayScale, orientation: .up)
        return Image(uiImage: image)
            .frame(width: side, height: side)
    }
}
