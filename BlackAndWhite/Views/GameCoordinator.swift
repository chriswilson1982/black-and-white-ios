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
    /// A new game is waiting for the player to tap Start.
    var startPrompt: StartPrompt?

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
    /// Settings asked to return to the title screen when it closes.
    @ObservationIgnored private var returnToTitleAfterSettings = false
    /// Settings was opened during a game: the difficulty is locked, and closing it carries on
    /// with the game instead of starting a new one.
    var settingsDuringGame = false

    init() {
        settings = GameSettings.load()
        SoundEngine.shared.enabled = settings.soundEnabled
        MusicPlayer.shared.enabled = settings.musicEnabled
        MusicPlayer.shared.level = settings.musicVolume
    }

    /// Called once the app appears: signs in to Game Center, and on first launch shows the tutorial.
    func start() {
        guard !started else { return }
        started = true
        // Load the music now, so it starts cleanly when the first game does.
        MusicPlayer.shared.prepare()
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
        settingsDuringGame = false
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
            if returnToTitleAfterSettings {
                // Keep any changes, but leave the game for the title screen rather than restarting.
                returnToTitleAfterSettings = false
                settingsDuringGame = false
                if let newSettings = pendingSettings {
                    pendingSettings = nil
                    settings = newSettings
                    settings.save()
                    SoundEngine.shared.enabled = newSettings.soundEnabled
                    MusicPlayer.shared.enabled = newSettings.musicEnabled
                    MusicPlayer.shared.level = newSettings.musicVolume
                    scene?.updateTheme(effectiveSettings)
                }
                returnToTitle()
                return
            }
            if settingsDuringGame {
                // Mid-game: keep playing, with any new colours, sounds or music applied in place
                // (the difficulty couldn't be changed).
                settingsDuringGame = false
                if let newSettings = pendingSettings {
                    pendingSettings = nil
                    settings = newSettings
                    settings.save()
                    SoundEngine.shared.enabled = newSettings.soundEnabled
                    MusicPlayer.shared.enabled = newSettings.musicEnabled
                    MusicPlayer.shared.level = newSettings.musicVolume
                    scene?.updateTheme(effectiveSettings)
                }
                scene?.setHeld(false)
                return
            }
            // Between games, as in the original, leaving settings starts a fresh game.
            if let newSettings = pendingSettings {
                pendingSettings = nil
                settings = newSettings
                settings.save()
                SoundEngine.shared.enabled = newSettings.soundEnabled
                MusicPlayer.shared.enabled = newSettings.musicEnabled
                MusicPlayer.shared.level = newSettings.musicVolume
                scene?.apply(settings: effectiveSettings)
            } else if scene?.awaitingStart != true {
                // (Already waiting at the start card: nothing to set up again.)
                scene?.startNewGame()
            }
        case .highScores, .help:
            break
        }
        scene?.setHeld(false)
    }

    /// Asked for from Settings: go back to the title screen once the sheet has closed.
    func requestReturnToTitle() {
        returnToTitleAfterSettings = true
    }

    /// Leaves the game for the title screen. The game waits, paused; Play starts a fresh one.
    private func returnToTitle() {
        // Leaving the game ends the music, with its outro as on game over; the next game's
        // Start brings it back from the intro.
        MusicPlayer.shared.playOutro()
        scene?.setHeld(true)
        roundSummary = nil
        gameOverSummary = nil
        startPrompt = nil
        mood = .playing
        withAnimation(.easeInOut(duration: 0.3)) { showingHome = true }
    }

    func restartConfirmed() {
        scene?.confirmRestart()
    }

    func restartCancelled() {
        scene?.setHeld(false)
    }

    // MARK: GameSceneDelegate

    func gameSceneWantsSettings(_ scene: GameScene) {
        settingsDuringGame = scene.isGameInProgress
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
        // A game over plays the music's outro (a restart does too, via `gameSceneDidRestart`).
        if !abandoned { MusicPlayer.shared.playOutro() }
        let isPersonalBest = scores.record(name: gameCenterAlias ?? settings.username, score: score,
                                           difficulty: settings.difficulty)
        // A restart part-way through goes straight into a new game, so no summary.
        guard !abandoned else { return }
        let summary = GameOverSummary(difficulty: settings.difficulty, level: level, score: score,
                                      isPersonalBest: isPersonalBest,
                                      personalBest: scores.syncedBest[settings.difficulty]?.score,
                                      playerName: gameCenterAlias)
        // A short pause, so the failed path can start to fall away first. Skipped if a new
        // game has started in the meantime.
        let round = backgroundShuffle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            // Not if a new game has started, or is waiting for Start, in the meantime.
            guard let self = self, self.backgroundShuffle == round, !self.showingHome,
                  self.startPrompt == nil else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) { self.gameOverSummary = summary }
        }
    }

    func gameSceneDidRestart(_ scene: GameScene) {
        // The game ended early: the music finishes with its outro, as on game over, and the
        // next Start brings it back from the intro.
        MusicPlayer.shared.playOutro()
    }

    func gameSceneWantsStart(_ scene: GameScene) {
        gameOverSummary = nil
        let prompt = StartPrompt(difficulty: settings.difficulty,
                                 personalBest: scores.syncedBest[settings.difficulty]?.score)
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { startPrompt = prompt }
    }

    /// The player tapped Start.
    func startGame() {
        guard startPrompt != nil else { return }
        SoundEngine.shared.play(.button)
        withAnimation(.easeIn(duration: 0.3)) { startPrompt = nil }
        // From the intro again, if the last game's outro has played.
        MusicPlayer.shared.start()
        scene?.beginNewGame()
    }

    func dismissGameOverSummary() {
        guard gameOverSummary != nil else { return }
        withAnimation(.easeIn(duration: 0.35)) { gameOverSummary = nil }
    }
}
