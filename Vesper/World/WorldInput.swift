import CoreGraphics
import Foundation

// The whole of gesture arbitration for One World, as a value type.
// No UIKit, no SwiftUI, no wall-clock: touches arrive as (point, timestamp)
// and every decision leaves as an `InputOutcome`. Same discipline as
// GameSimulation, for the same reason — this is the riskiest code in the
// rebuild (DELIVERY_ROADMAP §3, W03) and it has to be provable in CI rather
// than argued about on a device.
//
// The rules encoded here are the Director of Engineering's binding rulings
// (DELIVERY_ROADMAP §6) as amended by the R-SPIKE gate log (§7, items 1–6).
// Each one is commented with the failure it prevents, because every one of
// them looks like an over-complication until the bug it prevents shows up as
// "sometimes the swipe just doesn't work".
//
// SIGN CONVENTION (read this before touching anything below): all y values
// are UIKit view coordinates — y grows downward. So a finger moving *up* the
// screen produces a *negative* translation and a *negative* velocity, and
// commits `.up` (toward the sky). Getting this backwards is the single most
// likely mistake in this file, so the sign is asserted in the tests.
//
// WHAT THIS LAYER DELIBERATELY DOES NOT KNOW (R-SPIKE §7.1):
//   * what an orb is — `GameSimulation.tap` is the single authority, and it
//     already returns no events on a miss, so an empty-space touch costs
//     nothing. A second copy of the hit test can only ever subtract pops.
//   * where the camera is — the arbiter emits a DIRECTION, never a
//     destination. Mapping direction (and `.settleToNearest`) onto a Place
//     lives in exactly one place: WorldCamera.
//   * how fast the world is allowed to move (W05a). This layer measures a
//     finger, in points, because that is what a finger is measured in. How
//     much of the WORLD may slide past her eye in a second is a property of
//     the camera, is measured in screen heights, and is bounded in exactly
//     one place: `WorldCamera.Config.maxOpticalFlow`. See the note where
//     `maxCommitVelocity` used to be, in `Config`.
//
// ISOLATION. `InputArbiter` is `@MainActor`, matching WorldCamera. It is a
// value type and its decisions are pure, but it is not isolation-free: it
// stores `isFieldAtRest`, a non-Sendable closure that reads live camera state
// and is called from UIKit touch callbacks. Those callbacks are main-thread by
// definition and the only owner of an arbiter is a UIView (itself
// `@MainActor`), so the annotation states what is already true and lets Swift
// 6's strict concurrency checking confirm it across the camera/arbiter
// boundary rather than leaving the closure as an unchecked crossing. The
// outcome types (`InputOutcome`, `WorldDirection`) stay non-isolated — they
// are plain data and travel freely.

// MARK: - Outcomes

// Which way through the world the camera was asked to go.
enum WorldDirection: Equatable {
    case up     // toward the sky (finger moved up the screen)
    case down   // toward the journal (finger moved down the screen)
}

// Everything the arbiter can decide — the shared outcome contract fixed by
// the Director at R-SPIKE (§7) so W01 (camera) and W03′ (input) cannot drift.
// There is deliberately no `.retractPop` / `.cancelPop` case: ruling 4 says a
// pop emitted at touch-down is never taken back, and the cheapest way to
// guarantee that is to make it unrepresentable.
enum InputOutcome: Equatable {
    case pop(CGPoint)
    case panBegan
    case panChanged(translation: CGFloat)
    // Velocity travels with the commit so the camera can seed its 300–650 ms
    // settle easing (04 §5) without re-deriving velocity from a second,
    // slightly different sample history.
    //
    // THE CONTRACT (amended by W05a; it previously read "always clamped to
    // `Config.maxCommitVelocity`"). This is the FINGER'S OWN release
    // velocity, in points per second, signed by the sign convention above,
    // and it is NOT BOUNDED ABOVE. A whip flick really does read 6000 pt/s
    // and the arbiter no longer rounds that down to something that looks
    // safe. The one ceiling on how fast the world may slide is
    // `WorldCamera.Config.maxOpticalFlow`, in screen heights per second,
    // applied by the camera — the only layer that can convert points into
    // screen heights, because it is the only one that knows the view height.
    // Any future consumer of this value must clamp it itself, in its own
    // units, rather than assume a bound that is not stated here.
    case commit(WorldDirection, velocity: CGFloat)
    // A transit grab released without a decisive gesture: the camera settles
    // to whichever place is nearer *by its own offset*. The arbiter cannot
    // decide that — it does not know the offset — so it says only "you
    // decide" (§7.3).
    case settleToNearest
    case cancelToRest
}

