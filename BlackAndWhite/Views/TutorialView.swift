import Observation
import SpriteKit
import SwiftUI
import UIKit

/// A short guided tutorial, played on the real game screen with a fixed practice board.
/// Instruction cards sit on top; the clock is held and only the tap each step asks for works.
/// Shown on first launch and from Settings.
struct TutorialView: View {
    let settings: GameSettings
    /// Called when the tutorial ends. If nil, the view dismisses itself (when pushed from Settings).
    var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tutorial = TutorialController()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ZStack {
                    // Exactly the game's own background and scene.
                    GameBackground(mood: tutorial.mood, shuffle: tutorial.backgroundShuffle, settings: settings)
                    if let scene = tutorial.scene {
                        SpriteView(scene: scene, options: [.ignoresSiblingOrder, .allowsTransparency])
                    }
                }
                .ignoresSafeArea()

                // The same round score card as the game.
                if let summary = tutorial.roundSummary {
                    RoundSummaryCard(summary: summary, settings: settings) { tutorial.dismissRoundSummary() }
                        .id(summary.id)
                        .transition(.roundSummary(reduceMotion: reduceMotion))
                }

                // The card stays inside the safe area, clear of the notch and home indicator.
                VStack {
                    if !tutorial.step.cardAtTop { Spacer() }
                    card
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 560)
                    if tutorial.step.cardAtTop { Spacer() }
                }
            }
            .onAppear {
                let insets = proxy.safeAreaInsets
                let fullSize = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                      height: proxy.size.height + insets.top + insets.bottom)
                Art.displayScale = displayScale
                tutorial.prepare(size: fullSize,
                                 insets: UIEdgeInsets(top: insets.top, left: insets.leading,
                                                      bottom: insets.bottom, right: insets.trailing),
                                 settings: settings)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .animation(.easeInOut(duration: 0.25), value: tutorial.step)
        .animation(.easeInOut(duration: 0.25), value: tutorial.hint)
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    ForEach(TutorialController.Step.allCases, id: \.rawValue) { s in
                        Circle()
                            .fill(.primary.opacity(s.rawValue <= tutorial.step.rawValue ? 1 : 0.2))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
                Spacer()
                if tutorial.step != .ready {
                    Button("Skip") { finish() }
                        .font(.subheadline.weight(.semibold))
                }
            }

            Text(tutorial.step.title)
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let hint = tutorial.hint {
                Text(hint)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(settings.pathColor.color)
                    .transition(.opacity)
            }

            switch tutorial.step {
            case .goal:
                primaryButton("Next") { tutorial.advance(to: .tap) }
            case .scored:
                primaryButton("Next") { tutorial.advance(to: .powerups) }
            case .powerups:
                primaryButton("Next") { tutorial.advance(to: .ready) }
            case .ready:
                primaryButton("Play") { finish() }
            case .tap, .commit:
                // The next move happens on the game screen itself.
                EmptyView()
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .id(tutorial.step)
        .transition(.opacity)
    }

    private var message: String {
        switch tutorial.step {
        case .goal:
            return "Make an unbroken line of white squares from the start on the left to the finish "
                + "on the right. Squares join through their edges, not their corners."
        case .tap:
            return "Tapping a square locks it and flips the colour of the eight squares around it. "
                + "Tap the highlighted square."
        case .commit:
            return "The path is clear! Tap the ✓ button below to test it. In a real game this happens "
                + "automatically when the timer runs out."
        case .scored:
            if let r = tutorial.result {
                return "+\(r.pathCount) for squares in the path, −\(r.leftoverWhites) for white squares left over "
                    + "and −\(r.lockedCount) for locked squares: \(r.total) this round. Use as many squares as you "
                    + "can and tap as few as possible. Score zero or less and the next grid is a tricky 4×4."
            }
            return "Use as many squares as you can in the path and tap as few as possible."
        case .powerups:
            return "The buttons at the top are power-ups: flip all squares, unlock a square you tapped, "
                + "and flip one square on its own. You start with a few of each; get a star into your path "
                + "to earn more."
        case .ready:
            return "The clock gets quicker every level. After each round, tap the timer or the arrow to carry on. "
                + "You can replay this tutorial from Settings."
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.primary)
        .foregroundStyle(Color(uiColor: .systemBackground))
    }

    private func finish() {
        SoundEngine.shared.play(.button)
        if let onFinish = onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }
}

