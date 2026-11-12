import SwiftUI

/// The card that rises after a won round, explaining its score line by line: a swatch and
/// label for each part, revealed one after another, then the total counting up.
/// Tap it, or anywhere else, to dismiss it.
struct RoundSummaryCard: View {
    let summary: RoundSummary
    /// Resolved settings, for the theme's colours.
    let settings: GameSettings
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownRows = 0
    @State private var shownTotal = 0

    private enum Swatch {
        case color(Color)
        case star
        case symbol(String)
    }

    private struct Row: Identifiable {
        let id: Int
        let swatch: Swatch
        let label: String
        let value: String
        /// A small line under the label explaining it, if needed.
        let detail: String?
    }

    private var textColor: Color { Color(uiColor: settings.textColor) }
    private var pathColor: Color { settings.pathColor.color }
    private var lockColor: Color { settings.lockColor.color }

    private var rows: [Row] {
        var rows: [Row] = []
        func add(_ swatch: Swatch, _ label: String, _ value: String, detail: String? = nil) {
            rows.append(Row(id: rows.count, swatch: swatch, label: label, value: value, detail: detail))
        }
        add(.color(pathColor), "Path squares", "+\(summary.pathCount)")
        if summary.noWhitesBonus > 0 {
            add(.symbol("square.slash.fill"), "No whites left", "+\(summary.noWhitesBonus)")
        } else if summary.leftoverWhites > 0 {
            add(.color(.white), "White squares left", "−\(summary.leftoverWhites)")
        }
        if summary.lockedCount > 0 {
            add(.color(lockColor), "Locked squares", "−\(summary.lockedCount)")
        }
        switch summary.star {
        case .powerup: add(.star, "Star", "+1 power-up")
        case .points(let points): add(.star, "Star", "+\(points)")
        case nil: break
        }
        if summary.powerupReward {
            add(.symbol("plus.square"), "Power-up reward", "+1 each",
                detail: "Score ≥ grid size (\(summary.gridSize))")
        }
        return rows
    }

    var body: some View {
        let rows = rows
        SummaryCardContainer(settings: settings, accessibilityText: accessibilityText(rows),
                             accessibilityHint: "Closes the round score", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 14) {
                SummaryCardTitle("Level \(summary.level)")

                ForEach(rows) { row in
                    let shown = row.id < shownRows
                    HStack(spacing: 12) {
                        swatch(row.swatch)
                        VStack(alignment: .leading, spacing: 1) {
                            // One line each: shrinks a little rather than wrapping.
                            Text(row.label)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if let detail = row.detail {
                                Text(detail)
                                    .font(.caption)
                                    .opacity(0.6)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(row.value)
                            .font(.body.bold().monospacedDigit())
                            .lineLimit(1)
                            // The value keeps its full width; the label gives way first.
                            .layoutPriority(1)
                    }
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 8)
                }

                SummaryCardDivider(color: textColor)

                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(.title3.bold())
                    Spacer()
                    SummaryCardScore(value: shownTotal, signed: true,
                                     color: summary.total > 0 ? pathColor : lockColor)
                }

                SummaryCardFooter()
            }
        }
        .task { await reveal(rowCount: rows.count) }
    }

    /// Rows appear one by one with a soft click, then the total counts up. All at once with
    /// Reduce Motion. The card then stays until it's tapped away (which also stops this task).
    private func reveal(rowCount: Int) async {
        if reduceMotion {
            shownRows = rowCount
            shownTotal = summary.total
        } else {
            try? await Task.sleep(for: .milliseconds(350))
            for index in 0..<rowCount {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { shownRows = index + 1 }
                SoundEngine.shared.play(.button)
                try? await Task.sleep(for: .milliseconds(220))
            }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.snappy(duration: 0.6)) { shownTotal = summary.total }
        }
    }

    @ViewBuilder
    private func swatch(_ swatch: Swatch) -> some View {
        let side: CGFloat = 24
        switch swatch {
        case .color(let color):
            RoundedRectangle(cornerRadius: side * 0.22)
                .fill(color)
                // A faint edge, so a swatch that matches the card still shows.
                .overlay(RoundedRectangle(cornerRadius: side * 0.22)
                    .strokeBorder(textColor.opacity(0.25), lineWidth: 1))
                .frame(width: side, height: side)
        case .star:
            // The game's own rounded star.
            let art = Art.star(fill: settings.starColor.uiColor, outline: .black, pointSize: side)
            Image(uiImage: UIImage(cgImage: art.texture.cgImage(), scale: Art.displayScale, orientation: .up))
                .frame(width: side, height: side)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: side * 0.85, weight: .semibold))
                .foregroundStyle(pathColor)
                .frame(width: side, height: side)
        }
    }

    private func accessibilityText(_ rows: [Row]) -> String {
        let lines = rows.map { row in
            "\(row.label), \(row.value)" + (row.detail.map { ", \($0)" } ?? "")
        }
        return (["Level \(summary.level)"] + lines + ["Total, \(summary.total)"]).joined(separator: ". ")
    }
}