// MARK: - Batching

extension Array where Element == InputOutcome {
    // Appends a batch while collapsing consecutive `.panChanged` down to the
    // most recent value (§7.6). Every coalesced sample still reaches the
    // arbiter — velocity fidelity depends on it — but the camera offset is
    // written at most once per event, because writing it five times inside
    // one frame just costs four discarded writes.
    //
    // Only *consecutive* runs collapse: an interposed `.panBegan` or `.pop`
    // is a real boundary and the order it establishes is preserved.
    mutating func appendCollapsingPanChanges(_ outcomes: [InputOutcome]) {
        for outcome in outcomes {
            if case .panChanged = outcome, let previous = last, case .panChanged = previous {
                self[count - 1] = outcome
            } else {
                append(outcome)
            }
        }
    }
}

// MARK: - Arbiter

@MainActor
struct InputArbiter {

    // MARK: Config

    // Every threshold is named and injectable. These are the roadmap's
    // *starting* values — 04 §4 says the spike measures the final numbers on
    // device and that section then records the measured values. Nothing here
    // is a feel decision made in an editor; they are placeholders with the
    // right shape so the measurement has something to replace.
    struct Config {
        // Commit gate 1 — distance, as a fraction of screen height.
        // 04 §4 starts the spike at ~10–12%.
        var commitDistanceFraction: CGFloat = 0.11

        // Commit gate 2 — release velocity in points/second.
        // 04 §4: a swipe commits only past *both* gates. AND, not OR: an OR
        // rule commits on any long slow drift of the thumb, which is exactly
        // what happens when she is resting her hand while reading a fortune.
        var commitVelocity: CGFloat = 300

        // THERE IS DELIBERATELY NO CEILING ON RELEASE VELOCITY HERE (W05a,
        // the carry-forward item from R-ARCH §7). There used to be:
        // `maxCommitVelocity = 2400` pt/s, added by R-SPIKE fix 5 so that
        // "the arbiter must not be able to hand the camera a number the
        // camera is not allowed to honour". It is gone, and fix 5's intent is
        // better served without it. Do not put it back; put the number in
        // `WorldCamera.Config.maxOpticalFlow` instead.
        //
        // WHY IT WENT. The quantity being bounded is peak OPTICAL FLOW — how
        // much of the world slides past her eye per second — and that is a
        // screen-height quantity, because a vestibular system does not count
        // points. 2400 pt/s is 2.84 screen heights per second on an 844 pt
        // phone and 1.76 on a 1366 pt iPad: one constant meaning a different
        // thing on every device, sitting beside a camera ceiling of 2.0
        // screen heights per second that means the same thing everywhere.
        // Two ceilings on one physical quantity, in units that cannot be
        // compared without knowing the view height, is not two safety
        // properties. It is one safety property and one number that merely
        // looked like one — and the one that merely looked like one was this
        // one, because the camera re-clamps every seed anyway ("a ceiling
        // that depends on another file staying correct is not a ceiling").
        // Deleting it removes a number rather than synchronising two.
        //
        // WHAT IS LEFT HERE IS MEASUREMENT, NOT POLICY. `deadZone`, `panSlop`
        // and the distance gate stay in points because they are physical
        // finger distances and points is what a finger is measured in. The
        // release velocity this layer reports is the same kind of thing: a
        // record of what her hand did. What the world is allowed to do about
        // it belongs to the camera.

        // Movement before a pan is considered started, in points. Below this
        // the touch is just a touch — without it, the ~1 pt of jitter in a
        // real thumb press turns every pop into a 1 pt camera nudge.
        var panSlop: CGFloat = 10

        // Top and bottom dead zones as a fraction of screen height (04 §4).
        // The OS edge gestures (Control Center, Home) must always win
        // instantly; we buy that by giving up the edges, NOT by calling
        // preferredScreenEdgesDeferringSystemGestures, which makes her phone
        // sticky in her own home. "Her evening, respected."
        //
        // The zones scope COMMITS, not catches (§7.4) — see `began`.
        var edgeDeadZoneFraction: CGFloat = 0.10

        // Window over which release velocity is measured, in seconds.
        // Long enough to survive one dropped frame, short enough that a
        // finger which stopped moving reads as stopped.
        var velocityWindow: TimeInterval = 0.08