/// Runs the tutorial: owns the practice scene, moves through the steps and reacts to what the
/// player does on the game screen.
@Observable
final class TutorialController: GameSceneDelegate {
    enum Step: Int, CaseIterable {
        case goal, tap, commit, scored, powerups, ready

        var title: String {
            switch self {
            case .goal: return "Clear a path"
            case .tap: return "Tap to flip"
            case .commit: return "Test your path"
            case .scored: return "Scoring"
            case .powerups: return "Power-ups"
            case .ready: return "You're ready!"
            }
        }

        /// The card goes where it won't hide what the step is about: at the top while the ✓
        /// button and score matter, at the bottom while the grid and power-ups do.
        var cardAtTop: Bool {
            self == .commit || self == .scored
        }
    }

    private(set) var step: Step = .goal
    private(set) var scene: GameScene?
    private(set) var mood: GameMood = .playing
    private(set) var backgroundShuffle = 0
    /// The practice round's score breakdown, while its card is showing.
    private(set) var roundSummary: RoundSummary?
    private(set) var hint: String?
    private(set) var result: RoundResult?

    /// One tap here clears row 1: the path then scores 5 - 3 leftover whites - 1 locked = 1 point.
    private static let target = GridPoint(row: 0, col: 1)

    private static func makeBoard() -> Board {
        let rows = ["WBWB", "BBBW", "BWBB", "WBWW"]
        let tones = rows.flatMap { row in row.map { $0 == "B" ? Tone.black : Tone.white } }
        return Board(rows: 4, cols: 4, startRow: 1, finishRow: 1, tones: tones)
    }

    func prepare(size: CGSize, insets: UIEdgeInsets, settings: GameSettings) {
        guard scene == nil, size.width > 0, size.height > 0 else { return }
        let newScene = GameScene(size: size, settings: settings, safeInsets: insets,
                                 tutorialBoard: Self.makeBoard())
        newScene.gameDelegate = self
        newScene.onTutorialEvent = { [weak self] event in self?.handle(event) }
        scene = newScene
    }

    func advance(to next: Step) {
        SoundEngine.shared.play(.button)
        hint = nil
        step = next
        switch next {
        case .tap:
            scene?.tutorialGate = .square(Self.target)
        case .commit:
            scene?.tutorialGate = .commitButton
        case .goal, .scored, .powerups, .ready:
            scene?.tutorialGate = .nothing
        }
    }

    private func handle(_ event: GameScene.TutorialEvent) {
        switch event {
        case .tapped:
            hint = nil
            scene?.tutorialGate = .nothing
            // Let the flips play out before moving on.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self = self, self.step == .tap else { return }
                self.step = .commit
                self.scene?.tutorialGate = .commitButton
            }
        case .blocked:
            switch step {
            case .tap: hint = "Tap the highlighted square."
            case .commit: hint = "Now tap the ✓ button."
            default: break
            }
        case .won(let outcome):
            result = outcome
            hint = nil
            step = .scored
        }
    }

    // MARK: GameSceneDelegate

    func gameScene(_ scene: GameScene, didChangeMood mood: GameMood) {
        guard mood != self.mood else { return }
        self.mood = mood
    }

    func gameSceneDidStartRound(_ scene: GameScene) {
        backgroundShuffle += 1
        roundSummary = nil
    }

    func gameScene(_ scene: GameScene, didFinishRound summary: RoundSummary) {
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { roundSummary = summary }
    }

    func dismissRoundSummary() {
        withAnimation(.easeIn(duration: 0.35)) { roundSummary = nil }
    }

    // The tutorial has no settings, high scores or restarts, and never records a score.
    func gameSceneWantsSettings(_ scene: GameScene) {}
    func gameSceneWantsHighScores(_ scene: GameScene) {}
    func gameSceneWantsRestartConfirmation(_ scene: GameScene) {}
    func gameScene(_ scene: GameScene, didEndGameWithScore score: Int, level: Int, abandoned: Bool) {}
}
