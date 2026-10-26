import Foundation
import Observation

struct ScoreEntry: Codable, Identifiable {
    var id = UUID()
    let name: String
    let score: Int
    let date: Date
    let difficulty: Difficulty
}

/// A best score and when it was set.
struct BestScore: Equatable {
    let score: Int
    let date: Date
}

/// Every finished game played on this device, for the personal high scores screen, plus the
/// best score at each difficulty synced through iCloud across the player's devices.
/// Replaces the original SQLite database. Comparing with other players is Game Center's job.
@Observable
final class HighScoreStore {
    private(set) var entries: [ScoreEntry] = []
    /// The best score at each difficulty on any of the player's devices.
    private(set) var syncedBest: [Difficulty: BestScore] = [:]

    private let fileURL: URL
    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var cloudObserver: NSObjectProtocol?

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("scores.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([ScoreEntry].self, from: data) {
            entries = saved
        }

        // Another device set a new best: take it on.
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            self?.mergeWithCloud()
        }
        cloud.synchronize()
        mergeWithCloud()
    }

    deinit {
        if let cloudObserver = cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
    }

    /// Saves a finished game's score. Scores of zero or less are not recorded.
    /// Returns true if it beats the player's best at this difficulty on any of their devices.
    @discardableResult
    func record(name: String, score: Int, difficulty: Difficulty) -> Bool {
        guard score > 0 else { return false }
        let localBest = entries.filter { $0.difficulty == difficulty }.map(\.score).max() ?? 0
        let previousBest = max(localBest, syncedBest[difficulty]?.score ?? 0)
        let entry = ScoreEntry(name: name, score: score, date: Date(), difficulty: difficulty)
        entries.append(entry)
        save()
        guard score > previousBest else { return false }
        let best = BestScore(score: score, date: entry.date)
        syncedBest[difficulty] = best
        writeToCloud(best, for: difficulty)
        return true
    }

    /// The highest-scoring games at a difficulty, best first (earlier games first on a tie).
    func bestGames(for difficulty: Difficulty, limit: Int = 10) -> [ScoreEntry] {
        Array(entries.filter { $0.difficulty == difficulty }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.date < $1.date }
            .prefix(limit))
    }

    /// The latest games at a difficulty, newest first.
    func recentGames(for difficulty: Difficulty, limit: Int = 5) -> [ScoreEntry] {
        Array(entries.filter { $0.difficulty == difficulty }
            .sorted { $0.date > $1.date }
            .prefix(limit))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: iCloud

    /// Keeps the highest of iCloud's best, this device's best and what's already known,
    /// for each difficulty, and sends it back to iCloud if this device has a better one.
    private func mergeWithCloud() {
        for difficulty in Difficulty.allCases {
            let fromCloud = readFromCloud(for: difficulty)
            let fromDevice = bestGames(for: difficulty, limit: 1).first.map { BestScore(score: $0.score, date: $0.date) }
            let candidates = [fromCloud, fromDevice, syncedBest[difficulty]].compactMap { $0 }
            // Highest score wins; on a tie, the earlier date (when it was first set).
            guard let best = candidates.max(by: { ($0.score, $1.date) < ($1.score, $0.date) }) else { continue }
            syncedBest[difficulty] = best
            if best.score > (fromCloud?.score ?? 0) {
                writeToCloud(best, for: difficulty)
            }
        }
    }

    private func cloudKey(for difficulty: Difficulty) -> String {
        "bestScore.\(difficulty.name.lowercased())"
    }

    private func readFromCloud(for difficulty: Difficulty) -> BestScore? {
        guard let saved = cloud.dictionary(forKey: cloudKey(for: difficulty)),
              let score = saved["score"] as? Int, score > 0,
              let time = saved["date"] as? Double
        else { return nil }
        return BestScore(score: score, date: Date(timeIntervalSince1970: time))
    }

    private func writeToCloud(_ best: BestScore, for difficulty: Difficulty) {
        cloud.set(["score": best.score, "date": best.date.timeIntervalSince1970] as [String: Any],
                  forKey: cloudKey(for: difficulty))
    }
}
