import AVFoundation

/// The game's sound effects. The original used Pythonista's built-in sounds, which aren't
/// available on iOS, so these are small retro-style tones generated at launch.
enum SoundEffect: CaseIterable {
    case tap, button, win, fail, noWhite, newGame, flip, unlock
    case starBonus, star, starAway, negative, tick, powerup

    /// Every pitch is a note of C major (A minor for the failure sounds, its relative minor),
    /// in equal temperament at A4 = 440 Hz, so the effects sit happily with music in that key.
    /// Glides start and end on notes of the scale; noise has no pitch.
    fileprivate var notes: [SynthNote] {
        typealias P = Pitch
        switch self {
        case .tap:
            return [SynthNote(P.A4, P.E5, 0.07, .square)]
        case .button:
            return [SynthNote(P.F6, P.F6, 0.03, .triangle)]
        case .win:
            return [SynthNote(P.C5, 0.08), SynthNote(P.E5, 0.08), SynthNote(P.G5, 0.08), SynthNote(P.C6, 0.2)]
        case .fail:
            // A quick, low crunch of noise and a beat's pause, then three falling tones (A, E, A),
            // each sagging slightly as it fades.
            return [SynthNote(1400, 350, 0.12, .noise), SynthNote(0, 0.07, .rest),
                    SynthNote(P.A4, P.A4 * 0.955, 0.14, .saw), SynthNote(P.E4, P.E4 * 0.94, 0.14, .saw),
                    SynthNote(P.A3, P.C3, 0.32, .saw)]
        case .noWhite:
            return [P.C5, P.E5, P.G5, P.C6, P.E6, P.G6].map { SynthNote($0, 0.06, .square) }
        case .newGame:
            return [SynthNote(P.A3, P.A5, 0.25, .square)]
        case .flip:
            return [SynthNote(P.G4, P.D6, 0.12, .triangle), SynthNote(P.D6, P.G4, 0.12, .triangle)]
        case .unlock:
            return [SynthNote(P.D5, 0.07, .sine), SynthNote(P.G5, 0.07, .sine), SynthNote(P.D6, 0.14, .sine)]
        case .starBonus:
            return [SynthNote(P.C6, 0.07, .sine), SynthNote(P.E6, 0.07, .sine),
                    SynthNote(P.G6, 0.07, .sine), SynthNote(P.C7, 0.28, .sine)]
        case .star:
            return [SynthNote(P.C5, P.C7, 0.3, .sine)]
        case .starAway:
            return [SynthNote(P.G6, P.D4, 0.35, .sine)]
        case .negative:
            return [SynthNote(P.D5, P.G3, 0.35, .saw)]
        case .tick:
            return [SynthNote(P.B5, 0.05, .sine)]
        case .powerup:
            return [SynthNote(P.G5, 0.07, .square), SynthNote(P.D6, 0.12, .square)]
        }
    }
}

/// The notes of C major used by the effects, in hertz (equal temperament, A4 = 440).
fileprivate enum Pitch {
    static let C3 = 130.81
    static let G3 = 196.00
    static let A3 = 220.00
    static let D4 = 293.66
    static let E4 = 329.63
    static let G4 = 392.00
    static let A4 = 440.00
    static let C5 = 523.25
    static let D5 = 587.33
    static let E5 = 659.26
    static let G5 = 783.99
    static let A5 = 880.00
    static let B5 = 987.77
    static let C6 = 1046.50
    static let D6 = 1174.66
    static let E6 = 1318.51
    static let F6 = 1396.91
    static let G6 = 1567.98
    static let C7 = 2093.00
}

/// `rest` is silence, for a pause between notes. `noise` is retro console-style noise: a new
/// random level each cycle, so the frequency sets how low and crunchy (or high and hissy) it sounds.
fileprivate enum Wave { case sine, square, triangle, saw, noise, rest }

fileprivate struct SynthNote {
    let from: Double
    let to: Double
    let duration: Double
    let wave: Wave

    init(_ from: Double, _ to: Double, _ duration: Double, _ wave: Wave) {
        self.from = from
        self.to = to
        self.duration = duration
        self.wave = wave
    }

    init(_ frequency: Double, _ duration: Double, _ wave: Wave = .triangle) {
        self.init(frequency, frequency, duration, wave)
    }
}

final class SoundEngine {
    static let shared = SoundEngine()

    var enabled = true

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var isConfigured = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    }

    func play(_ effect: SoundEffect) {
        guard enabled else { return }
        configureIfNeeded()
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        guard let buffer = buffers[effect], !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        // Ambient: respects the silent switch and mixes with the player's music.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        // Activating can wait on the system's audio service, so keep it off the main thread
        // (this runs when the first sound plays, mid-game).
        if #available(iOS 27.0, *) {
            session.activate { _, _ in }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                try? session.setActive(true)
            }
        }

        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.35
        for effect in SoundEffect.allCases {
            buffers[effect] = render(effect.notes)
        }
        engine.prepare()
    }

    private func render(_ notes: [SynthNote]) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = notes.reduce(0) { $0 + Int($1.duration * rate) }
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)

        var offset = 0
        var phase = 0.0
        var noiseLevel = 0.0
        for note in notes {
            let count = Int(note.duration * rate)
            let attack = min(0.004 * rate, Double(count) / 4)
            for i in 0..<count {
                let t = Double(i) / Double(max(count - 1, 1))
                // Exponential glide between the two frequencies.
                let frequency = note.wave == .rest ? 0 : note.from * pow(note.to / note.from, t)
                phase += frequency / rate
                if phase >= 1 {
                    // A new noise level each time round.
                    noiseLevel = Double.random(in: -1...1)
                }
                phase -= floor(phase)

                let raw: Double
                switch note.wave {
                case .sine: raw = sin(2 * .pi * phase)
                case .square: raw = (phase < 0.5 ? 1 : -1) * 0.45
                case .triangle: raw = 4 * abs(phase - 0.5) - 1
                case .saw: raw = (2 * phase - 1) * 0.5
                case .noise: raw = noiseLevel * 0.5
                case .rest: raw = 0
                }
                // Short fade in, then decay, so notes don't click.
                let envelope = min(1, Double(i) / max(attack, 1)) * pow(1 - t, 1.5)
                samples[offset + i] = Float(raw * envelope * 0.6)
            }
            offset += count
        }
        return buffer
    }
}
