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
                        Button {
                            onShowGameCenter(difficulty)
                        } label: {
                            Label("Game Center Leaderboard", systemImage: "gamecontroller.fill")
                                // In a list row the system may otherwise show the title alone.
                                .labelStyle(.titleAndIcon)
                                .imageScale(.large)
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                        Button(action: onShowAchievements) {
                            Label("Achievements", systemImage: "rosette")
                                .labelStyle(.titleAndIcon)
                                .imageScale(.large)
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases) { level in
                            Text(level.name).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if let best = store.syncedBest[difficulty] {
                    Section {
                        LabeledContent("Best score") {
                            Text("\(best.score)").monospacedDigit().bold()
                        }
                        LabeledContent("Set on") {
                            Text(best.date, format: .dateTime.day().month().year())
                        }
                    } header: {
                        Text("Personal best")
                    } footer: {
                        Text("Your best on any of your devices, synced with iCloud.")
                    }
                }

                worldwideSection

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

    @ViewBuilder
    private var worldwideSection: some View {
        Section {
            if !gameCenterAvailable {
                Text("Sign in to Game Center in the Settings app to see your worldwide ranking.")
                    .foregroundStyle(.secondary)
            } else {
                switch standing {
                case .loading:
                    HStack {
                        Text("Loading…").foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                case .failed:
                    Text("Couldn't reach Game Center. Try again later.")
                        .foregroundStyle(.secondary)
                case .loaded(nil):
                    Text("No \(difficulty.name.lowercased()) score on Game Center yet. Finish a game to post one.")
                        .foregroundStyle(.secondary)
                case .loaded(let mine?):
                    LabeledContent("Best score") {
                        Text("\(mine.bestScore)").monospacedDigit().bold()
                    }
                    LabeledContent("Worldwide rank") {
                        Text("#\(mine.rank.formatted()) of \(mine.totalPlayers.formatted())").monospacedDigit()
                    }
                    LabeledContent("Set on") {
                        Text(mine.date, format: .dateTime.day().month().year())
                    }
                }
            }
        } header: {
            Text("Worldwide")
        }
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
