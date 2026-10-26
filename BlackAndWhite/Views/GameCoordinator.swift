import Observation
import SwiftUI
import UIKit

/// Connects the SpriteKit scene to the SwiftUI screens (settings, high scores, alerts).
@Observable
final class GameCoordinator: GameSceneDelegate {
    enum Sheet: String, Identifiable {
        case settings, highScores, help
        var id: String { rawValue }
    }

    var settings: GameSettings
    /// The phone is in dark mode (used when Appearance is Automatic).
    var systemIsDark = false

    /// Settings with the background and text colours resolved for the current appearance.
    var effectiveSettings: GameSettings { settings.resolved(systemIsDark: systemIsDark) }
    let scores = HighScoreStore()
    var scene: GameScene?
    /// Colours the background: all four colours while playing, then the path or locked colour.
    var mood: GameMood = .playing
    /// Goes up each round, so the background shuffles where its colours sit.
    var backgroundShuffle = 0
    /// The won round's score breakdown, while its card is showing.
    var roundSummary: RoundSummary?
    /// How the game ended, while the game-over card is showing.
    var gameOverSummary: GameOverSummary?

    var activeSheet: Sheet?
    var confirmingRestart = false
    /// True once the player is signed in to Game Center.
    var gameCenterReady = false
    /// The tutorial is on screen.
    var showingTutorial = false
    /// The home screen is showing; the game starts when the player taps Play.
    var showingHome = true

    /// Settings chosen on the settings screen, applied once it has closed.
    @ObservationIgnored var pendingSettings: GameSettings?
    @ObservationIgnored private var presentedSheet: Sheet?
    @ObservationIgnored private var gameCenterStarted = false
    @ObservationIgnored private var heldForSignIn = false
    /// The player's Game Center nickname, when signed in.
    @ObservationIgnored private var gameCenterAlias: String?
    /// Screen size, safe area and pixel density, kept until the game is created.
    @ObservationIgnored private var layout: (size: CGSize, insets: UIEdgeInsets, displayScale: CGFloat)?
    /// The first-launch tutorial goes straight into the game when it ends; from the home screen
    /// it just returns there.
    @ObservationIgnored private var tutorialStartsGame = false
    @ObservationIgnored private var started = false

    init() {
        settings = GameSettings.load()
        SoundEngine.shared.enabled = settings.soundEnabled
    }

    /// Called once the app appears: signs in to Game Center, and on first launch shows the tutorial.
    func start() {
        guard !started else { return }
        started = true
        if !settings.hasSeenTutorial {
            tutorialStartsGame = true
            showingTutorial = true
        }
        startGameCenter()
    }

    /// Records the screen's size, safe area and pixel density (the game is created with them
    /// when the player taps Play).
    func updateLayout(size: CGSize, insets: UIEdgeInsets, displayScale: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        layout = (size, insets, displayScale)
        if !showingHome && scene == nil { createScene() }
    }

    /// Leaves the home screen and starts a game.
    func play() {
        SoundEngine.shared.play(.button)
        showingHome = false
        if let scene = scene {
            scene.startNewGame()
            scene.setHeld(heldForSignIn)
        } else {
            createScene()
        }
    }

    private func createScene() {
        guard let layout = layout else { return }
        Art.displayScale = layout.displayScale
        let newScene = GameScene(size: layout.size, settings: effectiveSettings, safeInsets: layout.insets)
        newScene.gameDelegate = self
        // If Game Center's sign-in screen is up, the clock waits for it.
        newScene.setHeld(heldForSignIn)
        scene = newScene
    }

    // MARK: Home screen

    func showSettings() {
        SoundEngine.shared.play(.button)
        presentedSheet = .settings
        activeSheet = .settings
    }

    func showHighScores() {
        SoundEngine.shared.play(.button)
        presentedSheet = .highScores
        activeSheet = .highScores
    }

    func showHelp() {
        SoundEngine.shared.play(.button)
        presentedSheet = .help
        activeSheet = .help
    }

    func showTutorial() {
        SoundEngine.shared.play(.button)
        tutorialStartsGame = false
        showingTutorial = true
    }

