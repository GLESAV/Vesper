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
// ─────────────────────────────────────────────────────────────────────────
// RULING 7, IN FULL. NOT `@Published`, NOT `ObservableObject`, and it never
// will be. The view reads this object's per-frame values once per frame
// inside its own draw; a published per-frame value rebuilds the
// TimelineView/Canvas/input subtree 120 times a second, which is verbatim the
// condition v1.2 blames for cancelled taps. `WorldModel` publishes `place`
// only (W07).
//
// That applies to EVERY derived per-frame scalar on this object, not only to
// `offset`: `offset`, `dragProgress`, `transition` (and the `opacity(of:)`
// helper built on it), `flow`, `exceedsTransitFlow`, `elapsed`, `isAtRest`.
// All of them are read INSIDE the `TimelineView` content closure, at the
// moment they are needed. None of them may be:
//
//   * mirrored into an `@Published` property, an `@State`, an
//     `@ObservedObject`, or any other value SwiftUI diffs;
//   * captured into a `withAnimation` block or an `.animation(_:value:)`
//     modifier — this camera IS the animation, and layering SwiftUI's
//     interpolation on top of it produces two curves fighting over one
//     number, which is how overshoot re-enters a settle that is provably
//     monotone here (barrier condition 12);
//   * written back to the camera from the render pass in any form.
//
// The single legitimate `@Published` in the world layer is `WorldModel.place`,
// which changes at most once per commit.
// ─────────────────────────────────────────────────────────────────────────
//
// ─────────────────────────────────────────────────────────────────────────
// HOST CONTRACT — the camera cannot enforce these, so they are stated here
// and any host that breaks one is a review failure.
//
//   H1. EXACTLY ONE OWNER CALLS `step(dt:)`. One camera, one driver — the
//       world's `TimelineView` frame closure. A second caller (a second view,
//       a preview, a debug overlay, a Combine timer) double-advances every
//       settle and halves its duration, and nothing about the result looks
//       like a bug: the world simply becomes subtly faster than the
//       optical-flow ceiling this file spends its length proving.
//
//   H2. THE HOST MUST CALL `step(dt:)` EVERY FRAME WHILE THE WORLD IS ON
//       SCREEN. This object has no clock of its own and no way to catch up;
//       an unstepped camera does not drift, it FREEZES — mid-settle, halfway
//       between two places, holding her there.
//
//   H3. THE PAUSE PREDICATE PAIRS WITH `WorldModel.worldMoving`, AND NEVER
//       READS THIS OBJECT. v1.2 pauses rendering once the field is cleared and
//       the effects have faded, and that habit is correct and worth keeping —
//       but a paused `TimelineView` stops calling `step(dt:)`, so pausing on
//       the SIM's quiescence alone silently freezes an in-flight settle.
//
//       `camera.isAtRest` CANNOT REPAIR THAT PREDICATE, and putting it there
//       is worse than leaving it out (R-ARCH#2, Nadia). Ruling 7 forbids this
//       object being observable, so nothing about it can invalidate a SwiftUI
//       view: once `sim.isQuiescent && camera.isAtRest` has evaluated true the
//       body is not re-evaluated, the `TimelineView` stays paused, and the
//       next commit begins a settle that is never stepped. The world does not
//       freeze because it was paused too eagerly — it freezes because the one
//       thing that could un-pause it is invisible to SwiftUI.
//
//       So the MOVING half of the predicate is a published value on
//       `WorldModel`, and this is the required pattern for W04:
//
//           // WorldModel — with `place`, the only @Published in this layer.
//           @Published private(set) var worldMoving = false
//
//           // Set in the SAME handler that feeds the camera. That handler is
//           // a UIKit touch callback, outside the render pass, so publishing
//           // from it is safe:
//           func handle(_ outcomes: [InputOutcome]) {
//               camera.consume(outcomes)
//               if !camera.isAtRest { worldMoving = true }
//           }
//
//           // Cleared when the settle ARRIVES, which is only observable from
//           // the frame closure — so the model owns one call for it and the
//           // write is DEFERRED, exactly as GameViewModel defers chain-pop
//           // events, because publishing during the render pass is SwiftUI's
//           // publishing-during-view-update hazard:
//           func worldSettled() {
//               guard worldMoving else { return }
//               DispatchQueue.main.async { self.worldMoving = false }
//           }
//
//           // …called from the frame closure, after the one step (H1):
//           camera.step(dt: dt)
//           if camera.isAtRest { model.worldSettled() }
//
//           TimelineView(.animation(paused: sim.isQuiescent && !model.worldMoving))
//
//       `worldMoving` changes at most twice per gesture — once when her finger
//       or a commit starts the world moving, once when it stops — so it is not
//       the per-frame published value ruling 7 bars. The deferred clear costs
//       one extra frame of an already-at-rest camera, which moves nothing
//       (invariant A). The alternative costs a frozen world.
//
//       Never `paused: sim.isQuiescent` on its own, and never
//       `paused: … && camera.isAtRest`.
//
//       AMENDED AT W05c — "KEEP RENDERING" AND "THE WORLD IS MOVING" ARE TWO
//       QUESTIONS. They only ever looked like one because movement was the
//       only per-frame state this object had. The end-of-axis acknowledgement
//       is a time envelope that runs while the camera is GENUINELY AT REST, so
//       the host publishes both halves and spends them on different things:
//
//           @Published private(set) var worldMoving = false   // mirrors !isAtRest
//           @Published private(set) var worldAwake  = false   // mirrors !isIdle
//
//           TimelineView(.animation(paused: … && !model.worldAwake))
//           …
//           .allowsHitTesting(model.place == place && !model.worldMoving)
//
//       Overloading `worldMoving` with the acknowledgement instead would make
//       the sky's stars untappable for the third of a second after every flick
//       at the ceiling, breaking W09's ≥ 44 pt targets. Pausing on
//       `worldMoving` instead would freeze the envelope mid-glow — the
//       unobservable-pause failure this whole contract exists to forbid,
//       reached from the other side.
//
//       `!isAtRest` implies `!isIdle`, so `worldAwake` is strictly weaker than
//       `worldMoving` and can never pause anything the W04 predicate kept
//       alive. `worldAwake` is written in the same touch handler and cleared
//       by the same deferred hop, for the same reasons.
//
//   H4. `viewHeight` and `reduceMotion` are written by the view (on layout,
//       and from the live system setting via `onAppear` + `onChange`).
//       `config` is written only through `apply(_:)`.
//
//   H5. EVERY `.panBegan` MUST EVENTUALLY BE FOLLOWED BY A TERMINATING
//       OUTCOME — `.commit`, `.settleToNearest`, or `.cancelToRest`. The
//       `.dragging` state is absorbing by design (invariant A: the camera
//       must not decide on its own that her finger is gone), so a gesture
//       dropped without one strands the camera mid-drag with nothing on the
//       glass and nothing left that could end it. The input layer owns this:
//       teardown and touch-loss recovery emit `arbiter.cancelled()` rather
//       than resetting silently (Keiko's liveness finding, W03′).
// ─────────────────────────────────────────────────────────────────────────
//
// `@MainActor` IS PART OF THE CONTRACT, NOT DECORATION. This object is
// written from UIKit touch callbacks (`consume(_:)`, on the main thread by
// definition) and read from the SwiftUI render closure (also main). It has no
// internal synchronization and wants none — the confinement is stated here so
// that Swift 6's strict concurrency checking confirms what is already true
// rather than forcing a rewrite of a file whose numbers have been audited.
// The outcome types it consumes (`Place`, `WorldDirection`, `InputOutcome`)
// stay non-isolated: they are plain data and travel freely.
//
// `InputArbiter` does NOT. It is a value type, but it stores `isFieldAtRest` —
// a non-Sendable closure that reads this camera's live state and is called
// from UIKit touch callbacks — so leaving it non-isolated would put an
// unchecked crossing on exactly the camera/arbiter boundary this annotation
// exists to make honest. It carries the same `@MainActor`, which is likewise
// a statement of what is already true (its only owner is a UIView), and the
// test fixtures are annotated to match.
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
//
// BUT CLAMPING IS NOT SILENCE (W05c). A flick at an end passes every gate the
// arbiter has and then resolves to the place she is already standing in, which
// before W05c produced nothing visible at all — she asked, and the world did
// not answer. It answers now, WITH LIGHT RATHER THAN WITH MOVEMENT: a soft
// brightening at the leading edge that rises and settles back, costing zero
// translation and therefore zero optical flow. `resolveCommit(moving:)` is
// where the axis end is distinguished from every other commit, and
// `Config.acknowledgementRise` carries the ruling and the four reasons a
// rubber-band was refused.
// ─────────────────────────────────────────────────────────────────────────
//
// AMARA OSEI'S VESTIBULAR BARRIER CONDITIONS (R-SPIKE items 10–14) are pass
// conditions at R-ARCH, so each one is implemented here with the failure it
// prevents named at the site:
//
//   10  travel distance is a named constant in screen heights, peak optical
//       flow has a hard ceiling, and one commit's travel has a stated bound —
//       see `Config.travelPerPlace`, `Config.maxOpticalFlow`,
//       `Config.maxTransitPerCommit`, and the arithmetic spelled out there.
//   11  Reduce Motion produces ZERO translation, while a drag still gives
//       proportional non-translating feedback — see `reduceMotion` and
//       `transition`.
//   12  the settle is monotone and non-overshooting at every seeded velocity
//       — see `Ease` and `beginSettle`.
//   13  repeated spring-backs damp, and a commit ends the sequence — see
//       `dragGain`, `lastReturnAt`, `gestureOrigin` and `beginSettle`.
//   14  the light takes turns while the camera is moving — see `flow`,
//       `isTransitioning` and `Config.transitFlowThreshold`. The camera does
//       not dim anything itself; it answers the question, once, so W05 and the
//       renderer do not each invent their own idea of "moving fast" — and
//       `isTransitioning` answers it under Reduce Motion too, where there is
//       no translation to measure a rate from.
//
// THE INVARIANTS, stated so a test can state them too:
//
//   A. The camera never moves unasked. `offset` and `place` change only inside
//      `consume(_:)`, inside `step(dt:)` while finishing a settle that a
//      `consume(_:)` started, and inside `apply(_:)` — which is the host
//      deliberately changing the shape of the world and re-clamping the
//      camera into it, never the camera choosing to move. Stepping an
//      untouched camera forever changes nothing.
//      (testStepWithoutInputNeverMoves)
//   B. Every move is interruptible. `.panBegan` at any point during a settle
//      stops it where it is and hands the camera to her finger.
//      (testGrabMidSettleFreezesTheCameraExactly)
//   C. A settle never overshoots, never reverses, and ends exactly on the
//      destination. (testSettleNeverOvershootsAcrossTheVelocitySweep)
//   D. An unlaid-out camera (`viewHeight <= 0`) refuses every outcome. Moving
//      against a screen height we are guessing at is a move she did not ask
//      for. (testUnlaidOutCameraNeverMoves)
//   E. WHERE THE CAMERA IS, NOT WHERE IT MEANT TO GO, decides what a gesture
//      means. Every destination is resolved from `axisPosition` (via
//      `nearestPlace`); `place` is a record of intent and is never used as a
//      position. (testCommitAfterATransitDragResolvesFromPosition)
//   F. The place of record is always the destination of the settle in flight.
//      `apply(_:)` depends on it, and every path that assigns `motion =
//      .settling` also assigns `place`.
//   G. THE ACKNOWLEDGEMENT IS NOT MOTION. It writes no position and no place,
//      so `isAtRest` — and therefore `WorldModel.simActive`, and therefore
//      whether a touch-down pops an orb — is bit-identical to what it would
//      have been if W05c had never happened. A light that could swallow a tap
//      would be a far worse defect than the silence it replaced.
//      (testTheAcknowledgementNeverLeavesTheCameraNotAtRest)

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

