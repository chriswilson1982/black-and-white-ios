import Foundation
import GameKit

/// The game's Game Center achievements. Each needs a matching entry in App Store Connect
/// with the same ID (see the README for the full list with points and descriptions).
enum Achievement: String, CaseIterable {
    // Score in one game, any difficulty.
    case score100, score250, score500, score1000, score1500, score2000
    // Score in one game on Hard.
    case hardScore250, hardScore500, hardScore1000
    // Reach a level, any difficulty.
    case level10, level20, level30, level40, level50
    // Firsts.
    case noWhitesLeft, powerupReward, starPoints
    // Extras.
    case starCollector, fullHouse, purist, trickyGrid, photoFinish, oneTapWonder, noTapsNeeded, goodbyeStar

    /// The ID set up in App Store Connect.
    var id: String { "com.chriswilson.blackandwhite.achievement.\(rawValue)" }

    /// Single-game score milestones, any difficulty.
    static let scoreTiers: [(score: Int, achievement: Achievement)] = [
        (100, .score100), (250, .score250), (500, .score500),
        (1000, .score1000), (1500, .score1500), (2000, .score2000),
    ]

    /// Single-game score milestones on Hard.
    static let hardScoreTiers: [(score: Int, achievement: Achievement)] = [
        (250, .hardScore250), (500, .hardScore500), (1000, .hardScore1000),
    ]

    static let levelTiers: [(level: Int, achievement: Achievement)] = [
        (10, .level10), (20, .level20), (30, .level30), (40, .level40), (50, .level50),
    ]

    /// Stars needed, over all games, for Star Collector.
    static let starCollectorTarget = 25
}

/// Works out which achievements the player has earned from what happens in the game, and
/// reports them to Game Center. Earned achievements are remembered on the device, so each is
/// only sent once and any earned while signed out are sent after the next sign-in.
final class AchievementTracker {
    static let shared = AchievementTracker()

    private let defaults = UserDefaults.standard
    private let earnedKey = "achievements.earned"
    private let reportedKey = "achievements.reported"
    private let starsKey = "achievements.starsCollected"

    private var earned: Set<String>
    private var reported: Set<String>
    private var starsCollected: Int

    private init() {
        earned = Set(defaults.stringArray(forKey: earnedKey) ?? [])
        reported = Set(defaults.stringArray(forKey: reportedKey) ?? [])
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
    func roundWon(noWhitesLeft: Bool, powerupReward: Bool, squareTaps: Int, usedPowerups: Bool,
                  wasTrickyGrid: Bool, timeLeft: TimeInterval) {
        var unlocked: [Achievement] = []
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
        if forPoints { earn([.starPoints]) }
        starsCollected += 1
        defaults.set(starsCollected, forKey: starsKey)
        if starsCollected >= Achievement.starCollectorTarget {
            earn([.starCollector])
        } else {
            // Progress towards Star Collector, shown in Game Center.
            let progress = Double(starsCollected) / Double(Achievement.starCollectorTarget) * 100
            report([progressEntry(.starCollector, percent: progress)])
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

    /// Sends anything earned while signed out. Call after Game Center sign-in.
    func reportPending() {
        let pending = earned.subtracting(reported)
        guard !pending.isEmpty else { return }
        report(pending.map { completedEntry(id: $0) }, completing: pending)
    }

    // MARK: Reporting

    private func earn(_ achievements: [Achievement]) {
        let new = Set(achievements.map(\.id)).subtracting(earned)
        guard !new.isEmpty else { return }
        earned.formUnion(new)
        defaults.set(Array(earned), forKey: earnedKey)
        report(new.map { completedEntry(id: $0) }, completing: new)
    }

    private func completedEntry(id: String) -> GKAchievement {
        let entry = GKAchievement(identifier: id)
        entry.percentComplete = 100
        entry.showsCompletionBanner = true
        return entry
    }

    private func progressEntry(_ achievement: Achievement, percent: Double) -> GKAchievement {
        let entry = GKAchievement(identifier: achievement.id)
        entry.percentComplete = percent
        return entry
    }

    /// Sends to Game Center when signed in. Completed IDs are marked as sent once Game Center
    /// accepts them; until then they stay pending and go with the next `reportPending()`.
    private func report(_ entries: [GKAchievement], completing ids: Set<String> = []) {
        guard GKLocalPlayer.local.isAuthenticated, !entries.isEmpty else { return }
        GKAchievement.report(entries) { [weak self] error in
            if let error = error {
                print("Game Center achievement report failed: \(error.localizedDescription)")
                return
            }
            guard !ids.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.reported.formUnion(ids)
                self.defaults.set(Array(self.reported), forKey: self.reportedKey)
            }
        }
    }
}
