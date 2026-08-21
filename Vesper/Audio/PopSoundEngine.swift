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

    /// Whirr buffers, cached by start frequency.
    private var whirrBank: [Int: AVAudioPCMBuffer?] = [:]
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

    /// The whirr of a shell climbing.
    ///
    /// **The one rising pitch in the game.** Everything else was floored
    /// against falling sweeps because a fast fall is an arcade laser — but a
    /// firework fuse genuinely does rise, and rising is the safe direction:
    /// it reads as something leaving, not as something firing at you. It is
    /// also the only sound here that is deliberately noisy rather than
    /// pitched, because a fuse is air and grit, not a note.
    ///
    /// Rendered on demand and cached by start frequency: there are 36 shells
    /// and most fields hold a handful, so the bank stays small.
    func playWhirr(startFreq: Double) {
        guard SettingsStore.shared.soundEnabled else { return }
        ensureRunning()
        guard engine.isRunning else { return }
        let key = Int(startFreq.rounded())
        if whirrBank[key] == nil {
            whirrBank[key] = makeWhirrBuffer(startFreq: startFreq)
        }
        guard let buffer = whirrBank[key] ?? nil else { return }
        play(buffer)
    }

    private func makeWhirrBuffer(startFreq: Double) -> AVAudioPCMBuffer? {
        let duration = 1.05
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]

        var rngState = UInt64(bitPattern: Int64(key(startFreq))) | 1
        func noise() -> Double {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: rngState >> 11)) / Double(1 << 52) - 1
        }

        var bp1 = 0.0, bp2 = 0.0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let progress = t / duration
            // Rises as it climbs, and thins as it goes away from her.
            let freq = startFreq * (1 + 0.9 * progress)
            let k = min(0.5, freq / sampleRate * 8)
            let n = noise()
            bp1 += k * (n - bp1)
            bp2 += k * (bp1 - bp2)
            // A quiet pitched core under the air, so it has a direction.
            let core = sin(2.0 * .pi * freq * t) * 0.16
            let envelope = sin(min(1, progress * 12) * .pi / 2) * (1 - progress * 0.85)
            channel[frame] = Float(((bp1 - bp2) * 5 + core) * envelope * 0.22)
        }
        return buffer
    }

    private func key(_ freq: Double) -> Int { Int(freq.rounded()) }

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

        // THE SPACE INVADERS BUG. The owner heard it immediately: the base pop
        // sounded like an arcade laser. The data says exactly why — the classic
        // profile sweeps from 460 Hz down to 55% of that (253 Hz) in 140 ms,
        // and a fast DOWNWARD pitch sweep is, definitionally, the "pew". It is
        // the sound of every zap ever made, and it had been the base pop since
        // v1.0.
        //
        // Two fixes, both here rather than in 100 catalog entries.
        //
        // 1. NO STEEP FALLS. A drop of more than a few percent inside a pop's
        //    length is a laser; anything gentler is a settle. Voices that WANT
        //    a fall — `.drop` is a drop into water — opt back in below.
        // The catalog's sweeps are all lifts now (see the standard's envelope,
        // which used to REQUIRE a fall). `.drop` is the one voice whose whole
        // identity is a falling pitch — a drop into still water — so it
        // computes its own fall here rather than needing the data to carry a
        // value that would be wrong for every other voice.
        let laserFloor = 0.94
        let dropFall = 0.72
        let sweepUsed = profile.voice == .drop ? dropFall : max(profile.sweep, laserFloor)

        // 2. EVERY POP IS A NOTE IN ONE SCALE. Frequencies were free-floating,
        //    so a chain of five was five arbitrary pitches — which is noise,
        //    however soft each one is. Snapped to a major pentatonic, any
        //    combination of pops is consonant, and a cascade becomes an
        //    arpeggio instead of a clatter. This is the single biggest reason
        //    the game will now sound pleasant rather than merely quiet, and it
        //    costs one lookup.
        let rawStart = profile.startFreq + pitch * profile.freqSpread + detune
        let startFreq = Self.snapToPentatonic(rawStart)
        let endFreq = startFreq * sweepUsed
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
            case .breath, .shimmer:
                attack = sin(min(1, progress * 6) * .pi / 2)      // slow, arriving
            case .pop, .glass, .pluck, .wood, .crackle:
                attack = sin(min(1, progress * 90) * .pi / 2)     // near-instant
            default:
                attack = sin(min(1, progress * 40) * .pi / 2)     // v1.0
            }

            var sample: Double
            var norm = 1.0

            switch profile.voice {
            case .pop:
                // THE ASMR POP. What a bubble, a water drop or a mouth pop
                // actually does: a very short broadband transient, then a
                // resonant body that lifts slightly as it goes. The lift is
                // the opposite of the laser and is most of why this reads as
                // pleasant — things that open go up.
                let transient = exp(-progress * 90) * noise() * 0.5
                let lift = 1 + 0.06 * progress
                let body = sin(2.0 * .pi * startFreq * lift * t)
                sample = transient + body
                    + 0.22 * sin(2.0 * .pi * startFreq * 2.02 * t) * exp(-progress * profile.decay * 2.5)
                norm = 1.6

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

    // MARK: - The scale

    /// Major pentatonic across the range a pop can occupy.
    ///
    /// Pentatonic because it has no semitone clashes at all: every pair of
    /// notes in it is consonant, so pops arriving in any order and any overlap
    /// still sound like music. That property is what makes a five-orb chain
    /// pleasant rather than merely quiet, and it is why this scale and not a
    /// major one.
    private static let scale: [Double] = {
        // C, D, E, G, A relative to a 65.41 Hz root, over seven octaves.
        let steps: [Double] = [1, 9.0 / 8, 5.0 / 4, 3.0 / 2, 5.0 / 3]
        var notes: [Double] = []
        for octave in 0..<7 {
            let root = 65.41 * pow(2, Double(octave))
            for s in steps { notes.append(root * s) }
        }
        return notes
    }()

    /// Nearest note in the scale. Binary search would be faster and is not
    /// worth it: this runs once per pop at buffer-render time, not per frame.
    static func snapToPentatonic(_ freq: Double) -> Double {
        guard freq > 0 else { return freq }
        var best = scale[0]
        var bestDistance = Double.infinity
        for note in scale {
            // Compared in log space: pitch distance is ratio, not difference.
            let d = abs(log2(note / freq))
            if d < bestDistance { bestDistance = d; best = note }
        }
        return best
    }

    // A soft C5–E5–G5 arpeggio for clearing the field: quiet, round, brief.
    private func makeChimeBuffer() -> AVAudioPCMBuffer? {
        // SHORT. It was 1.8 seconds — a C–E–G arpeggio spread over more than
        // half a second of onsets and then left to ring — and the owner heard
        // it for what it had become: an announcement.
        //
        // The failure was one of GRAMMAR rather than length. A rising
        // arpeggio that resolves is a fanfare, and a fanfare says "well
        // done", which is the one thing the end of a field must never say
        // (05 §6, and the whole argument behind the done card's rewrite).
        // The field going quiet is not an achievement, it is a room settling.
        //
        // So: 0.62 s, the three notes nearly together rather than in
        // sequence, and the top note quietest — the shape of a small bell
        // being touched once, not a phrase being played. Still the same three
        // pitches, so it is recognisably the sound she already knows.
        let duration = 0.62
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]

        // Onsets 40 ms apart, so they arrive as one struck thing rather than
        // as a tune. Amplitude falls with pitch: the top note is a highlight
        // on the chord, never the point of it.
        let notes: [(freq: Double, start: Double, gain: Double)] = [
            (523.25, 0.00, 0.13), (659.25, 0.04, 0.10), (783.99, 0.08, 0.07)
        ]
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            var sample = 0.0
            for note in notes where t >= note.start {
                let nt = t - note.start
                let attack = min(1, nt * 60)
                let decay = exp(-nt * 7.5)
                sample += sin(2.0 * .pi * note.freq * nt) * attack * decay * note.gain
            }
            // A short raised-cosine tail so the buffer cannot end on a
            // non-zero sample and click — at 0.62 s the decay has not quite
            // reached silence on its own.
            let fadeStart = duration - 0.06
            if t > fadeStart {
                sample *= 0.5 * (1 + cos(.pi * (t - fadeStart) / 0.06))
            }
            channel[frame] = Float(sample)
        }
        return buffer
    }
}