@MainActor
final class WorldCamera {

    // MARK: Config

    struct Config {
        // BARRIER CONDITION 10, first part. The distance between adjacent
        // places, in screen heights.
        //
        // Three quarters, not one, because the world is meant to be
        // continuous (04 §2): at rest on the field, the bottom quarter of the
        // sky is already on screen above her and the journal's ribbon is
        // already visible at her feet. She can see where she is going before
        // she goes, which is most of what makes a place feel like a place
        // rather than a screen.
        var travelPerPlace: CGFloat = 0.75

        // BARRIER CONDITION 10, second part. THE PER-COMMIT TRAVEL BOUND, in
        // place-units: the most axis distance one commit may put on screen.
        //
        // 1.5, AND MEASURED BETWEEN REST OFFSETS (Director's ruling, R-ARCH#2
        // blocker 2). Destinations resolve from where the camera IS (invariant
        // E) and the camera can sit up to half a place from the place nearest
        // it, so the true worst case for a single commit is 1.5 ×
        // `travelPerPlace` — one and an eighth screen heights. That number is
        // the bound, so it is the number the constant states.
        //
        // WHY IT IS NO LONGER 1.0, i.e. what was wrong before. The cap was
        // measured from the LIVE AXIS POSITION to the proposed place, which
        // made it a gate that opened and shut as the camera crossed a place
        // centre. One pixel above the field, an upward flick travelled a whole
        // place; one pixel below it the same flick measured 0.75 + ε, tripped
        // the cap, fell back to `origin` — the place she was already standing
        // on — and travelled ε. A commit that had passed every gate the
        // arbiter has, decisive in both distance and velocity, produced no
        // visible movement at all, and which side of a centre a drifting
        // camera happened to stop on decided which she got. Measuring between
        // `restOffset(origin)` and `restOffset(proposed)` removes the
        // discontinuity entirely: the decision no longer reads the axis at all.
        //
        // WHAT BOUNDS THE 1.5 WORST CASE: `maxOpticalFlow`, which bounds the
        // RATE — the property condition 10 actually protects. A
        // 1.125-screen-height transit at the ceiling simply takes longer
        // (≥ 1.125 s), and slower is never a vestibular hazard; faster is.
        //
        // The comparison below is kept rather than deleted because it is an
        // INVARIANT rather than a gate: adjacent places are exactly one
        // `travelPerPlace` apart, so at 1.5 it never binds, and if anyone ever
        // tunes it under 1 the commit falls back to the place the camera is
        // nearest instead of silently exceeding the stated bound.
        var maxTransitPerCommit: CGFloat = 1.5

