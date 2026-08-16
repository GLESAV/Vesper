import CoreGraphics
import Foundation

// The camera for One World, as a pure state machine. Imports CoreGraphics and
// Foundation and nothing else: no SwiftUI, no UIKit, no Combine, no wall-clock.
// Time arrives as `dt` and every decision arrives as an `InputOutcome` from
// InputArbiter, exactly the discipline GameSimulation follows and for the same
// reason — this is the code that decides how the world moves under a person's
// eyes, and it has to be provable in CI rather than argued about on a device
// (DELIVERY_ROADMAP §3 W01, gate R-ARCH).
//
// NOT `@Published`, NOT `ObservableObject`, and it never will be (ruling 7).
// The view reads `offset` once per frame inside its own draw; a published
// per-frame offset rebuilds the TimelineView/Canvas/input subtree 120 times a
// second, which is verbatim the condition v1.2 blames for cancelled taps.
// `WorldModel` publishes `place` only (W07).
//
// ─────────────────────────────────────────────────────────────────────────
// SIGN CONVENTION — read this before touching anything below.
//
//   offset  <  0   the camera has travelled UP, toward the sky
//   offset ==  0   the field is centred (cold launch, P1)
//   offset  >  0   the camera has travelled DOWN, toward the journal
//
// This is the same y-down sense as WorldInput: a finger moving up the screen
// produces a negative translation, which drags the camera 1:1 to a negative
// offset, which is the sky. One convention, two files, no conversion anywhere
// in between. Offsets are NORMALIZED — one unit is one screen height — so the
// camera is resolution independent and nothing here changes on iPad.
//
// The axis has ENDS AND IT CLAMPS. There is nothing above the sky and nothing
// below the journal: a commit past an end is a spring-back to that end, and a
// drag past an end stops dead at it. It does not wrap (waking up somewhere she
// did not choose) and it does not rubber-band (a rubber band is a rebound, and
// a rebound is a direction reversal — see the settle contract below).
// ─────────────────────────────────────────────────────────────────────────
//
// AMARA OSEI'S VESTIBULAR BARRIER CONDITIONS (R-SPIKE items 10–13) are pass
// conditions at R-ARCH, so each one is implemented here with the failure it
// prevents named at the site:
//
//   10  travel distance is a named constant in screen heights, and peak
//       optical flow has a hard ceiling — see `Config.maxOpticalFlow` and the
//       arithmetic spelled out there.
//   11  Reduce Motion produces ZERO translation, while a drag still gives
//       proportional non-translating feedback — see `reduceMotion` and
//       `dragProgress`.
//   12  the settle is monotone and non-overshooting at every seeded velocity
//       — see `Ease` and `beginSettle`.
//   13  repeated spring-backs damp — see `dragGain`.
//
// THE INVARIANTS, stated so a test can state them too:
//
//   A. The camera never moves unasked. `offset` and `place` change only inside
//      `consume(_:)`, and inside `step(dt:)` while finishing a settle that a
//      `consume(_:)` started. Stepping an untouched camera forever changes
//      nothing. (testStepWithoutInputNeverMoves)
//   B. Every move is interruptible. `.panBegan` at any point during a settle
//      stops it where it is and hands the camera to her finger.
//      (testGrabMidSettleFreezesTheCameraExactly)
//   C. A settle never overshoots, never reverses, and ends exactly on the
//      destination. (testSettleNeverOvershootsAcrossTheVelocitySweep)
//   D. An unlaid-out camera (`viewHeight <= 0`) refuses every outcome. Moving
//      against a screen height we are guessing at is a move she did not ask
//      for. (testUnlaidOutCameraNeverMoves)

// MARK: - Place

// The three places on the one vertical axis. The raw values ARE the axis
// order — sky above field above journal — and `restOffset(of:)` is the only
// thing that converts them into a position.
enum Place: Int, CaseIterable {
    case sky = -1
    case field = 0
    case journal = 1
}

// MARK: - Camera

final class WorldCamera {

    // MARK: Config

