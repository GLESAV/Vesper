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

    // ── THE PLACE'S OWN SCROLL (the sky) ────────────────────────────────
    //
    // A place may have somewhere to go on the SAME axis the world travels on:
    // the sky's tree grows taller than one screenful, and looking back along
    // it is a vertical drag. The arbiter gives the place FIRST REFUSAL and
    // hands the camera only what is left over — the ordinary nested-scroll
    // rule, and the reason a single unbroken gesture can walk her back up her
    // own path and then, when the path runs out, carry her to the field.
    //
    // THESE ARE NOT CAMERA OUTCOMES. `WorldCamera.consume` ignores all three
    // explicitly, the way it ignores `.pop`. They are routed to the place.
    //
    // The arbiter still does not know what a sky is. It knows only how many
    // points the current place said it could absorb in each direction, which
    // it asks for exactly once, when the pan arms (`scrollRoom`).
    case scrollBegan
    // Cumulative FINGER translation absorbed by the place, signed by the file's
    // convention — negative is a finger moving up. Cumulative for the same
    // reason `.panChanged` is: assignment is idempotent under a dropped or
    // duplicated event, accumulation is not.
    case scrollChanged(translation: CGFloat)
    // Released, with the finger's own velocity — unbounded, exactly like
    // `.commit`'s. What a glide is allowed to do with it belongs to the place.
    case scrollEnded(velocity: CGFloat)
}

// MARK: - Scroll room

/// How many points the current place can absorb in each FINGER direction
/// before the world should start moving instead.
///
/// Both values are non-negative magnitudes; the direction is the key, not the
/// sign. `.down` is a finger moving down the screen.
struct ScrollRoom: Equatable {
    var up: CGFloat
    var down: CGFloat

    init(up: CGFloat = 0, down: CGFloat = 0) {
        self.up = max(0, up)
        self.down = max(0, down)
    }

    /// A place with nowhere of its own to go. Every place but the sky, and the
    /// sky itself whenever the tree fits on one screen — which is every map
    /// for its first several generations, so this is the common case and it
    /// reproduces the pre-scroll behaviour exactly.
    static let none = ScrollRoom()

