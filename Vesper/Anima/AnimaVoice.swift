import Foundation

// ANIMA — sound. A voice is an instrument described as data and rendered to
// samples by one small loop.
//
// ─────────────────────────────────────────────────────────────────────────
// THE PROBLEM, STATED FROM THE EXISTING CODE.
//
// `PopSoundEngine.makePopBuffer` is a ~200-line `for frame` loop with a
// ten-way `switch` inside it, one branch per voice. It is good code and it
// sounds right, but it has a property that decides this file: ADDING AN
// ELEVENTH SOUND IS AN ENGINEERING TASK. Someone has to open the synthesis
// loop, add a branch, reason about the shared envelope and the shared gain,
// rebuild, and listen on a device. That is the cost this engine exists to
// remove, and it is the same cost that made new 2-D objects expensive.
//
// So: an instrument is a bag of partials, a bag of noise, and an envelope.
// Every one of the ten existing voices is expressible in it — `bell` is
// inharmonic partials with a long decay, `wood` is one low partial under a
// fast-decaying noise burst, `glass` is a detuned pair, `breath` is noise
// with no partials at all. Authoring an eleventh becomes a row in a catalog.
//
// ─────────────────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES NOT DO, ON PURPOSE.
//
// It does not import AVFoundation and it does not play anything. It answers
// an array of `Float` in −1...1. That keeps it testable (a test can assert
// the peak, the DC offset, the click-freeness of the attack) and it keeps it
// exportable — `AnimaStudio` writes these samples into the browser previewer
// so that what an author hears in a browser is the same arithmetic that will
// come out of the phone, not a WebAudio approximation of it.
//
// Wiring a rendered buffer into `AVAudioEngine` is `PopSoundEngine`'s job and
// stays there.
//
// ─────────────────────────────────────────────────────────────────────────
// THE SAFETY PROPERTIES ARE INHERITED, NOT REDISCOVERED.
//
// Three rules were learned the expensive way in `PopSoundEngine` and are
// enforced here so a data-authored voice cannot break them:
//
//   1. NO STEEP DOWNWARD PITCH SWEEP. A fall of more than a few percent
//      inside a pop's length is, definitionally, an arcade laser — it is
//      what made the base pop sound like Space Invaders. Voices that want a
//      fall (a drop into water) must say so explicitly with `allowsFall`.
//   2. A RAISED-COSINE ATTACK. Any envelope that starts at full amplitude
//      clicks, and a click in a calm game is the loudest thing in it.
//   3. NOTHING IS EVER LOUD. A master gain well under unity, and a final
//      clamp so no sum of partials can clip.
//
// All three are asserted in `AnimaTests` against every voice in the library,
// which is the point of having them here rather than in a review checklist.

// MARK: - Partials

/// One sine component of a voice.
///
/// `ratio` is a multiple of the fundamental. Integer ratios are harmonic and
/// read as pitched; non-integer ratios are inharmonic and read as struck
/// metal or glass — which is the whole difference between a tone and a bell,
/// and it is one number.
struct AnimaPartial: Equatable {
    var ratio: Double
    var gain: Double
    /// Exponential decay rate for THIS partial. Higher partials decaying
    /// faster than lower ones is what makes a struck object sound struck:
    /// the brightness dies before the body does.
    var decay: Double
    /// Hz of detune against an identical partial, producing a slow beat.
    /// Small values (0.5–4 Hz) shimmer; large ones sound broken.
    var detune: Double

    init(_ ratio: Double, gain: Double, decay: Double, detune: Double = 0) {
        self.ratio = ratio
        self.gain = gain
        self.decay = decay
        self.detune = detune
    }
}

// MARK: - Noise

/// The unpitched half of a voice: air, transient, texture.
struct AnimaNoise: Equatable {
    var gain: Double
    var decay: Double
    /// One-pole low-pass coefficient, 0 (opaque) ... 1 (untouched). This is
    /// what turns white noise into breath rather than static.
    var lowpass: Double
    /// When set, the noise is band-passed around this multiple of the
    /// fundamental instead of merely low-passed — the difference between
    /// "air" and "a pitched rush".
    var band: Double?

    init(gain: Double, decay: Double, lowpass: Double, band: Double? = nil) {
        self.gain = gain
        self.decay = decay
        self.lowpass = lowpass
        self.band = band
    }

    static let none = AnimaNoise(gain: 0, decay: 1, lowpass: 1)
}

// MARK: - Voice

/// A complete instrument.
struct AnimaVoice: Equatable {

    var name: String

    /// Seconds. The engine's own ceiling is applied at render time — nothing
    /// in this game may ring for longer than a breath.
    var duration: Double

    var partials: [AnimaPartial]
    var noise: AnimaNoise

    /// Attack, in seconds. Raised-cosine, never linear, never zero.
    var attack: Double

    /// End pitch as a fraction of start. See `allowsFall`.
    var glide: Double

    /// Whether this voice is permitted a downward glide.
    ///
    /// DEFAULT FALSE, AND THAT IS THE ANTI-LASER RULE. A voice that does not
    /// opt in has its glide floored at `Self.glideFloor` however the catalog
    /// was written, so a mistyped sweep produces a slightly flat pop rather
    /// than a phaser. Exactly one kind of sound should say yes: something
    /// falling.
    var allowsFall: Bool

    init(_ name: String,
         duration: Double,
         partials: [AnimaPartial],
         noise: AnimaNoise = .none,
         attack: Double = 0.004,
         glide: Double = 1.0,
         allowsFall: Bool = false) {
        self.name = name
        self.duration = duration
        self.partials = partials
        self.noise = noise
        self.attack = attack
        self.glide = glide
        self.allowsFall = allowsFall
    }

