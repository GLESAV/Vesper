import XCTest
import Combine
import CoreGraphics
@testable import Vesper

// W20 — THE INSTRUMENTED REGRESSION (DELIVERY_ROADMAP §3, a Director barrier).
//
// Its acceptance, verbatim: "all suites green; tap success within 2% of the
// W20a baseline; zero unintended camera transitions in a scripted pop storm",
// and — the phrase that decides how this file is written — "MEASURED, NOT
// ASSERTED".
//
// So every number here is counted and printed. The assertions sit on top of
// the measurements rather than instead of them: a green run says what the
// false-trigger count WAS, and a red one names the gesture that produced the
// transition nobody asked for. A gate that can only say "pass" tells the
// owner's playtest nothing on the day the world moves by itself.
//
// WHAT THIS FILE DOES NOT DO. It does not re-test the camera (WorldCameraTests)
// or the arbiter (WorldInputTests) in isolation. Those suites prove each half
// against its own rules; this one runs them TOGETHER, with a live
// GameSimulation underneath, because every defect this barrier exists to catch
// lives in the seam: a pop that eats a swipe, a swipe that eats a pop, a camera
// that moves because a thumb rested on the glass, a field that keeps simulating
// where she cannot see it.
//
// DETERMINISTIC, LIKE EVERY OTHER SUITE HERE. Fixed seeds, synthetic
// timestamps, synthetic `dt`. Nothing reads the wall clock and nothing renders.
//
// `@MainActor` mirrors the isolation of the types under test (WorldCamera,
// InputArbiter, WorldModel), exactly as WorldCameraTests and WorldInputTests do.
@MainActor
final class WorldRegressionTests: XCTestCase {

    // MARK: - The reference device

    // The 390 × 844 pt portrait iPhone every number in the roadmap and in
    // TapBaselineTests is quoted on.
    private let screen = CGSize(width: 390, height: 844)
    private var screenHeight: CGFloat { screen.height }

    // 120 Hz, because it is the harder case: more deliveries per gesture and
    // more chances for a coalesced sample to be mis-attributed.
    private let frame: TimeInterval = 1.0 / 120.0

    // The thresholds the storm is scripted around, read from the arbiter's own
    // config so a retune moves the script rather than invalidating it.
    private var gateDistance: CGFloat {
        screenHeight * InputArbiter.Config.default.commitDistanceFraction
    }
    private var gateVelocity: CGFloat { InputArbiter.Config.default.commitVelocity }
    private var panSlop: CGFloat { InputArbiter.Config.default.panSlop }
    private var deadZone: CGFloat {
        screenHeight * InputArbiter.Config.default.edgeDeadZoneFraction
    }

    // MARK: - The world under test

    private func makeCamera() -> WorldCamera { WorldCamera(viewHeight: screenHeight) }

    // Wired exactly as the shipped composition wires it: `isFieldAtRest` is a
    // LIVE closure reading the camera, and it is the place-aware predicate
    // R-ARCH made a blocking acceptance condition (`camera.isAtRest &&
    // camera.place == .field`), not the bare `isAtRest` that would let a touch
    // at the sky pop a field she cannot see. A fixture with a constant `true`
    // would make most of this file pass for the wrong reason.
    private func makeArbiter(reading camera: WorldCamera) -> InputArbiter {
        InputArbiter(bounds: screen,
                     isFieldAtRest: { camera.isAtRest && camera.place == .field },
                     isCameraAtRest: { camera.isAtRest })
    }

    private func isPop(_ outcome: InputOutcome) -> Bool {
        if case .pop = outcome { return true }
        return false
    }

    private func poppedCount(_ events: [GameEvent]) -> Int {
        events.reduce(into: 0) { total, event in
            if case .popped = event { total += 1 }
        }
    }

    // MARK: - The storm script

    private enum GestureKind: String {
        case restingTap        // a pop, and nothing else
        case jitter            // a thumb press with ~3 pt of wobble
        case decisiveSwipe     // past BOTH gates — the only kind that may commit
        case slowDrag          // past the distance gate, nowhere near the velocity gate
        case shortFlick        // past the velocity gate, nowhere near the distance gate
        case horizontalDrag    // a long sideways drag with a couple of points of vertical slip
        case edgeSwipe         // decisive in every way except where it began
        case changeOfMind      // long one way, flicked back the other at release
        case cancelledSwipe    // decisive, but the system takes the touch away
    }

    private struct ScriptedGesture {
        var kind: GestureKind
        // `points[0]` is the touch-down; the rest are moves; the last is where
        // the finger left the glass.
        var points: [CGPoint]
        var times: [TimeInterval]
        // A second thumb landing mid-gesture, modelled the way WorldInputView
        // models it: an extra finger gets `began` and NOTHING else, because the
        // host filters `moved`/`ended`/`cancelled` to the steering touch. A test
        // that also called `ended` for it would terminate the FIRST touch's
        // tracking and prove a sequence the app cannot deliver.
        var extraFinger: CGPoint?
        var cancelledRatherThanLifted: Bool
        // Frames between this gesture's release and the next touch-down. 0–2 is
        // rapid alternation; ~8–18 lands the next touch in the middle of a
        // settle; ~90 lets the world come fully to rest.
        var gapFrames: Int
        // Whether she then STOPS until the world has landed, rather than
        // touching again on a fixed count of frames.
        //
        // This is not a detail. Every touch that lands off-rest is a transit
        // grab, and releasing it undecided settles the world again — so a storm
        // of nothing but short gaps re-grabs the world before it can ever land
        // and never comes back to rest at all. The first version of this script
        // did exactly that: 383 of 420 touch-downs off-rest, and ruling 6's
        // case (a swipe begun on an orb, at rest) exercised three times in the
        // whole run. A session is the other way round — the world is still
        // while she pops, and only navigation moves it — so most gestures rest
        // afterwards and the storm keeps both halves of the collision live.
        var restsAfterward: Bool

        var origin: CGPoint { points[0] }
        var release: CGPoint { points[points.count - 1] }
    }

    // A NECESSARY condition for a legitimate commit, computed only from the
    // touch points this test injected — never from the arbiter's internals,
    // which would make the oracle a copy of the thing it is checking.
    //
    //   * gate 1 (distance): the arbiter measures translation from an anchor
    //     that sits within `panSlop` of the origin, so |translation| can never
    //     exceed the gross vertical excursion plus `panSlop`;
    //   * gate 2 (velocity): release velocity is (y_last − y_first) / (t_last −
    //     t_first) over a run of CONSECUTIVE samples, which is a convex
    //     combination of the consecutive-sample slopes and is therefore bounded
    //     in magnitude by the largest of them;
    //   * the edge dead zone is decided once, from where the touch began, and
    //     suppresses the commit unconditionally.
    //
    // Deliberately one-directional and deliberately loose: it names the
    // gestures that COULD NOT have passed the gates. A commit from a gesture
    // outside this set is a false trigger by construction, whatever the
    // arbiter's internal reasoning was.
    private func couldLegitimatelyCommit(_ g: ScriptedGesture) -> Bool {
        let originY = g.origin.y
        if originY < deadZone || originY > screenHeight - deadZone { return false }

        var excursion: CGFloat = 0
        for p in g.points { excursion = max(excursion, abs(p.y - originY)) }
        if excursion + panSlop < gateDistance { return false }

        var maxSlope: CGFloat = 0
        for i in 1..<g.points.count {
            let dt = g.times[i] - g.times[i - 1]
            guard dt > 0 else { continue }
            maxSlope = max(maxSlope, abs(g.points[i].y - g.points[i - 1].y) / CGFloat(dt))
        }
        return maxSlope >= gateVelocity
    }

