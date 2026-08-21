import Foundation

// The formal standard for a "pop" — the unit of content in Vesper.
//
// A pop is pure data: how an orb looks (PopStyle), how it behaves when it
// bursts (PopBehavior), how its shockwave talks to neighbors (ChainBehavior),
// and how a player earns it (UnlockRule). The engine (simulation, renderer,
// audio, haptics) reads these values; authoring a new pop never requires
// touching engine code. Everything here is UI-framework-free so the
// simulation and the catalog stay unit-testable.
//
// The reference implementation is pop #001 "Vesper" in PopCatalog.swift,
// which codifies the original v1.0 pop exactly, sourcing its numbers from
// GameConfig. The authoring rules and value envelopes live in
// docs/pop_standard.md.

// MARK: - Color (UI-free)

struct PopColor: Hashable {
    let r: Double
    let g: Double
    let b: Double
}

struct PopPaint: Hashable {
    let fill: PopColor
    let glow: PopColor
}

// MARK: - Style: how the orb and its debris look

enum ParticleShape: String {
    case dot      // the classic soft circle
    case spark    // short streak along its velocity
    case petal    // elongated oval, drifting like a leaf
    case shard    // small triangle, glassy
    case ring     // tiny hollow circle
}

struct PopStyle {
    // one or more paint variants; each orb of this pop picks one at seed time
    let paints: [PopPaint]
    let particleShape: ParticleShape
    let particleSizeRange: ClosedRange<Double>   // classic 1.2...3.4
    let haloOpacity: Double                      // classic 0.18
    let highlightOpacity: Double                 // classic 0.14
    let shimmer: Bool                            // subtle brightness pulse
}

// MARK: - Behavior: what one burst does

// HOW A POP IS SOUNDED — the instrument, not the note.
//
// THE DIAGNOSIS THIS EXISTS TO ANSWER. Every one of the 100 pops was rendered
// by one synthesis model: a sine wave, an optional second harmonic, a linear
// pitch sweep and an exponential decay. `freq` and `duration` were overridden
// in ~95 of 100 entries, so the catalog *was* varied — in pitch and length,
// on a single instrument. That is exactly a one-trick musician: a hundred
// notes, all played on the same string.
//
// A voice changes the SYNTHESIS, not its parameters. Two pops with identical
// frequencies and different voices do not sound like the same thing higher or
// lower; they sound like different objects. That is what "memorably
// different" requires, and no amount of parameter tuning inside one model can
// reach it.
//
// One voice per family (10 families, 10 pops each): the family is the
// instrument, and the ten pops in it are the notes. That is how a catalogue
// this size stays coherent instead of becoming a hundred unrelated noises.
enum SoundVoice: String, Hashable, CaseIterable {
    /// THE ASMR POP: a soft broadband transient and a resonant body that
    /// lifts very slightly as it decays. This is what a bubble, a water drop
    /// or a mouth pop actually does, and it is the base sound of the game.
    case pop
    /// Sine with an optional second harmonic and an exponential decay. The
    /// v1.0 shape, kept for pops that want a plain round tone.
    case tone
    /// Struck and inharmonic, long ringing tail. Bells, not tones.
    case bell
    /// Hard attack, fast harmonic collapse. A string touched once.
    case pluck
    /// Band-passed noise with a soft swell. Air rather than pitch.
    case breath
    /// Bright, detuned pair, very short. Glass tapped with a nail.
    case glass
    /// Low, damped, almost pitchless. A knuckle on a table.
    case wood
    /// Filtered noise bursts over a low body. Embers settling.
    case crackle
    /// Layered detuned sines with slow amplitude drift. Barely a pitch.
    case shimmer
    /// A pitch that falls and lands. A single drop into water.
    case drop
}

struct SoundProfile: Hashable {
    /// The instrument. Defaulted to `.tone` so every existing entry keeps the
    /// classic voice unless it is deliberately given another.
    var voice: SoundVoice = .tone
    let startFreq: Double     // Hz at the deepest pitch (largest orb); classic 460
    let freqSpread: Double    // Hz added as orbs get smaller; classic 420
    let sweep: Double         // end frequency as a fraction of start; classic 0.55
    let duration: Double      // seconds; classic 0.14
    let decay: Double         // exponential decay rate; classic 7.5
    let brightness: Double    // 0...0.5 second-harmonic mix; classic 0
}