    // MARK: Envelopes

    /// The shallowest downward glide a non-falling voice may have.
    /// 0.94 is the value `PopSoundEngine` settled on after the Space Invaders
    /// finding; it is repeated rather than shared because these two engines
    /// must be able to disagree without one silently changing the other.
    static let glideFloor = 0.94

    /// The longest anything may ring, in seconds. A calm game has no long
    /// tails: past about a second a pop stops being punctuation and starts
    /// being a drone she has to wait out.
    static let maximumDuration = 1.2

    /// Master gain. Everything is quiet, and this is where that is true.
    static let masterGain = 0.5

    // MARK: Rendering

    /// Renders one note.
    ///
    /// `pitch` is the fundamental in Hz — the caller has already decided it
    /// (and, in the game, snapped it to the pentatonic so any chain of pops
    /// is consonant). This function does not know about scales.
    ///
    /// DETERMINISTIC. The noise generator is a small LCG seeded from the
    /// voice's own numbers — never `Double.random`, and never `hashValue`,
    /// because Swift seeds its hasher per process and a hash-seeded texture
    /// would make a pop a subtly different sound on every launch. A pop has
    /// to be the same sound every time anyone hears it.
    func render(pitch: Double, sampleRate: Double = 44_100) -> [Float] {
        let seconds = min(max(duration, 0.01), Self.maximumDuration)
        let count = Int(sampleRate * seconds)
        guard count > 0 else { return [] }

        let fundamental = max(20, min(pitch, sampleRate / 3))
        let endGlide = allowsFall ? max(0.3, glide) : max(glide, Self.glideFloor)
        let attackSeconds = max(0.001, min(attack, seconds * 0.5))

        var rng = (fundamental.bitPattern &* 31)
            ^ (duration.bitPattern &* 131)
            ^ UInt64(truncatingIfNeeded: name.utf8.reduce(7) { $0 &* 31 &+ Int($1) })
        rng |= 1
        func white() -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Double(Int64(bitPattern: rng >> 11)) / Double(1 << 52) - 1
        }

        // Phase is ACCUMULATED, not computed as 2π·f·t.
        //
        // With a glide, `f` changes every sample, and `2π·f(t)·t` is not the
        // integral of a changing frequency — it jumps backwards whenever the
        // frequency falls, which is a discontinuity in the waveform and
        // therefore an audible click in the middle of the note. Accumulating
        // the per-sample increment is the integral, and it is continuous by
        // construction.
        var phases = [Double](repeating: 0, count: partials.count)
        var detunePhases = [Double](repeating: 0, count: partials.count)
        var lowpassState = 0.0
        var band1 = 0.0, band2 = 0.0

        var samples = [Float](repeating: 0, count: count)

        for frame in 0..<count {
            let t = Double(frame) / sampleRate
            let progress = t / seconds
            let frequency = fundamental * (1 + (endGlide - 1) * progress)

            // The shared envelope: a raised-cosine in, and then whatever each
            // component's own decay says. Rule 2.
            let attackGain = t < attackSeconds
                ? 0.5 - 0.5 * cos(Double.pi * t / attackSeconds)
                : 1.0

            var value = 0.0

            for (i, partial) in partials.enumerated() {
                let f = frequency * partial.ratio
                phases[i] += 2 * Double.pi * f / sampleRate
                var component = sin(phases[i])
                if partial.detune > 0 {
                    detunePhases[i] += 2 * Double.pi * (f + partial.detune) / sampleRate
                    component = (component + sin(detunePhases[i])) * 0.5
                }
                value += component * partial.gain * exp(-partial.decay * t)
            }

            if noise.gain > 0 {
                let raw = white()
                let coefficient = min(max(noise.lowpass, 0.001), 1)
                lowpassState += (raw - lowpassState) * coefficient
                var textured = lowpassState
                if let band = noise.band {
                    // A cheap two-pole resonator. Enough to give noise a
                    // centre without pretending to be a filter design.
                    let centre = min(0.49, frequency * band / sampleRate)
                    let feedback = 2 * cos(2 * Double.pi * centre) * 0.985
                    let output = lowpassState + feedback * band1 - 0.970 * band2
                    band2 = band1
                    band1 = output
                    // Scaled well down: a two-pole resonator at r = 0.985 has
                    // a resonant gain near 1/(1 − r), so the raw output is
                    // some sixty times its input and would sit on the clamp
                    // for the whole note without this.
                    textured = output * 0.05
                }
                value += textured * noise.gain * exp(-noise.decay * t)
            }

            // Rule 3, in two parts: the master gain, then a hard clamp so no
            // sum of partials an author happens to type can clip.
            let out = min(max(value * attackGain * Self.masterGain, -1), 1)
            samples[frame] = Float(out)
        }

        // A short raised-cosine fade at the tail. Without it a voice whose
        // decay has not reached silence by `duration` ends on a step, which
        // is the same click as rule 2 in the other direction — and it is the
        // one an author is most likely to author by accident, by shortening a
        // duration without touching a decay.
        let fade = min(count, Int(sampleRate * 0.006))
        if fade > 1 {
            for i in 0..<fade {
                let k = Double(i) / Double(fade - 1)
                let gain = 0.5 + 0.5 * cos(Double.pi * k)
                samples[count - fade + i] = Float(Double(samples[count - fade + i]) * gain)
            }
        }
        return samples
    }
}