    // Only `decisiveSwipe` may produce a commit. Everything else in the
    // repertoire is something she does while NOT asking to go anywhere —
    // resting a thumb, reading a fortune, turning a page sideways, reaching
    // past the home indicator, changing her mind.
    private func mustNotCommit(_ kind: GestureKind) -> Bool { kind != .decisiveSwipe }

    private func script(count: Int, seed: UInt64) -> [ScriptedGesture] {
        var rng = SplitMix64(seed: seed)
        var gestures: [ScriptedGesture] = []
        var clock: TimeInterval = 0

        // Weighted so the storm reads like a session rather than like a fuzzer:
        // mostly popping, with navigation and near-misses mixed through it.
        let bag: [GestureKind] = [
            .restingTap, .restingTap, .restingTap, .restingTap, .restingTap,
            .jitter, .jitter, .jitter,
            .decisiveSwipe, .decisiveSwipe, .decisiveSwipe,
            .slowDrag, .shortFlick, .horizontalDrag,
            .edgeSwipe, .changeOfMind, .cancelledSwipe,
        ]

        for _ in 0..<count {
            let kind = bag[Int.random(in: 0..<bag.count, using: &rng)]
            let goingUp = Bool.random(using: &rng)
            let sign: CGFloat = goingUp ? -1 : 1     // negative y is up the screen
            let x = CGFloat.random(in: 40...350, using: &rng)

            var points: [CGPoint] = []
            var times: [TimeInterval] = []
            var duration: TimeInterval = 0.06

            // An origin whose whole path stays on screen and outside the edge
            // dead zone, so a gesture only fails a gate for the reason its kind
            // is named after.
            func safeOrigin(travel: CGFloat) -> CGPoint {
                let low = goingUp ? deadZone + 6 + travel : deadZone + 6
                let high = goingUp
                    ? screenHeight - deadZone - 6
                    : screenHeight - deadZone - 6 - travel
                let y = high > low ? CGFloat.random(in: low...high, using: &rng) : (low + high) / 2
                return CGPoint(x: x, y: y)
            }

            // A straight vertical ramp of `steps` evenly spaced samples.
            func ramp(from o: CGPoint, travel: CGFloat, over span: TimeInterval, steps: Int) {
                points = [o]
                times = [clock]
                for i in 1...steps {
                    let f = CGFloat(i) / CGFloat(steps)
                    points.append(CGPoint(x: o.x, y: o.y + sign * travel * f))
                    times.append(clock + span * (TimeInterval(i) / TimeInterval(steps)))
                }
            }

            switch kind {
            case .restingTap:
                let p = CGPoint(x: x, y: CGFloat.random(in: 30...814, using: &rng))
                points = [p, p]
                times = [clock, clock + 0.06]

            case .jitter:
                // Every sample stays inside the slop, in both axes, so nothing
                // here may arm a pan from a resting field.
                let p = CGPoint(x: x, y: CGFloat.random(in: 120...720, using: &rng))
                points = [p,
                          CGPoint(x: p.x + 2, y: p.y - 3),
                          CGPoint(x: p.x - 1, y: p.y + 2),
                          CGPoint(x: p.x + 1, y: p.y - 1)]
                times = [clock, clock + 0.03, clock + 0.06, clock + 0.09]
                duration = 0.09

            case .decisiveSwipe:
                let travel = CGFloat.random(in: 140...260, using: &rng)
                duration = TimeInterval(CGFloat.random(in: 0.10...0.16, using: &rng))
                ramp(from: safeOrigin(travel: travel), travel: travel, over: duration, steps: 8)

            case .slowDrag:
                // Her hand resting on the glass while she reads a fortune: real
                // distance, no speed. This is the exact gesture "AND, not OR"
                // (04 §4) was written for, and an OR rule commits on it.
                let travel = CGFloat.random(in: 120...200, using: &rng)
                duration = 1.4
                ramp(from: safeOrigin(travel: travel), travel: travel, over: duration, steps: 10)

            case .shortFlick:
                // Fast, but nowhere near far enough — a twitch, not a decision.
                let travel = CGFloat.random(in: 30...60, using: &rng)
                duration = 0.05
                ramp(from: safeOrigin(travel: travel), travel: travel, over: duration, steps: 4)

            case .horizontalDrag:
                // One axis, one meaning (04 §4). A page turn must not drag the
                // world sideways-then-up.
                duration = 0.18
                let o = CGPoint(x: 200, y: CGFloat.random(in: 200...640, using: &rng))
                points = [o]
                times = [clock]
                for i in 1...8 {
                    let f = CGFloat(i) / 8
                    points.append(CGPoint(x: o.x + (goingUp ? -1 : 1) * 220 * f,
                                          y: o.y + sign * 4 * f))
                    times.append(clock + duration * (TimeInterval(i) / 8))
                }

            case .edgeSwipe:
                // Decisive in every respect except where it began: the OS edge
                // gestures own these strips and §7.4 gives them up.
                duration = 0.12
                let o = goingUp
                    ? CGPoint(x: x, y: CGFloat.random(in: (screenHeight - deadZone + 4)...(screenHeight - 10),
                                                      using: &rng))
                    : CGPoint(x: x, y: CGFloat.random(in: 10...(deadZone - 4), using: &rng))
                ramp(from: o, travel: 160, over: duration, steps: 8)

            case .changeOfMind:
                // A long committed-looking drag one way, then a flick back the
                // other at release. Distance says one thing and velocity says
                // the opposite: gate 3 refuses to guess which she meant.
                duration = 0.34
                let o = safeOrigin(travel: 244)
                points = [o]
                times = [clock]
                for i in 1...6 {
                    let f = CGFloat(i) / 6
                    points.append(CGPoint(x: o.x, y: o.y + sign * 200 * f))
                    times.append(clock + 0.30 * (TimeInterval(i) / 6))
                }
                points.append(CGPoint(x: o.x, y: o.y + sign * 156))
                times.append(clock + 0.34)

            case .cancelledSwipe:
                duration = 0.12
                ramp(from: safeOrigin(travel: 200), travel: 200, over: duration, steps: 8)
            }

            // A second thumb on one gesture in eight.
            let extra: CGPoint? = Int.random(in: 0..<8, using: &rng) == 0
                ? CGPoint(x: CGFloat.random(in: 40...350, using: &rng),
                          y: CGFloat.random(in: 150...700, using: &rng))
                : nil

            let gapChoices = [0, 1, 2, 8, 18, 90]
            let gap = gapChoices[Int.random(in: 0..<gapChoices.count, using: &rng)]

            // Two gestures in three let the world land before she touches
            // again; the third deliberately lands mid-motion. That keeps the
            // interrupted-settle half of the storm well over its coverage
            // floor while leaving the field genuinely poppable.
            let rests = Int.random(in: 0..<3, using: &rng) != 0

            gestures.append(ScriptedGesture(kind: kind,
                                            points: points,
                                            times: times,
                                            extraFinger: extra,
                                            cancelledRatherThanLifted: kind == .cancelledSwipe,
                                            gapFrames: gap,
                                            restsAfterward: rests))
            // The rest itself takes an unknown number of frames — the camera
            // decides, not the script — so the finger clock gets a nominal
            // allowance for it. Only monotonicity matters here: both gates are
            // measured WITHIN a gesture, and the two clocks are independent by
            // design (see the note above).
            clock += duration + 0.25 + TimeInterval(gap) * frame + (rests ? 0.5 : 0)
        }
        return gestures
    }