// HOW A POP FEELS.
//
// The other half of the diagnosis, and the more damning half: `baseIntensity`
// and `intensityPerSize` were overridden in ONE of the hundred entries. Only
// `sharp` — a Bool — varied at all, in 18. So the game had a hundred
// different-looking, different-sounding pops that all said the same single
// thing to the hand, every time, for the entire life of the app.
//
// Touch is the sense with the least bandwidth and the longest memory. A
// pattern is a rhythm, not an intensity: two taps, a swell, a decaying
// ripple. It is the cheapest way to make a pop feel like a *thing* rather
// than a notification.
enum HapticPattern: String, Hashable, CaseIterable {
    /// One impact. v1.0's behaviour, and pop #001's forever.
    case single
    /// Two quick impacts — the second lighter. Reads as "tick-tick".
    case double
    /// Three impacts, decaying, ~40 ms apart. A small cascade in the hand.
    case ripple
    /// A soft impact followed by a heavier one: it arrives rather than hits.
    case swell
    /// One heavy, damped impact. Weight.
    case thud
}

struct HapticProfile {
    let baseIntensity: Double      // classic 0.35
    let intensityPerSize: Double   // classic 0.5
    let sharp: Bool                // false = .soft impact, true = .light impact
    /// The rhythm of the tap. Defaulted so pop #001 is untouched.
    var pattern: HapticPattern = .single
}

// HOW A POP MOVES.
//
// The third axis, and the third finding: every burst in the catalog was the
// same shape. Particles were thrown at a uniform random angle over a full
// circle with a small upward bias, then fell under gravity — for all 100.
// Shape (5 options, 46 of them `.dot`) and speed (27 of 100) were the only
// variation, and neither changes the *gesture* of a burst.
//
// A motion is that gesture. It is the thing the eye actually remembers about
// a pop, because it is what the pop DID.
enum BurstMotion: String, Hashable, CaseIterable {
    /// v1.0 exactly: full-circle scatter with a slight upward bias, falling
    /// under gravity. Pop #001's forever.
    case radial
    /// Slow outward, held, drifting down — petals opening.
    case bloom
    /// Thrown inward first, then out. A breath taken before it goes.
    case implode
    /// Tangential launch: the burst turns as it leaves.
    case spiral
    /// Mostly downward, heavy, few particles far. Something falling.
    case drip
    /// Upward and slowing, gravity nearly off. Sparks leaving a fire.
    case ascend
    /// Wide, fast, flat — a horizontal sweep more than a circle.
    case scatter
    /// Small, jittering, barely travelling. It trembles apart.
    case shiver
    /// A thin expanding band: everything at one speed, one ring.
    case ring
    /// Almost no speed, almost no gravity: it hangs and fades.
    case veil
}

struct PopBehavior {
    let particleCountBase: Int                    // classic 18 (+1 per pt of radius)
    let particleSpeedRange: ClosedRange<Double>   // classic 1.2...6
    let particleGravity: Double                   // classic 0.07
    let sound: SoundProfile
    let haptic: HapticProfile
    /// The gesture of the burst. Defaulted so pop #001 is untouched.
    var burst: BurstMotion = .radial
}

// MARK: - Chain: how the shockwave talks to neighbors

struct ChainBehavior {
    let ringCount: Int               // visual rings per burst; only the first arms chains
    let maxRadiusBase: Double        // classic 110
    let maxRadiusPerOrbRadius: Double // classic 2.6
    let growthFactor: Double         // classic 0.1  (eased approach to maxR)
    let growthLinear: Double         // classic 1.5  (pt per frame floor)
    let shellThickness: Double       // classic 24   (how forgiving the wavefront is)
    let disarmFraction: Double       // classic 0.5  (ring stops chaining past this)
    let lifeDecay: Double            // classic 0.03
}

// MARK: - Progression

enum PopRarity: String {
    case common, uncommon, rare, secret

    // base pop-point value; see docs/pop_points.md
    var pointValue: Int {
        switch self {
        case .common: return 10
        case .uncommon: return 25
        case .rare: return 60
        case .secret: return 150
        }
    }
}

enum UnlockRule {
    case start                 // available from the first launch
    case points(Int)           // lifetime pop points
    case totalPops(Int)        // lifetime orbs popped
    case fieldsCleared(Int)
    case fortunesFound(Int)
    case bestChain(Int)        // longest cascade ever