        // BARRIER CONDITION 10, third part — THE OPTICAL FLOW CEILING, and
        // the single most important number in this file.
        //
        // Screen heights per second.
        //
        // WHAT THIS BOUNDS, EXACTLY (rewritten at R-ARCH; the previous
        // wording claimed the world may never slide faster than this "at any
        // instant", which is not true and must not be relied on). It bounds
        // CAMERA-GENERATED MOTION: every settle, at every seeded velocity —
        // the whole class of motion the camera produces on its own after her
        // finger has left the glass. That is the entire set of moves she does
        // not control, which is the set a vestibular review is about.
        //
        // FINGER-COUPLED MOTION IS DELIBERATELY EXEMPT. While a finger is
        // down the world tracks it 1:1 and can therefore slide arbitrarily
        // fast, because the finger can. This is a REVIEWED DECISION, not an
        // oversight — Amara's condition 10, taken with 04 §5's "1:1 finger
        // tracking", on three grounds:
        //
        //   * it is self-generated. Motion a person is producing with their
        //     own hand, in real time, with full efference copy, is not the
        //     provocation an imposed large-field flow event is;
        //   * it stops when she stops. There is no follow-through to ride
        //     out: releasing the glass ends it that frame, and whatever
        //     happens next is a settle, which IS bounded;
        //   * it is bounded in extent by the axis clamp. The world has ends,
        //     so the most a drag can ever produce is 2 × `travelPerPlace` of
        //     travel — after that the finger keeps moving and the world does
        //     not.
        //
        // A rate limiter on the drag would buy nothing and cost the one thing
        // 04 §5 insists on: the world would lag her thumb and then catch up,
        // and "catch up" is camera-generated motion she did not ask for.
        //
        // ONE CLAMP, AND IT IS THIS ONE (W05a — the R-ARCH §7 carry-forward,
        // now closed). There used to be two: the arbiter also clamped release
        // velocity, to `InputArbiter.Config.maxCommitVelocity` = 2400 pt/s
        // (R-SPIKE fix 5). Two ceilings on one physical quantity, expressed in
        // units that cannot be compared without knowing the view height, is
        // one safety property and one number that merely looks like one — and
        // the one that merely looked like one was the arbiter's, because this
        // camera re-clamped every seed anyway (a ceiling that depends on
        // another file staying correct is not a ceiling). So the arbiter's is
        // deleted rather than converted, and this is now the only ceiling on
        // camera-generated motion in the codebase.
        //
        // The arbiter therefore hands over the finger's measured release
        // velocity in points per second, UNBOUNDED ABOVE — see
        // `InputOutcome.commit`. That widens the range of numbers arriving
        // here, and the answer is that the clamp in `beginSettle` is total: it
        // maps every finite seed into [0, maxOpticalFlow] and reads a
        // non-finite one as unseeded. The proof below has never depended on
        // anything upstream, which is exactly why it can absorb this.
        //
        // WHERE THIS IS A BEHAVIOUR CHANGE, stated so nobody has to rediscover
        // it: the old points ceiling bound BELOW this one only on a view
        // taller than 1200 pt (= 2400 / 2.0). On a 1366 pt iPad in portrait a
        // whip flick used to settle at 1.76 screen heights per second and now
        // settles at up to 2.0 — the reviewed ceiling doing what it says, on
        // the one device class where the old number was stricter by accident
        // of unit rather than by decision. Every iPhone, and every iPad in
        // landscape, is unchanged: 2400 pt/s was already looser than 2.0 sh/s
        // there, so this ceiling was the binding one and still is. If 2.0 is
        // the wrong number for a 13-inch iPad, the fix is to turn it down —
        // and it is now the only number there is to turn.
        //
        // THE ARITHMETIC, stated as Amara asked. On a 390 × 844 pt iPhone:
        //
        //   travel between places   0.75 × 844  =  633 pt
        //   peak rate at the cap    2.0  × 844  = 1688 pt/s
        //
        // So at MAX SEEDED VELOCITY the peak on-screen travel rate of a
        // settle is two screen heights per second — one full screen of world
        // passes her eye in no less than 500 ms — and only instantaneously,
        // at the moment of release. The ease (below) has a peak-to-average
        // ratio of exactly 2, so the AVERAGE rate across a transit is at most
        // one screen height per second, and a full 633 pt transit therefore
        // takes at least 750 ms. Turn this number DOWN to make the world
        // calmer; there is no other number to turn.
        var maxOpticalFlow: CGFloat = 2.0

        // BARRIER CONDITION 14, the named threshold. Screen heights per
        // second, measured by `flow`. Above it the light takes turns: W05 and
        // the renderer attenuate pop and chain-flash peak luminance, exactly
        // as they already do during a dense cascade.
        //
        // WHY 0.25. A settle's rate is `peak × (1 − s)`, so with the ceiling
        // binding (peak = 2.0) a full transit sits above this threshold for
        // its first ~87% and drops below it about 90 ms before it lands —
        // the light comes back exactly as the world stops, not after a pause.
        // Below a quarter of a screen height per second the world is drifting
        // rather than travelling, and dimming a pop there would read as the
        // app deciding her tap mattered less. On the 844 pt reference screen
        // this is 211 pt/s.
        var transitFlowThreshold: CGFloat = 0.25

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
        // last spring-back ARRIVING is treated as a re-attempt at the same
        // move, and damped. Measured from arrival, not from release — see
        // `lastReturnAt`.
        var oscillationWindow: TimeInterval = 1.0

        // Each successive rapid re-attempt keeps this fraction of the last
        // one's travel, down to the floor. 0.6 → 1.00, 0.60, 0.36, 0.35…
        var dragDampingFactor: CGFloat = 0.6
        var dragDampingFloor: CGFloat = 0.35

        // Same clamp as the game's frame factor: a stalled frame, a
        // breakpoint, or a resumed app must not teleport the world across the
        // screen in one step.
        var maxStep: TimeInterval = 0.05

        // ─────────────────────────────────────────────────────────────────
        // W05c — THE END-OF-AXIS ACKNOWLEDGEMENT, its whole time envelope.
        //
        // THE DEFECT THESE CLOSE. At the sky, an upward flick passes both of
        // the arbiter's commit gates, arrives here as a real `.commit`, and
        // resolves — correctly — to the place she is already in, because
        // there is nothing above the sky. The world then did NOTHING AT ALL:
        // she asked and got silence, which is the same class of defect as a
        // swallowed tap, and it was the last open item of W05.
        //
        // THE FORM IS LIGHT, NOT MOVEMENT (Director's ruling; settled, not to
        // be re-litigated). A soft brightening at the leading edge of the
        // world — the edge she tried to travel toward — which rises and
        // settles back. An iOS-style rubber-band translation was explicitly
        // REFUSED, on four grounds worth carrying here so nobody has to
        // reconstruct them:
        //
        //   * a bounce is an out-and-back translation, which is verbatim the
        //     direction-reversal signature barrier condition 12 removed from
        //     the settle. Reintroducing it at the axis end reintroduces the
        //     kinematics Amara blocked, at the one moment the world is most
        //     likely to be flicked at repeatedly;
        //   * under Reduce Motion it would have to produce zero translation
        //     anyway (condition 11), so it would need a second,
        //     non-translating variant: two behaviours to tune and two to test;
        //   * a luminance cue costs ZERO OPTICAL FLOW, so it cannot erode the
        //     ceiling `maxOpticalFlow` exists to defend (condition 10). There
        //     is no arithmetic above to re-check because there is no motion;
        //   * it is more Vesper. This game acknowledges with light.
        //
        // So the envelope is IDENTICAL WITH AND WITHOUT REDUCE MOTION and
        // produces zero translation on both paths. Nothing below reads
        // `reduceMotion`, deliberately — there is no second path to keep
        // honest, which is most of the point.
        // ─────────────────────────────────────────────────────────────────

        // 0.18 s up. Fast enough that the light still reads as CAUSED BY the
        // flick — a visual change has roughly 200 ms to appear before it stops
        // being bound to the gesture that asked for it — and slow enough to be
        // a rise rather than a blink.
        var acknowledgementRise: TimeInterval = 0.18

        // 0.42 s back down: longer than the rise by a factor of 2.3, because a
        // symmetric envelope reads as a flash and an asymmetric one reads as
        // something settling.
        //
        // AND THE SUM IS THE REAL CONSTANT. 0.18 + 0.42 = 0.60 s, just inside
        // `maxSettleDuration`, so the world's answer to "there is nothing
        // above this" never takes longer than actually going somewhere would
        // have. If either number is retuned, keep the sum under the band.
        var acknowledgementFall: TimeInterval = 0.42

        // BARRIER CONDITION 13'S SHAPE, APPLIED TO A SECOND SEQUENCE.
        // Repeated flicks at the ceiling are the same behaviour as repeated
        // spring-backs — a person asking twice — so they get the same
        // treatment: each rapid re-attempt keeps `Factor` of the last one's
        // peak, down to `Floor`, and one genuinely idle `Window` forgives.
        //
        // SEPARATE CONSTANTS RATHER THAN REUSING `oscillationWindow` AND
        // `dragDamping*`, even though they are set to the same numbers,
        // because the two sequences are independent behaviours: rocking the
        // world and flicking at a wall are different things a person does, and
        // either may need retuning without disturbing the other's proof.
        //
        // THE FLOOR IS LOAD-BEARING, not a rounding detail. An acknowledgement
        // that damped all the way to nothing would put the fifth flick back
        // exactly where the first one started — asking and getting silence —
        // which is the defect this envelope exists to close.
        //
        // AND THE CLOCK IS STAMPED WHEN AN ENVELOPE ENDS, NOT WHEN IT BEGINS.
        // That is R-ARCH major 4's lesson (see `lastReturnAt`) applied here
        // before it could be relearned: the envelope occupies 0.6 s of a 1 s
        // window, so stamping at the trigger would let a second flick 0.7 s
        // later — while the first has barely finished — read as a fresh,
        // undamped attempt, and the damping would terminate itself exactly as
        // the spring-back damping once did.
        var acknowledgementWindow: TimeInterval = 1.0
        var acknowledgementDampingFactor: CGFloat = 0.6
        var acknowledgementDampingFloor: CGFloat = 0.35

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