    // MARK: - THE POP STORM

    // THE FALSE-TRIGGER CRITERION, MEASURED.
    //
    // A camera transition is UNINTENDED when it is not traceable to a gesture
    // that passed both gates. Three counts stand for that, and all three must
    // be zero:
    //
    //   1. a `.commit` from a gesture that could not have passed both gates
    //      (the oracle above), or from any kind the script does not intend as
    //      a navigation;
    //   2. a change of `camera.place` arriving in a batch that contains no
    //      terminating pan outcome at all — a place change out of nowhere;
    //   3. any movement of `camera.offset` during a touch that never armed a
    //      pan, i.e. a pop moving the world.
    //
    // A `.settleToNearest` that completes or abandons a move in flight IS
    // traceable and IS intended: 04 §5 makes every move interruptible, and a
    // thumb landing on a moving world is a person steadying it. Those are
    // counted and PRINTED rather than failed, because "how often did a touch
    // abort a move" is a playtest question, not a correctness one.
    //
    // A NOTE ON THE TWO CLOCKS. The arbiter's timestamps and the camera's `dt`
    // advance independently here (one frame is stepped per touch delivery).
    // They are independent in the app too — the digitizer and the display are
    // not locked — and nothing in either gate reads the other's clock: the
    // commit gates are measured in finger points and finger seconds, and the
    // camera's only time-dependent behaviour is the anti-oscillation damping,
    // which can lower the drag gain but can never manufacture a commit.
    func testPopStormProducesZeroUnintendedCameraTransitions() {
        let camera = makeCamera()
        var arbiter = makeArbiter(reading: camera)

        // A live field underneath, so this is a POP storm and not an input
        // storm: swipes begin on orbs, chains resolve between gestures, and the
        // simulation is gated by the same predicate the world gates it with
        // (W07 / ruling 9).
        let sim = GameSimulation(seed: 0xA1C0_5A70_D065)
        sim.pinnedWeather = .clear
        sim.reduceMotion = true
        sim.layout(size: screen)

        var pops = 0                    // `.pop` outcomes emitted
        var orbPops = 0                 // orbs removed by a direct touch
        var chainPops = 0
        var commits = 0
        var placeChanges = 0
        var settleToNearests = 0
        var movesInterruptedByATouch = 0
        var touchDownsAtRestOnField = 0
        var touchDownsOffRest = 0
        var swipesBegunOnALiveOrb = 0
        var swipesThatBothPoppedAndCommitted = 0
        var frameCount = 0

        var unintendedCommits: [String] = []
        var untraceablePlaceChanges: [String] = []
        var popsThatMovedTheWorld: [String] = []

        func fieldIsLive() -> Bool { camera.isAtRest && camera.place == .field }

        // One frame of the world: the camera always steps, the simulation steps
        // only while the field is the place at rest — exactly as
        // WorldModel.advance gates it.
        func stepWorld(_ n: Int) {
            for _ in 0..<n {
                camera.step(dt: frame)
                if fieldIsLive() {
                    for event in sim.step(dt: frame) {
                        if case .popped(_, let chained) = event, chained { chainPops += 1 }
                    }
                }
                frameCount += 1
            }
        }

        // Applies one touch delivery the way WorldModel.handle applies it: pops
        // first (ruling 4 — the pop is never delayed and never retracted), then
        // the camera.
        func deliver(_ batch: [InputOutcome], kind: GestureKind, index: Int) {
            let placeBefore = camera.place
            let offsetBefore = camera.offset

            for outcome in batch {
                if case .pop(let p) = outcome {
                    pops += 1
                    for event in sim.tap(at: p) {
                        if case .popped(_, let chained) = event, !chained { orbPops += 1 }
                    }
                }
            }

            camera.consume(batch)

            var terminated = false
            var hasPop = false
            var hasPan = false
            for outcome in batch {
                switch outcome {
                case .pop:
                    hasPop = true
                case .panBegan, .panChanged:
                    hasPan = true
                case .commit:
                    terminated = true
                    hasPan = true
                    commits += 1
                case .settleToNearest:
                    terminated = true
                    hasPan = true
                    settleToNearests += 1
                case .cancelToRest:
                    terminated = true
                    hasPan = true
                case .scrollBegan, .scrollChanged, .scrollEnded:
                    // Unreachable in this fixture and asserted to be: this
                    // arbiter is built with the default `scrollRoom`, which
                    // answers `.none` for every place. If one of these ever
                    // shows up here it means the arbiter started handing a
                    // place points nobody offered, and the invariants below —
                    // which all reason about a gesture the CAMERA saw in
                    // full — would be measuring the wrong thing.
                    XCTFail("#\(index) \(kind.rawValue): a place with no room scrolled")
                }
            }

            if camera.place != placeBefore {
                placeChanges += 1
                if !terminated {
                    untraceablePlaceChanges.append(
                        "#\(index) \(kind.rawValue): place \(placeBefore) → \(camera.place) "
                        + "with no terminating pan outcome in \(batch)")
                }
            }

            if hasPop && !hasPan && camera.offset != offsetBefore {
                popsThatMovedTheWorld.append(
                    "#\(index) \(kind.rawValue): offset \(offsetBefore) → \(camera.offset)")
            }
        }

        let gestures = script(count: 420, seed: 0x5709_3D_0FF5)

        for (index, scripted) in gestures.enumerated() {
            var g = scripted

            // Ruling 6, at scale: aim decisive swipes at the centre of a live
            // orb, so the storm keeps re-running the one case where the two
            // systems collide — the pop must not eat the swipe, and the swipe
            // must not eat the pop.
            var begunOnOrb = false
            if g.kind == .decisiveSwipe || g.kind == .restingTap,
               let orb = sim.orbs.first(where: {
                   $0.alive
                       && $0.pos.y > self.deadZone + 8
                       && $0.pos.y < self.screenHeight - self.deadZone - 8
               }) {
                let dx = orb.pos.x - g.points[0].x
                let dy = orb.pos.y - g.points[0].y
                let shifted = g.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                let ys = shifted.map(\.y)
                // The shift may carry the path off screen; only take it if the
                // whole gesture is still a touch the device could deliver.
                if let lo = ys.min(), let hi = ys.max(), lo > 4, hi < screenHeight - 4 {
                    g.points = shifted
                    // The counter is about ruling 6 specifically — a SWIPE
                    // begun on an orb. Taps aimed at orbs are here so the storm
                    // actually clears fields, not to be counted as that case.
                    begunOnOrb = g.kind == .decisiveSwipe
                }
            }

            let atRestOnField = fieldIsLive()
            if atRestOnField { touchDownsAtRestOnField += 1 } else { touchDownsOffRest += 1 }
            if begunOnOrb { swipesBegunOnALiveOrb += 1 }

            let popsBefore = pops
            let orbPopsBefore = orbPops
            let commitsBefore = commits
            let offsetAtTouchDown = camera.offset
            let placeAtTouchDown = camera.place
            var outcomesThisGesture: [InputOutcome] = []

            var batch = arbiter.began(at: g.points[0], timestamp: g.times[0])
            outcomesThisGesture += batch
            deliver(batch, kind: g.kind, index: index)

            if let extra = g.extraFinger {
                // Extra fingers never steer. Whether they POP is decided by the
                // same `isFieldAtRest` every other touch-down asks, so they pop
                // only while the field is genuinely at rest.
                batch = arbiter.began(at: extra, timestamp: g.times[0] + 0.004)
                outcomesThisGesture += batch
                deliver(batch, kind: g.kind, index: index)
            }

            for i in 1..<g.points.count {
                batch = arbiter.moved(to: g.points[i], timestamp: g.times[i])
                outcomesThisGesture += batch
                deliver(batch, kind: g.kind, index: index)
                stepWorld(1)
            }

            batch = g.cancelledRatherThanLifted
                ? arbiter.cancelled()
                : arbiter.ended(at: g.release, timestamp: g.times[g.times.count - 1])
            outcomesThisGesture += batch
            deliver(batch, kind: g.kind, index: index)

            // A gesture must never leave the arbiter believing it is still
            // steering: that is the liveness hole the removal of `reset()`
            // closed, and it strands the camera mid-drag with no finger on it.
            XCTAssertFalse(arbiter.isTracking,
                           "gesture #\(index) (\(g.kind.rawValue)) left the arbiter tracking")

            // ── The false-trigger checks, per gesture ──
            let committed = commits > commitsBefore
            if committed && mustNotCommit(g.kind) {
                unintendedCommits.append(
                    "#\(index) \(g.kind.rawValue) committed: \(outcomesThisGesture)")
            }
            if committed && !couldLegitimatelyCommit(g) {
                unintendedCommits.append(
                    "#\(index) \(g.kind.rawValue) committed but could not have passed both gates: "
                    + "\(outcomesThisGesture)")
            }
            if g.kind == .decisiveSwipe && !committed {
                XCTFail("gesture #\(index): a swipe past both gates did not commit — a SWALLOWED "
                        + "navigation, the same defect as a swallowed tap: \(outcomesThisGesture)")
            }

            // The sharpest form of the criterion: at rest on the field, a tap
            // is a pop and NOTHING else. No pan, no settle, not one point of
            // camera movement.
            if atRestOnField && g.kind == .restingTap {
                for outcome in outcomesThisGesture {
                    XCTAssertTrue(isPop(outcome),
                                  "gesture #\(index): a tap on a resting field produced \(outcome)")
                }
                XCTAssertEqual(camera.offset, offsetAtTouchDown,
                               "gesture #\(index): a tap moved the world")
                XCTAssertEqual(camera.place, placeAtTouchDown,
                               "gesture #\(index): a tap changed the place")
                XCTAssertTrue(camera.isAtRest,
                              "gesture #\(index): a tap started the camera moving")
            }
            if atRestOnField && g.kind == .jitter {
                XCTAssertEqual(camera.offset, offsetAtTouchDown,
                               "gesture #\(index): a few points of thumb wobble moved the world")
                XCTAssertTrue(camera.isAtRest,
                              "gesture #\(index): a few points of thumb wobble armed a pan")
            }

            // Ruling 4 in its measurable form: a touch-down on a resting field
            // always pops, and a touch anywhere else never does.
            let popsThisGesture = pops - popsBefore
            if atRestOnField {
                XCTAssertGreaterThanOrEqual(popsThisGesture, 1,
                                            "gesture #\(index): a touch-down on a resting field "
                                            + "produced no pop — a SWALLOWED TAP")
            } else {
                XCTAssertEqual(popsThisGesture, 0,
                               "gesture #\(index): a touch popped a field that was not on screen "
                               + "at rest")
            }

            if begunOnOrb && atRestOnField && orbPops > orbPopsBefore && committed {
                swipesThatBothPoppedAndCommitted += 1
            }
            if camera.place != placeAtTouchDown && !committed { movesInterruptedByATouch += 1 }

            stepWorld(g.gapFrames)

            // She stops until the world has landed. Capped, and the cap is
            // asserted rather than absorbed: a camera that cannot reach rest in
            // ten seconds of frames is the liveness failure this test exists to
            // catch, and silently continuing the storm would hide it behind a
            // coverage number at the end.
            if g.restsAfterward {
                var restFrames = 0
                while !camera.isAtRest && restFrames < 600 {
                    stepWorld(1)
                    restFrames += 1
                }
                XCTAssertTrue(camera.isAtRest,
                              "gesture #\(index) (\(g.kind.rawValue)): the world could not come to "
                              + "rest in \(restFrames) frames")
            }

            // Keep a field under the storm so there is always something to hit.
            if sim.orbs.allSatisfy({ !$0.alive }) { sim.restart() }
        }

        // The world must be able to come to rest when the storm stops. A camera
        // stranded between places is a liveness failure, not a cosmetic one.
        var settleFrames = 0
        while !camera.isAtRest && settleFrames < 10_000 {
            camera.step(dt: frame)
            settleFrames += 1
        }
        XCTAssertTrue(camera.isAtRest, "the world never came to rest after the storm")
        XCTAssertEqual(camera.offset, camera.restOffset(of: camera.place), accuracy: 1e-12,
                       "the world came to rest between places")

        // ── MEASURED, NOT ASSERTED ──
        print("""
        [W20] pop storm — \(gestures.count) gestures over \(frameCount) frames
              touch-downs:            \(touchDownsAtRestOnField) at rest on the field, \
        \(touchDownsOffRest) off-rest
              pops emitted:           \(pops) (orbs by touch: \(orbPops), by chain: \(chainPops))
              commits:                \(commits)
              place changes:          \(placeChanges)
              settleToNearest:        \(settleToNearests)
              moves interrupted:      \(movesInterruptedByATouch)
              swipes begun on an orb: \(swipesBegunOnALiveOrb) \
        (\(swipesThatBothPoppedAndCommitted) both popped and committed)
              UNINTENDED COMMITS:     \(unintendedCommits.count)
              UNTRACEABLE PLACE Δ:    \(untraceablePlaceChanges.count)
              POPS THAT MOVED WORLD:  \(popsThatMovedTheWorld.count)
        """)

        XCTAssertEqual(unintendedCommits.count, 0,
                       "the camera committed on \(unintendedCommits.count) gesture(s) that did not "
                       + "ask it to:\n" + unintendedCommits.joined(separator: "\n"))
        XCTAssertEqual(untraceablePlaceChanges.count, 0,
                       "the camera changed place with nothing to trace it to:\n"
                       + untraceablePlaceChanges.joined(separator: "\n"))
        XCTAssertEqual(popsThatMovedTheWorld.count, 0,
                       "a pop moved the world:\n" + popsThatMovedTheWorld.joined(separator: "\n"))

        // Coverage guards: a storm that never navigated, never popped, or never
        // landed a touch during a settle would pass all of the above vacuously.
        XCTAssertGreaterThan(commits, 20, "the storm never navigated — the measurement is vacuous")
        XCTAssertGreaterThan(orbPops, 30, "the storm never popped anything")
        XCTAssertGreaterThan(touchDownsOffRest, 10,
                             "no touch landed while the world was moving — the interrupted-settle "
                             + "half of the storm did not run")
        XCTAssertGreaterThan(swipesBegunOnALiveOrb, 10,
                             "ruling 6's case (swipes begun on an orb) was never exercised")
    }