    struct Config {
        // BARRIER CONDITION 10, first half. The distance between adjacent
        // places, in screen heights.
        //
        // Three quarters, not one, because the world is meant to be
        // continuous (04 §2): at rest on the field, the bottom quarter of the
        // sky is already on screen above her and the journal's ribbon is
        // already visible at her feet. She can see where she is going before
        // she goes, which is most of what makes a place feel like a place
        // rather than a screen.
        var travelPerPlace: CGFloat = 0.75

        // BARRIER CONDITION 10, second half — THE OPTICAL FLOW CEILING, and
        // the single most important number in this file.
        //
        // Screen heights per second. The world may never slide faster than
        // this, at any instant, at any seeded velocity.
        //
        // TWO CLAMPS, AND WHICH ONE BINDS. The arbiter clamps release velocity
        // to `InputArbiter.Config.maxCommitVelocity` = 2400 pt/s (R-SPIKE fix
        // 5), which on the 844 pt reference screen is 2.84 screen heights per
        // second. That is the coarse upstream guard, and it is expressed in
        // POINTS, so it means different things on different devices. This
        // ceiling is expressed in screen heights, is stricter, and is
        // therefore the one that binds: seeds above ~1688 pt/s on a 844 pt
        // screen all settle identically. The camera re-clamps rather than
        // trusting the arbiter because a ceiling that depends on another file
        // staying correct is not a ceiling. (For the Director: these two
        // numbers should eventually be one number, expressed as a fraction of
        // screen height. Until then the strict one is here.)
        //
        // THE ARITHMETIC, stated as Amara asked. On a 390 × 844 pt iPhone:
        //
        //   travel between places   0.75 × 844  =  633 pt
        //   peak rate at the cap    2.0  × 844  = 1688 pt/s
        //
        // So at MAX SEEDED VELOCITY the peak on-screen travel rate is two
        // screen heights per second — one full screen of world passes her eye
        // in no less than 500 ms — and only instantaneously, at the moment of
        // release. The ease (below) has a peak-to-average ratio of exactly 2,
        // so the AVERAGE rate across a transit is at most one screen height
        // per second, and a full 633 pt transit therefore takes at least
        // 750 ms. Turn this number DOWN to make the world calmer; there is no
        // other number to turn.
        var maxOpticalFlow: CGFloat = 2.0

        // 04 §5 commits the settle to 300–650 ms. That band applies to the
        // settle only — never to a move she cannot touch — and it is honoured
        // for every commit, because a commit has already spent the distance
        // gate (~11% of screen height) getting there.
        //
        // WHERE THE BAND YIELDS: if the ceiling and the band disagree, THE
        // CEILING WINS and the settle takes longer. This happens only for a
        // spring-back from the far end of a drag (up to a full 0.75 travel).
        // Slower is never a vestibular hazard; faster is.
        var minSettleDuration: TimeInterval = 0.30
        var maxSettleDuration: TimeInterval = 0.65

        // Below this seeded speed (screen heights/second) the release carries
        // no useful intent, so the settle simply takes the long, calm end of
        // the band instead of dividing by something near zero.
        var seedVelocityFloor: CGFloat = 0.05

        // BARRIER CONDITION 13. A drag that begins within this window of the
        // last spring-back is treated as a re-attempt at the same move, and
        // damped.
        var oscillationWindow: TimeInterval = 1.0

        // Each successive rapid re-attempt keeps this fraction of the last
        // one's travel, down to the floor. 0.6 → 1.00, 0.60, 0.36, 0.35…
        var dragDampingFactor: CGFloat = 0.6
        var dragDampingFloor: CGFloat = 0.35

        // Same clamp as the game's frame factor: a stalled frame, a
        // breakpoint, or a resumed app must not teleport the world across the
        // screen in one step.
        var maxStep: TimeInterval = 0.05

        static let `default` = Config()
    }

    // MARK: Ease

