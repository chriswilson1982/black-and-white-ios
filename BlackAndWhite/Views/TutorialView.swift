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

                // The card fills the gap between the power-ups and the grid, so it never covers
                // the grid or the controls. The frame is in full-screen coordinates, like the scene.
                Color.clear
                    .overlay(alignment: .topLeading) {
                        let frame = tutorial.cardFrame
                        if frame.height > 0 {
                            card(maxHeight: frame.height)
                                .frame(width: frame.width)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                    .ignoresSafeArea()
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

    /// The instruction card, scrolling if its text doesn't fit the space (on small phones,
    /// or with large text).
    private func card(maxHeight: CGFloat) -> some View {
        ViewThatFits(in: .vertical) {
            cardContent
            ScrollView { cardContent }
        }
        .frame(maxHeight: max(maxHeight - 32, 0))
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .id(tutorial.step)
        .transition(.opacity)
    }

    private var cardContent: some View {
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
            case .tap, .flipOne, .unlock, .commit:
                // The next move happens on the game screen itself.
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        switch tutorial.step {
        case .goal:
            return "Make an unbroken line of white squares from the start on the left to the finish "
                + "on the right. Squares join through their edges, not their corners."
        case .tap:
            return "Tapping a square locks it and flips the colour of the eight squares around it. "
                + "Tap the highlighted square."
        case .flipOne:
            return "The path is clear, but the white squares at the bottom are cut off. This power-up flips "
                + "one square without touching its neighbours. Tap it, then the highlighted square."
        case .unlock:
            return "Every locked square costs a point. This power-up unlocks a square you tapped, without "
                + "flipping anything else. Tap it, then the locked square."
        case .commit:
            return "Every white square is in the path now. Tap the ✓ button below to test it. In a real game "
                + "this happens automatically when the timer runs out."
        case .scored:
            let total = tutorial.result.map { "You scored \($0.total): " } ?? "You score "
            return total + "a point for each square in the path, minus one for each white square left over "
                + "and each locked square, plus a bonus for leaving no white squares at all. "
                + "Score zero or less and the next grid is a tricky 4×4."
        case .powerups:
            return "The first power-up flips every square on the grid at once. You start each game with "
                + "a few of each power-up (fewer on harder difficulties); get a star into your path to earn more."
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
        case goal, tap, flipOne, unlock, commit, scored, powerups, ready

        var title: String {
            switch self {
            case .goal: return "Clear a path"
            case .tap: return "Tap to flip"
            case .flipOne: return "Flip one square"
            case .unlock: return "Unlock a square"
            case .commit: return "Test your path"
            case .scored: return "Scoring"
            case .powerups: return "More power-ups"
            case .ready: return "You're ready!"
            }
        }

        /// The step that follows a move on the grid, for the steps that wait for one.
        var nextAfterMove: Step? {
            switch self {
            case .tap: return .flipOne
            case .flipOne: return .unlock
            case .unlock: return .commit
            default: return nil
            }
        }
    }

    private(set) var step: Step = .goal
    private(set) var scene: GameScene?
    /// Where the instruction card goes: between the power-ups and the grid.
    private(set) var cardFrame: CGRect = .zero
    /// The step's power-up has been tapped and is waiting for its square.
    private var armed = false
    private(set) var mood: GameMood = .playing
    private(set) var backgroundShuffle = 0
    /// The practice round's score breakdown, while its card is showing.
    private(set) var roundSummary: RoundSummary?
    private(set) var hint: String?
    private(set) var result: RoundResult?

    /// One tap here clears row 1 (with 3 white squares left cut off at the bottom).
    private static let target = GridPoint(row: 0, col: 1)
    /// Flipping this black square on its own joins the bottom row's whites to the path, so no
    /// white squares are left over. Unlocking `target` afterwards leaves nothing locked either.
    private static let flipTarget = GridPoint(row: 3, col: 1)

    /// What the scene lets the player tap during a step.
    private func gate(for step: Step) -> GameScene.TutorialGate {
        switch step {
        case .tap: return .square(Self.target)
        case .flipOne: return armed ? .square(Self.flipTarget) : .powerup(.flipOne)
        case .unlock: return armed ? .square(Self.target) : .powerup(.unlock)
        case .commit: return .commitButton
        case .goal, .scored, .powerups, .ready: return .nothing
        }
    }

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
        cardFrame = newScene.tutorialCardFrame
    }

    func advance(to next: Step) {
        SoundEngine.shared.play(.button)
        move(to: next)
    }

    private func move(to next: Step) {
        hint = nil
        armed = false
        step = next
        scene?.tutorialGate = gate(for: next)
    }

    private func handle(_ event: GameScene.TutorialEvent) {
        switch event {
        case .armed:
            hint = nil
            armed = true
            scene?.tutorialGate = gate(for: step)
        case .tapped:
            hint = nil
            scene?.tutorialGate = .nothing
            let current = step
            guard let next = current.nextAfterMove else { return }
            // Let the flips play out before moving on.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self = self, self.step == current else { return }
                self.move(to: next)
            }
        case .blocked:
            switch step {
            case .tap: hint = "Tap the highlighted square."
            case .flipOne, .unlock: hint = armed ? "Now tap the highlighted square." : "Tap the highlighted power-up."
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
    func gameSceneWantsStart(_ scene: GameScene) {} // The tutorial starts straight away.
    func gameScene(_ scene: GameScene, didEndGameWithScore score: Int, level: Int, abandoned: Bool) {}
}