    // The criterion again, isolated and absolute, so a red run says which of
    // the two it is. Two hundred consecutive taps, at rest, on the field.
    func testTwoHundredConsecutiveTapsMoveTheWorldNotAtAll() {
        let camera = makeCamera()
        var arbiter = makeArbiter(reading: camera)
        var rng = SplitMix64(seed: 0x7A9_0000)
        var t: TimeInterval = 0
        var pops = 0

        for i in 0..<200 {
            let p = CGPoint(x: CGFloat.random(in: 20...370, using: &rng),
                            y: CGFloat.random(in: 20...824, using: &rng))
            var batch = arbiter.began(at: p, timestamp: t)
            // A couple of points of thumb wobble on every third tap: that is
            // what a real press looks like, and it is what `panSlop` is for.
            if i % 3 == 0 {
                batch += arbiter.moved(to: CGPoint(x: p.x + 2, y: p.y - 3), timestamp: t + 0.02)
                batch += arbiter.moved(to: CGPoint(x: p.x - 2, y: p.y + 3), timestamp: t + 0.04)
            }
            batch += arbiter.ended(at: p, timestamp: t + 0.06)

            for outcome in batch { if isPop(outcome) { pops += 1 } }
            camera.consume(batch)
            camera.step(dt: frame)
            t += 0.12

            XCTAssertEqual(camera.offset, 0, "tap #\(i) moved the world")
            XCTAssertEqual(camera.place, .field, "tap #\(i) changed the place")
            XCTAssertTrue(camera.isAtRest, "tap #\(i) started the camera moving")
        }

        print("[W20] 200 taps at rest → \(pops) pops, 0 camera transitions, offset still 0")
        XCTAssertEqual(pops, 200, "every tap on a resting field must pop")
    }