    // The gentle hint shown on a locked pop in the collection.
    //
    // R-CRAFT J3: STATIVE, NOT IMPERATIVE. These read one at a time in code
    // and a hundred at once on the page, and a grid of a hundred commands —
    // `gather` · `set` · `clear` · `find` · `ride` — is a task list, however
    // kindly each one is worded. A task list is an obligation, and guardrail
    // 1 asks for a kind hint rather than a wall or a chore. `with you from
    // the start` was already right, and it was right by being stative; the
    // other five now match it.
    //
    // EVERY NUMBER IS UNCHANGED. This is a mood change, not a difficulty
    // change — nothing here is harder or easier to reach than it was.
    var hint: String {
        switch self {
        case .start: return "with you from the start"
        case .points(let n): return "arrives at \(n.formatted()) pop points"
        case .totalPops(let n): return "arrives at \(n.formatted()) orbs set free"
        case .fieldsCleared(let n): return "arrives after \(n.formatted()) fields"
        case .fortunesFound(let n): return "arrives with \(n.formatted()) fortunes found"
        case .bestChain(let n): return "arrives after a chain of \(n)"
        }
    }
}

// MARK: - Family

enum PopFamily: String, CaseIterable {
    case vesper, ember, tide, bloom, frost, chime, lantern, current, prism, aurora

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    // MARK: - The family signature

    // TEN FAMILIES, TEN INSTRUMENTS. The catalog is ten families of ten, and
    // that structure is the answer to "make the hundred truly unique" — the
    // FAMILY is the instrument, and the ten pops inside it are notes on it.
    //
    // The alternative, a hundred hand-authored one-offs, is worse and not
    // better: it is a hundred unrelated noises with nothing to learn, and a
    // player cannot build a memory of something that has no pattern. A person
    // who has met three Frost pops should recognise the fourth before they see
    // it — and should never mistake it for an Ember. That is what "memorably
    // different" actually means, and it needs coherence as much as contrast.
    //
    // Every value here is a DEFAULT. An individual pop can override any of the
    // three, and the rare and secret ones do.

    /// The instrument this family is played on.
    var voice: SoundVoice {
        switch self {
        case .vesper:  return .pop       // the ASMR pop — the base sound
        case .ember:   return .crackle   // embers settling
        case .tide:    return .drop      // one drop into still water
        case .bloom:   return .tone      // a plain round tone, no sweep
        case .frost:   return .glass     // glass tapped with a nail
        case .chime:   return .bell      // struck metal, ringing
        case .lantern: return .wood      // a knuckle on a table
        case .current: return .breath    // air with a pitch centre
        case .prism:   return .pluck     // a string touched once
        case .aurora:  return .shimmer   // barely a pitch at all
        }
    }

    /// What this family says to the hand.
    var hapticPattern: HapticPattern {
        switch self {
        case .vesper:  return .single    // v1.0's forever
        case .ember:   return .double    // tick-tick
        case .tide:    return .swell     // it arrives
        case .bloom:   return .single
        case .frost:   return .double    // two small sharp taps
        case .chime:   return .ripple    // a cascade in the hand
        case .lantern: return .thud      // weight
        case .current: return .swell
        case .prism:   return .double
        case .aurora:  return .ripple
        }
    }

    /// How this family's burst moves.
    var burst: BurstMotion {
        switch self {
        case .vesper:  return .radial    // v1.0's forever
        case .ember:   return .ascend    // sparks leaving a fire
        case .tide:    return .veil      // it hangs and fades
        case .bloom:   return .bloom     // petals opening
        case .frost:   return .shiver    // it trembles apart
        case .chime:   return .ring      // a thin expanding band
        case .lantern: return .drip      // something falling
        case .current: return .spiral    // it turns as it leaves
        case .prism:   return .scatter   // flat and fast
        case .aurora:  return .implode   // a breath taken before it goes
        }
    }
}

// MARK: - The pop itself

struct PopDefinition: Identifiable {
    let number: Int            // 1...100, stable forever
    let name: String
    let family: PopFamily
    let rarity: PopRarity
    let flavor: String         // one calm line, in the fortune voice
    let style: PopStyle
    let behavior: PopBehavior
    let chain: ChainBehavior
    let unlock: UnlockRule

    var id: Int { number }
}