// MARK: - Game over

/// How a game ended, for the game-over card.
struct GameOverSummary: Identifiable, Equatable {
    let id = UUID()
    let difficulty: Difficulty
    /// The level the game ended on.
    let level: Int
    let score: Int
    /// The score beats the player's best at this difficulty on any of their devices.
    let isPersonalBest: Bool
    /// The player's best ever at this difficulty, on any of their devices (this game included).
    let personalBest: Int?
    /// The player's Game Center nickname, when signed in, to greet them by.
    let playerName: String?

    var personalBestText: String {
        playerName.map { "New personal best, \($0)!" } ?? "New personal best!"
    }
}

/// The simpler card shown when a game ends: difficulty, level reached and final score,
/// with a note when it's a new personal best.
struct GameOverCard: View {
    let summary: GameOverSummary
    /// Resolved settings, for the theme's colours.
    let settings: GameSettings
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownScore = 0

    private var textColor: Color { Color(uiColor: settings.textColor) }

    var body: some View {
        SummaryCardContainer(settings: settings, accessibilityText: accessibilityText,
                             accessibilityHint: "Closes the game over summary", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 14) {
                SummaryCardTitle("Game over")

                row("Difficulty", summary.difficulty.name)
                row("Level reached", "\(summary.level)")
                if let best = summary.personalBest {
                    row("Personal best", "\(best)")
                }

                SummaryCardDivider(color: textColor)

                HStack(alignment: .firstTextBaseline) {
                    Text("Final score")
                        .font(.title3.bold())
                    Spacer()
                    SummaryCardScore(value: shownScore, signed: false,
                                     color: summary.score > 0 ? settings.pathColor.color : settings.lockColor.color)
                }

                if summary.isPersonalBest {
                    Label(summary.personalBestText, systemImage: "crown.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                        .foregroundStyle(.yellow, textColor)
                        .frame(maxWidth: .infinity)
                }

                SummaryCardFooter()
            }
        }
        .task {
            if reduceMotion {
                shownScore = summary.score
            } else {
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.snappy(duration: 0.7)) { shownScore = summary.score }
            }
            if summary.isPersonalBest { SoundEngine.shared.play(.starBonus) }
        }
    }

    private var accessibilityText: String {
        "Game over. Difficulty, \(summary.difficulty.name). Level reached, \(summary.level). "
            + (summary.personalBest.map { "Personal best, \($0). " } ?? "")
            + "Final score, \(summary.score)" + (summary.isPersonalBest ? ". \(summary.personalBestText)" : "")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            Text(value).font(.body.bold().monospacedDigit())
        }
    }
}

// MARK: - Start

/// What the start card shows before a new game.
struct StartPrompt: Identifiable, Equatable {
    let id = UUID()
    let difficulty: Difficulty
    /// The player's best at this difficulty, if they have one.
    let personalBest: Int?
}

/// Shown before each new game, so the clock doesn't start until the player is ready.
/// The grid is dealt when they tap Start. Taps elsewhere reach the game screen, so the
/// settings and high scores buttons still work.
struct StartCard: View {
    let prompt: StartPrompt
    /// Resolved settings, for the theme's colours.
    let settings: GameSettings
    let onStart: () -> Void

    private var textColor: Color { Color(uiColor: settings.textColor) }
    private var seconds: Int { Int(prompt.difficulty.timeAllowed(level: 1)) }