    // Read freely; written only through `apply(_:)`, which re-clamps the axis
    // and rebuilds any settle in flight against the new geometry. A bare
    // `var` here is a live hazard: changing `travelPerPlace` mid-settle with a
    // plain assignment leaves the camera outside its own axis and the settle
    // aiming at an offset that no longer exists.
    private(set) var config: Config

    // Set by the view on layout, in points. Until it is known the camera
    // refuses to move at all (invariant D). Not routed through `apply(_:)`:
    // the axis is normalized, so a rotation or a Split View resize changes
    // what a screen height is worth without moving the camera through the
    // world.
    var viewHeight: CGFloat

    // BARRIER CONDITION 11. Reduce Motion is a property the view WRITES from
    // the live system setting (`onAppear` + `onChange`); the camera never
    // reads system state itself, because reading it would make this file
    // impure and untestable. While it is true `offset` is identically zero —
    // the places crossfade instead, via `transition` — and the crossfade still
    // answers her finger, so the control never feels dead.
    //
    // A `didSet`, not a bare `var` (R-ARCH#2 minor 7): `offset` steps
    // discontinuously the instant this flips — the entire axis position
    // appears or disappears — and `flow` is measured against the previous
    // frame's `offset`. Without re-seeding that reference the very next
    // `step(dt:)` reports a one-frame optical flow of tens of screen heights
    // per second, and every consumer of condition 14 dims for a frame over a
    // world that did not move.
    var reduceMotion: Bool { didSet { flowReference = offset } }

    // MARK: State the view reads

    // The place the camera belongs to: where it is, or where it is going.
    //
    // It flips at COMMIT time, not on arrival, for three reasons: the sim must
    // stop the instant she has decided to leave the field so no chain resolves
    // unseen (04 §5, W07's `simActive`), the whispers must re-label to name
    // where she can go from there, and `.cancelToRest` needs a home that means
    // "where the camera belongs" rather than "where it happened to start".
    //
    // IT IS A RECORD OF INTENT AND NEVER A POSITION (invariant E). After a
    // transit grab the axis can be anywhere — including past `place`, or on
    // the far side of it — so anything that needs to know where the camera IS
    // asks `axisPosition`/`nearestPlace`. Nothing visual keys off this either:
    // the crossfade keys off `transition`, which is continuous.
    private(set) var place: Place = .field

    // The continuous normalized axis position the view applies as a
    // translation. Zero under Reduce Motion, always (barrier condition 11).
    var offset: CGFloat { reduceMotion ? 0 : axisPosition }

    // MARK: The crossfade

    // The place the transition in flight departed from. Captured at
    // `.panBegan` and at `beginSettle` — the two moments a transition can
    // start — and used ONLY to orient `transition` (which of the two places
    // bracketing the camera she is leaving). It is never a position.
    private(set) var transitionFrom: Place = .field

    // THE CROSSFADE, RESOLVED. The single accessor a view fades with, and the
    // only correct answer to "which two places are on screen and how much of
    // each".
    //
    //   from   the place being left
    //   to     the place being arrived at
    //   t      ALWAYS in [0, 1], and always the ARRIVING place's opacity.
    //          The departing place's opacity is 1 − t.
    //
    // When `from == to` there is no transition in flight: the camera is
    // centred on that place, `t` is 1, and the view draws that place alone.
    // `opacity(of:)` below states all of this in the form a view actually
    // wants, and is the recommended way to consume this.
    //
    // WHY THIS EXISTS, i.e. what was wrong before (R-ARCH, found independently
    // by the chair and by Keiko). The crossfade used to ride on
    // `dragProgress`, a SIGNED distance from `place` — and `place` flips at
    // the commit instant. So the number's reference point moved underneath it
    // mid-transition: a drag toward the sky reading −0.25 became +0.75 the
    // moment she committed, inverting both the sign and the meaning while the
    // world had not moved at all. Every RM view fading on it would have cut
    // rather than crossfaded, once, at the exact instant she asked to go
    // somewhere. Carrying the pair explicitly makes that unrepresentable:
    // `t` is a position between two NAMED places, so it cannot invert, and it
    // is monotone across the commit seam for a fixed pair.
    //
    // The pair changes only when the camera passes a place's centre, where
    // per-place opacity is continuous by construction: the arriving place is
    // at 1 and the departing one at 0 exactly there, so nothing jumps.
    var transition: (from: Place, to: Place, t: CGFloat) {
        guard config.travelPerPlace > 0 else { return (place, place, 1) }

        // Where the camera sits in place-units, clamped to the axis.
        let unit = min(1, max(-1, axisPosition / config.travelPerPlace))
        let lowerRaw = max(-1, min(1, Int(unit.rounded(.down))))
        let upperRaw = max(-1, min(1, Int(unit.rounded(.up))))
        guard let lower = Place(rawValue: lowerRaw),
              let upper = Place(rawValue: upperRaw) else {
            return (place, place, 1)
        }

        // Centred on a place: nothing is crossfading.
        guard lower != upper else { return (lower, lower, 1) }

        // Orient the bracketing pair with the departure anchor. If the anchor
        // is one of the two, it is `from`; if the gesture has carried the
        // camera clean past a place, the anchor is outside the bracket and
        // the near side of it is the place being left.
        let from: Place
        let to: Place
        if transitionFrom == upper {
            from = upper
            to = lower
        } else if transitionFrom == lower {
            from = lower
            to = upper
        } else if transitionFrom.rawValue < lowerRaw {
            from = lower
            to = upper
        } else {
            from = upper
            to = lower
        }

        // Non-zero by construction: `from` and `to` are distinct places and
        // `travelPerPlace` is positive.
        let span = restOffset(of: to) - restOffset(of: from)
        let t = (axisPosition - restOffset(of: from)) / span
        return (from, to, min(1, max(0, t)))
    }

    // How much of a given place is on screen, in [0, 1] — `transition` said
    // the way a view wants to hear it. Under Reduce Motion this is the whole
    // of the navigation: two places, cross-faded, nothing translating.
    func opacity(of candidate: Place) -> CGFloat {
        let resolved = transition
        if resolved.from == resolved.to { return candidate == resolved.to ? 1 : 0 }
        if candidate == resolved.to { return resolved.t }
        if candidate == resolved.from { return 1 - resolved.t }
        return 0
    }

    // RAW, SIGNED, AND NOT THE CROSSFADE. Signed progress away from `place`,
    // in place-units, clamped to [-1, 1]: negative toward the sky, positive
    // toward the journal.
    //
    // It is kept because it is the one value that answers "how far is the
    // camera from the place of record, and on which side" in a single number,
    // which is what a debug HUD and the tests want. It is NOT continuous
    // across a commit — `place` flips there, so this flips with it — so
    // ANYTHING VISUAL MUST USE `transition`/`opacity(of:)` INSTEAD. If a view
    // ever needs the signed form, take it from `transition` and the sign of
    // `to.rawValue - from.rawValue`.
    var dragProgress: CGFloat {
        // Guarded exactly as `transition` is (R-ARCH#2 minor 7). A zero or
        // negative `travelPerPlace` is a degenerate world; dividing by it here
        // produced an infinity or a NaN that then travelled into whatever read
        // it, while `transition` next door answered calmly.
        guard config.travelPerPlace > 0 else { return 0 }
        let d = (axisPosition - restOffset(of: place)) / config.travelPerPlace
        return min(1, max(-1, d))
    }

    // MARK: Motion the view reads

    // True when nothing is in flight: no settle running, no finger down.
    //
    // NOT FOR A PAUSE PREDICATE (host contract H3). It is the right question
    // asked from the wrong place: this object is deliberately not observable,
    // so a SwiftUI predicate built on it never re-evaluates and latches the
    // world frozen mid-settle. The host mirrors it into the published
    // `WorldModel.worldMoving` and pauses on that; the camera answers here for
    // the host's own handlers, and for the tests.
    var isAtRest: Bool {
        if case .rest = motion { return true }
        return false
    }

