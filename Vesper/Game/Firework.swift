import CoreGraphics
import Foundation

// FIREWORKS — the one thing on the field that is not a pop.
//
// Owner: "make fireworks which are not pop objects. they are objects you
// click; they shoot off and whirr like fireworks, disrupt the pops on the
// screen to move, and explode. Many kinds. They leave a smoke cloud that
// slowly disappears, and it should stack like real smoke does at fireworks
// shows."
//
// WHY THIS IS SAFE, AND WHY IT IS THE FIRST PURELY OPTIONAL THING IN THE GAME.
// A firework cannot be failed, cannot be missed, and gates nothing: the field
// is clear when the ORBS are gone, and a shell she never touched simply fades
// with the field. Ignoring every firework in the game costs her nothing at
// all. That is what lets it be the loudest, most theatrical object here
// without breaking a product whose first rule is no pressure — it is spectacle
// offered, never spectacle demanded.
//
// It also does the thing the catalog could not: a firework is UNMISTAKABLE.
// The owner's complaint that a hundred pops look alike is a complaint about
// variations on a sphere. This is not a sphere, does not pop, and behaves
// nothing like anything else on the glass.
//
// NO BANGS. Every real firework's defining sound is a report, and this game
// cannot have one. What it has instead is the whirr of the rise — the fuse
// noise, which is the part that is actually pleasant — and a soft bloom at the
// top. A firework here is a thing seen, not a thing heard.

// MARK: - How many, and why not a hundred
//
// The owner asked for as many as possible, a hundred ideally, "but only make
// them as much as can be unique and interesting, like real different fireworks
// are". That last clause is the brief, and it is the one worth honouring.
//
// A hundred is reachable by multiplying fourteen break patterns by colours and
// durations — and it would be the pop catalog's mistake made a second time.
// That catalog had a hundred entries varying pitch and length on ONE synthesis
// model, and the owner heard it in a minute: a hundred notes on the same
// string. Fireworks generated the same way would be a hundred recolourings of
// fourteen shapes, and he would hear that too, only later and with more of the
// app built on top of it.
//
// So the count is what survives the test "would she notice this was a
// different firework?" — the fourteen break patterns are genuine structural
// differences, and each is given two or three treatments that change something
// STRUCTURAL rather than decorative: how it flies, how long it hangs, whether
// it splits, whether it twinkles, what register it whirrs in. That is the
// number below, and it will grow the way the pop families grew — by adding
// mechanisms, not by adding hues.
//
// TWO OF THOSE AXES ARE NOT BUILT YET. `splits` and `twinkles` are authored
// on the shells and read by nothing, so the crossette and the strobe are
// currently told apart by paint, hang and voice alone. Kept rather than cut,
// because the intent is good and the copy is written — but recorded here so
// the paragraph above is not read as a description of the shipping build.
// `docs/firework_behaviours.md` holds the decision.

// MARK: - The shells

/// The shell types, templated off the real vocabulary of a fireworks show.
enum FireworkKind: String, CaseIterable {
    /// A clean sphere of stars, no trails. The archetype.
    case peony
    /// A sphere whose stars trail — the same shape, drawn in lines.
    case chrysanthemum
    /// Long, slow, drooping golden trails. The quietest of them.
    case willow
    /// A thick rising trunk, then a few heavy branches.
    case palm
    /// Stars that split again in flight and fly apart crosswise.
    /// (Intent. `splits` is not implemented — this breaks as a sphere today.)
    case crossette
    /// A flat expanding ring, seen edge-on or face-on.
    case ring
    /// One bright streak that rises and simply keeps going.
    case comet
    /// Stays low and sprays upward — the one that does not leave the ground.
    case fountain
    /// A cloud of small, sharp, glittering breaks.
    case crackle
    /// Slow twinkling points that come and go rather than fade.
    /// (Intent. `twinkles` is not implemented — these fade once, but slowly.)
    case strobe
    /// Spins as it rises and throws stars off its own rotation.
    case spinner
    /// Rises in an erratic zigzag before it goes.
    case serpent
    /// Dense, heavy, overlapping trails — the show's finale shell.
    case brocade
    /// Heavy stars that barely rise and fall almost at once.
    case horsetail