    // THE EXPOSURE THIS TEST USED TO MEASURE IS REPAIRED. The arbiter once
    // decided the transit grab from `!isFieldAtRest()`, so at the resting sky
    // an ordinary press read as a grab of a world in flight: the pan armed
    // with no slop and a 3 pt thumb wobble moved the world where the same
    // wobble on the field moved it not at all. The grab decision now has its
    // own question — `isCameraAtRest` — so a press at a RESTING place is a
    // press, with the same slop everywhere.
    //
    // This test pins the repaired symmetry: a sub-slop press at the resting
    // sky pops nothing, arms nothing, moves nothing, and ends in silence.
    func testASubSlopPressAwayFromTheFieldMovesNothingAtAll() {
        let camera = makeCamera()
        var arbiter = makeArbiter(reading: camera)

        camera.consume(.commit(.up, velocity: 1200))
        var settled = 0
        while !camera.isAtRest && settled < 10_000 { camera.step(dt: frame); settled += 1 }
        XCTAssertEqual(camera.place, .sky)

        // DOWNWARD, 3 pt — toward the field, where an excursion would have
        // room to show. (Upward pushes against the end of the axis, where
        // `clampToAxis` would absorb it and hide a regression.)
        let restingOffset = camera.offset
        var batch = arbiter.began(at: CGPoint(x: 195, y: 420), timestamp: 0)
        batch += arbiter.moved(to: CGPoint(x: 195, y: 423), timestamp: 0.02)
        XCTAssertEqual(batch, [], "a sub-slop press at a resting place asks for nothing")
        camera.consume(batch)
        XCTAssertEqual(abs(camera.offset - restingOffset), 0, accuracy: 1e-12,
                       "a 3 pt press at the resting sky must move the world exactly as far "
                       + "as it moves it on the field: not at all")

        let tail = arbiter.ended(at: CGPoint(x: 195, y: 423), timestamp: 0.05)
        XCTAssertEqual(tail, [], "a touch that never armed has nothing to terminate")
        camera.consume(tail)

        settled = 0
        while !camera.isAtRest && settled < 10_000 { camera.step(dt: frame); settled += 1 }
        XCTAssertEqual(camera.place, .sky, "a sub-slop press must never change the place")
        XCTAssertEqual(camera.offset, camera.restOffset(of: .sky), accuracy: 1e-12)
    }

    // MARK: - Tap success against the W20a baseline

    // ─────────────────────────────────────────────────────────────────────────
    // WHAT CHANGED SINCE W20a, AND WHY THE COMPARISON IS STILL LIKE-FOR-LIKE.
    //
    // Two things changed in the input model. Neither changes the question the
    // baseline answers.
    //
    //   1. v1.2 popped on touch-UP, through a UITapGestureRecognizer; the world
    //      pops on touch-DOWN (ruling 3). In this harness the down and up
    //      points are identical — a tap does not move — so both models are
    //      asked about the same point. The case where they genuinely differ, a
    //      swipe begun on an orb, is tested separately below, and the world
    //      path WINS it: v1.2 popped nothing at all there.
    //
    //   2. The input layer no longer hit-tests. It emits `.pop` UNCONDITIONALLY
    //      while the field is at rest (R-SPIKE §7.1), and `GameSimulation.tap`
    //      remains the single authority on whether an orb was there. So the
    //      world path cannot subtract a pop the simulation would have resolved;
    //      it can only fail by never emitting `.pop` at all.
    //
    // What the baseline measures is therefore unchanged: RESOLUTION — given
    // where a thumb lands, does a pop happen. Both paths run over the same
    // fields, the same orbs and the same trial points in the same loop, and are
    // compared trial by trial, so the comparison is exact rather than
    // statistical; the 2% gate against the committed constant is then the
    // roadmap's own phrasing of the same fact.
    //
    // THE ONE NEW WAY THE WORLD PATH CAN LOSE A POP is the `isFieldAtRest`
    // gate, so this harness drives the REAL predicate against a REAL camera —
    // never a constant `true`, which would make the measurement vacuous. Its
    // off-rest half is measured separately, below.
    // ─────────────────────────────────────────────────────────────────────────

    // A prefix of TapBaselineTests' seed set. The committed baseline is the
    // population expectation and is seed-count independent, so a smaller sample
    // is a wider confidence interval, not a different target.
    private static let baselineSeeds: [UInt64] = (1...60).map { UInt64($0) }

    // The W20a trial grid, restated because it is private there. THE BASELINE
    // CONSTANT ITSELF IS NOT RESTATED — it is read from TapBaselineTests, which
    // is the entire point of having committed it.
    private static let offsetDistances: [CGFloat] = [4, 10, 16, 22, 28, 33, 38, 41]
    private static let offsetDirections: [CGVector] = [
        CGVector(dx: 1, dy: 0), CGVector(dx: -1, dy: 0),
        CGVector(dx: 0, dy: 1), CGVector(dx: 0, dy: -1),
    ]