        // Samples are retained by TIME, not by count (§7.6): anything older
        // than `velocityWindow * velocityRetentionMultiple` relative to the
        // newest sample is dropped. A count-based cap is a different amount
        // of history at 60 Hz than at 120 Hz than under coalesced delivery,
        // where one event can carry a dozen samples; a time-based one is the
        // same gesture history on every device. 2× keeps a full window plus
        // one window of slack for jitter in sample spacing.
        var velocityRetentionMultiple: Double = 2

        static let `default` = Config()
    }

    // MARK: State

    var config: Config

    // Set by the host view in layoutSubviews. Until it is known, no gate can
    // be evaluated, so the arbiter refuses to commit anything (see
    // `isInEdgeDeadZone`) — a camera move triggered by an unlaid-out view is
    // a move she did not ask for.
    var bounds: CGSize

    // 04 §5, transit input policy: while the camera is settling, a touch-down
    // grabs the camera instead of playing. This is not an exception to ruling
    // 4 — ruling 4 governs the field at rest, where pop and pan both resolve.
    // Off-rest there is no field under her finger to pop.
    //
    // A CLOSURE, NOT A STORED Bool (§7.2). SwiftUI's update pass is not
    // ordered against UIKit touch delivery, so a copy pushed down through
    // `updateUIView` is wrong for about a frame at each end of every settle —
    // and being wrong there costs a pop. This is queried live, exactly once,
    // inside `began` (i.e. inside `touchesBegan`). Whatever supplies it must
    // read the camera's live state, never capture a Bool.
    var isFieldAtRest: () -> Bool = { true }

    private var tracking: Touch?

    private struct Touch {
        var origin: CGPoint
        // Where pan translation is measured from. Once the slop is crossed
        // this is pulled back by exactly `panSlop`, so the camera starts from
        // zero instead of jumping by the slop distance the instant it arms.
        var anchor: CGPoint
        var panArmed: Bool
        var deadZoned: Bool
        // True when this touch began while the camera was moving. It is what
        // makes `.settleToNearest` distinguishable from `.cancelToRest` at
        // release: a grab has no "rest" to go back to.
        var isTransitGrab: Bool
        var samples: [Sample]
    }

    private struct Sample {
        var y: CGFloat
        var t: TimeInterval
    }

    init(bounds: CGSize = .zero,
         config: Config = .default,
         isFieldAtRest: @escaping () -> Bool = { true }) {
        self.bounds = bounds
        self.config = config
        self.isFieldAtRest = isFieldAtRest
    }

    // The host uses this to learn whether the arbiter adopted a touch as the
    // steering touch; tests use it to prove no state leaks between gestures.
    var isTracking: Bool { tracking != nil }

    // MARK: - Touch phases

    // RULING 4. The pop is emitted here, first, unconditionally, and the same
    // touch stays alive as a candidate pan. Both may resolve; neither cancels
    // the other. With ~11 orbs drifting on a portrait field, any rule where
    // the pop suppresses the swipe (or vice versa) makes navigation work or
    // fail depending on where the orbs happened to drift — intermittent,
    // unreproducible, and indistinguishable from a bug.
    //
    // R-SPIKE §7.1. There is no hit test here any more. Every touch-down on a
    // resting field reports `.pop(p)`; `GameSimulation.tap` decides whether
    // anything was there, and returns no events if not. A miss therefore
    // costs one function call and nothing else, while a duplicated hit test
    // could only ever subtract pops — and would drift against a field that
    // keeps moving between the copy and the sim.
    //
    // RULING 3. This is touch-DOWN. v1.2 popped on touch-up via
    // UITapGestureRecognizer; that is a deliberate, measurable change, not a
    // wash.
    mutating func began(at p: CGPoint, timestamp: TimeInterval) -> [InputOutcome] {
        var out: [InputOutcome] = []

        // Queried live, once per touch-down, and reused for the whole of this
        // decision so a settle finishing mid-call cannot make the branch
        // disagree with itself.
        let atRest = isFieldAtRest()

        if atRest { out.append(.pop(p)) }

        // Extra fingers never steer: the second thumb must not yank the
        // camera away from the first, and must not reset the first touch's
        // velocity history.
        //
        // Whether an extra finger POPS is decided above, by `atRest`, and
        // nothing here changes that — so the honest statement of the policy
        // is: extra fingers pop only while the field is at rest, exactly like
        // first fingers. In the real composition `isFieldAtRest` reads the
        // camera, and the camera is not at rest once a pan is armed, so a
        // second thumb landing mid-drag emits nothing at all. That is
        // deliberate and it is the same rule as everywhere else in this file
        // (04 §5): off-rest there is no field under her finger to pop. It is
        // not an exception to ruling 4 — ruling 4 governs the field at rest,
        // where a first or second finger both pop and neither cancels a pan.
        // Only a fixture whose `isFieldAtRest` is a constant `true` makes it
        // look like extra fingers pop unconditionally.
        guard tracking == nil else { return out }

        var touch = Touch(origin: p,
                          anchor: p,
                          panArmed: false,
                          deadZoned: isInEdgeDeadZone(p),
                          isTransitGrab: !atRest,
                          samples: [Sample(y: p.y, t: timestamp)])

        // Transit grab (04 §5): every move is interruptible, and a touch
        // during a settle catches the camera where it is — with no slop,
        // because she is already holding something that is moving.
        //
        // §7.4: the dead zone does NOT apply here. A catch is not a commit.
        // An edge touch during a settle used to produce total silence — the
        // camera kept flying while her finger sat still on it — which breaks
        // "every move is interruptible" (04 §5) in the one place she is most
        // likely to reach: low, one-handed, thumb near the bottom of the
        // screen. The zone still suppresses the *commit* at release, so the
        // OS edge gestures keep everything they were given.
        if !atRest {
            touch.panArmed = true
            out.append(.panBegan)
        }

        tracking = touch
        return out
    }

