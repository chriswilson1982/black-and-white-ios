import CoreMotion
import SwiftUI

/// The moving background behind the game: a mesh gradient of the game's four colours
/// (white, black, locked and path) that sways gently and leans as the phone tilts.
/// Each round shuffles where the colours sit. After a win it blends to shades of the path colour,
/// after a loss to shades of the locked colour.
struct GameBackground: View {
    let mood: GameMood
    /// Changes each round; a new value shuffles the colours.
    let shuffle: Int
    /// Resolved settings, for the background, locked and path colours.
    let settings: GameSettings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = TiltReader()
    /// Which of the four colours sits at each of the nine mesh points, row by row.
    @State private var arrangement = GameBackground.randomArrangement()
    /// What's being blended away from, and when the blend started.
    @State private var previousMood: GameMood = .playing
    @State private var previousArrangement = GameBackground.randomArrangement()
    @State private var changedAt = Date.distantPast

    /// How strongly the colours show over the plain background, so the board stays easy to read.
    private let strength = 0.35
    private let blendDuration: TimeInterval = 0.8

    var body: some View {
        ZStack {
            Color(uiColor: settings.background.uiColor)
            // 30 frames a second is plenty for a slow sway.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                gradient(at: context.date)
            }
            .opacity(strength)
        }
        .ignoresSafeArea()
        .onChange(of: mood) { oldMood, _ in
            previousMood = oldMood
            previousArrangement = arrangement
            changedAt = .now
        }
        .onChange(of: shuffle) { _, _ in
            previousArrangement = arrangement
            arrangement = Self.randomArrangement()
            changedAt = .now
        }
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
    }

    @ViewBuilder
    private func gradient(at date: Date) -> some View {
        let colors = colors(at: date).map { Color(uiColor: $0) }
        if #available(iOS 18.0, *) {
            MeshGradient(width: 3, height: 3, points: points(at: date), colors: colors)
        } else {
            // Mesh gradients need iOS 18; a diagonal blend of the same colours stands in.
            LinearGradient(colors: [colors[0], colors[4], colors[8]],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Colours

    /// The four colours, numbered as in `arrangement`.
    private var fourColors: [UIColor] {
        [.white, .black, settings.lockColor.uiColor, settings.pathColor.uiColor]
    }

    /// Each of the four colours twice, plus one more at random, shuffled over the nine points,
    /// so every colour always shows.
    private static func randomArrangement() -> [Int] {
        ([0, 0, 1, 1, 2, 2, 3, 3] + [Int.random(in: 0..<4)]).shuffled()
    }

    /// The nine mesh colours, part-way through blending from the previous look to the current one.
    private func colors(at date: Date) -> [UIColor] {
        let raw = min(max(date.timeIntervalSince(changedAt) / blendDuration, 0), 1)
        let progress = raw * raw * (3 - 2 * raw) // Ease in and out.
        let from = palette(for: previousMood, arrangement: previousArrangement)
        let to = palette(for: mood, arrangement: arrangement)
        return zip(from, to).map { $0.blended(with: $1, amount: progress) }
    }

    /// Row by row, top to bottom.
    private func palette(for mood: GameMood, arrangement: [Int]) -> [UIColor] {
        switch mood {
        case .playing:
            return arrangement.map { fourColors[$0] }
        case .won:
            return shades(of: settings.pathColor.uiColor)
        case .lost:
            return shades(of: settings.lockColor.uiColor)
        }
    }

    /// One colour at different strengths, faded towards the background.
    private func shades(of color: UIColor) -> [UIColor] {
        let backdrop = settings.background.uiColor
        return [0, 0.5, 0.15,
                0.6, 0.3, 0.7,
                0.2, 0.55, 0].map { color.blended(with: backdrop, amount: $0) }
    }

    // MARK: Movement

    /// The mesh's points. Corners stay put, edge points sway along their edges and the
    /// middle point wanders, each on its own slow cycle (roughly 10–20 seconds), so the
    /// colours drift gently around. Still when Reduce Motion is on.
    private func points(at date: Date) -> [SIMD2<Float>] {
        let t = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
        let lean = reduceMotion ? SIMD2<Double>(0, 0) : tilt.lean()
        func wave(_ speed: Double, _ phase: Double) -> Double { sin(t * speed + phase) }
        func p(_ x: Double, _ y: Double) -> SIMD2<Float> {
            SIMD2(Float(min(max(x, 0), 1)), Float(min(max(y, 0), 1)))
        }
        let top = 0.5 + 0.18 * wave(0.50, 0) + 0.1 * lean.x
        let bottom = 0.5 + 0.18 * wave(0.42, 2.1) + 0.1 * lean.x
        let left = 0.5 + 0.18 * wave(0.46, 4.2) + 0.1 * lean.y
        let right = 0.5 + 0.18 * wave(0.55, 1.3) + 0.1 * lean.y
        // Two waves each way, so the middle point loops around rather than just swinging.
        let middleX = 0.5 + 0.16 * wave(0.33, 3.3) + 0.06 * wave(0.71, 0.4) + 0.15 * lean.x
        let middleY = 0.5 + 0.16 * wave(0.29, 5.0) + 0.06 * wave(0.63, 2.7) + 0.15 * lean.y
        return [p(0, 0), p(top, 0), p(1, 0),
                p(0, left), p(middleX, middleY), p(1, right),
                p(0, 1), p(bottom, 1), p(1, 1)]
    }
}

/// Reads how the phone is tilted, so the background can lean with it.
final class TiltReader {
    private let manager = CMMotionManager()
    private var smoothed = SIMD2<Double>(0, 0)

    func start() {
        guard manager.isAccelerometerAvailable, !manager.isAccelerometerActive else { return }
        manager.accelerometerUpdateInterval = 1.0 / 30
        manager.startAccelerometerUpdates()
    }

    func stop() {
        manager.stopAccelerometerUpdates()
    }

    /// Sideways and forward tilt, each roughly -1...1 (0 when held upright), eased so it doesn't jitter.
    func lean() -> SIMD2<Double> {
        guard let a = manager.accelerometerData?.acceleration else { return smoothed }
        // Held upright, y is about -1; leaning the top away brings it towards 0.
        let target = SIMD2(min(max(a.x, -1), 1), min(max(a.y + 0.6, -1), 1))
        smoothed += (target - smoothed) * 0.1
        return smoothed
    }
}