    private func trialPoints(around o: Orb) -> [CGPoint] {
        var points = [o.pos]
        for d in Self.offsetDistances {
            for dir in Self.offsetDirections {
                points.append(CGPoint(x: o.pos.x + dir.dx * d, y: o.pos.y + dir.dy * d))
            }
        }
        return points
    }

    func testWorldPathTapSuccessStaysWithinTwoPercentOfTheW20aBaseline() {
        let camera = makeCamera()
        var arbiter = makeArbiter(reading: camera)

        var trials = 0
        var controlPops = 0     // the v1.2 path: straight into GameSimulation.tap
        var worldPops = 0       // the world path: arbiter → `.pop` → GameSimulation.tap
        var disagreements = 0
        var popOutcomes = 0
        var t: TimeInterval = 0

        for seed in Self.baselineSeeds {
            let sim = GameSimulation(seed: seed)
            sim.pinnedWeather = .clear
            sim.reduceMotion = true
            sim.layout(size: screen)
            let seeded = sim.orbs
            XCTAssertFalse(seeded.isEmpty, "seed \(seed) produced an empty field")

            for target in seeded {
                for point in trialPoints(around: target) {
                    // The v1.2 control, on this exact orb, on an isolated field.
                    sim.replaceOrbs([target])
                    let control = poppedCount(sim.tap(at: point)) > 0

                    // The world path, on the same orb, through the real arbiter
                    // and the real live `isFieldAtRest` closure.
                    sim.replaceOrbs([target])
                    var world = false
                    let down = arbiter.began(at: point, timestamp: t)
                    for outcome in down {
                        if case .pop(let p) = outcome {
                            popOutcomes += 1
                            world = poppedCount(sim.tap(at: p)) > 0
                        }
                    }
                    let up = arbiter.ended(at: point, timestamp: t + 0.05)
                    camera.consume(down)
                    camera.consume(up)
                    camera.step(dt: frame)
                    t += 0.12

                    trials += 1
                    if control { controlPops += 1 }
                    if world { worldPops += 1 }
                    if control != world { disagreements += 1 }
                }
            }
        }

        XCTAssertGreaterThan(trials, 10_000,
                             "the harness degenerated — too few trials to trust the rate")
        XCTAssertEqual(popOutcomes, trials,
                       "the input layer must emit exactly one `.pop` per touch-down on a resting "
                       + "field (ruling 4 / R-SPIKE §7.1)")
        XCTAssertTrue(camera.isAtRest, "the tap grid moved the camera")

        let worldRate = Double(worldPops) / Double(trials)
        let controlRate = Double(controlPops) / Double(trials)
        let baseline = TapBaselineTests.v12TapSuccessBaseline
        let drift = abs(worldRate - baseline) / baseline

        print("""
        [W20] tap success — world path \(worldRate) vs v1.2 control \(controlRate)
              committed W20a baseline  \(baseline)
              relative drift           \(drift * 100)%  (gate: 2%)
              \(worldPops)/\(trials) trials over \(Self.baselineSeeds.count) seeds, \
        \(disagreements) trial-by-trial disagreements
        """)

        // The exact half: the world path and the v1.2 path resolve the SAME
        // touches identically, orb by orb. This is what would catch a
        // regression of one trial in twenty thousand.
        XCTAssertEqual(disagreements, 0,
                       "the world path resolved \(disagreements) touches differently from the v1.2 "
                       + "path on identical fields — tap resolution has regressed")
        XCTAssertEqual(worldPops, controlPops)

        // The roadmap's half, phrased the way the roadmap phrases it.
        XCTAssertLessThanOrEqual(drift, 0.02,
                                 "world-path tap success \(worldRate) is \(drift * 100)% off the "
                                 + "committed W20a baseline \(baseline) — W20's gate is 2%")
    }

    // The one case where ruling 3 changes the ANSWER rather than the timing: a
    // swipe begun on an orb. v1.2 hit-tested where the finger LEFT; the world
    // hit-tests where it LANDED. This is the direction the change was made in,
    // and it is worth a test of its own so nobody "fixes" it back.
    func testASwipeBegunOnAnOrbPopsTheOrbItBeganOn() {
        let camera = makeCamera()
        var arbiter = makeArbiter(reading: camera)
        let sim = GameSimulation(seed: 7)
        sim.pinnedWeather = .clear
        sim.reduceMotion = true
        sim.layout(size: screen)

        var orb = Orb(pos: CGPoint(x: 195, y: 500), vel: .zero, r: 26, baseR: 26,
                      popNumber: PopCatalog.classic.number, variantIndex: 0, phase: 0)
        orb.spawn = 1
        sim.replaceOrbs([orb])

        var popped = 0
        var committed = false
        var t: TimeInterval = 0

        var batch = arbiter.began(at: orb.pos, timestamp: t)
        for outcome in batch {
            if case .pop(let p) = outcome { popped += poppedCount(sim.tap(at: p)) }
        }
        camera.consume(batch)

        for i in 1...8 {
            t += 0.015
            batch = arbiter.moved(to: CGPoint(x: orb.pos.x, y: orb.pos.y - 25 * CGFloat(i)),
                                  timestamp: t)
            camera.consume(batch)
            camera.step(dt: frame)
        }
        t += 0.015
        let release = arbiter.ended(at: CGPoint(x: orb.pos.x, y: orb.pos.y - 200), timestamp: t)
        for outcome in release { if case .commit = outcome { committed = true } }
        camera.consume(release)

        XCTAssertEqual(popped, 1, "the swipe must pop the orb it began on")
        XCTAssertTrue(committed, "the pop must not eat the swipe")
        XCTAssertEqual(camera.place, .sky, "an upward swipe goes to the sky")
    }

    // The deliberate suppression, stated so it is never mistaken for the
    // regression above: away from the resting field there is no field under her
    // finger, so there is no pop. Two cameras, because the second half must not
    // inherit a move the first half interrupted.
    func testTouchesAwayFromTheRestingFieldDoNotPopIt() {
        // Mid-settle, over the field.
        let moving = makeCamera()
        var movingArbiter = makeArbiter(reading: moving)
        moving.consume(.commit(.up, velocity: 900))
        moving.step(dt: frame)
        XCTAssertFalse(moving.isAtRest)
        var batch = movingArbiter.began(at: CGPoint(x: 195, y: 450), timestamp: 0)
        for outcome in batch {
            XCTAssertFalse(isPop(outcome), "a touch during a settle must not pop a field in flight")
        }
        moving.consume(batch)
        moving.consume(movingArbiter.ended(at: CGPoint(x: 195, y: 450), timestamp: 0.05))

        // At rest, at the sky.
        let parked = makeCamera()
        var parkedArbiter = makeArbiter(reading: parked)
        parked.consume(.commit(.up, velocity: 900))
        var settled = 0
        while !parked.isAtRest && settled < 10_000 { parked.step(dt: frame); settled += 1 }
        XCTAssertEqual(parked.place, .sky)
        batch = parkedArbiter.began(at: CGPoint(x: 195, y: 450), timestamp: 1)
        for outcome in batch {
            XCTAssertFalse(isPop(outcome), "a touch at the sky must not pop the field below it")
        }
        parked.consume(batch)
        parked.consume(parkedArbiter.ended(at: CGPoint(x: 195, y: 450), timestamp: 1.05))
    }