    mutating func moved(to p: CGPoint, timestamp: TimeInterval) -> [InputOutcome] {
        guard tracking != nil else { return [] }
        // Mutated in place through the optional, never via a local copy:
        // `var touch = tracking` would leave two references to the sample
        // array and pay a full copy-on-write for every coalesced sample of
        // every swipe (§7.6).
        record(Sample(y: p.y, t: timestamp))

        var out: [InputOutcome] = []

        if !tracking!.panArmed {
            // A pan can only ARM from a resting field outside the dead zone.
            // The zone is decided once, from where the touch BEGAN, and is
            // never re-evaluated: a swipe that starts mid-screen and travels
            // up through the top 10% must still commit — killing it on the
            // way past the edge would make long swipes fail and short ones
            // succeed.
            guard !tracking!.deadZoned else { return [] }

            let dy = p.y - tracking!.origin.y
            let dx = p.x - tracking!.origin.x
            // One axis, one meaning (04 §4): vertical is movement through the
            // world, horizontal belongs to whatever the current place does
            // with it. Arming only on vertical-dominant motion keeps a
            // horizontal page turn from dragging the camera sideways-then-up.
            guard abs(dy) > config.panSlop, abs(dy) > abs(dx) else { return out }

            // Read the origin out before writing the anchor: `tracking!.anchor
            // = f(tracking!.origin)` would be a read of `self.tracking` inside
            // a write to it, which is exactly the overlapping-access shape
            // Swift's exclusivity checking exists to reject.
            let origin = tracking!.origin
            tracking!.panArmed = true
            tracking!.anchor = CGPoint(x: origin.x,
                                       y: origin.y + (dy > 0 ? config.panSlop : -config.panSlop))
            out.append(.panBegan)
        }

        // Cumulative translation from the anchor, not a per-event delta.
        // Cumulative is idempotent: a dropped or duplicated event costs one
        // frame of smoothness instead of permanently offsetting the camera
        // from her finger, which is what breaks 1:1 finger tracking (04 §5).
        out.append(.panChanged(translation: p.y - tracking!.anchor.y))
        return out
    }

    mutating func ended(at p: CGPoint, timestamp: TimeInterval) -> [InputOutcome] {
        guard tracking != nil else { return [] }
        record(Sample(y: p.y, t: timestamp))

        // One copy, once, at the end of the gesture — not per sample.
        let touch = tracking!
        tracking = nil

        // A touch that never became a pan simply ends. Nothing to spring
        // home, nothing to report — and critically, nothing that could
        // retract the pop already delivered at touch-down.
        guard touch.panArmed else { return [] }

        let translation = p.y - touch.anchor.y
        let velocity = releaseVelocity(of: touch)

        // §7.4: the dead zone suppresses the commit and nothing else.
        //
        // The measured velocity is handed over as measured (W05a) — no
        // clamp, sign intact. The camera bounds the rate of the world in
        // screen heights; this layer reports the finger in points.
        if !touch.deadZoned,
           let direction = commitDirection(translation: translation, velocity: velocity) {
            return [.commit(direction, velocity: velocity)]
        }

        return [undecidedRelease(of: touch)]
    }

