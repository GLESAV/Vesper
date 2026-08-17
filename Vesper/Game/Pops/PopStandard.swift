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

struct SoundProfile: Hashable {
    let startFreq: Double     // Hz at the deepest pitch (largest orb); classic 460
    let freqSpread: Double    // Hz added as orbs get smaller; classic 420
    let sweep: Double         // end frequency as a fraction of start; classic 0.55
    let duration: Double      // seconds; classic 0.14
    let decay: Double         // exponential decay rate; classic 7.5
    let brightness: Double    // 0...0.5 second-harmonic mix; classic 0
}

struct HapticProfile {
    let baseIntensity: Double      // classic 0.35
    let intensityPerSize: Double   // classic 0.5
    let sharp: Bool                // false = .soft impact, true = .light impact
}

struct PopBehavior {
    let particleCountBase: Int                    // classic 18 (+1 per pt of radius)
    let particleSpeedRange: ClosedRange<Double>   // classic 1.2...6
    let particleGravity: Double                   // classic 0.07
    let sound: SoundProfile
    let haptic: HapticProfile
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
