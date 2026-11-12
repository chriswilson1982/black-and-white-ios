import Foundation
import GameKit
import OSLog

/// The game's Game Center achievements. Each needs a matching entry in App Store Connect
/// with the same ID (see the README for the full list with points and descriptions).
enum Achievement: String, CaseIterable {
    // Score in one game, any difficulty.
    case score100, score250, score500, score1000, score1500, score2000
    // Score in one game on Hard.
    case hardScore500, hardScore1000
    // Reach a level, any difficulty.
    case level10, level20, level30, level40, level50
    // Firsts.
    case noWhitesLeft, powerupReward, starBonus
    // Extras.
    case starCollector, fullHouse, purist, trickyGrid, photoFinish, oneTapWonder, noTapsNeeded, goodbyeStar
    // Hidden jokes: a game that ends on zero or less, and a level that scores exactly zero or below zero.
    case score0, zero, goingDown

    /// The ID set up in App Store Connect.
    var id: String { "com.chriswilson.blackandwhite.achievement.\(rawValue)" }

    /// Single-game score milestones, any difficulty.
    static let scoreTiers: [(score: Int, achievement: Achievement)] = [
        (100, .score100), (250, .score250), (500, .score500),
        (1000, .score1000), (1500, .score1500), (2000, .score2000),
    ]

    /// Single-game score milestones on Hard.
    static let hardScoreTiers: [(score: Int, achievement: Achievement)] = [
        (500, .hardScore500), (1000, .hardScore1000),
    ]

    static let levelTiers: [(level: Int, achievement: Achievement)] = [
        (10, .level10), (20, .level20), (30, .level30), (40, .level40), (50, .level50),
    ]

    /// Stars needed, over all games, for Star Collector.
    static let starCollectorTarget = 100
}

/// Works out which achievements the player has earned from what happens in the game, and
/// reports them to Game Center (with a banner) as they're earned. Earned achievements are
/// remembered on the device and sent again at each sign-in, so none are lost.
final class AchievementTracker {
    static let shared = AchievementTracker()

    private let defaults = UserDefaults.standard
    private let earnedKey = "achievements.earned"
    private let starsKey = "achievements.starsCollected"

    private var earned: Set<String>
    private var starsCollected: Int

    #if DEBUG
    private static let log = Logger(subsystem: "com.chriswilson.blackandwhite", category: "Achievements")
    #endif

    private init() {
        var saved = Set(defaults.stringArray(forKey: earnedKey) ?? [])
        // Star Bonus was briefly called starPoints; carry it over.
        if saved.contains("com.chriswilson.blackandwhite.achievement.starPoints") {
            saved.insert(Achievement.starBonus.id)
        }
        // Only achievements that still exist, so a removed one isn't sent again.
        let current = Set(Achievement.allCases.map(\.id))
        earned = saved.intersection(current)
        starsCollected = defaults.integer(forKey: starsKey)
    }

    // MARK: Game events

    /// The game's running score changed (after a won round, or star points).
    func scoreChanged(to score: Int, difficulty: Difficulty) {
        var unlocked = Achievement.scoreTiers.filter { score >= $0.score }.map(\.achievement)
        if difficulty == .hard {
            unlocked += Achievement.hardScoreTiers.filter { score >= $0.score }.map(\.achievement)
        }
        earn(unlocked)
    }

    /// A round was won.
    /// - Parameters:
    ///   - squareTaps: squares tapped this round.
    ///   - usedPowerups: any power-up used this round.
    ///   - wasTrickyGrid: the round was a penalty 4×4 grid.
    ///   - timeLeft: seconds left on the clock when the path was tested.
    ///   - roundScore: the round's points (star bonus points not included).
    func roundWon(noWhitesLeft: Bool, powerupReward: Bool, squareTaps: Int, usedPowerups: Bool,
                  wasTrickyGrid: Bool, timeLeft: TimeInterval, roundScore: Int) {
        var unlocked: [Achievement] = []
        if roundScore == 0 { unlocked.append(.zero) }
        if roundScore < 0 { unlocked.append(.goingDown) }
        if noWhitesLeft { unlocked.append(.noWhitesLeft) }
        if powerupReward { unlocked.append(.powerupReward) }
        if wasTrickyGrid { unlocked.append(.trickyGrid) }
        if timeLeft < 1 { unlocked.append(.photoFinish) }
        if !usedPowerups && squareTaps == 0 { unlocked.append(.noTapsNeeded) }
        if !usedPowerups && squareTaps == 1 { unlocked.append(.oneTapWonder) }
        earn(unlocked)
    }

