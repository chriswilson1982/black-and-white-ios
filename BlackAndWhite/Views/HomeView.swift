import SwiftUI

/// The screen the app opens on: the title over the game's moving background, a Play button,
/// and the way into high scores, settings, help and the tutorial.
struct HomeView: View {
    /// Resolved settings, for the text, path and background colours.
    let settings: GameSettings
    /// The synced personal best at the current difficulty, if there is one.
    let best: BestScore?
    let onPlay: () -> Void
    let onHighScores: () -> Void
    let onSettings: () -> Void
    let onHelp: () -> Void
    let onTutorial: () -> Void

    private var textColor: Color { Color(uiColor: settings.textColor) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            title
            if let best = best {
                VStack(spacing: 4) {
                    Text("Personal best · \(settings.difficulty.name)")
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1)
                        .opacity(0.7)
                    Text("\(best.score)")
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                        .foregroundStyle(settings.pathColor.color)
                }
                .padding(.top, 28)
                .accessibilityElement(children: .combine)
            }
            Spacer()
            playButton
            Spacer().frame(height: 36)
            HStack(spacing: 14) {
                menuButton("trophy.fill", "Scores", action: onHighScores)
                menuButton("gearshape.fill", "Settings", action: onSettings)
                menuButton("questionmark", "How to Play", action: onHelp)
                menuButton("graduationcap.fill", "Tutorial", action: onTutorial)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 520)
        .foregroundStyle(textColor)
    }

    /// "black & white", as in the game's title.
    private var title: some View {
        HStack(spacing: 0) {
            Text("black").fontWeight(.light)
            Text("&").fontWeight(.bold)
            Text("white").fontWeight(.light)
        }
        .font(.system(size: 56))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Black and White")
        .accessibilityAddTraits(.isHeader)
    }

    /// Looks like the game's centre button.
    private var playButton: some View {
        Button(action: onPlay) {
            ZStack {
                Capsule().fill(.black)
                Capsule()
                    .fill(settings.pathColor.color)
                    .overlay(Capsule().stroke(.white, lineWidth: 2))
                    .padding(6)
                Label("Play", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.title.bold())
                    .foregroundStyle(textColor)
            }
            .frame(width: 220, height: 76)
        }
        .buttonStyle(.plain)
    }

    /// Chunky rounded buttons like the power-ups, with a caption underneath.
    private func menuButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.black)
                    // Square, like the power-up buttons.
                    .frame(width: 60, height: 60)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.85)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.black, lineWidth: 2.5))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        GameBackground(mood: .playing, shuffle: 0, settings: GameSettings().resolved(systemIsDark: false))
        HomeView(settings: GameSettings().resolved(systemIsDark: false),
                 best: BestScore(score: 128, date: .now),
                 onPlay: {}, onHighScores: {}, onSettings: {}, onHelp: {}, onTutorial: {})
    }
}

/// How to Play in its own sheet, opened from the home screen.
struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HelpView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