    // MARK: - W07 / ruling 9: simulation gating

    private func makeGatedGame() -> (GameViewModel, Date) {
        let vm = GameViewModel()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        vm.simActive = true
        vm.frame(date: t0, size: screen)                            // layout + seed; dt is 0
        vm.frame(date: t0.addingTimeInterval(frame), size: screen)  // one real step
        XCTAssertFalse(vm.sim.orbs.isEmpty, "the field never seeded")
        return (vm, t0.addingTimeInterval(frame))
    }

    // `phase` is the cleanest witness the simulation has to the `dt` it was
    // handed: it accumulates `wobbleSpeed * f` on every step and, unlike
    // position, it never bounces off a wall. Dividing the delta by `wobbleSpeed`
    // recovers the exact frame factor — which is the number under test, since
    // `lastFrameDate` itself is private.
    private func frameFactorConsumed(_ vm: GameViewModel, since phases: [CGFloat]) -> Double {
        guard let now = vm.sim.orbs.first?.phase, let was = phases.first else { return .nan }
        return Double((now - was) / GameConfig.wobbleSpeed)
    }

    func testAPausedWorldNeitherAdvancesTheSimulationNorReseedsTheField() {
        let (vm, t1) = makeGatedGame()
        let phases = vm.sim.orbs.map(\.phase)
        let positions = vm.sim.orbs.map(\.pos)
        let count = vm.sim.orbs.count

        vm.simActive = false
        var t = t1
        for _ in 0..<1_800 {                       // 30 s at 60 Hz, spent in the journal
            t = t.addingTimeInterval(1.0 / 60.0)
            vm.frame(date: t, size: screen)
        }
        // A rotation while she is away must not re-lay-out the field either:
        // the gate sits ABOVE `sim.layout`, deliberately.
        vm.frame(date: t.addingTimeInterval(1), size: CGSize(width: 834, height: 1194))

        XCTAssertEqual(vm.sim.orbs.count, count, "the paused field was reseeded")
        XCTAssertEqual(vm.sim.orbs.map(\.phase), phases, "the paused simulation advanced")
        XCTAssertEqual(vm.sim.orbs.map(\.pos), positions, "the paused simulation advanced")
        XCTAssertEqual(vm.sim.bounds, screen, "the paused simulation re-laid-out")
    }

    // The other half, and the reason the gate is not a bare `return`: coming
    // back must cost ONE ORDINARY FRAME, never one enormous clamped catch-up
    // step. `lastFrameDate` has to keep advancing while paused, and this
    // measures — through the frame factor the simulation actually received —
    // that it does.
    func testReturningFromAPausedWorldDoesNotDeliverOneEnormousStep() {
        // Case 1: the TimelineView kept ticking while she was at the sky, which
        // is what actually happens (the field is not quiescent, so the world is
        // not paused; only the simulation is).
        let (vm, t1) = makeGatedGame()
        vm.simActive = false
        var t = t1
        for _ in 0..<1_800 {
            t = t.addingTimeInterval(1.0 / 60.0)
            vm.frame(date: t, size: screen)
        }
        var phases = vm.sim.orbs.map(\.phase)
        vm.simActive = true
        t = t.addingTimeInterval(frame)
        vm.frame(date: t, size: screen)

        var f = frameFactorConsumed(vm, since: phases)
        print("[W20] resume after 30 s of paused frames: frame factor \(f) "
              + "(one 120 Hz frame is \(frame * 60))")
        XCTAssertEqual(f, frame * 60, accuracy: 1e-6,
                       "returning to the field cost more than the frame it actually was — "
                       + "`lastFrameDate` is not advancing while paused")
        XCTAssertLessThan(f, GameConfig.maxFrameDt * 60,
                          "the field lurched forward by a full clamped step on arrival")

        // Case 2: the harsher one — the world was backgrounded, so exactly one
        // paused frame arrives, 90 s later, before she returns.
        let (vm2, t2) = makeGatedGame()
        vm2.simActive = false
        let away = t2.addingTimeInterval(90)
        vm2.frame(date: away, size: screen)
        phases = vm2.sim.orbs.map(\.phase)
        vm2.simActive = true
        vm2.frame(date: away.addingTimeInterval(frame), size: screen)

        f = frameFactorConsumed(vm2, since: phases)
        print("[W20] resume after a single 90 s paused frame: frame factor \(f)")
        XCTAssertEqual(f, frame * 60, accuracy: 1e-6,
                       "a single long paused frame left a 90 s dt waiting for the simulation")
    }

    // MARK: - R-ARCH carry-forward, the parts testable without a device

    // BLOCKING ACCEPTANCE: "`WorldModel` publishes `place` and `worldMoving`,
    // and nothing else" — amended at W05c to "`place`, `worldMoving` and
    // `worldAwake`, and nothing else".
    //
    // THE AMENDMENT IS A SPLIT, NOT A RELAXATION. R-ARCH wrote the condition
    // when movement was the only per-frame state the camera had, so "keep the
    // frame clock running" and "the world is travelling" were one sentence.
    // The end-of-axis acknowledgement is per-frame camera state that runs
    // while the camera is AT REST, so the one flag became the two questions it
    // always was: `worldMoving` (mirrors `!camera.isAtRest`) gates
    // hit-testing, `worldAwake` (mirrors `!camera.isIdle`) gates the pause
    // predicate. Neither is derived from the other or from `place`, both are
    // written in the same touch handler, and both still change at most twice
    // per gesture. The thing the condition actually forbids — a per-frame
    // value on this object — is unchanged and still checked below.
    //
    // Checked STRUCTURALLY rather than by review, because the failure mode is
    // somebody adding one convenient `@Published var offset` — verbatim the
    // condition ruling 7 blames for cancelled taps, and one that no behavioural
    // test would notice until the device felt wrong in somebody's hands.
    func testWorldModelPublishesPlaceMovingAndAwakeAndNothingElse() {
        let model = WorldModel()
        var published: Set<String> = []
        for child in Mirror(reflecting: model).children {
            guard let label = child.label, label.hasPrefix("_") else { continue }
            guard String(describing: type(of: child.value)).hasPrefix("Published<") else { continue }
            published.insert(String(label.dropFirst()))
        }
        XCTAssertEqual(published, ["place", "worldMoving", "worldAwake"],
                       "WorldModel's published surface changed. Anything per-frame here rebuilds "
                       + "the TimelineView/Canvas/input subtree at frame rate, which is the "
                       + "condition ruling 7 names for cancelled taps.")
    }