    // "IS THERE ANYTHING LEFT TO STEP?" — AND IT IS NOT THE SAME QUESTION AS
    // `isAtRest`. W05c is the item that proves they are two: during an
    // end-of-axis acknowledgement the world is genuinely at rest — nothing
    // translates, `offset` does not change, `flow` is exactly zero — and yet
    // the camera is carrying a time envelope that must be stepped every frame
    // or it freezes part-way through a glow.
    //
    // The host pairs the two with two published mirrors and spends them on
    // different questions; the whole of that is written out at host contract
    // H3's W05c amendment, and the short form is:
    //
    //   isAtRest → worldMoving → hit-testing, and the field's sim gate
    //   isIdle   → worldAwake  → the pause predicate
    //
    // ASKED OF THE PHASE, NEVER OF THE LEVEL. The trigger arrives in a touch
    // callback and the first step comes a frame later, so a newly armed
    // acknowledgement is still sitting at level zero: an `isIdle` that read
    // the level would answer "nothing to do" on precisely the frame whose job
    // is to un-pause the world, and the envelope would never be stepped at
    // all. That is the frozen-world failure, reached through the one door
    // W05c opens.
    var isIdle: Bool { isAtRest && acknowledgementPhase == .idle }

    // BARRIER CONDITION 14. How fast the world is sliding on screen, in
    // screen heights per second, measured over the frame that just ended.
    //
    // Measured, not modelled, and therefore valid during BOTH kinds of
    // motion: it is the change in `offset` since the previous `step(dt:)`,
    // divided by that step. A settle contributes the eased rate; a finger
    // contributes whatever the finger did between the two frames (see the
    // finger-coupled exemption on `maxOpticalFlow`). It is zero at rest, and
    // zero on the frame after arrival.
    //
    // Two consequences worth knowing before using it:
    //   * it is one frame OLD. That is the honest answer for a value the
    //     renderer uses to decide how bright the next frame may be.
    //   * under Reduce Motion it is identically zero, because `offset` is —
    //     nothing slides, so no light needs to take a turn. RM transitions
    //     are still detectable via `isAtRest` and `transition`.
    private(set) var flow: CGFloat = 0

    // The question condition 14 actually asks, answered once, here, so that
    // W05 and the renderer cannot each invent their own idea of "moving".
    var exceedsTransitFlow: Bool { flow > config.transitFlowThreshold }

    // BARRIER CONDITION 14, THE ANSWER THAT IS ALSO CORRECT UNDER REDUCE
    // MOTION (R-ARCH#2 minor 6). `exceedsTransitFlow` is derived from
    // translation, and under RM there is none: `offset` is identically zero,
    // so `flow` is identically zero, so the light would never take its turn
    // during an RM transition even though two whole places are crossfading
    // through each other — condition 14 had no answer at all on the accessible
    // path.
    //
    // This is the question W05 and the renderer should ask. It is true when
    // the world is sliding faster than the named threshold AND something is
    // actually in flight — so the frame the camera lands on does not claim a
    // transit out of the delta that carried it there — and it is true for the
    // whole of a Reduce Motion settle. `flow` and `exceedsTransitFlow` remain
    // for anything that wants the rate itself.
    var isTransitioning: Bool {
        if reduceMotion, case .settling = motion { return true }
        return exceedsTransitFlow && !isAtRest
    }

    // The camera's own clock, in seconds, advanced only by `step(dt:)` with dt
    // clamped. Not wall-clock: during a stall it deliberately runs slow,
    // because it measures motion, not time of day. Only the oscillation
    // damping and the acknowledgement damping read it.
    private(set) var elapsed: TimeInterval = 0

    // MARK: The end-of-axis acknowledgement the view reads (W05c)

    // How far into the acknowledgement the world is, in [0, 1].
    //
    // A NORMALIZED ENVELOPE AND NOT A BRIGHTNESS. What one unit of it looks
    // like is `WorldRender.edgeAcknowledgementOpacity`'s decision, in the
    // renderer, for exactly the reason the mote lag and the transit dim live
    // there (W05b): the camera decides how the world moves and the renderer
    // decides what that looks like, and the camera may never decide the
    // second thing. Turning the renderer's peak to zero must leave every
    // number in this file bit-identical.
    //
    // Zero at rest, and EXACTLY zero: the fall assigns the literal 0 and parks
    // the phase, so a paused frame can never be left holding a fraction of a
    // glow.
    private(set) var acknowledgementLevel: CGFloat = 0

    // Which edge of the world she asked to travel past, and therefore which
    // edge answers. It means nothing while the level is zero, which is why
    // `edgeAcknowledgement` is the accessor a view should use: it makes a
    // level without an edge unrepresentable.
    private(set) var acknowledgementEdge: WorldDirection = .up

    // THE ACCESSOR THE VIEW READS — once per frame, inside the frame closure,
    // at the moment it is needed, exactly like every other per-frame scalar on
    // this object (ruling 7). `nil` means there is nothing to draw, which is
    // the overwhelmingly common answer.
    var edgeAcknowledgement: (edge: WorldDirection, level: CGFloat)? {
        guard acknowledgementLevel > 0 else { return nil }
        return (acknowledgementEdge, acknowledgementLevel)
    }

    // MARK: Private state

    private var axisPosition: CGFloat = 0

    // `offset` as of the end of the previous `step(dt:)`. `flow` is measured
    // against this rather than against the position at the top of the current
    // step, so motion written between frames — i.e. every `.panChanged` — is
    // counted in the frame that carries it instead of vanishing.
    private var flowReference: CGFloat = 0

    private enum Motion {
        case rest
        case dragging(anchor: CGFloat)
        // `isReturn` travels with the settle because barrier condition 13's
        // clock is stamped on ARRIVAL, which happens in `step(dt:)`, long
        // after the decision was made in `beginSettle`.
        case settling(from: CGFloat,
                      to: CGFloat,
                      duration: TimeInterval,
                      elapsed: TimeInterval,
                      isReturn: Bool)
    }

    private var motion: Motion = .rest

    // Why a settle is happening. Passed in explicitly rather than inferred,
    // because the two look identical at the destination and mean opposite
    // things (see `beginSettle`).
    private enum SettleReason {
        case commit       // she asked to go somewhere
        case undecided    // `.cancelToRest` / `.settleToNearest`
    }

    // BARRIER CONDITION 13, the whole of it. 1.0 is undamped, 1:1 with her
    // finger; each rapid re-attempt shrinks it toward the floor.
    private var dragGain: CGFloat = 1

    // The camera clock at which the last spring-back ARRIVED.
    //
    // ON ARRIVAL, NOT AT RELEASE — this is the fix for R-ARCH major 4. Stamped
    // at the start of the spring-back, the damping terminated itself: each
    // damped return is deliberately made LONGER, so the following return began
    // more than `oscillationWindow` after the previous one STARTED even when
    // she was rocking the world as fast as she could, and the gain reset to 1
    // on the third attempt. The window has to measure the idle gap between one
    // return finishing and the next beginning, which is what "a return
    // beginning within ~1 s of a previous return" means when the returns
    // themselves take most of a second.
    private var lastReturnAt: TimeInterval?

    // BARRIER CONDITION 13's classifier, half of it. The axis position the
    // camera occupied when the current gesture began (`.panBegan`), or nil
    // when no gesture is in flight. A settle terminates the gesture that
    // produced it (H5), so `beginSettle` reads it once and clears it — a stale
    // departure must never be able to classify the next gesture's settle.
    private var gestureOrigin: CGFloat?

    // W05c. The acknowledgement's own little state machine. Three named
    // states rather than a pair of Bools, so "rising and falling at once" is
    // unrepresentable and `isIdle` has one thing to ask.
    private enum AcknowledgementPhase: Equatable { case idle, rising, falling }
    private var acknowledgementPhase: AcknowledgementPhase = .idle

