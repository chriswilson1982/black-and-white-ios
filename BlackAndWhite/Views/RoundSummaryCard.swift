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
    }

    private var textColor: Color { Color(uiColor: settings.textColor) }
    private var pathColor: Color { settings.pathColor.color }
    private var lockColor: Color { settings.lockColor.color }

    private var rows: [Row] {
        var rows: [Row] = []
        func add(_ swatch: Swatch, _ label: String, _ value: String) {
            rows.append(Row(id: rows.count, swatch: swatch, label: label, value: value))
        }
        add(.color(pathColor), "Path squares", "+\(summary.pathCount)")
        if summary.noWhitesBonus > 0 {
            add(.color(.white), "No whites left", "+\(summary.noWhitesBonus)")
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
            add(.symbol("plus.square.fill"), "Power-up reward", "+1 of each")
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
                        Text(row.label)
                        Spacer(minLength: 12)
                        Text(row.value)
                            .font(.body.bold().monospacedDigit())
                    }
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 8)
                }

                SummaryCardDivider(color: textColor)

                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(.title3.bold())
                    Spacer()
                    SummaryCardScore(value: shownTotal, signed: true, textColor: textColor,
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
        let lines = rows.map { "\($0.label), \($0.value)" }
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

                SummaryCardDivider(color: textColor)

                HStack(alignment: .firstTextBaseline) {
                    Text("Final score")
                        .font(.title3.bold())
                    Spacer()
                    SummaryCardScore(value: shownScore, signed: false, textColor: textColor,
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

// MARK: - Shared pieces

/// The frosted card both summaries sit on. A tap on it, or anywhere else on screen, dismisses it;
/// a tap outside doesn't also press whatever is underneath.
private struct SummaryCardContainer<Content: View>: View {
    let settings: GameSettings
    /// What VoiceOver reads for the whole card, and its hint.
    let accessibilityText: String
    let accessibilityHint: String
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 26, style: .continuous) }

    var body: some View {
        let textColor = Color(uiColor: settings.textColor)
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            content
                .foregroundStyle(textColor)
                .padding(22)
                .frame(maxWidth: 320)
                // Frosted, with a tint of the theme's background: the board shows through softly
                // while the text stays easy to read.
                .background {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(settings.background.color.opacity(0.6))
                }
                .overlay(shape.strokeBorder(textColor.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
                .contentShape(shape)
                .onTapGesture(perform: onDismiss)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityHint(accessibilityHint)
                .accessibilityAddTraits(.isButton)
        }
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

/// The big score that counts up, with a fine edge in the text colour so a light colour still reads.
private struct SummaryCardScore: View {
    let value: Int
    /// Shows a + on positive values.
    let signed: Bool
    let textColor: Color
    let color: Color

    var body: some View {
        Text(signed && value > 0 ? "+\(value)" : "\(value)")
            .font(.system(size: 40, weight: .bold).monospacedDigit())
            .contentTransition(.numericText(value: Double(value)))
            // Before the colour, so the outline copies keep the text colour.
            .fineOutline(textColor, width: 0.8)
            .foregroundStyle(color)
    }
}

extension View {
    /// A fine outline around text (SwiftUI has no text stroke): eight copies in `color`, each
    /// offset a hairline in a different direction, side by side behind it. (Chained shadows
    /// would copy each other and build up into a thick blur.)
    ///
    /// Apply it before the text's own `foregroundStyle`, so the copies keep `color`.
    func fineOutline(_ color: Color, width: CGFloat) -> some View {
        let d = width * 0.7071 // Diagonal offsets, so every direction is the same distance out.
        let offsets = [CGSize(width: width, height: 0), CGSize(width: -width, height: 0),
                       CGSize(width: 0, height: width), CGSize(width: 0, height: -width),
                       CGSize(width: d, height: d), CGSize(width: -d, height: d),
                       CGSize(width: d, height: -d), CGSize(width: -d, height: -d)]
        return background {
            ZStack {
                ForEach(offsets.indices, id: \.self) { i in
                    self.foregroundStyle(color).offset(offsets[i])
                }
            }
            .accessibilityHidden(true)
        }
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
