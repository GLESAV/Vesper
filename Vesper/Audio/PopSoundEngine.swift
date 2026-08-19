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

        // ONE INSTRUMENT PER VOICE. Everything below shares the envelope
        // discipline of the original — a fast raised-cosine attack so nothing
        // clicks, an exponential decay, and a final 0.5 gain so nothing in
        // this game is ever loud — and differs in how the sample itself is
        // made. That is the difference between a hundred notes on one string
        // and a hundred sounds.
        //
        // Deterministic noise: a small LCG seeded from the profile's own
        // numbers, never `Double.random` and never `hashValue` — Swift seeds
        // its hasher per process, so a hash-seeded texture would be subtly
        // different on every launch. Buffers are pre-rendered and cached, and
        // a pop has to be the same sound every time anyone hears it.
        var rngState = (profile.startFreq.bitPattern &* 31)
            ^ (profile.duration.bitPattern &* 131)
            ^ UInt64(profile.voice.rawValue.count &+ 7)
        rngState |= 1
        func noise() -> Double {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: rngState >> 11)) / Double(1 << 52) - 1
        }

        // A one-pole low-pass, for the voices built out of noise.
        var lp = 0.0
        // A two-sample history for the band-passed voices.
        var bp1 = 0.0, bp2 = 0.0

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let progress = t / duration
            let freq = startFreq + (endFreq - startFreq) * progress
            let phase = 2.0 * .pi * freq * t
            let decay = exp(-progress * profile.decay)

            // Attack shape is part of a voice's identity: a bell and a breath
            // differ more in how they START than in what they contain.
            let attack: Double
            switch profile.voice {
            case .swell, .breath, .shimmer:
                attack = sin(min(1, progress * 6) * .pi / 2)      // slow, arriving
            case .glass, .pluck, .wood, .crackle:
                attack = sin(min(1, progress * 90) * .pi / 2)     // near-instant
            default:
                attack = sin(min(1, progress * 40) * .pi / 2)     // v1.0
            }

            var sample: Double
            var norm = 1.0

            switch profile.voice {
            case .tone:
                sample = sin(phase)
                if profile.brightness > 0 { sample += sin(phase * 2) * profile.brightness }
                norm = 1.0 + profile.brightness

            case .bell:
                // Inharmonic partials — the ratios are what make a bell read
                // as struck metal rather than as a chord.
                sample = sin(phase)
                    + 0.6 * sin(phase * 2.76) * exp(-progress * profile.decay * 1.6)
                    + 0.35 * sin(phase * 5.40) * exp(-progress * profile.decay * 2.4)
                norm = 1.95

            case .pluck:
                // Harmonics that collapse at different rates: bright for a
                // few milliseconds, then just a body.
                sample = sin(phase)
                    + 0.5 * sin(phase * 2) * exp(-progress * profile.decay * 3)
                    + 0.25 * sin(phase * 3) * exp(-progress * profile.decay * 6)
                norm = 1.75

            case .breath:
                // Band-passed noise: air with a pitch centre rather than a
                // pitch. Two poles are enough to hear the centre move.
                let n = noise()
                let k = min(0.45, freq / sampleRate * 6)
                bp1 += k * (n - bp1)
                bp2 += k * (bp1 - bp2)
                sample = (bp1 - bp2) * 6
                norm = 1.4

            case .glass:
                // A detuned pair beating against itself, very short.
                sample = sin(phase) + 0.85 * sin(phase * 1.008)
                    + 0.3 * sin(phase * 4.1) * exp(-progress * profile.decay * 4)
                norm = 2.0

            case .wood:
                // Low, damped, and mostly transient: the pitch barely
                // survives the attack.
                let body = sin(phase) * exp(-progress * profile.decay * 2.2)
                lp += 0.22 * (noise() - lp)
                sample = body + lp * 1.6 * exp(-progress * profile.decay * 5)
                norm = 1.9

            case .crackle:
                // Sparse noise grains over a quiet low body. The grains are
                // gated so it reads as crackling rather than as hiss.
                let n = noise()
                let grain = abs(n) > 0.86 ? n * 1.4 : n * 0.12
                lp += 0.4 * (grain - lp)
                sample = lp * 1.5 + 0.35 * sin(phase * 0.5)
                norm = 1.7

            case .swell:
                // Water: a low sine under a slow noise wash, both arriving.
                lp += 0.05 * (noise() - lp)
                sample = sin(phase) * 0.75 + lp * 1.1
                norm = 1.6

            case .shimmer:
                // Three detuned sines with slow amplitude drift — the pitch
                // is present but never quite settles.
                let drift = 1 + 0.02 * sin(2 * .pi * 3.1 * t)
                sample = sin(phase * drift)
                    + 0.7 * sin(phase * 1.004)
                    + 0.5 * sin(phase * 0.996)
                sample *= 0.6 + 0.4 * sin(2 * .pi * 5.5 * t)
                norm = 2.2

            case .drop:
                // A pitch that falls fast and lands: the sweep does the work,
                // so it is steepened here rather than in the profile.
                let fallen = startFreq + (endFreq - startFreq) * pow(progress, 0.35)
                sample = sin(2.0 * .pi * fallen * t)
                    + 0.3 * sin(2.0 * .pi * fallen * 2 * t) * exp(-progress * profile.decay * 3)
                norm = 1.3
            }

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