    private func startGameCenter() {
        guard !gameCenterStarted else { return }
        gameCenterStarted = true
        let gameCenter = GameCenter.shared
        gameCenter.onPresentingSignIn = { [weak self] in
            // Game Center's sign-in screen covers the game: hold the clock until it's done.
            guard let self = self else { return }
            self.heldForSignIn = true
            self.scene?.setHeld(true)
        }
        gameCenter.onAuthenticationFinished = { [weak self] authenticated, alias in
            guard let self = self else { return }
            self.gameCenterReady = authenticated
            self.gameCenterAlias = alias
            if self.heldForSignIn {
                self.heldForSignIn = false
                if self.activeSheet == nil && !self.confirmingRestart && !self.showingTutorial {
                    self.scene?.setHeld(false)
                }
            }
        }
        gameCenter.authenticate()
    }

    /// Light / dark mode changed. With Automatic appearance, the game recolours in place.
    func systemAppearanceChanged(isDark: Bool) {
        guard isDark != systemIsDark else { return }
        systemIsDark = isDark
        if settings.appearance == .system {
            scene?.updateTheme(effectiveSettings)
        }
    }

    func finishTutorial() {
        showingTutorial = false
    }

    /// Runs after the tutorial has closed.
    func tutorialDismissed() {
        settings.hasSeenTutorial = true
        settings.save()
        // After the first-launch tutorial its Play button goes straight into a game;
        // from the home screen it just returns there.
        if tutorialStartsGame {
            tutorialStartsGame = false
            play()
        }
    }

    func showGameCenterLeaderboard(for difficulty: Difficulty) {
        GameCenter.shared.showLeaderboard(for: difficulty)
    }

    func sheetDismissed() {
        guard let sheet = presentedSheet else { return }
        presentedSheet = nil
        switch sheet {
        case .settings:
            // As in the original, leaving settings always starts a fresh game.
            if let newSettings = pendingSettings {
                pendingSettings = nil
                settings = newSettings
                settings.save()
                SoundEngine.shared.enabled = newSettings.soundEnabled
                scene?.apply(settings: effectiveSettings)
            } else {
                scene?.startNewGame()
            }
        case .highScores, .help:
            break
        }
        scene?.setHeld(false)
    }

    func restartConfirmed() {
        scene?.confirmRestart()
    }

    func restartCancelled() {
        scene?.setHeld(false)
    }

    // MARK: GameSceneDelegate

    func gameSceneWantsSettings(_ scene: GameScene) {
        presentedSheet = .settings
        activeSheet = .settings
    }

    func gameSceneWantsHighScores(_ scene: GameScene) {
        presentedSheet = .highScores
        activeSheet = .highScores
    }

    func gameSceneWantsRestartConfirmation(_ scene: GameScene) {
        confirmingRestart = true
    }

    func gameScene(_ scene: GameScene, didChangeMood mood: GameMood) {
        // The scene reports this on every round and rebuild; only a real change restarts the blend.
        guard mood != self.mood else { return }
        self.mood = mood
    }

    func gameSceneDidStartRound(_ scene: GameScene) {
        backgroundShuffle += 1
        dismissRoundSummary()
        dismissGameOverSummary()
    }

    func gameScene(_ scene: GameScene, didFinishRound summary: RoundSummary) {
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { roundSummary = summary }
    }

    func dismissRoundSummary() {
        guard roundSummary != nil else { return }
        withAnimation(.easeIn(duration: 0.35)) { roundSummary = nil }
    }

    func gameScene(_ scene: GameScene, didEndGameWithScore score: Int, level: Int, abandoned: Bool) {
        GameCenter.shared.submit(score: score, difficulty: settings.difficulty)
        let isPersonalBest = scores.record(name: gameCenterAlias ?? settings.username, score: score,
                                           difficulty: settings.difficulty)
        // A restart part-way through goes straight into a new game, so no summary.
        guard !abandoned else { return }
        let summary = GameOverSummary(difficulty: settings.difficulty, level: level, score: score,
                                      isPersonalBest: isPersonalBest, playerName: gameCenterAlias)
        // A short pause, so the failed path can start to fall away first. Skipped if a new
        // game has started in the meantime.
        let round = backgroundShuffle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self = self, self.backgroundShuffle == round, !self.showingHome else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) { self.gameOverSummary = summary }
        }
    }

    func dismissGameOverSummary() {
        guard gameOverSummary != nil else { return }
        withAnimation(.easeIn(duration: 0.35)) { gameOverSummary = nil }
    }
}