    // The peak this acknowledgement is climbing toward, in
    // [acknowledgementDampingFloor, 1], and — between attempts — the memory of
    // the last one's peak. `dragGain`'s counterpart for this sequence.
    private var acknowledgementGoal: CGFloat = 1

    // The camera clock at which the last acknowledgement FINISHED. On the end,
    // not on the start, for the reason spelled out on the Config constants and
    // learned the hard way at `lastReturnAt`.
    private var lastAcknowledgedAt: TimeInterval?

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

    // The only way to change tuning after init. Re-clamps the axis to the new
    // geometry and rebuilds any settle in flight against it, because a bare
    // assignment would leave the camera outside its own world and a settle
    // aiming at an offset that no longer exists.
    //
    // The rebuild restarts the ease from the CURRENT position toward the new
    // target, keeping whatever time the old settle had left (and re-applying
    // the optical-flow ceiling to it). Position is therefore continuous — no
    // jump — while the rate may step once, at the instant of a deliberate
    // tuning change. It cannot overshoot or reverse: the new settle is a fresh
    // single-signed ease from here to there.
    //
    // THE ACKNOWLEDGEMENT IS DELIBERATELY NOT REBUILT (W05c). It carries no
    // positions and no places, so a geometry change cannot leave it aiming at
    // an offset that no longer exists — the failure this whole function exists
    // to prevent is simply not available to it. A change to its own durations
    // takes effect on the next `step(dt:)` as a change of ramp rate, with no
    // step in the level, which is the same continuity guarantee the rebuilt
    // settle gets.
    func apply(_ newConfig: Config) {
        config = newConfig
        axisPosition = clampToAxis(axisPosition)

        // R-ARCH#2 minor 7, first half. The re-clamp above and the new
        // `restOffset` geometry can both move `offset` without a frame passing,
        // so the flow reference is re-seeded on every exit from here for the
        // same reason `reduceMotion` does it — otherwise the next `step(dt:)`
        // reports a phantom transit across a world that only changed shape.
        defer { flowReference = offset }

        switch motion {
        case .rest:
            // Second half: a `travelPerPlace` change moves the brackets under
            // the crossfade anchor, which can leave it naming a place the
            // camera is no longer between. Re-anchored to the pair already
            // resolved, exactly as `.panBegan` does, so nothing on screen
            // changes at the instant of the tuning change.
            transitionFrom = transition.from
            return

        case .dragging(let anchor):
            transitionFrom = transition.from
            // Keep her finger's reference inside the new axis too.
            motion = .dragging(anchor: clampToAxis(anchor))

        case .settling(_, _, let duration, let settled, let isReturn):
            // Invariant F: the place of record IS the destination in flight.
            let target = restOffset(of: place)
            let distance = abs(target - axisPosition)
            let remaining = max(duration - settled, 0)

            guard distance > epsilon, remaining > 1e-9 else {
                axisPosition = target
                motion = .rest
                transitionFrom = place
                if isReturn { lastReturnAt = elapsed }
                return
            }

            transitionFrom = departurePlace(for: place)

            var rebuilt = remaining
            if !reduceMotion {
                rebuilt = max(rebuilt,
                              TimeInterval(Self.easePeakFactor * distance / config.maxOpticalFlow))
            }
            motion = .settling(from: axisPosition,
                               to: target,
                               duration: rebuilt,
                               elapsed: 0,
                               isReturn: isReturn)
        }
    }

    // MARK: - Geometry

    // The axis position at which a place is centred. The ONLY place → position
    // conversion in the codebase.
    func restOffset(of place: Place) -> CGFloat {
        CGFloat(place.rawValue) * config.travelPerPlace
    }

    // The place nearest the camera right now. Ties go to `place` — a tie must
    // never be resolved into a move she did not ask for (invariant A).
    //
    // This, not `place`, is where the camera IS (invariant E).
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

    // WHERE A COMMIT GOES, AND WHY IT GOES THERE. Resolved FROM THE AXIS
    // (invariant E) and bounded by `maxTransitPerCommit` (barrier condition
    // 10) — and, since W05c, also reporting whether the answer is the place
    // she is already standing in BECAUSE THE AXIS CLAMPED.
    //
    // THE TWO WAYS A COMMIT CAN NAME ITS OWN ORIGIN ARE DIFFERENT EVENTS, and
    // the caller has to be able to tell them apart, which is the whole reason
    // this returns a pair rather than a `Place`:
    //
    //   * THE AXIS END. `destination(from:moving:)`'s two clamping rows —
    //     `.up` from the sky, `.down` from the journal — answer the origin
    //     because there is nothing beyond it. She asked to go somewhere that
    //     does not exist, and the world owes her an answer for that (W05c);
    //   * THE PER-COMMIT CAP. A proposal further than `maxTransitPerCommit`
    //     falls back to the place the camera is nearest. That is the world
    //     saying "not that far in one go", which is not the same sentence at
    //     all, and it does not get the light. At the shipped 1.5 it never
    //     binds anyway — it is the invariant that keeps a future retune honest.
    //
    // The two are disjoint by construction rather than by ordering: when the
    // table clamps, `nominal` is exactly zero, so the cap could never have
    // been the reason.
    //
    // THIS IS THE ONLY PLACE THAT CAN KNOW. The arbiter emits a direction and
    // never a destination — deliberately, so the direction → place table
    // exists once — so nothing upstream of here has any idea the axis has
    // ends, and nothing upstream of here should be taught.
    //
    // R-ARCH blocker 1: this used to read `destination(from: place, …)`, which
    // is the place she committed to earlier and not where the camera is. After
    // a transit grab the two can be a whole place apart, and the failure is
    // not subtle — parked in the sky, dragged all the way down past the field,
    // released with a downward flick, the old resolution sent the camera back
    // UP to the field: a direction reversal at the end of the largest flow
    // event in the app, which is the exact provocation barrier condition 12
    // exists to forbid. `.settleToNearest` already resolved from position; now
    // every path does.
    private struct CommitResolution {
        let destination: Place
        let gatedByAxisEnd: Bool
    }

    private func resolveCommit(moving direction: WorldDirection) -> CommitResolution {
        let origin = nearestPlace
        let proposed = destination(from: origin, moving: direction)

        // The end of the world, and the only thing that ever sets this flag.
        guard proposed != origin else {
            return CommitResolution(destination: origin, gatedByAxisEnd: true)
        }

        // R-ARCH#2 blocker 2: measured BETWEEN REST OFFSETS, never from the
        // live axis position. Measuring from the axis made this a gate that
        // flipped at the place centre, and a fully gated commit one pixel on
        // the wrong side of it travelled ε — see `Config.maxTransitPerCommit`
        // for the whole account. Adjacent places are one `travelPerPlace`
        // apart, so at the shipped 1.5 this never binds; it is the invariant
        // that keeps a future retune honest rather than a live decision.
        let cap = config.maxTransitPerCommit * config.travelPerPlace
        let nominal = abs(restOffset(of: proposed) - restOffset(of: origin))
        guard nominal > cap + epsilon else {
            return CommitResolution(destination: proposed, gatedByAxisEnd: false)
        }

        // Too far for one commit: stop at the place she is nearest, which is
        // never more than half a place away and always lies in the direction
        // she asked for (it is between the camera and `proposed`).
        return CommitResolution(destination: origin, gatedByAxisEnd: false)
    }