    // BARRIER CONDITION 12, and the reason this is a parametric ease rather
    // than a spring.
    //
    // A critically damped spring seeded with velocity DOES overshoot: with
    // error x0 and initial velocity v0 the solution is (x0 + (v0 + ωx0)t)e^-ωt,
    // whose bracket changes sign — i.e. crosses the destination — whenever the
    // seeded speed exceeds ω·x0. That is precisely a fast flick caught close to
    // the destination, and the resulting direction reversal at the end of a
    // large-field flow event is exactly the provocation Amara barred.
    //
    // So the settle is expressed as a normalized progress u ∈ [0, 1] and the
    // position is start + (destination − start) · u. Overshoot is then not
    // "tuned out", it is UNREPRESENTABLE: u never exceeds 1, so the position
    // never passes the destination, at any seeded velocity, ever. Velocity
    // seeds the DURATION instead of the initial slope.
    //
    //   u(s) = s(2 − s)     u(0) = 0, u(1) = 1, u′(0) = 2, u′(1) = 0
    //
    // Monotone increasing on [0, 1] (u′ = 2 − 2s ≥ 0), terminal velocity
    // exactly zero, and a peak-to-average ratio of exactly `easePeakFactor`,
    // which is what lets the ceiling arithmetic above be exact rather than
    // approximate. If you change the curve you MUST change this constant with
    // it — it is not a tuning knob, it is a property of the function.
    private static let easePeakFactor: CGFloat = 2

    private static func ease(_ s: CGFloat) -> CGFloat { s * (2 - s) }

    // MARK: Settable by the host

    var config: Config

    // Set by the view on layout, in points. Until it is known the camera
    // refuses to move at all (invariant D).
    var viewHeight: CGFloat

    // BARRIER CONDITION 11. Reduce Motion is a property the view WRITES from
    // the live system setting (`onAppear` + `onChange`); the camera never
    // reads system state itself, because reading it would make this file
    // impure and untestable. While it is true `offset` is identically zero —
    // the places crossfade instead — and `dragProgress` still answers her
    // finger, so the control never feels dead.
    var reduceMotion: Bool

    // MARK: State the view reads

    // The place the camera belongs to: where it is, or where it is going.
    //
    // It flips at COMMIT time, not on arrival, for three reasons: the sim must
    // stop the instant she has decided to leave the field so no chain resolves
    // unseen (04 §5, W07's `simActive`), the whispers must re-label to name
    // where she can go from there, and `.cancelToRest` needs a home that means
    // "where the camera belongs" rather than "where it happened to start".
    // Nothing visual keys off this: the crossfade keys off `dragProgress`,
    // which is continuous.
    private(set) var place: Place = .field

    // The continuous normalized axis position the view applies as a
    // translation. Zero under Reduce Motion, always (barrier condition 11).
    var offset: CGFloat { reduceMotion ? 0 : axisPosition }

    // Signed progress AWAY from `place`, in place-units, clamped to [-1, 1]:
    // negative toward the sky, positive toward the journal.
    //
    // This is the value a Reduce Motion view crossfades with, and it is the
    // reason RM never feels dead: while she drags, it answers her finger
    // proportionally even though nothing translates. It runs during settles
    // too — after a commit it eases from ±1 to 0 — so under RM one number
    // drives the whole transition: |dragProgress| is the outgoing place's
    // opacity and 1 − |dragProgress| the arriving one's, and its sign says
    // which neighbour is which.
    var dragProgress: CGFloat {
        let d = (axisPosition - restOffset(of: place)) / config.travelPerPlace
        return min(1, max(-1, d))
    }

    // True when nothing is in flight: no settle running, no finger down.
    var isAtRest: Bool {
        if case .rest = motion { return true }
        return false
    }

    // The camera's own clock, in seconds, advanced only by `step(dt:)` with dt
    // clamped. Not wall-clock: during a stall it deliberately runs slow,
    // because it measures motion, not time of day. Only the oscillation
    // damping reads it.
    private(set) var elapsed: TimeInterval = 0

    // MARK: Private state

    private var axisPosition: CGFloat = 0

    private enum Motion {
        case rest
        case dragging(anchor: CGFloat)
        case settling(from: CGFloat, to: CGFloat, duration: TimeInterval, elapsed: TimeInterval)
    }

    private var motion: Motion = .rest

    // BARRIER CONDITION 13, the whole of it. 1.0 is undamped, 1:1 with her
    // finger; each rapid re-attempt shrinks it toward the floor.
    private var dragGain: CGFloat = 1
    private var lastReturnAt: TimeInterval?

    // Distances below this are already arrived.
    private let epsilon: CGFloat = 1e-9

    // MARK: Init

