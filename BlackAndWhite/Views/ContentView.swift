import SpriteKit
import SwiftUI

struct ContentView: View {
    @State private var coordinator = GameCoordinator()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Frame rate, draw calls, quads and node count in the bottom corner, for performance checks.
    /// Debug builds only: release builds never show them.
    #if DEBUG
    private static let debugOptions: SpriteView.DebugOptions = [.showsFPS, .showsDrawCount, .showsQuadCount, .showsNodeCount]
    #else
    private static let debugOptions: SpriteView.DebugOptions = []
    #endif

    /// Forces light or dark for the menus when the player picked a fixed appearance.
    private var forcedScheme: ColorScheme? {
        switch coordinator.settings.appearance {
        case .light: return .light
        case .dark: return .dark
        case .system, .custom: return nil
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GameBackground(mood: coordinator.mood, shuffle: coordinator.backgroundShuffle,
                               settings: coordinator.effectiveSettings)
                    .ignoresSafeArea()
                if coordinator.showingHome {
                    HomeView(settings: coordinator.effectiveSettings,
                             best: coordinator.scores.syncedBest[coordinator.settings.difficulty],
                             onPlay: { withAnimation(.easeInOut(duration: 0.3)) { coordinator.play() } },
                             onHighScores: { coordinator.showHighScores() },
                             onSettings: { coordinator.showSettings() },
                             onHelp: { coordinator.showHelp() },
                             onTutorial: { coordinator.showTutorial() })
                        .transition(.opacity)
                } else if let scene = coordinator.scene {
                    // Transparent, so the background shows through the scene.
                    SpriteView(scene: scene, options: [.ignoresSiblingOrder, .allowsTransparency],
                               debugOptions: Self.debugOptions)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                if let summary = coordinator.roundSummary, !coordinator.showingHome {
                    RoundSummaryCard(summary: summary, settings: coordinator.effectiveSettings) {
                        coordinator.dismissRoundSummary()
                    }
                    .id(summary.id)
                    .transition(.roundSummary(reduceMotion: reduceMotion))
                }
                if let summary = coordinator.gameOverSummary, !coordinator.showingHome {
                    GameOverCard(summary: summary, settings: coordinator.effectiveSettings) {
                        coordinator.dismissGameOverSummary()
                    }
                    .id(summary.id)
                    .transition(.roundSummary(reduceMotion: reduceMotion))
                }
            }
            .onAppear {
                coordinator.systemAppearanceChanged(isDark: colorScheme == .dark)
                updateLayout(proxy)
                coordinator.start()
            }
            .onChange(of: proxy.size) { _, _ in
                // In case the first layout pass reported a zero size.
                updateLayout(proxy)
            }
            .onChange(of: proxy.safeAreaInsets) { _, newInsets in
                coordinator.scene?.safeInsets = UIEdgeInsets(newInsets)
            }
            .alert("Start again?", isPresented: $coordinator.confirmingRestart) {
                Button("Restart", role: .destructive) { coordinator.restartConfirmed() }
                Button("Cancel", role: .cancel) { coordinator.restartCancelled() }
            } message: {
                Text("Your score will be reset to zero!")
            }
        }
        // Keep the game layout fixed if the keyboard ever appears.
        .ignoresSafeArea(.keyboard)
        .onChange(of: colorScheme) { _, newScheme in
            coordinator.systemAppearanceChanged(isDark: newScheme == .dark)
        }
        .preferredColorScheme(forcedScheme)
        .statusBarHidden()
        .sheet(item: $coordinator.activeSheet, onDismiss: { coordinator.sheetDismissed() }) { sheet in
            Group {
                switch sheet {
                case .settings:
                    SettingsView(settings: coordinator.settings,
                                 onSave: { coordinator.pendingSettings = $0 },
                                 // Only offered from a game; on the title screen there's nowhere to return to.
                                 onReturnToTitle: coordinator.showingHome ? nil : { coordinator.requestReturnToTitle() })
                case .highScores:
                    HighScoresView(store: coordinator.scores, difficulty: coordinator.settings.difficulty,
                                   gameCenterAvailable: coordinator.gameCenterReady,
                                   onShowGameCenter: { coordinator.showGameCenterLeaderboard(for: $0) },
                                   onShowAchievements: { GameCenter.shared.showAchievements() })
                case .help:
                    HelpSheet()
                }
            }
            .fontDesign(.rounded)
        }
        .fullScreenCover(isPresented: $coordinator.showingTutorial,
                         onDismiss: { coordinator.tutorialDismissed() }) {
            TutorialView(settings: coordinator.effectiveSettings) { coordinator.finishTutorial() }
                .fontDesign(.rounded)
        }
    }
}

extension ContentView {
    /// Passes the full-screen size (the view's size plus its safe area) on to the coordinator.
    private func updateLayout(_ proxy: GeometryProxy) {
        let insets = proxy.safeAreaInsets
        let fullSize = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                              height: proxy.size.height + insets.top + insets.bottom)
        coordinator.updateLayout(size: fullSize, insets: UIEdgeInsets(insets), displayScale: displayScale)
    }
}

private extension UIEdgeInsets {
    init(_ insets: EdgeInsets) {
        self.init(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)
    }
}
