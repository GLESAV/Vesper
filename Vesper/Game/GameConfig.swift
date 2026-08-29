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
    /// Extra room below the field's ceiling where an orb is first placed, so
    /// nothing is seeded already touching the band above it. Was
    /// `spawnTopInset = 100` measured from the screen edge; it is a margin
    /// below `GameSimulation.topInset` now, because the ceiling itself moved
    /// into `FieldLayout` and depends on the device's safe area.
    static let spawnMargin: CGFloat = 30

    /// The fallback ceiling, used only before a `FieldLayout` has been
    /// applied — the real one comes from the layout and clears the signage.
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

    /// The fastest a drifter may travel. Barely above the weather-capped orb
    /// ceiling (`orbMaxSpeed` × the fastest air's 1.6 headroom ≈ 0.29), so a
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

    // MARK: Fireworks

    /// A shell's tap radius. Generous — larger than the biggest orb — because
    /// a firework is an offer, not a test, and having to aim at one would
    /// make it the hardest thing on a screen where nothing is hard.
    static let fireworkTouchRadius: CGFloat = 30

    /// How much of the fuse one tap burns through. A long fuse takes several
    /// taps to hurry; a short one is nearly gone at the first.
    static let fuseTapBoost: CGFloat = 0.22

    /// The cord: how many nodes, how far apart, and how it hangs.
    static let fuseNodeCount = 8
    static let fuseSegmentLength: CGFloat = 7
    static let fuseGravity: CGFloat = 0.14
    static let fuseDamping: CGFloat = 0.94
    static let fuseRelaxPasses = 3

    /// How close a touch must come to the cord to count. Generous, because a
    /// fuse she can see burning and cannot touch would be the one thing on
    /// this field that looks interactive and is not.
    static let fuseTouchRadius: CGFloat = 22

    /// Frames from launch to break, before the kind's speed multiplier.
    static let fireworkRiseFrames: CGFloat = 62

    /// How far a wobbling shell strays from its line, in points.
    static let fireworkWobbleWidth: CGFloat = 26

    /// How hard a break shoves the field, and how far it reaches. The shove
    /// is clamped to the same speed ceiling everything else obeys: it may
    /// move the field, never make it harder to play.
    static let fireworkShove: CGFloat = 0.5
    static let fireworkShoveRadius: CGFloat = 190

    // MARK: Smoke

    /// How many orbs a break brings up from the reserve. Bounded by what the
    /// reserve actually holds, so a shell never adds to the field's total.
    static let orbsSownPerBurst = 3

    /// The most shells one field may hold. A display is a handful of things
    /// worth watching, not a firing range.
    static let maxFireworksPerField = 6

    /// Puffs a peony leaves; other shells scale from this.
    static let smokePuffsPerBurst = 5

    /// The most smoke that may exist at once. High, because the stacking is
    /// the point — but bounded, because a Canvas drawing a thousand soft
    /// blobs is a dropped frame.
    static let smokeCap = 90

    /// How fast a puff thins. Slow: a haze that cleared quickly would not
    /// gather, and gathering is what makes it read as a display.
    static let smokeDecayRange: ClosedRange<CGFloat> = 0.0016...0.0034

    /// How fast a puff spreads, in points per frame.
    static let smokeSpread: CGFloat = 0.16

    // MARK: Touch

    static let tapTolerance: CGFloat = 12

    // MARK: Orb motion

    static let wobbleAmount: CGFloat = 0.03
    static let wobbleSpeed: CGFloat = 0.02
    static let spawnGrowth: CGFloat = 0.05

    // MARK: Depth — the field is a surface, with more underneath

    /// How many orbs may be on the SURFACE at once. A field can hold far more
    /// than this; the rest wait below and rise as room is made.
    ///
    /// This is what lets a field grow without ever crowding the glass, and it
    /// is why the growth curves below can compound at all: what grows is the
    /// field's DEPTH, not how much is in front of her at any moment.
    static let surfaceCapacity = 14

    /// Frames for an orb to rise from below to the surface. Deliberately slow
    /// — about a second — because the whole point is that it RISES rather
    /// than appears. `spawnGrowth` is four times faster and is what made
    /// generated orbs read as teleporting in.
    static let riseFrames: CGFloat = 58

    /// How small and how faint an orb is at the bottom of its rise. It is
    /// visible down there: she should be able to see that there is more.
    static let depthMinScale: CGFloat = 0.42
    static let depthMinAlpha: Double = 0.22

    // MARK: Field growth

    /// Multiplier per step along the Path. Compounds, and is capped by
    /// `maxFieldOrbs` — an uncapped 1.2× per generation reaches 38× by
    /// generation twenty, and a field that cannot be finished is not a
    /// bigger field, it is a broken one.
    static let depthGrowthPerGeneration: Double = 1.2

    /// Replaying a stone she has already cleared. Second visit is twice the
    /// field, third and beyond is three times.
    static let replayMultipliers: [Double] = [1, 2, 3]

    /// The most pops one field may hold, surface and reserve together.
    static let maxFieldOrbs = 96

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

    /// How long the done card is hers alone before the world rises to the
    /// sky. Long enough to read the verse, which is the whole reason the card
    /// exists.
    static let onwardToSkyDelay: TimeInterval = 3.4

    /// How long the sky is held before stepping onto the next stone — time
    /// for the completion ring to land on the stone she just finished, and
    /// for the road ahead to light.
    static let onwardInSkyPause: TimeInterval = 2.2
    static let chainNoteThreshold = 3
    static let chainWindow: TimeInterval = 0.9
    static let chainNoteDuration: TimeInterval = 1.4

    // MARK: Animals

    /// The first stage a balloon animal can appear on. Late enough that she
    /// has met splitters and drifters — an animal is a drifter that answers
    /// back, and it reads as one idea only if the plain version came first.
    static let animalStartStage = 3

    /// Taps it takes. Two or three, and the range stops there on purpose:
    /// this is a creature that REACTS, not a thing with a health bar. Four
    /// would already be a chore, and a chore is a difficulty curve wearing a
    /// friendly face.
    static let animalHealthRange: ClosedRange<Int> = 2...3

    /// Frames for shyness to fall from 1 to 0 — about twenty-five seconds.
    ///
    /// THIS NUMBER IS THE SAFETY ARGUMENT, so it is chosen against the length
    /// of a field rather than against a feeling. A field runs a minute and
    /// more, so an animal that keeps to the edges for the first twenty-five
    /// seconds and then comes out and waits has been shy for a third of the
    /// time she is there and reachable for the rest of it. Anyone who simply
    /// keeps playing meets it in the open, including someone tired and not
    /// really trying.
    static let animalShyFrames: CGFloat = 1500

    /// How far from the nearest wall a shy animal wants to sit.
    ///
    /// A BAND, NOT A WALL, and that is what keeps this out of the corners.
    /// Outside the band it drifts out; inside it, it drifts back in. It
    /// therefore comes to rest in the margin instead of pressing the glass,
    /// which is the failure mode that would read as the game fighting her.
    static let animalEdgeBand: CGFloat = 66

    /// Peak acceleration of that perimeter-seeking. Very small: it is a
    /// preference, not a wind.
    static let animalEdgeSeek: CGFloat = 0.005

    /// It notices a finger inside this radius. A little wider than the
    /// drifter's, because an animal should read as aware sooner — and it uses
    /// the drifter's own `evadeSurrenderRadius` for where it gives up, so the
    /// two mechanics can never quietly disagree about what "up close" means.
    static let animalEvadeRadius: CGFloat = 120

    /// Peak acceleration of the ease-away, before shyness scales it down.
    static let animalEvadeStrength: CGFloat = 0.022

    /// The fastest it may ordinarily travel: about twenty-five points a
    /// second. A moving thumb is an order of magnitude past that, so a follow
    /// always gains and the animal can never actually escape.
    static let animalMaxSpeed: CGFloat = 0.42

    /// The dart after a tap that did not finish it, and how long it lasts —
    /// about 120 points a second for four tenths of a second, so roughly
    /// twenty-six points of travel. Deliberately less than the animal's own
    /// tap radius: a second tap in the same place still finds it.
    static let animalStartleSpeed: CGFloat = 2.0
    static let animalStartleFrames: CGFloat = 26

    /// Reduce Motion scales the startle and the evasion, the only two things
    /// here that move quickly enough to be worth damping.
    static let animalReduceMotionScale: CGFloat = 0.42

    /// Extra tap tolerance on an animal, because its silhouette reaches past
    /// the body circle the tap radius is measured from. Ears must be
    /// touchable; nothing on this field is a precision test.
    static let animalTapBonus: CGFloat = 8

    /// A creature's going is a larger event than an orb's: more particles,
    /// and a wider shockwave. Both only ever help — a bigger ring clears more
    /// of the field, never less.
    static let animalBurstScale: CGFloat = 1.8
    static let animalRingScale: CGFloat = 1.3

    /// And it is worth more, because it took longer to meet. Points only ever
    /// accrue, so this is a larger gift and never a tax on missing it.
    static let animalPointsMultiplier: Double = 2.5

    // MARK: Weather field

    // The air as things that EXIST in the field rather than as multipliers —
    // crests, eddies, gusts, flakes, shafts, banks. Every array these bound is
    // small and fixed: at most 3 crests (rain uses 2), 4 eddies, 3 shafts, 7 fog banks, 72
    // flakes and 72 splash droplets, so the whole weather layer is under 160
    // moving things in the very worst air, well inside the same budget the
    // particle cap protects.
    //
    // THE AIR CARRIES THE POP; IT DOES NOT PUSH IT. `WeatherField` moves an
    // orb's POSITION by the velocity of the air around it and never touches
    // the orb's own velocity, and the amount it may move it is whatever is
    // left under the ceiling once the orb's own motion is counted. So the
    // most anything can ever travel across the glass is exactly the ceiling
    // that was already there — weather cannot add to it, and cannot
    // accumulate into it the way a per-frame push can.

    /// How wide a crest's band is, as a fraction of the field's width, and
    /// how fast the crest line travels in points per frame.
    ///
    /// WIDE AND UNHURRIED, AND THAT IS THE WHOLE POINT. How far a wave can
    /// carry a pop is `airSpeed × bandWidth / crestSpeed` — the water has to
    /// stay in contact to take anything anywhere — so a narrow, quick band
    /// only ever taps: at 1.4 pt/frame a wave moved a resting pop nine points
    /// and was gone. At half a screen wide and 0.5–0.9 pt/frame it carries it
    /// twenty-five, and a swell crosses in about eighteen seconds, which is
    /// also the difference between a breaker and a tide.
    static let weatherCrestWidth: CGFloat = 0.50
    static let weatherCrestSpeedRange: ClosedRange<CGFloat> = 0.5...0.9

    /// Frames between crests. Long enough that a wave is an event and short
    /// enough that the water is the weather — usually two on the glass.
    static let weatherCrestGapRange: ClosedRange<CGFloat> = 260...460

    /// The vertical part of a crest's orbital motion, as a fraction of its
    /// forward carry. Water lifts about half as much as it shoves.
    static let weatherCrestLift: CGFloat = 0.45

    /// How much of the band draws BACK. At 0.45 the core runs forward at full
    /// speed and the shoulders barely move, which is what makes a crest read
    /// as water gathering rather than as a bar sliding past.
    static let weatherCrestBackwash: CGFloat = 0.45

    /// A wave does not break evenly along its whole length: the front is cut
    /// into cells this many points tall, and the pull varies between them.
    /// This is also what stops a crest from moving the entire field as one
    /// rigid block — the field is sheared, and so it keeps its spread.
    static let weatherCrestCellHeight: CGFloat = 260

    /// How hard the other airs pull, as a fraction of their own carry.
    /// Eddies turn firmly, gusts less so, and a thermal is barely a lift.
    static let weatherEddyPull: CGFloat = 0.85
    static let weatherGustPull: CGFloat = 0.70
    static let weatherThermalPull: CGFloat = 0.50

    /// Splash droplets thrown where a crest meets a pop, and the most that may
    /// exist at once.
    static let weatherSplashPerHit = 4
    static let weatherSplashCap = 72

    /// An eddy's radius as a fraction of the field's smaller side, and how
    /// long one turns before it wanders off and another forms.
    static let weatherEddyRadius: ClosedRange<CGFloat> = 0.22...0.40
    static let weatherEddyLifeRange: ClosedRange<CGFloat> = 420...900

    /// Frames between gusts, and how quickly one arrives and ebbs away.
    ///
    /// THE EBB IS THE POINT, and it is the reason these three numbers were
    /// retuned: at a gentler decay the gusts overlapped and the wind never
    /// dropped below a third of its peak, which is a fan. A gust now arrives
    /// over about two seconds, ebbs to nothing over ten, and the field is
    /// still for a while before the next one gathers.
    static let weatherGustGapRange: ClosedRange<CGFloat> = 220...600
    static let weatherGustRise: CGFloat = 0.014
    static let weatherGustEbb: CGFloat = 0.991

    /// How long a settled flake rests before it melts and falls again.
    /// Nothing is lost: the same flakes return.
    static let weatherFlakeRestRange: ClosedRange<CGFloat> = 240...900

    /// Everything the weather layer moves is scaled by this under Reduce
    /// Motion, and the carrying is switched off entirely — an air she can
    /// look at, with nothing travelling toward her.
    static let weatherStillnessScale: CGFloat = 0.22

    /// Ceilings on how much light the weather may put on the screen. The
    /// scene is dark and stays dark: bands and banks are barely there, and
    /// only the splash and the specular pin-lights are allowed to be bright.
    static let weatherBandOpacity: Double = 0.06
    static let weatherFoamOpacity: Double = 0.16
    static let weatherFogOpacity: Double = 0.14
    static let weatherShineOpacity: Double = 0.22
}
