import AVFoundation

/// The background music: "On Synthwave" (4/4, 105 bpm, C major), played as an intro, then a
/// seamless loop, then an outro on game over.
///
/// The file is 48 bars: intro bars 1–4, loop bars 5–45, outro bars 46–48. Each piece is queued
/// on an `AVAudioPlayerNode` ahead of time, so the joins are exact to the sample. At 44.1 kHz
/// one bar is exactly 100,800 frames, so every bar line falls on a whole frame.
///
/// - The music starts from the intro when a game starts, unless it's already playing.
/// - On game over it switches to the outro on the next beat, then stays quiet until asked to start again.
/// - It stays off while another app is playing audio, and pauses with the app in the background.
final class MusicPlayer {
    static let shared = MusicPlayer()

    /// The Music switch in Settings. Turning it off fades out; turning it on lets the next
    /// game start it.
    var enabled = true {
        didSet {
            if !enabled && oldValue { stop(fade: true) }
        }
    }

    /// The volume slider in Settings, from 0 (silent) to 1. Changes take effect straight away.
    var level: Float = 0.5 {
        didSet {
            level = min(max(level, 0), 1)
            if state != .stopped && !isFading {
                loopPlayer.volume = playerVolume
                outroPlayer.volume = playerVolume
            }
        }
    }

    // The track's layout, in frames at 44.1 kHz.
    private static let beatFrames: AVAudioFramePosition = 25_200
    private static let barFrames: AVAudioFramePosition = 100_800
    /// The loop runs from the start of bar 5 to the start of bar 46.
    private static let loopStart = 4 * barFrames
    private static let loopEnd = 45 * barFrames

    /// The player's volume at full `level`. The track is mastered much louder than the effects,
    /// so even the top of the slider keeps it well under them.
    private static let maxVolume: Float = 0.35
    private var playerVolume: Float { Self.maxVolume * level }
    private var isFading = false

    private enum State {
        case stopped
        /// The intro, then the loop (queued ahead, forever).
        case playing
        /// The outro is playing out; nothing follows.
        case outro
    }

    private let engine = AVAudioEngine()
    private let loopPlayer = AVAudioPlayerNode()
    private let outroPlayer = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var state: State = .stopped
    /// Changes whenever playback is restarted or stopped, so callbacks from older playback are ignored.
    private var generation = 0
    private var isConfigured = false
    /// Paused for the background or for another app's audio; resumed when that's over.
    private var pausedForBackground = false
    /// The audio output changed while in the background, so the music needs starting afresh.
    private var restartOnResume = false
    private var silencedByOtherAudio = false

    private init() {}

    // MARK: Controls

    /// Loads the track and readies the audio engine without playing, so the first start is clean
    /// rather than stuttering while the app is still busy launching.
    func prepare() {
        _ = configureIfNeeded()
    }

    /// Starts the track from the intro, unless the loop is already playing (an outro in progress
    /// is cut short: a new game gets the music straight away).
    func start() {
        guard enabled, state != .playing else { return }
        guard configureIfNeeded(), let file = file else { return }
        guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else {
            // Another app is playing; start when it stops (see `otherAudioChanged`).
            silencedByOtherAudio = true
            return
        }
        guard startEngine() else { return }

        generation += 1
        let current = generation
        loopPlayer.stop()
        outroPlayer.stop()
        loopPlayer.volume = playerVolume
        // The intro and the first time through the loop in one piece, then the loop queued twice
        // more; each finished loop queues another, so there's always one waiting.
        loopPlayer.scheduleSegment(file, startingFrame: 0, frameCount: AVAudioFrameCount(Self.loopEnd), at: nil)
        queueLoop(current)
        queueLoop(current)
        loopPlayer.play()
        state = .playing
    }

    /// Game over: switch to the outro on the next beat, then stay quiet.
    func playOutro() {
        // Nothing to end if the loop isn't playing (music off, or already finishing).
        guard state == .playing else { return }
        guard let file = file, engine.isRunning, !pausedForBackground,
              let nodeNow = loopPlayer.lastRenderTime, nodeNow.isHostTimeValid,
              let playerNow = loopPlayer.playerTime(forNodeTime: nodeNow)
        else {
            stop(fade: true)
            return
        }
        generation += 1
        let current = generation

        // Where the track is now, and how far to the next beat (at least a short lead, so the
        // outro can be queued in time).
        let position = trackPosition(afterPlaying: playerNow.sampleTime)
        let lead = AVAudioFramePosition(0.08 * 44_100)
        let nextBeat = ((position + lead) / Self.beatFrames + 1) * Self.beatFrames
        let delay = Double(nextBeat - position) / 44_100
        let startTime = AVAudioTime(hostTime: nodeNow.hostTime + AVAudioTime.hostTime(forSeconds: delay))

        outroPlayer.volume = playerVolume
        let outroFrames = AVAudioFrameCount(file.length - Self.loopEnd)
        outroPlayer.scheduleSegment(file, startingFrame: Self.loopEnd, frameCount: outroFrames, at: nil,
                                    completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.generation == current else { return }
                self.state = .stopped
            }
        }
        outroPlayer.play(at: startTime)
        state = .outro