    /// How this shell breaks.
    var burst: FireworkBurst {
        switch self {
        case .peony:
            return .init(stars: 46, speed: 2.6...4.2, gravity: 0.055, trail: 0,
                         pattern: .sphere, life: 0.9, smoke: 1.0)
        case .chrysanthemum:
            return .init(stars: 44, speed: 2.4...4.0, gravity: 0.06, trail: 0.55,
                         pattern: .sphere, life: 1.0, smoke: 1.2)
        case .willow:
            return .init(stars: 30, speed: 1.5...2.4, gravity: 0.11, trail: 0.85,
                         pattern: .droop, life: 1.5, smoke: 0.9)
        case .palm:
            return .init(stars: 12, speed: 2.8...3.6, gravity: 0.09, trail: 0.9,
                         pattern: .droop, life: 1.3, smoke: 1.3)
        case .crossette:
            return .init(stars: 20, speed: 2.2...3.2, gravity: 0.05, trail: 0.2,
                         pattern: .sphere, life: 0.8, smoke: 1.0, splits: true)
        case .ring:
            return .init(stars: 40, speed: 3.0...3.2, gravity: 0.03, trail: 0.15,
                         pattern: .ring, life: 1.0, smoke: 0.7)
        case .comet:
            return .init(stars: 8, speed: 1.0...1.6, gravity: 0.02, trail: 1.0,
                         pattern: .sphere, life: 1.4, smoke: 0.5)
        case .fountain:
            return .init(stars: 52, speed: 1.6...3.4, gravity: 0.13, trail: 0.4,
                         pattern: .spray, life: 1.1, smoke: 1.4)
        case .crackle:
            return .init(stars: 70, speed: 1.2...3.6, gravity: 0.045, trail: 0,
                         pattern: .sphere, life: 0.55, smoke: 0.8)
        case .strobe:
            return .init(stars: 34, speed: 1.4...2.6, gravity: 0.02, trail: 0,
                         pattern: .sphere, life: 1.6, smoke: 0.6, twinkles: true)
        case .spinner:
            return .init(stars: 38, speed: 2.0...3.4, gravity: 0.05, trail: 0.5,
                         pattern: .spiral, life: 1.0, smoke: 1.0)
        case .serpent:
            return .init(stars: 26, speed: 1.8...3.0, gravity: 0.06, trail: 0.7,
                         pattern: .spiral, life: 0.9, smoke: 1.1)
        case .brocade:
            return .init(stars: 60, speed: 2.0...3.8, gravity: 0.1, trail: 1.0,
                         pattern: .droop, life: 1.6, smoke: 1.6)
        case .horsetail:
            return .init(stars: 24, speed: 0.9...1.6, gravity: 0.16, trail: 0.9,
                         pattern: .droop, life: 1.2, smoke: 1.1)
        }
    }

    /// How it climbs. The rise is most of the pleasure and all of the sound.
    var flight: FireworkFlight {
        switch self {
        case .fountain:  return .init(rise: 0.10, wobble: 0, spin: 0, speed: 0.5,
                                     upwardBias: 0.95)
        case .serpent:   return .init(rise: 0.52, wobble: 0.55, spin: 0, speed: 1.15,
                                     upwardBias: 0.4)
        case .spinner:   return .init(rise: 0.50, wobble: 0.18, spin: 0.34, speed: 0.95)
        case .comet:     return .init(rise: 0.66, wobble: 0.04, spin: 0, speed: 1.35,
                                     upwardBias: 0.25)
        case .horsetail: return .init(rise: 0.34, wobble: 0.06, spin: 0, speed: 0.85)
        default:         return .init(rise: 0.52, wobble: 0.1, spin: 0, speed: 1.0)
        }
    }
}

/// The shape a shell breaks into.
enum FireworkPattern: String, Equatable {
    case sphere   // stars in every direction
    case ring     // a flat band
    case droop    // thrown out, then heavy
    case spray    // upward only
    case spiral   // thrown tangentially
}

/// How a shell breaks.
///
/// **THREE OF THESE FIELDS ARE AUTHORED BUT NOT YET READ: `gravity`, `splits`
/// and `twinkles`.** Every kind above sets them and several catalog entries'
/// flavour lines promise what they describe, but no consumer exists — a shell
/// with `splits: true` breaks exactly like its base pattern, and a strobe
/// fades once like everything else. Do not read the catalog and assume the
/// behaviour ships. The gap, where each would have to be consumed, and the
/// decision it needs (implement, or retire the flags and soften the copy) are
/// written up in `docs/firework_behaviours.md`. Each field below says for
/// itself whether it is live.
struct FireworkBurst: Equatable {
    /// Live. How many stars the break makes.
    var stars: Int
    /// Live. The range their initial speed is drawn from.
    var speed: ClosedRange<CGFloat>
    /// **Declared, not implemented.** Meant to be the per-shell fall rate of
    /// the stars. `GameSimulation.stepParticles` gives every particle the
    /// gravity of the pop that made it, and firework stars are all stamped
    /// with `PopCatalog.classic`, so these fourteen values change nothing —
    /// a willow currently falls at exactly a crackle's rate.
    var gravity: CGFloat
    /// Live. 0 = clean points, 1 = long trails.
    var trail: CGFloat
    /// Live. The shape the stars are thrown into.
    var pattern: FireworkPattern
    /// Live. Multiplier on how long the stars last.
    var life: CGFloat
    /// Live. How much smoke this shell leaves, relative to a peony.
    var smoke: CGFloat
    /// **Declared, not implemented.** Meant to be: stars break a second time
    /// part-way through (the crossette). Nothing reads it — see the note at
    /// the top of this type.
    var splits: Bool = false
    /// **Declared, not implemented.** Meant to be: stars come and go rather
    /// than fading once (the strobe). Nothing reads it, and implementing it
    /// raises a photosensitivity question — see the note at the top of this
    /// type.
    var twinkles: Bool = false
}