    init(viewHeight: CGFloat = 0,
         reduceMotion: Bool = false,
         config: Config = .default) {
        self.viewHeight = viewHeight
        self.reduceMotion = reduceMotion
        self.config = config
    }

    // MARK: - Geometry

    // The axis position at which a place is centred. The ONLY place → position
    // conversion in the codebase.
    func restOffset(of place: Place) -> CGFloat {
        CGFloat(place.rawValue) * config.travelPerPlace
    }

    // The place nearest the camera right now. Ties go to `place` — a tie must
    // never be resolved into a move she did not ask for (invariant A).
    var nearestPlace: Place {
        var best = place
        var bestDistance = abs(axisPosition - restOffset(of: place))
        for candidate in Place.allCases {
            let d = abs(axisPosition - restOffset(of: candidate))
            if d < bestDistance - 1e-12 {
                best = candidate
                bestDistance = d
            }
        }
        return best
    }

    // THE ONE MAPPING FROM DIRECTION TO DESTINATION IN THE CODEBASE.
    //
    // The arbiter emits a direction and never a destination, precisely so that
    // this table exists once. If you find yourself writing `if place == .sky`
    // anywhere else in order to decide where a swipe goes, the bug is that
    // this function was not called.
    //
    // The ends clamp: `.up` from the sky and `.down` from the journal name
    // the place they are already in, which makes them spring-backs.
    func destination(from origin: Place, moving direction: WorldDirection) -> Place {
        // `origin`, not the `place` property: this is a pure table, and the
        // caller decides which place it is asking about.
        switch (origin, direction) {
        case (.journal, .up):   return .field
        case (.field,   .up):   return .sky
        case (.sky,     .up):   return .sky        // nothing above the sky
        case (.sky,     .down): return .field
        case (.field,   .down): return .journal
        case (.journal, .down): return .journal    // nothing below the journal
        }
    }

    // MARK: - Consuming outcomes

    // Outcomes arrive batched, one batch per touch delivery (R-SPIKE fix 6),
    // and are applied in order.
    func consume(_ outcomes: [InputOutcome]) {
        for outcome in outcomes { consume(outcome) }
    }

    func consume(_ outcome: InputOutcome) {
        // Invariant D. An unlaid-out camera has no screen height to normalize
        // against, so every outcome is refused — including the commit, which
        // must not silently change `place` while the offset stays put.
        guard viewHeight > 0 else { return }

        switch outcome {

        case .pop:
            // The camera has no business with pops, and says so explicitly
            // rather than by omission: ruling 4 gives the pop and the pan
            // independent lives, and the camera is the pan's half.
            break

        case .panBegan:
            // Invariant B: this is the whole of interruptibility. Whatever the
            // camera was doing, it is hers now, from exactly where it is.
            dragGain = gainForDragBeginningNow()
            motion = .dragging(anchor: axisPosition)

        case .panChanged(let translation):
            // Cumulative from the arbiter's slop anchor, so this is an
            // assignment and not an accumulation: a dropped or duplicated
            // event costs one frame of smoothness rather than permanently
            // offsetting the world from her finger.
            //
            // A `.panChanged` with no `.panBegan` is refused rather than
            // treated as an implicit begin. The arbiter always emits the pair,
            // so an unpaired change is a malformed sequence, and invariant A
            // says a malformed sequence moves nothing.
            guard case .dragging(let anchor) = motion else { return }
            axisPosition = clampToAxis(anchor + dragGain * (translation / viewHeight))

        case .commit(let direction, let velocity):
            // Velocity magnitude only. The arbiter has already required the
            // translation and the velocity to agree in sign before it emits a
            // commit (gate 3), and the destination is decided by the direction
            // it sent; a disagreeing sign here could only mean a bug upstream,
            // and honouring it would mean settling away from the destination.
            beginSettle(to: destination(from: place, moving: direction),
                        seededSpeed: abs(velocity) / viewHeight)

        case .settleToNearest:
            // R-SPIKE fix 3: a transit grab released without a decisive
            // gesture. A near-complete move completes, an early catch springs
            // home. Unseeded — she let go without asking for speed.
            beginSettle(to: nearestPlace, seededSpeed: 0)

        case .cancelToRest:
            // Back to where the camera belongs. From the field that is the
            // field; caught mid-transit (the system took the touch away) it is
            // the destination she had already committed to.
            beginSettle(to: place, seededSpeed: 0)
        }
    }

