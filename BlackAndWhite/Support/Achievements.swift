import Foundation
import GameKit
import OSLog
import UIKit

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
    // Triple Clean (three Clean Sweeps in a row) and Marathon (100 games played).
    case hatTrick, marathon
    // Hidden jokes: a game that ends on zero or less, a level that scores exactly zero or below zero,
    // and every square on the grid locked.
    case score0, zero, goingDown, lockdown

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

    /// Games needed, over all time, for Marathon.
    static let marathonTarget = 100

    /// Clean Sweeps in a row, in one game, for Triple Clean.
    static let hatTrickTarget = 3
}

/// Works out which achievements the player has earned from what happens in the game, and
/// reports them to Game Center (with a banner) as they're earned. Earned achievements are
/// remembered on the device and sent again at each sign-in, so none are lost.
final class AchievementTracker {
    static let shared = AchievementTracker()

    private let defaults = UserDefaults.standard
    private let earnedKey = "achievements.earned"
    private let starsKey = "achievements.starsCollected"
    private let gamesKey = "achievements.gamesPlayed"
    private let deviceKey = "achievements.deviceID"

    private var earned: Set<String>
    /// Stars collected and games played on this device (this installation). The totals across
    /// all the player's devices are these plus the other devices' tallies in iCloud.
    private var starsCollected: Int
    private var gamesPlayed: Int

    // Counting achievements sync through iCloud key-value storage, one entry per installation
    // ("counts.<id>" holding "stars" and "games"), added up for the total. Separate tallies
    // rather than one shared number, so games on two devices at once both count; and an
    // entry stays in iCloud after the app is deleted, so a reinstall carries on from it.
    private let cloud = NSUbiquitousKeyValueStore.default
    private static let cloudPrefix = "counts."
    private let deviceID: String
    private var cloudKey: String { Self.cloudPrefix + deviceID }
    /// Rounds in a row won with no white squares left, in the current game.
    private var cleanSweepStreak = 0

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
        gamesPlayed = defaults.integer(forKey: gamesKey)
        // Each installation has its own entry, named with the system's ID for this app on this
        // device (which isn't carried over by backups, and changes on reinstall).
        let savedID = defaults.string(forKey: deviceKey)
        let vendorID = UIDevice.current.identifierForVendor?.uuidString ?? savedID ?? UUID().uuidString
        deviceID = vendorID
        if let savedID = savedID, savedID != vendorID {
            // These tallies came with a backup or an earlier installation, and are already in
            // iCloud under that one's entry: start this one from zero, so nothing counts twice.
            starsCollected = 0
            gamesPlayed = 0
            defaults.set(0, forKey: starsKey)
            defaults.set(0, forKey: gamesKey)
        }
        defaults.set(vendorID, forKey: deviceKey)

        // This device's own entry in iCloud may be ahead of the local tallies (say, after
        // restoring an older backup): never go backwards.
        if let own = cloud.dictionary(forKey: cloudKey) {
            starsCollected = max(starsCollected, own["stars"] as? Int ?? 0)
            gamesPlayed = max(gamesPlayed, own["games"] as? Int ?? 0)
            defaults.set(starsCollected, forKey: starsKey)
            defaults.set(gamesPlayed, forKey: gamesKey)
        }
        // Make sure this device's tallies (including any counted before syncing existed) are in
        // iCloud, and catch up when another device adds to its own.
        writeCountsToCloud()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud,
            queue: .main) { [weak self] _ in self?.cloudCountsChanged() }
        cloud.synchronize()
    }

    // MARK: Totals across devices

    private var totalStars: Int { starsCollected + otherDevices("stars") }
    private var totalGames: Int { gamesPlayed + otherDevices("games") }

    /// The sum of one count over every other installation's entry in iCloud.
    private func otherDevices(_ field: String) -> Int {
        cloud.dictionaryRepresentation
            .filter { $0.key.hasPrefix(Self.cloudPrefix) && $0.key != cloudKey }
            .compactMap { ($0.value as? [String: Any])?[field] as? Int }
            .reduce(0, +)
    }

    private func writeCountsToCloud() {
        cloud.set(["stars": starsCollected, "games": gamesPlayed], forKey: cloudKey)
    }

    /// Another device's tallies arrived: the totals may now have reached a target.
    private func cloudCountsChanged() {
        var unlocked: [Achievement] = []
        if totalStars >= Achievement.starCollectorTarget { unlocked.append(.starCollector) }
        if totalGames >= Achievement.marathonTarget { unlocked.append(.marathon) }
        earn(unlocked)
    }

    // MARK: Game events

    /// A new game began (not the tutorial): any Triple Clean run starts again.
    func gameStarted() {
        cleanSweepStreak = 0
    }

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
        // Any won round that leaves white squares breaks the run.
        cleanSweepStreak = noWhitesLeft ? cleanSweepStreak + 1 : 0
        if cleanSweepStreak >= Achievement.hatTrickTarget { unlocked.append(.hatTrick) }
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
        writeCountsToCloud()
        if totalStars >= Achievement.starCollectorTarget {
            earn([.starCollector])
        } else {
            report([progress(.starCollector, count: totalStars, target: Achievement.starCollectorTarget)])
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

    /// Every square on the grid is locked.
    func gridFullyLocked() {
        earn([.lockdown])
    }

    /// A game was lost (not abandoned with a restart), ending on `finalScore`.
    /// Marathon counts these: games played to the end, so restarting over and over doesn't count.
    func gameLost(finalScore: Int) {
        var unlocked: [Achievement] = []
        if finalScore <= 0 { unlocked.append(.score0) }
        gamesPlayed += 1
        defaults.set(gamesPlayed, forKey: gamesKey)
        writeCountsToCloud()
        if totalGames >= Achievement.marathonTarget {
            unlocked.append(.marathon)
        } else {
            report([progress(.marathon, count: totalGames, target: Achievement.marathonTarget)])
        }
        earn(unlocked)
    }

    /// Sends everything earned on this device again, plus Star Collector and Marathon progress. Call after
    /// Game Center sign-in.
    ///
    /// Game Center ignores achievements it already has, so this is safe to repeat. It's what
    /// delivers anything earned while signed out, or before the achievement was set up in
    /// App Store Connect (GameKit doesn't always report an error for an unknown ID, so "sent"
    /// can't be trusted to mean "received").
    func reportAll() {
        var entries = earned.map { completedEntry(id: $0, banner: false) }
        // Totals across devices; one may already have reached its target from another device.
        cloudCountsChanged()
        if !earned.contains(Achievement.starCollector.id), totalStars > 0 {
            entries.append(progress(.starCollector, count: totalStars, target: Achievement.starCollectorTarget))
        }
        if !earned.contains(Achievement.marathon.id), totalGames > 0 {
            entries.append(progress(.marathon, count: totalGames, target: Achievement.marathonTarget))
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

    /// Progress towards a counting achievement (Star Collector, Marathon), shown in Game Center.
    private func progress(_ achievement: Achievement, count: Int, target: Int) -> GKAchievement {
        let entry = GKAchievement(identifier: achievement.id)
        entry.percentComplete = min(100, Double(count) / Double(target) * 100)
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