    /// A new level began. `usedPowerupsThisGame` is false if no power-up has been used since level 1.
    func levelReached(_ level: Int, usedPowerupsThisGame: Bool) {
        var unlocked = Achievement.levelTiers.filter { level >= $0.level }.map(\.achievement)
        if level >= 10 && !usedPowerupsThisGame { unlocked.append(.purist) }
        earn(unlocked)
    }

    /// The winning wave collected the star, for a power-up or (when they're all full) for points.
    func starCollected(forPoints: Bool) {
        if forPoints { earn([.starBonus]) }
        starsCollected += 1
        defaults.set(starsCollected, forKey: starsKey)
        if starsCollected >= Achievement.starCollectorTarget {
            earn([.starCollector])
        } else {
            report([starCollectorProgress()])
        }
    }

    /// Power-up counts changed. Full House is all three at the maximum.
    func powerupsChanged(_ counts: [Int]) {
        if counts.allSatisfy({ $0 >= Board.maxPowerups }) { earn([.fullHouse]) }
    }

    /// The player tapped the star's square, destroying it.
    func starDestroyed() {
        earn([.goodbyeStar])
    }

    /// A game was lost (not abandoned with a restart), ending on `finalScore`.
    func gameLost(finalScore: Int) {
        if finalScore <= 0 { earn([.score0]) }
    }

    /// Sends everything earned on this device again, plus Star Collector progress. Call after
    /// Game Center sign-in.
    ///
    /// Game Center ignores achievements it already has, so this is safe to repeat. It's what
    /// delivers anything earned while signed out, or before the achievement was set up in
    /// App Store Connect (GameKit doesn't always report an error for an unknown ID, so "sent"
    /// can't be trusted to mean "received").
    func reportAll() {
        var entries = earned.map { completedEntry(id: $0, banner: false) }
        if !earned.contains(Achievement.starCollector.id), starsCollected > 0 {
            entries.append(starCollectorProgress())
        }
        report(entries)
    }

    // MARK: Reporting

    private func earn(_ achievements: [Achievement]) {
        let new = Set(achievements.map(\.id)).subtracting(earned)
        guard !new.isEmpty else { return }
        earned.formUnion(new)
        defaults.set(Array(earned), forKey: earnedKey)
        report(new.map { completedEntry(id: $0, banner: true) })
    }

    /// `banner`: show Game Center's "achievement earned" banner (only when it's newly earned).
    private func completedEntry(id: String, banner: Bool) -> GKAchievement {
        let entry = GKAchievement(identifier: id)
        entry.percentComplete = 100
        entry.showsCompletionBanner = banner
        return entry
    }

    /// Stars collected so far as a share of the Star Collector target, shown in Game Center.
    private func starCollectorProgress() -> GKAchievement {
        let entry = GKAchievement(identifier: Achievement.starCollector.id)
        entry.percentComplete = min(100, Double(starsCollected) / Double(Achievement.starCollectorTarget) * 100)
        return entry
    }

    /// Sends to Game Center when signed in. If not, nothing is lost: `reportAll()` sends it
    /// after the next sign-in.
    private func report(_ entries: [GKAchievement]) {
        guard GKLocalPlayer.local.isAuthenticated, !entries.isEmpty else { return }
        #if DEBUG
        // The system log timestamps each line as it happens (print output can arrive in a batch).
        let summary = entries.map { "\($0.identifier.split(separator: ".").last ?? "") \(Int($0.percentComplete))%" }
        Self.log.info("Reporting achievements: \(summary.joined(separator: ", "), privacy: .public)")
        #endif
        GKAchievement.report(entries) { error in
            if let error = error {
                print("Game Center achievement report failed: \(error.localizedDescription)")
            }
        }
    }
}