        // Stop the loop just after the outro comes in (the outro's opening hit covers the change).
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.02) { [weak self] in
            guard let self = self, self.generation == current else { return }
            self.loopPlayer.stop()
        }
    }

    /// Stops everything, optionally with a short fade.
    func stop(fade: Bool) {
        generation += 1
        let current = generation
        state = .stopped
        silencedByOtherAudio = false
        guard fade, engine.isRunning else {
            loopPlayer.stop()
            outroPlayer.stop()
            return
        }
        fadeOut(over: 0.6) { [weak self] in
            guard let self = self, self.generation == current else { return }
            self.loopPlayer.stop()
            self.outroPlayer.stop()
        }
    }

    /// The app went to the background: pause where it is.
    func pauseForBackground() {
        guard state != .stopped, !pausedForBackground else { return }
        pausedForBackground = true
        loopPlayer.pause()
        outroPlayer.pause()
    }

    /// Back from the background: carry on from where it paused.
    func resumeFromBackground() {
        guard pausedForBackground else { return }
        pausedForBackground = false
        if restartOnResume {
            // The audio output changed while away, which cleared the queue: from the intro again.
            restartOnResume = false
            if state == .playing {
                state = .stopped
                start()
            }
            return
        }
        guard state != .stopped, startEngine() else { return }
        if state == .playing { loopPlayer.play() } else { outroPlayer.play() }
    }

    // MARK: Setup

    /// Loads the track and wires up the engine, once. False if the track is missing.
    private func configureIfNeeded() -> Bool {
        if isConfigured { return file != nil }
        isConfigured = true
        SoundEngine.configureSessionIfNeeded()
        guard let url = Bundle.main.url(forResource: "On Synthwave", withExtension: "m4a"),
              let file = try? AVAudioFile(forReading: url)
        else {
            print("Music track missing")
            return false
        }
        self.file = file
        for player in [loopPlayer, outroPlayer] {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        }
        engine.prepare()

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil,
                           queue: .main) { [weak self] note in self?.otherAudioChanged(note) }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                           queue: .main) { [weak self] note in self?.interrupted(note) }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                           queue: .main) { [weak self] _ in self?.configurationChanged() }
        return true
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            print("Music engine couldn't start: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Looping

    /// Queues one more time through the loop; when it's been used, queues the next.
    private func queueLoop(_ current: Int) {
        guard let file = file else { return }
        loopPlayer.scheduleSegment(file, startingFrame: Self.loopStart,
                                   frameCount: AVAudioFrameCount(Self.loopEnd - Self.loopStart), at: nil,
                                   completionCallbackType: .dataConsumed) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.generation == current, self.state == .playing else { return }
                self.queueLoop(current)
            }
        }
    }

    /// Where in the file playback is, given how many frames the loop player has played since it
    /// started: the intro and first loop run straight through, then the loop repeats.
    private func trackPosition(afterPlaying played: AVAudioFramePosition) -> AVAudioFramePosition {
        guard played >= Self.loopEnd else { return max(played, 0) }
        let loopLength = Self.loopEnd - Self.loopStart
        return Self.loopStart + (played - Self.loopEnd) % loopLength
    }

    private func fadeOut(over duration: TimeInterval, then done: @escaping () -> Void) {
        isFading = true
        // A fade belongs to the playback it started on; anything newer cancels it.
        let current = generation
        let steps = 12
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * Double(step) / Double(steps)) { [weak self] in
                guard let self = self else { return }
                guard self.generation == current else {
                    self.isFading = false
                    return
                }
                let fraction = Float(steps - step) / Float(steps)
                self.loopPlayer.volume = min(self.loopPlayer.volume, self.playerVolume * fraction)
                self.outroPlayer.volume = min(self.outroPlayer.volume, self.playerVolume * fraction)
                if step == steps {
                    self.isFading = false
                    done()
                }
            }
        }
    }

    // MARK: System events

    /// Another app started or stopped playing audio: step aside, then start again afterwards.
    private func otherAudioChanged(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: raw) else { return }
        switch type {
        case .begin:
            if state != .stopped {
                stop(fade: true)
                silencedByOtherAudio = true
            }
        case .end:
            if silencedByOtherAudio {
                silencedByOtherAudio = false
                start()
            }
        @unknown default:
            break
        }
    }

    /// A phone call or similar: carry on afterwards if the system says so.
    private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw),
              type == .ended, state != .stopped, !pausedForBackground else { return }
        guard startEngine() else { return }
        if state == .playing { loopPlayer.play() } else { outroPlayer.play() }
    }

    /// The audio route changed (headphones, for example), which stops the engine and its queue:
    /// start the track again.
    private func configurationChanged() {
        // Rewire for the new output's sample rate and channels, as the old wiring may not suit it.
        engine.stop()
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.prepare()
        switch state {
        case .stopped:
            return
        case .outro:
            // Just a fading tail: let it go.
            stop(fade: false)
        case .playing where pausedForBackground:
            // The queued music is gone; start afresh once the app is back.
            restartOnResume = true
        case .playing:
            state = .stopped
            start()
        }
    }
}
