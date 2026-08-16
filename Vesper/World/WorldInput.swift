import CoreGraphics
import Foundation

// The whole of gesture arbitration for One World, as a pure value type.
// No UIKit, no SwiftUI, no wall-clock: touches arrive as (point, timestamp,
// did-this-land-on-an-orb) and every decision leaves as an `InputOutcome`.
// Same discipline as GameSimulation, for the same reason — this is the
// riskiest code in the rebuild (DELIVERY_ROADMAP §3, W03) and it has to be
// provable in CI rather than argued about on a device.
//
// The rules encoded here are the Director of Engineering's binding rulings
// (DELIVERY_ROADMAP §6) and the gesture map in 04_NAVIGATION_UX §4–5. Each
// one is commented with the failure it prevents, because every one of them
// looks like an over-complication until the bug it prevents shows up as
// "sometimes the swipe just doesn't work".
//
// SIGN CONVENTION (read this before touching anything below): all y values
// are UIKit view coordinates — y grows downward. So a finger moving *up* the
// screen produces a *negative* translation and a *negative* velocity, and
// commits `.up` (toward the sky). Getting this backwards is the single most
// likely mistake in this file, so the sign is asserted in the tests.

// MARK: - Outcomes

// Which way through the world the camera was asked to go.
enum WorldDirection: Equatable {
    case up     // toward the sky (finger moved up the screen)
    case down   // toward the journal (finger moved down the screen)
}

// Everything the arbiter can decide. There is deliberately no
// `.retractPop` / `.cancelPop` case: ruling 4 says a pop emitted at
// touch-down is never taken back, and the cheapest way to guarantee that is
// to make it unrepresentable.
enum InputOutcome: Equatable {
    case pop(CGPoint)
    case panBegan
    case panChanged(translation: CGFloat)
    // Velocity travels with the commit so the camera can seed its 300–650 ms
    // settle easing (04 §5) without re-deriving velocity from a second,
    // slightly different sample history.
    case commit(WorldDirection, velocity: CGFloat)
    case cancelToRest
}