    // The `from` of the crossfade pair for the settle about to begin: of the
    // two places the camera is BRACKETED BY right now, the one on the far side
    // from the destination. Centred on a place, that place is its own
    // departure.
    //
    // R-ARCH#2 major 5: this used to name a NEIGHBOUR OF THE DESTINATION,
    // which is the same place only while the camera is less than one place
    // away from it. Parked at the journal with a settle running to the sky,
    // the neighbour rule answered `.field`, so `transition` reported the camera
    // as ARRIVING at the journal — the place it was leaving — for the whole
    // first half of the move, and a view fading on it faded the wrong way
    // round and then snapped as the pair re-resolved at the field centre. The
    // anchor is now taken from the bracket the camera is actually in, exactly
    // as `.panBegan` re-anchors, and oriented so `to` is always the arriving
    // side.
    private func departurePlace(for arrival: Place) -> Place {
        let resolved = transition
        guard resolved.from != resolved.to else { return resolved.from }
        let target = restOffset(of: arrival)
        let fromDistance = abs(restOffset(of: resolved.from) - target)
        let toDistance = abs(restOffset(of: resolved.to) - target)
        return fromDistance >= toDistance ? resolved.from : resolved.to
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
            //
            // The crossfade is handed over the same way. Re-anchoring to the
            // pair already resolved is what makes the grab invisible to the
            // fade: `transition` depends only on the axis and this anchor, and
            // the grab moves neither, so nothing on screen changes on the
            // frame she touches it.
            transitionFrom = transition.from
            // R-ARCH#2 major 4: where the camera IS when her finger lands is
            // what makes the settle that ends this gesture a return or not.
            // Recorded here, read once in `beginSettle`, and never a `Place`.
            gestureOrigin = axisPosition
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
            //
            // AND THIS DIVISION IS THE UNIT BOUNDARY (W05a). `velocity` is the
            // finger, in points per second, unbounded; `seededSpeed` is the
            // world, in screen heights per second, in the same unit as
            // `maxOpticalFlow` — which is what makes the single ceiling
            // applied in `beginSettle` comparable to the thing it bounds. It
            // happens here, and only here, because `viewHeight` lives here.
            // `viewHeight > 0` is guaranteed by the guard at the top of this
            // function (invariant D), so the division is safe.
            let resolved = resolveCommit(moving: direction)

            // W05c. A commit that cannot go anywhere still gets an answer, and
            // a commit that CAN ends the run of them — barrier condition 13's
            // "a decision ends the sequence", applied to the second sequence.
            //
            // Both are decided here rather than inside `beginSettle`, because
            // `beginSettle` cannot see the difference: an axis-gated commit and
            // an ordinary one arrive there as the same three arguments, and at
            // an end the distance is usually zero, which is also what an
            // already-arrived settle looks like.
            if resolved.gatedByAxisEnd {
                acknowledgeAxisEnd(direction)
            } else {
                endAcknowledgementSequence()
            }

            beginSettle(to: resolved.destination,
                        seededSpeed: abs(velocity) / viewHeight,
                        reason: .commit)

        case .settleToNearest:
            // R-SPIKE fix 3: a transit grab released without a decisive
            // gesture. A near-complete move completes, an early catch springs
            // home. Unseeded — she let go without asking for speed.
            beginSettle(to: nearestPlace, seededSpeed: 0, reason: .undecided)

        case .cancelToRest:
            // Back to where the camera belongs. From the field that is the
            // field; caught mid-transit (the system took the touch away) it is
            // the destination she had already committed to.
            beginSettle(to: place, seededSpeed: 0, reason: .undecided)
        }
    }

    // MARK: - Settle

    private func beginSettle(to newPlace: Place,
                             seededSpeed: CGFloat,
                             reason: SettleReason) {
        // The position the camera occupied when this gesture began, consumed
        // here: a settle terminates its gesture, so the departure must not
        // outlive it and classify the next one.
        let departure = gestureOrigin
        gestureOrigin = nil

        // BARRIER CONDITION 13 — A COMMIT ENDS A ROCKING SEQUENCE (Director's
        // ruling, R-ARCH#2 blocker 1). A commit is a decision, and a decision
        // ends the run of undecided re-attempts the damping exists to decay.
        //
        // Clearing BOTH halves here is what stops the damping leaking across
        // it. `lastReturnAt` was previously cleared only by a genuinely idle
        // `oscillationWindow`, so a hesitant half-swipe that sprang back,
        // followed by an ordinary commit, left the NEXT drag damped: the world
        // no longer 1:1 with her finger, on the first drag after a move she had
        // just completed, for no reason she could see or undo.
        if reason == .commit {
            lastReturnAt = nil
            dragGain = 1
        }

        let target = restOffset(of: newPlace)
        let distance = abs(target - axisPosition)

        // Anchored BEFORE `place` moves: the crossfade pair belongs to the
        // world as it stands on this frame, and `transition`'s two degenerate
        // answers fall back to `place`.
        transitionFrom = departurePlace(for: newPlace)
        place = newPlace

        guard distance > epsilon else {
            axisPosition = target
            motion = .rest
            return
        }

        // BARRIER CONDITION 13 names one thing: a RETURN, i.e. she started a
        // move, did not ask for it, and the world went back where it was. That
        // is three facts, all required:
        //
        //   * the release was UNDECIDED. A commit is a decision, and a
        //     decision is not a re-attempt at anything;
        //   * THE WORLD ENDS WHERE THE GESTURE BEGAN — the settle's target is
        //     the position the camera held at `.panBegan`;
        //   * there is REAL DISTANCE to cover. A release with the camera
        //     already home is not a spring-back, it is a no-op (and is
        //     returned above before reaching here).
        //
        // R-ARCH major 5 removed the first error here: inferring the whole
        // thing from `newPlace == place` armed the damping on every completed
        // commit, so the world got slower the more confidently she used it.
        //
        // R-ARCH#2 major 4 removes the second. Comparing two PLACE values is
        // inverted on the `.settleToNearest` path, in both directions:
        //
        //   * a LATE transit grab released undecided COMPLETES the move — the
        //     world ends a whole place from where her finger landed — yet its
        //     destination equals the place of record, so it armed the damping
        //     and slowed the next drag she made;
        //   * a commit CAUGHT AT ONCE and released undecided puts the world
        //     back exactly where the gesture started — a spring-back by every
        //     meaning of the word — yet its destination differs from the place
        //     of record, so it did not damp at all. That is the rocking
        //     sequence condition 13 exists to decay, going undamped.
        //
        // Classify by what the WORLD did, against the departure position
        // carried in from `.panBegan`, and both come out right.
        var isReturn = false
        if reason == .undecided, let departure = departure {
            isReturn = abs(target - departure) <= epsilon
        }

        // THE CEILING ON THE SEED, and after W05a the only one anywhere: the
        // arbiter no longer clamps, so a whip flick arrives here as whatever
        // the finger actually did. R-SPIKE fix 5's requirement — that nothing
        // can hand this camera a number it is not allowed to honour — is met
        // by making the clamp TOTAL rather than by asking an upstream file to
        // pre-round it.
        //
        // Total means: every finite seed maps into [0, maxOpticalFlow], and a
        // non-finite one is read as unseeded — NOT as the ceiling. A seed that
        // is not a number is not evidence that she asked for speed, and the
        // unseeded settle is the long, calm end of the band; on nonsense
        // input this world slows down. NaN already fell into the
        // unseeded branch below, but only by way of a comparison that happens
        // to be false against NaN; saying it here means a later reordering of
        // that branch cannot turn a NaN seed into a NaN duration, which
        // `step(dt:)` would read as `s = 1` — a settle that is already
        // complete, i.e. the world teleporting on the one input the camera
        // does not control.
        let speed = seededSpeed.isFinite ? min(seededSpeed, config.maxOpticalFlow) : 0

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
        //
        // SKIPPED UNDER REDUCE MOTION (R-ARCH minor 10). Nothing translates
        // under RM, so there is no optical flow to bound — and stretching the
        // duration anyway would push the crossfade past the 300–650 ms the
        // navigation is committed to, making RM the slow, second-class path
        // instead of the equal one condition 11 asks for.
        if !reduceMotion {
            duration = max(duration,
                           TimeInterval(Self.easePeakFactor * distance / config.maxOpticalFlow))
        }

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

        motion = .settling(from: axisPosition,
                           to: target,
                           duration: duration,
                           elapsed: 0,
                           isReturn: isReturn)
    }

    // The gain for a drag beginning right now (barrier condition 13, the
    // "shorter" half). A drag that begins soon after a spring-back ARRIVED is
    // a re-attempt at the same move, and each re-attempt travels less, so a
    // rocking sequence decays instead of building a low-frequency vertical
    // oscillation.
    //
    // This attenuates the CAMERA, never the arbiter: the commit gates are
    // measured in finger points, so a damped drag still commits at exactly the
    // same finger distance and speed. The world moves less; navigation is not
    // made harder. That asymmetry is the point — the damping must not be
    // something she has to fight.
    //
    // And it forgives: one genuinely idle `oscillationWindow` after the last
    // return landed and the gain is 1 again.
    private func gainForDragBeginningNow() -> CGFloat {
        guard let last = lastReturnAt, elapsed - last < config.oscillationWindow else { return 1 }
        return max(config.dragDampingFloor, dragGain * config.dragDampingFactor)
    }