    var isEmpty: Bool { up <= 0 && down <= 0 }
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
    //
    // `.scrollChanged` collapses on exactly the same terms and for exactly the
    // same reason: it is cumulative, so only the newest value can matter, and
    // a place that writes its offset five times inside one frame has paid for
    // four writes nobody saw. The two kinds never collapse into each other —
    // they are different runs, and a `.panChanged` between two
    // `.scrollChanged` is a real boundary.
    mutating func appendCollapsingPanChanges(_ outcomes: [InputOutcome]) {
        for outcome in outcomes {
            switch outcome {
            case .panChanged:
                if let previous = last, case .panChanged = previous {
                    self[count - 1] = outcome
                } else {
                    append(outcome)
                }
            case .scrollChanged:
                if let previous = last, case .scrollChanged = previous {
                    self[count - 1] = outcome
                } else {
                    append(outcome)
                }
            default:
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

    // Whether the CAMERA is at rest — anywhere, not just at the field. This
    // is the transit-grab question, and it is a different question from
    // `isFieldAtRest`: the field predicate is false at the resting sky (no
    // orb to pop there), but a touch at the resting sky is not a grab of a
    // world in flight — it is a touch on a place at rest, whose own content
    // (the sky's scrollback) must get first refusal on the drag. Deciding the
    // grab from `!isFieldAtRest()` conflated the two and made every touch at
    // the resting sky arm the camera at touch-down, which (a) made the sky
    // scroll unreachable — `scrollRoom` is only queried on the slop-arming
    // path — and (b) put the world into `.dragging` under a stationary
    // finger, dimming every place and waking the frame clock for a mere tap.
    //
    // A CLOSURE, live, for the same reason the other two are (§7.2).
    var isCameraAtRest: () -> Bool = { true }

    // How much of a vertical drag the CURRENT PLACE wants for itself, before
    // the world starts moving. Queried exactly ONCE per gesture, at the moment
    // the pan arms, and then held for the whole of that gesture.
    //
    // ONCE, NOT LIVE, AND THAT IS THE WHOLE DESIGN. Room shrinks as she
    // scrolls; re-reading it every sample would make the split a function of
    // its own output, and the finger would stop tracking the content some way
    // into every drag. Captured at arm time, the split stays a pure,
    // monotonic, exactly-reversible function of one number — the cumulative
    // translation — so backing up unwinds the scroll and then the pan in the
    // same order they were spent.
    //
    // A CLOSURE, for the same reason `isFieldAtRest` is one (§7.2): SwiftUI's
    // update pass is not ordered against UIKit touch delivery, so a pushed
    // copy is stale at exactly the moments that matter. Its default is
    // `.none`, which reproduces the pre-scroll behaviour exactly.
    var scrollRoom: () -> ScrollRoom = { .none }

    private var tracking: Touch?

    private struct Touch {
        var origin: CGPoint
        // Where pan translation is measured from. Once the slop is crossed
        // this is pulled back by exactly `panSlop`, so the camera starts from
        // zero instead of jumping by the slop distance the instant it arms.
        var anchor: CGPoint
        var panArmed: Bool
        // Whether `.panBegan` has been emitted — i.e. whether the CAMERA is
        // involved in this gesture at all. Distinct from `panArmed`, because a
        // gesture inside a place that has scroll room of its own is a real,
        // armed, tracked vertical drag that the camera has not been told
        // about and must not be: telling it would put the world into
        // `.dragging` (and dim every place, and wake the frame clock) for a
        // gesture that is only moving the sky's own content.
        var cameraArmed: Bool
        var deadZoned: Bool
        // True when this touch began while the camera was moving. It is what
        // makes `.settleToNearest` distinguishable from `.cancelToRest` at
        // release: a grab has no "rest" to go back to.
        var isTransitGrab: Bool
        // The place's room, captured once at arm time. `.none` for a transit
        // grab: she is holding a world in flight, and there is no place under
        // her finger with content of its own to move.
        var room: ScrollRoom
        var samples: [Sample]
    }

    private struct Sample {
        var y: CGFloat
        var t: TimeInterval
    }

    init(bounds: CGSize = .zero,
         config: Config = .default,
         isFieldAtRest: @escaping () -> Bool = { true },
         isCameraAtRest: @escaping () -> Bool = { true },
         scrollRoom: @escaping () -> ScrollRoom = { .none }) {
        self.bounds = bounds
        self.config = config
        self.isFieldAtRest = isFieldAtRest
        self.isCameraAtRest = isCameraAtRest
        self.scrollRoom = scrollRoom
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

        // Both queried live, once per touch-down, and reused for the whole of
        // this decision so a settle finishing mid-call cannot make the branch
        // disagree with itself. TWO QUESTIONS, TWO ANSWERS: whether this
        // touch pops is the field's question; whether it is a grab of a world
        // in flight is the camera's. At the resting sky the first is false
        // and the second is true — the touch neither pops nor grabs, it is a
        // candidate scroll/pan that arms through the slop path below, where
        // `scrollRoom` gets its one query.
        let atRest = isFieldAtRest()
        let cameraResting = isCameraAtRest()

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
                          cameraArmed: false,
                          deadZoned: isInEdgeDeadZone(p),
                          isTransitGrab: !cameraResting,
                          room: .none,
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
        if !cameraResting {
            touch.panArmed = true
            // The camera is armed immediately AND the room stays `.none`: a
            // grab is a grab of the world, and the place under her finger is
            // in flight rather than at rest with content to move. The split is
            // then the identity and this path behaves exactly as it always
            // has.
            touch.cameraArmed = true
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
            // A pan can only ARM from a resting world outside the dead zone.
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

            // THE ONE QUERY. See `scrollRoom`.
            tracking!.room = scrollRoom()

            if tracking!.room.isEmpty {
                // No place scroll: arm the camera here, in the same call, so
                // this path is byte-for-byte the gesture it has always been.
                tracking!.cameraArmed = true
                out.append(.panBegan)
            } else {
                out.append(.scrollBegan)
            }
        }

        // Cumulative translation from the anchor, not a per-event delta.
        // Cumulative is idempotent: a dropped or duplicated event costs one
        // frame of smoothness instead of permanently offsetting the camera
        // from her finger, which is what breaks 1:1 finger tracking (04 §5).
        let translation = p.y - tracking!.anchor.y
        let (scroll, pan) = Self.split(translation: translation, room: tracking!.room)

        if !tracking!.room.isEmpty {
            out.append(.scrollChanged(translation: scroll))
        }

        // THE CAMERA IS TOLD ONLY ABOUT THE LEFTOVER, and is not told at all
        // until there is one. `pan != 0` is the moment the place ran out, and
        // it is also the moment the world may start moving — which is what
        // makes one unbroken gesture walk back up the sky and then carry her
        // out of it.
        //
        // Once armed it stays armed for the rest of the gesture, so backing up
        // into the scroll region drives the camera home to zero rather than
        // stranding it: `.dragging` is absorbing, and a camera that stopped
        // hearing `.panChanged` would sit wherever it was until release.
        if pan != 0 || tracking!.cameraArmed {
            if !tracking!.cameraArmed {
                tracking!.cameraArmed = true
                out.append(.panBegan)
            }
            out.append(.panChanged(translation: pan))
        }
        return out
    }

    // MARK: - The split

    /// Divides one cumulative finger translation between the place's own
    /// scroll and the world's travel: the place gets first refusal up to its
    /// room, the world gets whatever is left.
    ///
    /// PURE, STATIC AND TOTAL, so every sign question in this feature is
    /// settled in one testable function rather than argued about in three
    /// files. It is monotonic in `translation` and exactly reversible — the
    /// two halves always sum back to the input — which is what makes a
    /// gesture that overshoots and comes back unwind in the same order it was
    /// spent, with no hysteresis and nothing to reset.
    ///
    /// Sign convention, as everywhere in this file: negative is a finger
    /// moving UP the screen.
    static func split(translation: CGFloat, room: ScrollRoom) -> (scroll: CGFloat, pan: CGFloat) {
        if translation < 0 {
            let absorbed = max(translation, -room.up)
            return (absorbed, translation - absorbed)
        }
        if translation > 0 {
            let absorbed = min(translation, room.down)
            return (absorbed, translation - absorbed)
        }
        return (0, 0)
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
        let (_, pan) = Self.split(translation: translation, room: touch.room)

        var out: [InputOutcome] = []

        // The place is released first and unconditionally, including inside a
        // dead zone: the zone scopes COMMITS (§7.4), and a scroll is not one.
        // Leaving the sky mid-glide because her thumb happened to end low on
        // the glass would be the same silence §7.4 already refused once.
        if !touch.room.isEmpty { out.append(.scrollEnded(velocity: velocity)) }

        // THE GATES SEE THE LEFTOVER, NOT THE WHOLE FINGER. A drag that the
        // sky absorbed entirely has `pan == 0`, fails the distance gate, and
        // cannot commit — which is the point: scrolling the sky must never
        // also throw her out of it. A drag that ran the sky out and kept going
        // has a real residual, and travelling that far past the end of the
        // content is as clear a statement of intent as the same distance from
        // rest would be.
        //
        // `cameraArmed` guards the terminator for the same reason it guards
        // `.panChanged`: a camera that was never told `.panBegan` has nothing
        // to spring home and must not be sent `.cancelToRest` — invariant A
        // says a malformed sequence moves nothing, and this layer should not
        // be producing one.
        guard touch.cameraArmed else { return out }

        // §7.4: the dead zone suppresses the commit and nothing else.
        //
        // The measured velocity is handed over as measured (W05a) — no
        // clamp, sign intact. The camera bounds the rate of the world in
        // screen heights; this layer reports the finger in points.
        if !touch.deadZoned,
           let direction = commitDirection(translation: pan, velocity: velocity) {
            out.append(.commit(direction, velocity: velocity))
            return out
        }

        out.append(undecidedRelease(of: touch))
        return out
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

        var out: [InputOutcome] = []
        // Zero velocity: the touch was taken away, so there is no release to
        // read a flick from, and a scroll that coasted on because a call
        // arrived would be the system's motion rather than hers.
        if !touch.room.isEmpty { out.append(.scrollEnded(velocity: 0)) }
        guard touch.cameraArmed else { return out }
        out.append(undecidedRelease(of: touch))
        return out
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
