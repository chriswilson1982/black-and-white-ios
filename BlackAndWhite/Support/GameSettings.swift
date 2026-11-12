import SwiftUI
import UIKit

/// A colour that can be saved to disk.
struct RGBA: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Double { Double(min(max(v, 0), 1)) }
        self.init(clamp(r), clamp(g), clamp(b), clamp(a))
    }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
    var color: Color { Color(uiColor: uiColor) }
}

/// Light or dark colours for the background and text.
enum ColorTheme: String, Codable, CaseIterable, Identifiable {
    /// Follows the phone's light / dark mode.
    case system
    case light
    case dark
    /// The player's own background and text colours.
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        case .custom: return "Custom"
        }
    }
}

/// A ready-made set of the three accent colours: locked squares, the path and the bonus star.
/// Black and white squares and the background (see `ColorTheme`) aren't part of it, so every
/// palette works in light and dark mode.
struct ColorPalette: Identifiable, Equatable {
    let name: String
    let lockColor: RGBA
    let pathColor: RGBA
    let starColor: RGBA

    var id: String { name }

    static let all: [ColorPalette] = [
        // The original colours (also the defaults).
        ColorPalette(name: "Classic", lockColor: RGBA(1, 0, 0), pathColor: RGBA(0, 1, 0),
                     starColor: RGBA(1, 0.8, 0)),
        ColorPalette(name: "Ocean", lockColor: RGBA(1, 0.42, 0.35), pathColor: RGBA(0, 0.75, 0.85),
                     starColor: RGBA(1, 0.85, 0.2)),
        ColorPalette(name: "Sunset", lockColor: RGBA(0.78, 0.13, 0.42), pathColor: RGBA(1, 0.6, 0.1),
                     starColor: RGBA(1, 0.93, 0.45)),
        ColorPalette(name: "Forest", lockColor: RGBA(0.8, 0.35, 0.15), pathColor: RGBA(0.35, 0.75, 0.3),
                     starColor: RGBA(1, 0.75, 0.1)),
        ColorPalette(name: "Neon", lockColor: RGBA(1, 0.1, 0.6), pathColor: RGBA(0.1, 0.95, 1),
                     starColor: RGBA(0.8, 1, 0.1)),
        ColorPalette(name: "Pastel", lockColor: RGBA(0.95, 0.55, 0.6), pathColor: RGBA(0.55, 0.85, 0.7),
                     starColor: RGBA(1, 0.85, 0.45)),
        // Okabe–Ito colours, which stay distinct for the common forms of colour blindness.
        ColorPalette(name: "Accessible", lockColor: RGBA(0.84, 0.37, 0), pathColor: RGBA(0, 0.45, 0.7),
                     starColor: RGBA(0.94, 0.89, 0.26)),
    ]
}

/// Player settings, saved in UserDefaults.
struct GameSettings: Codable, Equatable {
    var difficulty: Difficulty = .regular
    var username: String = "Player"
    var whiteText: Bool = false
    var background = RGBA(1, 1, 1)
    /// Colour of locked (tapped) squares. "color3" in the original.
    var lockColor = RGBA(1, 0, 0)
    /// Colour of the cleared path. "color4" in the original.
    var pathColor = RGBA(0, 1, 0)
    /// Colour of the bonus star.
    var starColor = RGBA(1, 0.8, 0)
    var soundEnabled = true
    /// The background music track (separate from sound effects).
    var musicEnabled = true
    /// Music loudness from 0 (silent) to 1 (loudest); see `MusicPlayer.level`.
    var musicVolume: Float = 0.5
    var hasChosenName = false
    var hasSeenTutorial = false
    var appearance: ColorTheme = .system
    /// Black squares get rounded corners where they meet other colours, instead of the original solid grid.
    var roundedSquares = true

    init() {}

    enum CodingKeys: String, CodingKey {
        case difficulty, username, whiteText, background, lockColor, pathColor, starColor
        case soundEnabled, musicEnabled, musicVolume, hasChosenName, hasSeenTutorial, appearance, roundedSquares
    }

    static let lightBackground = RGBA(1, 1, 1)
    static let darkBackground = RGBA(0.11, 0.11, 0.12)

    /// The settings with the background and text colour the game should actually use,
    /// given whether the phone is in dark mode.
    func resolved(systemIsDark: Bool) -> GameSettings {
        let dark: Bool
        switch appearance {
        case .custom: return self
        case .light: dark = false
        case .dark: dark = true
        case .system: dark = systemIsDark
        }
        var copy = self
        copy.background = dark ? Self.darkBackground : Self.lightBackground
        copy.whiteText = dark
        return copy
    }

    var textColor: UIColor { whiteText ? .white : .black }

    mutating func resetColors() {
        let defaults = GameSettings()
        appearance = defaults.appearance
        whiteText = defaults.whiteText
        background = defaults.background
        lockColor = defaults.lockColor
        pathColor = defaults.pathColor
        starColor = defaults.starColor
    }

    /// The palette the current accent colours match, or nil if any has been changed by hand.
    var palette: ColorPalette? {
        ColorPalette.all.first {
            $0.lockColor == lockColor && $0.pathColor == pathColor && $0.starColor == starColor
        }
    }

    mutating func apply(_ palette: ColorPalette) {
        lockColor = palette.lockColor
        pathColor = palette.pathColor
        starColor = palette.starColor
    }

    private static let storageKey = "settings.v1"

    static func load() -> GameSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(GameSettings.self, from: data)
        else { return GameSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// Decoding tolerates missing keys, so settings saved by an older version still load
// (any new setting takes its default value).
extension GameSettings {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        difficulty = try c.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? difficulty
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? username
        whiteText = try c.decodeIfPresent(Bool.self, forKey: .whiteText) ?? whiteText
        background = try c.decodeIfPresent(RGBA.self, forKey: .background) ?? background
        lockColor = try c.decodeIfPresent(RGBA.self, forKey: .lockColor) ?? lockColor
        pathColor = try c.decodeIfPresent(RGBA.self, forKey: .pathColor) ?? pathColor
        starColor = try c.decodeIfPresent(RGBA.self, forKey: .starColor) ?? starColor
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? soundEnabled
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? musicEnabled
        musicVolume = try c.decodeIfPresent(Float.self, forKey: .musicVolume) ?? musicVolume
        hasChosenName = try c.decodeIfPresent(Bool.self, forKey: .hasChosenName) ?? hasChosenName
        hasSeenTutorial = try c.decodeIfPresent(Bool.self, forKey: .hasSeenTutorial) ?? hasSeenTutorial
        roundedSquares = try c.decodeIfPresent(Bool.self, forKey: .roundedSquares) ?? roundedSquares
        if let saved = try c.decodeIfPresent(ColorTheme.self, forKey: .appearance) {
            appearance = saved
        } else {
            // Saved before this setting existed: keep any custom colours the player picked.
            let customised = background != Self.lightBackground || whiteText
            appearance = customised ? .custom : .system
        }
    }
}