    // MARK: - The end-of-axis acknowledgement (W05c)

    // She asked to travel past the end of the world. Arm the light.
    //
    // THE LEVEL IS NEVER WRITTEN HERE — only the goal, the edge and the phase
    // — and that is what makes a re-trigger free of any step. Whatever the
    // light is doing it goes on doing from exactly where it is: either
    // climbing toward a new goal (which is never higher than the one it was
    // already climbing toward) or beginning its fall. A person flicking at the
    // ceiling four times in a second sees one continuous, decaying light
    // rather than four restarts, and there is no frame anywhere in that
    // sequence on which the brightness jumps.
    private func acknowledgeAxisEnd(_ direction: WorldDirection) {
        let goal = acknowledgementAmplitude()
        acknowledgementGoal = goal

        // Set unconditionally, so the light always names the edge she actually
        // asked about. Moving a LIT glow from one edge to the other would be a
        // step at both ends of the screen, but it is unreachable: getting from
        // one end of the axis to the other costs 1.5 place-units of travel,
        // which takes longer than this entire envelope, so the level is always
        // zero by the time the edge can change.
        acknowledgementEdge = direction

        // Already brighter than this attempt is entitled to? Then it does not
        // rise again; it settles from where it is. The light can only ever be
        // handed downward inside a sequence.
        acknowledgementPhase = acknowledgementLevel < goal ? .rising : .falling
    }

    // A commit that actually travels ends the sequence, exactly as it ends a
    // rocking sequence (barrier condition 13, the Director's R-ARCH#2 ruling).
    // Both halves of the damping are cleared, so the next time she does reach
    // an end she gets a whole answer rather than an inherited whisper of one.
    //
    // It also stops a rising glow rising: the world has just answered her with
    // MOVEMENT, which is the thing the light was standing in for, so the light
    // has nothing left to say and settles back. Set to `.falling` rather than
    // zeroed — zeroing it would be the one visible step in this whole design.
    private func endAcknowledgementSequence() {
        lastAcknowledgedAt = nil
        acknowledgementGoal = 1
        if acknowledgementPhase == .rising { acknowledgementPhase = .falling }
    }

    // The peak the acknowledgement about to begin is allowed to reach.
    // `gainForDragBeginningNow`'s counterpart, and deliberately the same
    // arithmetic on the same shape of state.
    private func acknowledgementAmplitude() -> CGFloat {
        let damped = max(config.acknowledgementDampingFloor,
                         acknowledgementGoal * config.acknowledgementDampingFactor)

        // ONE ALREADY IN FLIGHT IS A RE-ATTEMPT BY DEFINITION, and it has to
        // be named explicitly: the window's clock is stamped when an envelope
        // ENDS, so during a glow there is nothing for the guard below to
        // measure against, and a person flicking faster than 0.6 s apart —
        // which is what flicking at a wall looks like — would never damp at
        // all.
        guard acknowledgementPhase == .idle else { return damped }

        // And it forgives: one genuinely idle window after the last light went
        // out and the next flick gets the full answer again.
        guard let last = lastAcknowledgedAt,
              elapsed - last < config.acknowledgementWindow else { return 1 }
        return damped
    }

    // The envelope, stepped once per frame from `step(dt:)`, with the same
    // clamped dt everything else in this file uses.
    //
    // A FIXED-RATE LINEAR RAMP IN BOTH DIRECTIONS, and both consequences of
    // that are wanted. The on-screen SLOPE of the light is the same however
    // damped the glow is — a quieter answer is a smaller one, not a slower
    // one, and slope is what decides whether a light reads as a flash. And the
    // level is a plain function of accumulated stepped time, so 60 Hz and
    // 120 Hz agree to within one frame quantum, exactly as the settle's own
    // `s = elapsed / duration` does.
    //
    // NOT A SPRING, AND NOT AN EXPONENTIAL DECAY, for the reason `Ease` is not
    // a spring: an exponential never reaches zero, and "never reaches zero" on
    // a value the pause predicate is watching means a world that never pauses.
    //
    // IT REACHES EXACTLY ZERO AND PARKS THERE. The literal `0` is assigned and
    // the phase goes `.idle`, so `isIdle` turns true, the host lets the world
    // pause, and no paused frame is ever left holding a fraction of a glow.
    private func stepAcknowledgement(_ clamped: TimeInterval) {
        switch acknowledgementPhase {
        case .idle:
            break

        case .rising:
            // Guarded exactly as the divisions by `travelPerPlace` are: a
            // degenerate duration resolves to "instant" rather than to an
            // infinity or a NaN travelling out into every colour on screen.
            guard config.acknowledgementRise > 0 else {
                acknowledgementLevel = acknowledgementGoal
                acknowledgementPhase = .falling
                return
            }
            acknowledgementLevel += CGFloat(clamped / config.acknowledgementRise)
            if acknowledgementLevel >= acknowledgementGoal {
                // CLIPPED TO THE GOAL rather than allowed past it. This line,
                // together with the fact that a goal only ever shrinks inside
                // a window, is the whole of why repeated flicks cannot pump
                // the light: the level is bounded above by the largest goal
                // ever set, which is 1.
                acknowledgementLevel = acknowledgementGoal
                acknowledgementPhase = .falling
            }

        case .falling:
            guard config.acknowledgementFall > 0 else {
                acknowledgementLevel = 0
                acknowledgementPhase = .idle
                lastAcknowledgedAt = elapsed
                return
            }
            acknowledgementLevel -= CGFloat(clamped / config.acknowledgementFall)
            if acknowledgementLevel <= 0 {
                acknowledgementLevel = 0
                acknowledgementPhase = .idle
                // Stamped where the light actually went out, for the reason
                // `lastReturnAt` is stamped where the world actually stopped.
                lastAcknowledgedAt = elapsed
            }
        }
    }

    private func clampToAxis(_ value: CGFloat) -> CGFloat {
        // The ends of the world. Clamp, not wrap, not rubber-band.
        let limit = config.travelPerPlace
        return min(limit, max(-limit, value))
    }

    // MARK: - Step

    // Host contract H1–H3: one owner, every frame, and never paused while the
    // world is moving — which the host tracks through `WorldModel.worldMoving`,
    // not by observing this object (H3).
    func step(dt: TimeInterval) {
        guard dt > 0 else { return }
        let clamped = min(dt, config.maxStep)
        elapsed += clamped

        // Everything that has happened to `offset` since the previous frame,
        // including whatever her finger did between the two.
        let reference = flowReference

        if case .settling(let from, let to, let duration, let settled, let isReturn) = motion {
            let now = settled + clamped
            let s = min(1, CGFloat(now / duration))
            axisPosition = from + (to - from) * Self.ease(s)

            if s >= 1 {
                // Land exactly, not nearly: an arrival that leaves a residue
                // makes `restOffset` a lie and gives the next spring-back a
                // phantom distance to cover.
                axisPosition = to
                motion = .rest
                // BARRIER CONDITION 13's clock, stamped where the world
                // actually stopped moving.
                if isReturn { lastReturnAt = elapsed }
            } else {
                motion = .settling(from: from,
                                   to: to,
                                   duration: duration,
                                   elapsed: now,
                                   isReturn: isReturn)
            }
        }

        // W05c. Stepped OUTSIDE the settle block, because it is not a settle:
        // it runs while the camera is at rest, which is the entire reason
        // `isIdle` exists next to `isAtRest`. It writes no position, so it
        // contributes nothing to `flow` below and nothing to `isTransitioning`
        // — an acknowledgement never dims the world (W05b) and never claims a
        // transit, because there is none.
        stepAcknowledgement(clamped)

        flow = abs(offset - reference) / CGFloat(clamped)
        flowReference = offset
    }
}