    // The system took the touch away (a call arrived, a system gesture won),
    // or the host lost the touch some other way (leaving the window, a weak
    // UITouch that died). This is the ONLY way to drop a tracked touch other
    // than `ended`, and it is deliberately not silent.
    //
    // There used to be a `reset()` beside this that dropped the touch and
    // emitted nothing, offered to the host as a lifecycle escape hatch. It
    // was a liveness hole: `.dragging` is absorbing under an empty input
    // sequence — the camera leaves that state only when a further outcome
    // arrives — so dropping an ARMED touch without an outcome strands the
    // camera mid-drag with no finger on the glass and nothing left to end it.
    // The hatch is gone rather than merely unused, because "drop the touch
    // quietly" is a shape that reads as harmless at every future call site.
    //
    // Emits exactly one terminating outcome when a pan was armed, and nothing
    // at all otherwise: a touch that never armed has no camera state to
    // terminate, and a bare touch-down must stay a pure pop.
    //
    // Anything already popped stays popped: there is no outcome case that
    // could undo it, by design (ruling 4). Idempotent — a second call after
    // the touch is gone emits nothing.
    mutating func cancelled() -> [InputOutcome] {
        guard let touch = tracking else { return [] }
        tracking = nil
        guard touch.panArmed else { return [] }
        return [undecidedRelease(of: touch)]
    }

    // MARK: - Gates

    // What an armed pan that did not commit resolves to.
    //
    // From rest: `.cancelToRest`. 04 §4 — below threshold the camera springs
    // home and nothing happens; a hesitant half-swipe is free.
    //
    // From a transit grab: `.settleToNearest` (§7.3). She caught a camera
    // that was already moving, so there is no "rest" to return to: springing
    // back to the origin place would throw away a move that may be 90%
    // complete, and would do it precisely when she reached out to steady it.
    // The camera settles to whichever place is nearer by its own offset — a
    // near-complete move completes, an early catch springs home. The arbiter
    // does not know the offset and must not guess at it.
    private func undecidedRelease(of touch: Touch) -> InputOutcome {
        if touch.isTransitGrab { return .settleToNearest }
        return .cancelToRest
    }

    private func commitDirection(translation: CGFloat, velocity: CGFloat) -> WorldDirection? {
        guard bounds.height > 0 else { return nil }

        // Gate 1: distance.
        guard abs(translation) >= bounds.height * config.commitDistanceFraction else { return nil }
        // Gate 2: velocity. AND, per 04 §4.
        guard abs(velocity) >= config.commitVelocity else { return nil }
        // Gate 3: the two must agree. She dragged a long way down and then
        // flicked back up at release — that is a change of mind, and honoring
        // the distance alone would send her somewhere she just decided
        // against. Disagreement springs home.
        guard (translation < 0 ? velocity <= 0 : velocity >= 0) else { return nil }

        return translation < 0 ? .up : .down
    }

    private func isInEdgeDeadZone(_ p: CGPoint) -> Bool {
        // Unknown bounds means every touch is treated as dead: better to lose
        // a swipe on the first frame after layout than to move the camera
        // against a screen height we are guessing at.
        guard bounds.height > 0 else { return true }
        let zone = bounds.height * config.edgeDeadZoneFraction
        return p.y < zone || p.y > bounds.height - zone
    }

    private func releaseVelocity(of touch: Touch) -> CGFloat {
        let samples = touch.samples
        guard samples.count >= 2, let last = samples.last else { return 0 }

        // Oldest sample still inside the window. If the window contains only
        // the final sample — a stalled frame, or a thumb that stopped moving
        // and rested before lifting — fall back to the previous sample, which
        // spans the stall and therefore reads as ~0 rather than as the flick
        // that happened before it.
        var first = samples[samples.count - 2]
        for s in samples.dropLast() where last.t - s.t <= config.velocityWindow {
            first = s
            break
        }

        let dt = last.t - first.t
        guard dt > 0 else { return 0 }
        return (last.y - first.y) / CGFloat(dt)
    }

    // Appends to the tracked touch's sample buffer in place and drops
    // anything older than the retention window (§7.6). At least two samples
    // always survive, because `releaseVelocity` needs a pair to divide.
    private mutating func record(_ sample: Sample) {
        guard tracking != nil else { return }
        tracking!.samples.append(sample)

        let cutoff = sample.t - config.velocityWindow * config.velocityRetentionMultiple
        var stale = 0
        while stale < tracking!.samples.count - 2, tracking!.samples[stale].t < cutoff {
            stale += 1
        }
        if stale > 0 { tracking!.samples.removeFirst(stale) }
    }
}