struct FireworkFlight: Equatable {
    /// How far it travels before breaking, as a fraction of the field's
    /// height.
    ///
    /// DIRECTION IS NOT ALWAYS UP. Shells are launched along a heading chosen
    /// with a strong upward bias but free to go anywhere — the owner's note,
    /// and it is the better behaviour: fourteen shells that all climb
    /// vertically read as a mechanism, while the same fourteen fanning across
    /// the field read as a display. `upwardBias` is how strongly each kind
    /// prefers the sky; a fountain barely leaves the ground and a comet will
    /// cross the whole field sideways if that is where it is pointed.
    var rise: CGFloat
    /// How much it wanders on the way up.
    var wobble: CGFloat
    /// How fast it turns as it climbs.
    var spin: CGFloat
    /// Multiplier on climb speed.
    var speed: CGFloat
    /// 1 = straight up, 0 = any direction at all.
    var upwardBias: CGFloat = 0.72
}

// MARK: - One shell, in flight

struct Firework {
    enum Phase: Equatable {
        /// On the field, unlit.
        case waiting
        /// The fuse is burning. `burned` runs 0 (the trailing end) to 1 (the
        /// shell itself).
        ///
        /// **This is the phase the object exists for.** A firework you tap
        /// and watch leave is a button; a firework whose fuse you light and
        /// then hurry along is a thing you are doing. Tapping again while it
        /// burns pushes it faster, so the pacing is hers — light it and let
        /// it take its time, or chase it down the cord.
        case fuse(burned: CGFloat)
        /// Climbing. `progress` runs 0 to 1 toward `apex`.
        case rising(progress: CGFloat)
        /// Broken. Kept for a moment so the renderer can flash the break.
        case spent
    }

    var pos: CGPoint
    /// Where it came from, so the rise can be interpolated rather than
    /// integrated — a shell that accumulates velocity drifts off target.
    var origin: CGPoint
    /// Where it breaks.
    var apex: CGPoint
    var kind: FireworkKind
    var phase: Phase = .waiting
    /// Which shell in `FireworkCatalog` this is.
    var definitionID: Int
    var variantIndex: Int
    /// Turns as it climbs; also the wobble's phase.
    var angle: CGFloat = 0
    /// Slow drift while it waits, so it is alive on the field.
    var drift: CGVector = .zero
    var spawn: CGFloat = 0
    /// The frame factor of the rope's previous step, for exact Verlet
    /// velocity across frames of different length. 1 = a 60 fps frame.
    var fuseLastF: CGFloat = 1

    /// THE FUSE, AS A ROPE. Node 0 is pinned to the shell and the rest hang
    /// and trail behind it.
    ///
    /// Simulated rather than drawn as a curve, because the owner asked for it
    /// to "move like a tail — fluid like a string as it gets pushed", and a
    /// bezier that merely follows the shell reads as a decal stuck to it. A
    /// rope has slack: it whips when the shell is shoved, keeps swinging
    /// after it stops, and settles at its own pace. That lag is the whole
    /// difference between a drawn line and a thing made of string.
    ///
    /// Verlet integration with a couple of constraint passes — no springs, no
    /// tuning, and stable at any frame rate the clamped `dt` allows.
    var fuseNodes: [CGPoint] = []
    var fusePrev: [CGPoint] = []

    /// Frames this fuse takes to burn if she never touches it again.
    var fuseFrames: CGFloat = 90
}

// MARK: - Smoke

/// A puff left behind by a break.
///
/// **It stacks.** Real firework smoke does not clear between shells — it
/// accumulates over a show, drifts, and thins from the bottom up. Puffs here
/// are additive and overlapping, they grow as they age, and they fade slowly
/// enough that a busy field builds a haze the way a real display does. That
/// accumulation is the owner's actual request: one puff is an effect, a
/// gathering haze is a fireworks show.
struct Smoke {
    var pos: CGPoint
    var vel: CGVector
    var radius: CGFloat
    /// 1 at birth, 0 when gone.
    var life: CGFloat
    var decay: CGFloat
    /// Its own tint, taken from the shell that made it.
    var fireworkID: Int
    var variantIndex: Int
}
