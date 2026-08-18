import CoreGraphics
import Foundation

// Every gameplay tuning constant, transcribed 1:1 from v1.0.
// These values are the feel of the game — change deliberately, one at a time.
enum GameConfig {

    // MARK: Field

    /// The envelope a field's orb count stays inside. Since the stage
    /// mechanics landed, the actual count comes from `FieldPlan.forStage`,
    /// which is exact rather than random — a stage that teaches splitters has
    /// to contain splitters every time. This range is what every plan is held
    /// within, and the count a field is *seeded* with; a generator can raise
    /// the live count above it later, bounded by `activeOrbCeiling`.
    static let orbCountRange: Range<Int> = 7..<20
    static let orbRadiusRange: ClosedRange<CGFloat> = 18...34
    static let orbMaxSpeed: CGFloat = 0.18
    static let edgeInset: CGFloat = 24
    static let spawnTopInset: CGFloat = 100
    static let fieldTopInset: CGFloat = 70
    static let paintCount = 5

    // MARK: Splitters, drifters, generators (the stage mechanics)

    /// How many orbs a splitter becomes. Two, not three: three makes a field
    /// of splitters grow faster than she can enjoy it, and the point is more
    /// to pop, not more to keep up with.
    static let splitChildCount = 2

    /// A child's radius as a fraction of its parent's. Kept high — a nested
    /// doll should be *smaller*, never *fiddly*. At 0.72 a two-deep
    /// grandchild is still ~0.52 of the parent, comfortably above the tap
    /// tolerance, so splitting never becomes a precision test.
    static let splitChildScale: CGFloat = 0.72

    /// How far a child is thrown from where its parent was.
    static let splitSpread: CGFloat = 0.9

    /// A drifter notices a finger inside this radius and begins to ease away.
    static let evadeRadius: CGFloat = 96

    /// AND IT STOPS RUNNING INSIDE THIS ONE. This constant is the whole
    /// difference between a tease and a chase: closer than this, a drifter
    /// does not evade at all, so anybody who simply moves at it will always
    /// catch it. An orb that could actually escape would be a fail state
    /// wearing a friendly face, and this game does not have those.
    static let evadeSurrenderRadius: CGFloat = 38

    /// Peak acceleration of the ease-away, in the same units as orb velocity.
    static let evadeStrength: CGFloat = 0.019

    /// The fastest a drifter may travel. Barely above `orbMaxSpeed`, so a
    /// following finger always gains on it.
    static let evadeMaxSpeed: CGFloat = 0.34

    /// Evasion fades out this close to a wall, so a cornered drifter settles
    /// instead of jittering against the edge.
    static let evadeWallEasing: CGFloat = 70

    /// Frames between a generator's emissions (2 s and 3.3 s at 60 fps).
    static let generatorIntervalRange: ClosedRange<CGFloat> = 120...200

    /// A generator holds its emission while this many orbs are already alive.
    /// The owner's third expend-mechanism ("based on the number of active pops
    /// on the screen"), used here as the calm-guard: the field can always
    /// sustain itself, and it can never crowd.
    static let activeOrbCeiling = 26

    /// Presses to close a `.taps` generator, and orbs in a `.quota` one.
    static let generatorTapsRange: ClosedRange<Int> = 3...5
    static let generatorQuotaRange: ClosedRange<Int> = 3...6

    /// Frames a `.settles` generator stays open (~15–25 s).
    static let generatorSettleRange: ClosedRange<CGFloat> = 900...1500

    /// A generator is drawn a little larger than the orbs it makes.
    static let generatorRadiusScale: CGFloat = 1.18

    // MARK: Touch

    static let tapTolerance: CGFloat = 12

    // MARK: Orb motion

    static let wobbleAmount: CGFloat = 0.03
    static let wobbleSpeed: CGFloat = 0.02
    static let spawnGrowth: CGFloat = 0.05

    // MARK: Shockwave rings

    static let ringBaseMaxRadius: CGFloat = 110
    static let ringRadiusPerOrbRadius: CGFloat = 2.6
    static let ringGrowthFactor: CGFloat = 0.1
    static let ringGrowthLinear: CGFloat = 1.5
    static let ringLifeDecay: CGFloat = 0.03
    static let ringArmRadius: CGFloat = 18
    static let ringShellThickness: CGFloat = 24
    static let ringDisarmFraction: CGFloat = 0.5

    // MARK: Particles

    static let particleBaseCount = 18
    static let particleGravity: CGFloat = 0.07
    static let particleDamping: CGFloat = 0.986
    static let particleCap = 320

    // MARK: Ambient motes

    static let moteCount = 36

    // MARK: Frame stepping

    // dt is clamped so a long system stall or backgrounding never makes the
    // sim explode; 1 unit of f == one 60 fps frame's worth of motion.
    static let maxFrameDt: TimeInterval = 0.05

    // MARK: UI timing

    /// 3.6 s was the life of a card that STOPPED the field: short, because
    /// it was in her way. The fortune is a whisper now — it blocks nothing
    /// and eats no touches — so it can last as long as a sentence takes to
    /// read rather than as long as an interruption can be tolerated.
    static let fortuneDisplayDuration: TimeInterval = 5.5
    static let doneRevealDelay: TimeInterval = 0.65
    static let chainNoteThreshold = 3
    static let chainWindow: TimeInterval = 0.9
    static let chainNoteDuration: TimeInterval = 1.4
}
