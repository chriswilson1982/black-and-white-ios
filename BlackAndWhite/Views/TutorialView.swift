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

                        // The same round score card as the game, below the instruction card
                        // (over the grid, which is finished with by then) so both can be read.
                        if let summary = tutorial.roundSummary {
                            let area = summaryArea(below: frame, screenHeight: fullHeight(proxy),
                                                   bottomInset: proxy.safeAreaInsets.bottom)
                            RoundSummaryCard(summary: summary, settings: settings) { tutorial.dismissRoundSummary() }
                                .frame(width: area.width, height: area.height)
                                .position(x: area.midX, y: area.midY)
                                .id(summary.id)
                                .transition(.roundSummary(reduceMotion: reduceMotion))
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
            .onChange(of: proxy.safeAreaInsets) { _, insets in
                // The scene re-lays itself out (and reports the new card frame) when its size
                // changes; the safe area has to be passed on by hand.
                tutorial.scene?.safeInsets = UIEdgeInsets(top: insets.top, left: insets.leading,
                                                          bottom: insets.bottom, right: insets.trailing)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .animation(.easeInOut(duration: 0.25), value: tutorial.step)
        .animation(.easeInOut(duration: 0.25), value: tutorial.hint)
    }

    private func fullHeight(_ proxy: GeometryProxy) -> CGFloat {
        proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
    }

    /// The space under the instruction card, down to the home indicator, for the score card.
    private func summaryArea(below card: CGRect, screenHeight: CGFloat, bottomInset: CGFloat) -> CGRect {
        let top = card.maxY + 8
        let bottom = screenHeight - max(bottomInset, 8)
        return CGRect(x: card.minX, y: top, width: card.width, height: max(bottom - top, 0))
    }

    // MARK: Card

    /// The instruction card, scrolling if its text doesn't fit the space (on small phones,
    /// or with large text).
    private func card(maxHeight: CGFloat) -> some View {
        // As tall as its text, up to the space available (a plain maxHeight frame would stretch
        // the card to fill all of it).
        HeightCap(maxHeight: max(maxHeight - 32, 0)) {
            ViewThatFits(in: .vertical) {
                cardContent
                ScrollView { cardContent }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .id(tutorial.step)
        .transition(.opacity)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(TutorialController.Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(.primary.opacity(s.rawValue <= tutorial.step.rawValue ? 1 : 0.2))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)

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

            // Bottom right: Leave (ends the whole tutorial), then Next or Play. Steps without
            // Next wait for a move on the game screen itself.
            HStack(spacing: 12) {
                Spacer()
                if tutorial.step != .ready {
                    Button("Leave Tutorial") { finish() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                        .tint(.primary)
                }
                if let next = tutorial.step.nextOnButton {
                    primaryButton("Next") { tutorial.advance(to: next) }
                } else if tutorial.step == .ready {
                    primaryButton("Play") { finish() }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var message: String {
        switch tutorial.step {
        case .goal:
            return "Make a line of white squares from the start on the left to the finish on the right. "
                + "Squares join through their edges, not their corners."
        case .tap:
            return "Tapping a square locks it and flips the eight around it. Tap the highlighted square."
        case .tapAgain:
            return "Tap the highlighted square to finish the path."
        case .flipOne:
            return "A white square is cut off at the bottom left. This power-up flips just one square. "
                + "Tap it, then the highlighted square."
        case .unlock:
            return "Locked squares cost a point each. This power-up unlocks one. "
                + "Tap it, then the highlighted square."
        case .commit:
            return "Tap ✓ to test your path. In a real game this happens when the timer runs out."
        case .scored:
            return "A point for each square in the path, minus one for each white square left over "
                + "and each locked square."
        case .bonuses:
            return "Leave no white squares for a big bonus. Score zero or less and the next grid is a tricky 4×4."
        case .powerups:
            return "The first power-up flips every square. Get a star into your path to earn more power-ups."
        case .ready:
            return "The clock gets quicker every level. After each round, tap the timer or the arrow to carry on."
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
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

/// Offers its content no more than `maxHeight`, then takes the content's own size
/// (unlike `.frame(maxHeight:)`, which grows to fill whatever it's offered up to the limit).
private struct HeightCap: Layout {
    let maxHeight: CGFloat

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width, height: min(proposal.height ?? maxHeight, maxHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Runs the tutorial: owns the practice scene, moves through the steps and reacts to what the
/// player does on the game screen.
@Observable
final class TutorialController: GameSceneDelegate {
    enum Step: Int, CaseIterable {
        case goal, tap, tapAgain, flipOne, unlock, commit, scored, bonuses, powerups, ready

        var title: String {
            switch self {
            case .goal: return "Clear a path"
            case .tap: return "Tap to flip"
            case .tapAgain: return "Keep going"
            case .flipOne: return "Flip one square"
            case .unlock: return "Unlock a square"
            case .commit: return "Test your path"
            case .scored: return "Scoring"
            case .bonuses: return "Bonuses"
            case .powerups: return "More power-ups"
            case .ready: return "You're ready!"
            }
        }

        /// The step that follows a move on the grid, for the steps that wait for one.
        var nextAfterMove: Step? {
            switch self {
            case .tap: return .tapAgain
            case .tapAgain: return .flipOne
            case .flipOne: return .unlock
            case .unlock: return .commit
            default: return nil
            }
        }

        /// The step the card's Next button moves on to, for the steps that have one.
        var nextOnButton: Step? {
            switch self {
            case .goal: return .tap
            case .scored: return .bonuses
            case .bonuses: return .powerups
            case .powerups: return .ready
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

    // The practice board's moves, worked out so the score card shows every part:
    // the first tap opens up the left, the second completes the path (16 squares, 2 whites left
    // over, 2 locked), flipping `flipTarget` joins one cut-off white (18, 1 left over), and
    // unlocking `secondTap`, which is black, leaves 1 locked: 18 − 1 − 1 = 16.
    private static let firstTap = GridPoint(row: 2, col: 2)
    private static let secondTap = GridPoint(row: 1, col: 4)
    private static let flipTarget = GridPoint(row: 2, col: 0)

    /// What the scene lets the player tap during a step.
    private func gate(for step: Step) -> GameScene.TutorialGate {
        switch step {
        case .tap: return .square(Self.firstTap)
        case .tapAgain: return .square(Self.secondTap)
        case .flipOne: return armed ? .square(Self.flipTarget) : .powerup(.flipOne)
        case .unlock: return armed ? .square(Self.secondTap) : .powerup(.unlock)
        case .commit: return .commitButton
        case .goal, .scored, .bonuses, .powerups, .ready: return .nothing
        }
    }

    private static func makeBoard() -> Board {
        let rows = ["WWWBBB", "WBWWBB", "BBWWBB", "WWBWWW"]
        let tones = rows.flatMap { row in row.map { $0 == "B" ? Tone.black : Tone.white } }
        return Board(rows: 4, cols: 6, startRow: 1, finishRow: 1, tones: tones)
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
        case .layoutChanged:
            if let scene = scene { cardFrame = scene.tutorialCardFrame }
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
            case .tap, .tapAgain: hint = "Tap the highlighted square."
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
    func gameSceneDidRestart(_ scene: GameScene) {}
    func gameScene(_ scene: GameScene, didEndGameWithScore score: Int, level: Int, abandoned: Bool) {}
}