    // The same condition from the side that actually costs pops: a drag
    // delivers `.panChanged` at digitizer rate, and the world must publish once
    // for the whole of it.
    func testADragDoesNotRepublishTheWorldAtDigitizerRate() {
        let model = WorldModel()
        model.camera.viewHeight = screenHeight
        var publishes = 0
        let token = model.objectWillChange.sink { _ in publishes += 1 }
        defer { token.cancel() }

        model.handle([.panBegan])
        for i in 1...240 {
            model.handle([.panChanged(translation: -CGFloat(i))])
            model.advance(at: Date(timeIntervalSinceReferenceDate: Double(i) * frame))
        }

        print("[W20] 240 `.panChanged` deliveries → \(publishes) SwiftUI publish(es)")
        XCTAssertLessThanOrEqual(publishes, 2,
                                 "the world republished \(publishes) times across one drag — "
                                 + "`worldMoving` or `place` is being written unguarded")
        XCTAssertGreaterThan(abs(model.camera.offset), 0, "the drag did not move the camera")
    }

    // BLOCKING ACCEPTANCE: the pause predicate is
    // `sim.isQuiescent && !model.worldAwake` (it was `!worldMoving` until
    // W05c split the flag), and it may never read the camera. The failure it
    // prevents is a world frozen mid-settle, so the invariant to pin is the
    // implication: whenever the camera is NOT at rest, `worldMoving` is true —
    // and `worldMoving` implies `worldAwake`, so the predicate can never pause
    // a moving world. The converse is allowed to lag by one main-queue hop,
    // and does. `WorldCameraTests` pins the other half — that `worldAwake`'s
    // source, `camera.isIdle`, stays false for the whole of an end-of-axis
    // acknowledgement while `isAtRest` stays true.
    func testWorldMovingIsTrueEveryFrameTheCameraIsNotAtRest() {
        let model = WorldModel()
        model.camera.viewHeight = screenHeight

        model.handle([.panBegan])
        model.handle([.panChanged(translation: -140)])
        model.handle([.commit(.up, velocity: 1100)])
        XCTAssertTrue(model.worldMoving, "`worldMoving` must be set in the handler that commits")

        var frames = 0
        var date = Date(timeIntervalSinceReferenceDate: 0)
        while !model.camera.isAtRest && frames < 10_000 {
            date = date.addingTimeInterval(frame)
            model.advance(at: date)
            frames += 1
            if !model.camera.isAtRest {
                XCTAssertTrue(model.worldMoving,
                              "frame \(frames): the camera is moving and the pause predicate would "
                              + "have paused the world")
            }
        }
        XCTAssertTrue(model.camera.isAtRest)
        XCTAssertGreaterThan(frames, 30, "the settle was too short to have measured anything")

        // The clear is deferred to the next main-queue hop on purpose (the
        // render pass may never publish), so it needs a turn of the run loop.
        let hop = expectation(description: "worldMoving cleared")
        DispatchQueue.main.async { hop.fulfill() }
        wait(for: [hop], timeout: 2)
        XCTAssertFalse(model.worldMoving, "`worldMoving` never cleared after the settle arrived")
        XCTAssertEqual(model.place, .sky, "`place` must mirror the camera")
    }

    // BLOCKING ACCEPTANCE: `simActive` and the input layer's `isFieldAtRest`
    // are ONE predicate — `camera.isAtRest && camera.place == .field` — so they
    // cannot drift apart. Checked at every frame of a real transit, including
    // the two points it is easiest to get wrong: the instant of the commit (the
    // field must stop THEN, not on arrival) and at rest away from the field.
    func testSimActiveIsTheOnePredicateAtEveryPointOfATransit() {
        let model = WorldModel()
        model.camera.viewHeight = screenHeight
        var date = Date(timeIntervalSinceReferenceDate: 0)

        model.advance(at: date)
        XCTAssertTrue(model.simActive, "at rest on the field the simulation must run")
        XCTAssertTrue(model.game.simActive)

        model.handle([.panBegan, .panChanged(translation: -160)])
        model.handle([.commit(.up, velocity: 1100)])
        date = date.addingTimeInterval(frame)
        model.advance(at: date)
        XCTAssertFalse(model.simActive,
                       "the field must stop the instant she has decided to leave it, so no chain "
                       + "resolves where she cannot see it (04 §5)")
        XCTAssertFalse(model.game.simActive)

        var frames = 0
        while !model.camera.isAtRest && frames < 10_000 {
            date = date.addingTimeInterval(frame)
            model.advance(at: date)
            frames += 1
            XCTAssertEqual(model.simActive, model.camera.isAtRest && model.camera.place == .field)
            XCTAssertEqual(model.game.simActive, model.simActive)
        }
        XCTAssertEqual(model.camera.place, .sky)
        XCTAssertFalse(model.simActive, "at rest at the sky the field must stay stopped")

        model.handle([.panBegan, .panChanged(translation: 160)])
        model.handle([.commit(.down, velocity: 1100)])
        frames = 0
        while !model.camera.isAtRest && frames < 10_000 {
            date = date.addingTimeInterval(frame)
            model.advance(at: date)
            frames += 1
        }
        XCTAssertEqual(model.camera.place, .field)
        XCTAssertTrue(model.simActive, "coming home must start the field again")
        XCTAssertTrue(model.game.simActive)
    }

    // BLOCKING ACCEPTANCE: exactly one owner calls `camera.step(dt:)`. The debug
    // trap for a SECOND owner cannot be exercised from a test without tripping
    // its own assertion, but the property it is documented beside can be, and it
    // is the one SwiftUI actually exercises: a view body evaluated twice for one
    // timeline tick must be free. The second call computes `dt == 0`, which
    // `WorldCamera.step` refuses outright.
    func testAdvancingTwiceForOneTimelineTickIsFree() {
        let model = WorldModel()
        model.camera.viewHeight = screenHeight
        model.handle([.commit(.down, velocity: 900)])

        var date = Date(timeIntervalSinceReferenceDate: 0)
        for _ in 0..<10 {
            date = date.addingTimeInterval(frame)
            model.advance(at: date)
        }
        XCTAssertFalse(model.camera.isAtRest, "the settle was over before the check could run")

        let offset = model.camera.offset
        model.advance(at: date)
        model.advance(at: date)
        XCTAssertEqual(model.camera.offset, offset,
                       "a repeated frame for the same date advanced the world")
    }

    // `place` is mirrored from the camera inside the touch handler and nowhere
    // else, so the published value and the camera's own must agree after every
    // outcome the world can produce, and at every frame in between.
    func testPublishedPlaceMirrorsTheCameraAfterEveryOutcome() {
        let model = WorldModel()
        model.camera.viewHeight = screenHeight
        var date = Date(timeIntervalSinceReferenceDate: 0)

        let script: [[InputOutcome]] = [
            [.pop(CGPoint(x: 100, y: 400))],
            [.panBegan, .panChanged(translation: -200)],
            [.commit(.up, velocity: 1200)],
            [.panBegan, .panChanged(translation: 300)],
            [.settleToNearest],
            [.panBegan, .panChanged(translation: 40)],
            [.cancelToRest],
            [.commit(.down, velocity: 800)],
            [.commit(.down, velocity: 800)],
        ]

        for batch in script {
            model.handle(batch)
            XCTAssertEqual(model.place, model.camera.place,
                           "published place drifted from the camera after \(batch)")
            for _ in 0..<20 {
                date = date.addingTimeInterval(frame)
                model.advance(at: date)
                XCTAssertEqual(model.place, model.camera.place,
                               "published place drifted from the camera mid-settle")
            }
        }
    }
}