    var body: some View {
        SummaryCardContainer(settings: settings, accessibilityText: accessibilityText,
                             accessibilityHint: "", onDismiss: nil) {
            VStack(alignment: .leading, spacing: 14) {
                SummaryCardTitle("New game")

                row("Difficulty", prompt.difficulty.name)
                row("Clock", "\(seconds) seconds", detail: "Gets quicker every level")
                if let best = prompt.personalBest {
                    row("Personal best", "\(best)")
                }

                // Styled like the game's centre button and the title screen's Play.
                Button(action: onStart) {
                    ZStack {
                        Capsule().fill(.black)
                        Capsule()
                            .fill(settings.pathColor.color)
                            .overlay(Capsule().stroke(.white, lineWidth: 2))
                            .padding(5)
                        Label("Start", systemImage: "play.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.title3.bold())
                            .foregroundStyle(textColor)
                    }
                    .frame(height: 58)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityLabel("Start")
                .accessibilityHint("Starts the game")
            }
        }
    }

    private var accessibilityText: String {
        "New game. Difficulty, \(prompt.difficulty.name). Clock, \(seconds) seconds, gets quicker every level"
            + (prompt.personalBest.map { ". Personal best, \($0)" } ?? "")
    }

    private func row(_ label: String, _ value: String, detail: String? = nil) -> some View {
        HStack {
            // A smaller, fainter line under the label, as on the round summary.
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                if let detail = detail {
                    Text(detail)
                        .font(.caption)
                        .opacity(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 12)
            Text(value).font(.body.bold().monospacedDigit())
        }
    }
}

// MARK: - Shared pieces

/// The frosted card the summaries sit on. With `onDismiss`, a tap on it or anywhere else on screen
/// dismisses it, and a tap outside doesn't also press whatever is underneath. Without, only the
/// card's own buttons respond, and the rest of the screen stays usable.
private struct SummaryCardContainer<Content: View>: View {
    let settings: GameSettings
    /// What VoiceOver reads for the whole card, and its hint (for a card that dismisses on tap).
    let accessibilityText: String
    let accessibilityHint: String
    let onDismiss: (() -> Void)?
    @ViewBuilder let content: Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// A big window (an iPad, more or less full screen), where the card and its text grow.
    private var isLarge: Bool { horizontalSizeClass == .regular && verticalSizeClass == .regular }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: isLarge ? 32 : 26, style: .continuous) }

    var body: some View {
        if let onDismiss = onDismiss {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)
                card
                    .onTapGesture(perform: onDismiss)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText)
                    .accessibilityHint(accessibilityHint)
                    .accessibilityAddTraits(.isButton)
            }
        } else {
            // Only the card's own buttons act; the card still blocks taps to whatever is under it.
            card
                .accessibilityElement(children: .contain)
        }
    }

    private var card: some View {
        let textColor = Color(uiColor: settings.textColor)
        return content
            .foregroundStyle(textColor)
            // Larger text on a big screen, or the player's own size if that's larger still.
            .dynamicTypeSize(isLarge ? .xxxLarge ... .accessibility5 : .xSmall ... .accessibility5)
            .padding(isLarge ? 30 : 22)
            .frame(maxWidth: isLarge ? 420 : 320)
            // Frosted, with a tint of the theme's background: the board shows through softly
            // while the text stays easy to read.
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(settings.background.color.opacity(0.6))
            }
            .overlay(shape.strokeBorder(textColor.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
            .contentShape(shape)
    }
}

/// The small spaced capitals at the top of a summary card.
private struct SummaryCardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1)
            .opacity(0.6)
    }
}

private struct SummaryCardDivider: View {
    let color: Color

    var body: some View {
        Rectangle().fill(color.opacity(0.2)).frame(height: 1)
    }
}

private struct SummaryCardFooter: View {
    var body: some View {
        Text("Tap to continue")
            .font(.caption)
            .opacity(0.5)
            .frame(maxWidth: .infinity)
    }
}

/// The big score that counts up.
private struct SummaryCardScore: View {
    let value: Int
    /// Shows a + on positive values.
    let signed: Bool
    let color: Color

    var body: some View {
        Text(signed && value > 0 ? "+\(value)" : "\(value)")
            .font(.system(size: 40, weight: .bold).monospacedDigit())
            .contentTransition(.numericText(value: Double(value)))
            .foregroundStyle(color)
    }
}

extension AnyTransition {
    /// Rises in from below, then shrinks away down towards the score in the bottom left.
    /// A plain fade with Reduce Motion.
    static func roundSummary(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                           removal: .scale(scale: 0.3, anchor: .bottomLeading).combined(with: .opacity))
    }
}
