import SwiftUI

/// The player's own high scores: their Game Center best and worldwide rank, then their best
/// and most recent games on this device, for one difficulty at a time.
struct HighScoresView: View {
    let store: HighScoreStore
    @State private var difficulty: Difficulty
    @Environment(\.dismiss) private var dismiss
    private let gameCenterAvailable: Bool
    private let onShowGameCenter: (Difficulty) -> Void
    private let onShowAchievements: () -> Void

    private enum StandingState {
        case loading
        case loaded(GameCenter.Standing?)
        case failed
    }

    @State private var standing: StandingState = .loading

    /// - Parameter difficulty: shown first; normally the difficulty chosen in Settings.
    init(store: HighScoreStore, difficulty: Difficulty, gameCenterAvailable: Bool = false,
         onShowGameCenter: @escaping (Difficulty) -> Void = { _ in },
         onShowAchievements: @escaping () -> Void = {}) {
        self.store = store
        _difficulty = State(initialValue: difficulty)
        self.gameCenterAvailable = gameCenterAvailable
        self.onShowGameCenter = onShowGameCenter
        self.onShowAchievements = onShowAchievements
    }

    var body: some View {
        NavigationStack {
            List {
                if gameCenterAvailable {
                    Section {
                        HStack(spacing: 12) {
                            gameCenterButton("Leaderboard", image: "leaderboards") {
                                onShowGameCenter(difficulty)
                            }
                            gameCenterButton("Achievements", image: "achievements", action: onShowAchievements)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } header: {
                        GameCenterHeader()
                    }
                }

                Section {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { level in
                            Text(level.name).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    // Taller segments, for more room around the larger labels.
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                personalBestSection

                let best = store.bestGames(for: difficulty)
                if best.isEmpty {
                    ContentUnavailableView("No scores yet", systemImage: "trophy",
                                           description: Text("Finish a game with a score above zero to see it here."))
                } else {
                    Section("Your best games") {
                        ForEach(Array(best.enumerated()), id: \.element.id) { index, entry in
                            gameRow(entry, place: index + 1)
                        }
                    }
                    Section {
                        ForEach(store.recentGames(for: difficulty)) { entry in
                            gameRow(entry, place: nil)
                        }
                    } header: {
                        Text("Recent games")
                    } footer: {
                        Text("Games with a score above zero, played on this device.")
                    }
                }
            }
            .navigationTitle("High Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Reloads whenever the difficulty changes.
            .task(id: difficulty) { await loadStanding() }
        }
    }

    // MARK: Game Center

    /// The player's Game Center entry, once loaded.
    private var gameCenterStanding: GameCenter.Standing? {
        if case .loaded(let mine?) = standing { return mine }
        return nil
    }

    /// Game Center is still being asked for the player's entry.
    private var isLoading: Bool {
        guard gameCenterAvailable, case .loading = standing else { return false }
        return true
    }

    /// The best score and when it was set: the higher of the iCloud and Game Center bests.
    /// They normally match, but either can be missing (signed out, offline or not yet posted).
    private var personalBest: (score: Int, date: Date)? {
        let synced = store.syncedBest[difficulty].map { (score: $0.score, date: $0.date) }
        let online = gameCenterStanding.map { (score: $0.bestScore, date: $0.date) }
        switch (synced, online) {
        case let (synced?, online?): return online.score >= synced.score ? online : synced
        case let (synced?, nil): return synced
        case let (nil, online?): return online
        case (nil, nil): return nil
        }
    }

    /// One section for the personal best, with the worldwide rank from Game Center when there is one.
    @ViewBuilder
    private var personalBestSection: some View {
        if personalBest != nil || isLoading {
            Section {
                if let best = personalBest {
                    LabeledContent("Best score") {
                        Text("\(best.score)").monospacedDigit().bold()
                    }
                }
                if isLoading {
                    LabeledContent("Worldwide rank") { ProgressView() }
                } else if let mine = gameCenterStanding {
                    LabeledContent("Worldwide rank") {
                        Text("#\(mine.rank.formatted()) of \(mine.totalPlayers.formatted())").monospacedDigit()
                    }
                }
                if let best = personalBest {
                    LabeledContent("Set on") {
                        Text(best.date, format: .dateTime.day().month().year())
                    }
                }
            } header: {
                Text("Personal best")
            } footer: {
                Text(personalBestFooter)
            }
        }
    }

    private var personalBestFooter: String {
        guard gameCenterAvailable else {
            return "Your best on any of your devices. Sign in to Game Center in the Settings app to see your worldwide rank."
        }
        if case .failed = standing {
            return "Your best score on any of your devices. Could not reach Game Center for your worldwide rank; try again later."
        }
        return "Your best score on any of your devices."
    }

    /// A tile with one of Game Center's own symbols (tinted) above its title.
    private func gameCenterButton(_ title: String, image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // Apple's artwork has generous space around the glyph, so the frame is larger
                // than the symbol looks.
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .padding(.vertical, -6)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        }
        .buttonStyle(.bordered)
        // Each tile is its own button, not the whole row.
        .buttonBorderShape(.roundedRectangle(radius: 14))
    }

    private func loadStanding() async {
        guard gameCenterAvailable else { return }
        standing = .loading
        do {
            standing = .loaded(try await GameCenter.shared.standing(for: difficulty))
        } catch {
            // A difficulty change cancels the load; only show an error for a real failure.
            guard !Task.isCancelled else { return }
            standing = .failed
        }
    }

    // MARK: Rows

    /// A game's score and when it was played, numbered when `place` is given.
    private func gameRow(_ entry: ScoreEntry, place: Int?) -> some View {
        HStack {
            if let place = place {
                Text("\(place)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
            }
            Text(entry.date, format: .dateTime.day().month().year())
                .foregroundStyle(.secondary)
            Spacer()
            if place == 1 {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Personal best")
            }
            Text("\(entry.score)")
                .monospacedDigit()
                .bold()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A section header with Game Center's colour icon, for the Game Center buttons.
struct GameCenterHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("gameCenter")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text("Game Center")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        // Section headers are otherwise upper case.
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}