// MARK: - Arbiter

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

        // Movement before a pan is considered started, in points. Below this
        // the touch is just a touch — without it, the ~1 pt of jitter in a
        // real thumb press turns every pop into a 1 pt camera nudge.
        var panSlop: CGFloat = 10

        // Top and bottom dead zones as a fraction of screen height (04 §4).
        // The OS edge gestures (Control Center, Home) must always win
        // instantly; we buy that by giving up the edges, NOT by calling
        // preferredScreenEdgesDeferringSystemGestures, which makes her phone
        // sticky in her own home. "Her evening, respected."
        var edgeDeadZoneFraction: CGFloat = 0.10

        // Window over which release velocity is measured, in seconds.
        // Long enough to survive one dropped frame, short enough that a
        // finger which stopped moving reads as stopped.
        var velocityWindow: TimeInterval = 0.08

        // How many recent samples to retain. 12 covers ~100 ms at 120 Hz,
        // i.e. always more than `velocityWindow` worth.
        var velocitySampleCount: Int = 12

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
    var fieldAtRest: Bool = true

    private var tracking: Touch?

    private struct Touch {
        var origin: CGPoint
        // Where pan translation is measured from. Once the slop is crossed
        // this is pulled back by exactly `panSlop`, so the camera starts from
        // zero instead of jumping by the slop distance the instant it arms.
        var anchor: CGPoint
        var panArmed: Bool
        var deadZoned: Bool
        var samples: [Sample]
    }

    private struct Sample {
        var y: CGFloat
        var t: TimeInterval
    }

    init(bounds: CGSize = .zero, config: Config = .default) {
        self.bounds = bounds
        self.config = config
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
    // RULING 3. This is touch-DOWN. v1.2 popped on touch-up via
    // UITapGestureRecognizer; that is a deliberate, measurable change, not a
    // wash.
    mutating func began(at p: CGPoint, timestamp: TimeInterval, onOrb: Bool) -> [InputOutcome] {
        var out: [InputOutcome] = []

        if onOrb && fieldAtRest { out.append(.pop(p)) }

        // Extra fingers still pop (above) but never steer: the second thumb
        // must not yank the camera away from the first, and must not reset
        // the first touch's velocity history.
        guard tracking == nil else { return out }

        var touch = Touch(origin: p,
                          anchor: p,
                          panArmed: false,
                          deadZoned: isInEdgeDeadZone(p),
                          samples: [Sample(y: p.y, t: timestamp)])

        // Transit grab (04 §5): every move is interruptible, and a touch
        // during a settle catches the camera where it is — with no slop,
        // because she is already holding something that is moving.
        if !fieldAtRest && !touch.deadZoned {
            touch.panArmed = true
            out.append(.panBegan)
        }

        tracking = touch
        return out
    }

    mutating func moved(to p: CGPoint, timestamp: TimeInterval) -> [InputOutcome] {
        guard var touch = tracking else { return [] }
        append(Sample(y: p.y, t: timestamp), to: &touch)

        // The dead zone is decided once, from where the touch BEGAN, and is
        // never re-evaluated. A swipe that starts mid-screen and travels up
        // through the top 10% must still commit — killing it on the way past
        // the edge would make long swipes fail and short ones succeed.
        guard !touch.deadZoned else {
            tracking = touch
            return []
        }

        var out: [InputOutcome] = []

        if !touch.panArmed {
            let dy = p.y - touch.origin.y
            let dx = p.x - touch.origin.x
            // One axis, one meaning (04 §4): vertical is movement through the
            // world, horizontal belongs to whatever the current place does
            // with it. Arming only on vertical-dominant motion keeps a
            // horizontal page turn from dragging the camera sideways-then-up.
            guard abs(dy) > config.panSlop, abs(dy) > abs(dx) else {
                tracking = touch
                return out
            }
            touch.panArmed = true
            touch.anchor = CGPoint(x: touch.origin.x,
                                   y: touch.origin.y + (dy > 0 ? config.panSlop : -config.panSlop))
            out.append(.panBegan)
        }

        // Cumulative translation from the anchor, not a per-event delta.
        // Cumulative is idempotent: a dropped or duplicated event costs one
        // frame of smoothness instead of permanently offsetting the camera
        // from her finger, which is what breaks 1:1 finger tracking (04 §5).
        out.append(.panChanged(translation: p.y - touch.anchor.y))
        tracking = touch
        return out
    }

    mutating func ended(at p: CGPoint, timestamp: TimeInterval) -> [InputOutcome] {
        guard var touch = tracking else { return [] }
        append(Sample(y: p.y, t: timestamp), to: &touch)
        tracking = nil

        // A touch that never became a pan simply ends. Nothing to spring
        // home, nothing to report — and critically, nothing that could
        // retract the pop already delivered at touch-down.
        guard touch.panArmed, !touch.deadZoned else { return [] }

        let translation = p.y - touch.anchor.y
        let velocity = releaseVelocity(of: touch)

        guard let direction = commitDirection(translation: translation, velocity: velocity) else {
            // 04 §4: below threshold the camera springs home and nothing
            // happens — a hesitant half-swipe is free.
            return [.cancelToRest]
        }
        return [.commit(direction, velocity: velocity)]
    }

    // The system took the touch away (a call arrived, a system gesture won).
    // Anything already popped stays popped: there is no outcome case that
    // could undo it, by design (ruling 4).
    mutating func cancelled() -> [InputOutcome] {
        guard let touch = tracking else { return [] }
        tracking = nil
        return touch.panArmed ? [.cancelToRest] : []
    }

    // Lifecycle escape hatch for the host (view disappearing, place changing).
    // Drops the steering touch without emitting anything.
    mutating func reset() {
        tracking = nil
    }

    // MARK: - Gates

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
        // the final sample — a stalled frame, or a very slow drag sampled
        // sparsely — fall back to the previous sample so a stall reads as
        // "slow" rather than as a divide-by-zero-shaped zero.
        var first = samples[samples.count - 2]
        for s in samples.dropLast() where last.t - s.t <= config.velocityWindow {
            first = s
            break
        }

        let dt = last.t - first.t
        guard dt > 0 else { return 0 }
        return (last.y - first.y) / CGFloat(dt)
    }

    private func append(_ sample: Sample, to touch: inout Touch) {
        touch.samples.append(sample)
        if touch.samples.count > config.velocitySampleCount {
            touch.samples.removeFirst(touch.samples.count - config.velocitySampleCount)
        }
    }
}
