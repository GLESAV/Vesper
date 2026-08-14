import AVFoundation

// Synthesizes every sound in the game — no audio assets. Each pop's
// SoundProfile (see PopStandard.swift) is rendered into a small bank of
// buffers (pitch buckets × detuned variants) the first time it's needed —
// ideally at field-seed time via prepare(_:) — so playback is just
// scheduling: no synthesis on the tap path, ~zero latency. A pool of player
// nodes lets chain reactions overlap instead of cutting each other off.
// Sound is a nice-to-have throughout: every failure path degrades to
// silence, never to a crash.
final class PopSoundEngine {
    static let shared = PopSoundEngine()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sampleRate = 44100.0
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0

    private let pitchBuckets = 6
    private let variantsPerBucket = 2
    private var bank: [SoundProfile: [[AVAudioPCMBuffer]]] = [:]
    private var bankOrder: [SoundProfile] = []          // insertion order, for eviction
    private let bankLimit = 14                          // ≈ profiles worth of buffers kept
    private var chimeBuffer: AVAudioPCMBuffer?

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        for _ in 0..<10 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        prepare([PopCatalog.classic.behavior.sound])
        chimeBuffer = makeChimeBuffer()
        configureSession()
        observeInterruptions()
        ensureRunning()
    }

    // Touching .shared from onAppear does the real work; this just gives the
    // call site a name.
    func warmUp() {}

    // MARK: - Buffer bank

    // Render banks for the given profiles if not already cached. Call at
    // field-seed time so first pops never pay a synthesis cost.
    func prepare(_ profiles: [SoundProfile]) {
        for profile in profiles where bank[profile] == nil {
            var buckets: [[AVAudioPCMBuffer]] = []
            for b in 0..<pitchBuckets {
                let pitch = Double(b) / Double(pitchBuckets - 1)
                buckets.append((0..<variantsPerBucket).compactMap { _ in
                    makePopBuffer(profile: profile, pitch: pitch,
                                  detune: Double.random(in: -12...12))
                })
            }
            bank[profile] = buckets
            bankOrder.append(profile)
        }
        while bankOrder.count > bankLimit {
            bank.removeValue(forKey: bankOrder.removeFirst())
        }
    }

    // MARK: - Playback

    // pitch: 0 = large/deep orb, 1 = small/bright orb
    func playPop(profile: SoundProfile, pitch: Double) {
        guard SettingsStore.shared.soundEnabled else { return }
        ensureRunning()
        guard engine.isRunning else { return }
        if bank[profile] == nil { prepare([profile]) }
        guard let buckets = bank[profile] else { return }
        let clamped = min(1, max(0, pitch))
        let bucket = Int((clamped * Double(pitchBuckets - 1)).rounded())
        guard bucket < buckets.count, let buffer = buckets[bucket].randomElement() else { return }
        play(buffer)
    }

    func playCompletionChime() {
        guard SettingsStore.shared.soundEnabled else { return }
        ensureRunning()
        guard engine.isRunning, let chimeBuffer else { return }
        play(chimeBuffer)
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        let node = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }

    // MARK: - Lifecycle

    func setActive(_ active: Bool) {
        if active {
            try? AVAudioSession.sharedInstance().setActive(true)
            ensureRunning()
        } else {
            engine.pause()
        }
    }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended {
                try? AVAudioSession.sharedInstance().setActive(true)
                self.ensureRunning()
            }
        }
    }

    private func ensureRunning() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    // MARK: - Synthesis

    private func makePopBuffer(profile: SoundProfile, pitch: Double,
                               detune: Double) -> AVAudioPCMBuffer? {
        let duration = profile.duration
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount

        let startFreq = profile.startFreq + pitch * profile.freqSpread + detune
        let endFreq = startFreq * profile.sweep
        let channel = buffer.floatChannelData![0]

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let progress = t / duration
            let freq = startFreq + (endFreq - startFreq) * progress
            let phase = 2.0 * .pi * freq * t
            let attack = sin(min(1, progress * 40) * .pi / 2)
            let decay = exp(-progress * profile.decay)
            var sample = sin(phase)
            if profile.brightness > 0 {
                sample += sin(phase * 2) * profile.brightness
            }
            let norm = 1.0 + profile.brightness
            channel[frame] = Float(sample / norm * attack * decay * 0.5)
        }
        return buffer
    }

    // A soft C5–E5–G5 arpeggio for clearing the field: quiet, round, brief.
    private func makeChimeBuffer() -> AVAudioPCMBuffer? {
        let duration = 1.8
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]

        let notes: [(freq: Double, start: Double)] = [
            (523.25, 0.0), (659.25, 0.28), (783.99, 0.56)
        ]
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            var sample = 0.0
            for note in notes where t >= note.start {
                let nt = t - note.start
                let attack = min(1, nt * 30)
                let decay = exp(-nt * 2.6)
                sample += sin(2.0 * .pi * note.freq * nt) * attack * decay * 0.12
            }
            channel[frame] = Float(sample)
        }
        return buffer
    }
}