    // MARK: - Settle

    private func beginSettle(to newPlace: Place, seededSpeed: CGFloat) {
        // A settle that does not change place is a SPRING-BACK, and
        // spring-backs are what oscillate.
        let isReturn = (newPlace == place)
        place = newPlace

        if isReturn { lastReturnAt = elapsed }

        let target = restOffset(of: newPlace)
        let distance = abs(target - axisPosition)
        guard distance > epsilon else {
            axisPosition = target
            motion = .rest
            return
        }

        // Seeded speed is re-clamped to the ceiling here even though the
        // arbiter clamps it: the camera must not be able to be handed a number
        // it is not allowed to honour (R-SPIKE fix 5).
        let speed = min(seededSpeed, config.maxOpticalFlow)

        // Duration from the release, so the settle continues her gesture at
        // the pace she chose: peak rate = easePeakFactor · distance / duration,
        // so matching her release means duration = easePeakFactor · d / v.
        var duration: TimeInterval = config.maxSettleDuration
        if speed > config.seedVelocityFloor {
            duration = min(TimeInterval(Self.easePeakFactor * distance / speed),
                           config.maxSettleDuration)
        }

        // The 04 §5 band…
        duration = max(duration, config.minSettleDuration)

        // …and then THE CEILING, last, because it outranks the band. This is
        // the line that makes peak optical flow provably ≤ maxOpticalFlow for
        // every settle: peak = easePeakFactor · d / duration, and duration is
        // now at least easePeakFactor · d / maxOpticalFlow.
        duration = max(duration, TimeInterval(Self.easePeakFactor * distance / config.maxOpticalFlow))

        // BARRIER CONDITION 13, the "slower" half. A spring-back inherits the
        // damping of the drag it undoes, so a re-attempt returns more slowly;
        // the "shorter" half is the damped drag gain that made the excursion
        // smaller in the first place. The multiplier is ≥ 1 always, so damping
        // can only ever reduce peak flow, never raise it.
        //
        // Only spring-backs damp. A commit always completes at full pace: if
        // repeated attempts could slow the journey itself, the navigation
        // would degrade the harder she tried to use it.
        if isReturn { duration *= TimeInterval(2 - dragGain) }

        motion = .settling(from: axisPosition, to: target, duration: duration, elapsed: 0)
    }

    // The gain for a drag beginning right now (barrier condition 13, the
    // "shorter" half). A drag that begins soon after a spring-back is a
    // re-attempt at the same move, and each re-attempt travels less, so a
    // rocking sequence decays instead of building a low-frequency vertical
    // oscillation.
    //
    // This attenuates the CAMERA, never the arbiter: the commit gates are
    // measured in finger points, so a damped drag still commits at exactly the
    // same finger distance and speed. The world moves less; navigation is not
    // made harder. That asymmetry is the point — the damping must not be
    // something she has to fight.
    private func gainForDragBeginningNow() -> CGFloat {
        guard let last = lastReturnAt, elapsed - last < config.oscillationWindow else { return 1 }
        return max(config.dragDampingFloor, dragGain * config.dragDampingFactor)
    }

    private func clampToAxis(_ value: CGFloat) -> CGFloat {
        // The ends of the world. Clamp, not wrap, not rubber-band.
        let limit = config.travelPerPlace
        return min(limit, max(-limit, value))
    }

    // MARK: - Step

    func step(dt: TimeInterval) {
        guard dt > 0 else { return }
        let clamped = min(dt, config.maxStep)
        elapsed += clamped

        guard case .settling(let from, let to, let duration, let settled) = motion else { return }

        let now = settled + clamped
        let s = min(1, CGFloat(now / duration))
        axisPosition = from + (to - from) * Self.ease(s)

        if s >= 1 {
            // Land exactly, not nearly: an arrival that leaves a residue makes
            // `restOffset` a lie and gives the next spring-back a phantom
            // distance to cover.
            axisPosition = to
            motion = .rest
        } else {
            motion = .settling(from: from, to: to, duration: duration, elapsed: now)
        }
    }
}
