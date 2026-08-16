import XCTest
import CoreGraphics
@testable import Vesper

// Proof for the pure camera (DELIVERY_ROADMAP W01, gate R-ARCH). Every one of
// Amara Osei's vestibular barrier conditions from R-SPIKE (§7.10–14) is a
// named pass condition at R-ARCH, so every one of them is pinned here as a
// deterministic test rather than as a claim in a comment:
//
//   10  travel constant, peak optical-flow ceiling, one place per commit
//       → testSettlePeakOpticalFlowNeverExceedsTheCeiling
//       → testNoSingleCommitTravelsMoreThanOnePlace
//   11  Reduce Motion = zero translation, drag still gives feedback
//       → testReduceMotionProducesZeroTranslation*
//   12  monotone, non-overshooting settle at EVERY seeded velocity
//       → testSettleNeverOvershootsAcrossTheVelocitySweep
//   13  repeated spring-backs damp, and keep damping
//       → testRepeatedSpringBacksDampAndDoNotReset
//   14  a named speed threshold the light can take turns with
//       → testFlowMatchesTheAuditedPerFrameDelta, testExceedsTransitFlow*
//
// And the invariants the architecture rests on:
//
//   never moves unasked    → testStepWithoutInputNeverMoves
//   always interruptible   → testGrabMidSettleFreezesTheCameraExactly
//   resolves from position → testCommitAfterATransitDragResolvesFromPosition
//   one continuous fade    → testTransitionCrossesTheCommitSeam*
//
// No timing, no rendering, no randomness: `dt` is synthetic and fixed, exactly
// as GameSimulationTests drives the sim.
//
// `@MainActor` mirrors the camera's own isolation: it is written from UIKit
// touch callbacks and read from the SwiftUI render closure, both main, and
// saying so here keeps the test target building unchanged under Swift 6.
@MainActor
final class WorldCameraTests: XCTestCase {

    // The 390 × 844 pt reference screen the roadmap's arithmetic is quoted on.
    private let screenHeight: CGFloat = 844

    private let frame: TimeInterval = 1.0 / 120.0

    private func makeCamera(reduceMotion: Bool = false) -> WorldCamera {
        WorldCamera(viewHeight: screenHeight, reduceMotion: reduceMotion)
    }

    // MARK: - Helpers

    // One drag, in points. Negative is upward on screen (toward the sky) —
    // the same sign convention as WorldInput, deliberately not restated
    // anywhere else.
    private func drag(_ camera: WorldCamera, by points: CGFloat) {
        camera.consume(.panBegan)
        camera.consume(.panChanged(translation: points))
    }

    private struct SettleAudit {
        var duration: TimeInterval = 0
        var peakFlow: CGFloat = 0      // screen heights per second
        var reversed = false
        var overshot = false
        var finalOffset: CGFloat = 0
        var startOffset: CGFloat = 0
        var target: CGFloat = 0
        var distance: CGFloat { abs(target - startOffset) }
    }

    // Steps a camera to rest, auditing every frame for the three things a
    // vestibular review cares about: did it ever reverse, did it ever pass the
    // destination, and how fast did the world ever slide.
    @discardableResult
    private func runSettle(_ camera: WorldCamera, limit: Int = 10_000) -> SettleAudit {
        var audit = SettleAudit()
        audit.startOffset = camera.offset
        audit.target = camera.restOffset(of: camera.place)
        let toward: CGFloat = audit.target >= audit.startOffset ? 1 : -1
        var previous = camera.offset
        var steps = 0
        while !camera.isAtRest && steps < limit {
            camera.step(dt: frame)
            steps += 1
            let delta = camera.offset - previous
            if delta * toward < -1e-12 { audit.reversed = true }
            if (camera.offset - audit.target) * toward > 1e-12 { audit.overshot = true }
            audit.peakFlow = max(audit.peakFlow, abs(delta) / CGFloat(frame))
            previous = camera.offset
        }
        XCTAssertTrue(camera.isAtRest, "settle did not converge within \(limit) frames")
        audit.duration = TimeInterval(steps) * frame
        audit.finalOffset = camera.offset
        return audit
    }

    // The crossfade as a view would read it: how much of each place is on
    // screen. Every assertion about the transition is phrased in these terms
    // rather than in `t`, because `t` names the ARRIVING place and which place
    // is arriving legitimately changes when the camera passes a place centre.
    private func opacities(_ camera: WorldCamera) -> (sky: CGFloat, field: CGFloat, journal: CGFloat) {
        (camera.opacity(of: .sky), camera.opacity(of: .field), camera.opacity(of: .journal))
    }

    // MARK: - Rest and the no-move-unasked invariant

    func testStartsOnTheFieldCentred() {
        let camera = makeCamera()
        XCTAssertEqual(camera.place, .field)
        XCTAssertEqual(camera.offset, 0)
        XCTAssertTrue(camera.isAtRest)
        XCTAssertEqual(camera.opacity(of: .field), 1)
        XCTAssertEqual(camera.opacity(of: .sky), 0)
    }

    // INVARIANT A. The camera never moves unasked. Ten seconds of frames with
    // no input at all must leave the world exactly where she left it — this is
    // the test that would catch any future "idle drift", "attract loop", or
    // helpful auto-centring from ever reaching a person.
    func testStepWithoutInputNeverMoves() {
        let camera = makeCamera()
        for _ in 0..<1200 { camera.step(dt: frame) }
        XCTAssertEqual(camera.offset, 0)
        XCTAssertEqual(camera.dragProgress, 0)
        XCTAssertEqual(camera.flow, 0)
        XCTAssertEqual(camera.place, .field)
        XCTAssertTrue(camera.isAtRest)
    }

    // INVARIANT D. An unlaid-out camera has no screen height to normalize
    // against, so it refuses everything — including the commit, which must not
    // change `place` behind a stationary offset.
    func testUnlaidOutCameraNeverMoves() {
        let camera = WorldCamera(viewHeight: 0)
        drag(camera, by: -300)
        camera.consume(.commit(.up, velocity: -2000))
        for _ in 0..<240 { camera.step(dt: frame) }
        XCTAssertEqual(camera.offset, 0)
        XCTAssertEqual(camera.place, .field)
    }

    func testPopOutcomeMovesNothing() {
        let camera = makeCamera()
        camera.consume(.pop(CGPoint(x: 100, y: 400)))
        camera.step(dt: frame)
        XCTAssertEqual(camera.offset, 0)
        XCTAssertEqual(camera.place, .field)
    }

    // A `.panChanged` with no `.panBegan` is a malformed sequence, and a
    // malformed sequence moves nothing.
    func testPanChangedWithoutPanBeganMovesNothing() {
        let camera = makeCamera()
        camera.consume(.panChanged(translation: -300))
        XCTAssertEqual(camera.offset, 0)
    }

    // MARK: - Drag

    func testDragTracksTheFingerOneToOne() {
        let camera = makeCamera()
        drag(camera, by: -200)
        XCTAssertEqual(camera.offset, -200 / screenHeight, accuracy: 1e-12)
        // Cumulative, not accumulated: a second event at the same translation
        // must not move the camera twice.
        camera.consume(.panChanged(translation: -200))
        XCTAssertEqual(camera.offset, -200 / screenHeight, accuracy: 1e-12)
    }

    // The axis CLAMPS at both ends: nothing above the sky, nothing below the
    // journal, and no rubber-band (a rubber band is a rebound, and a rebound
    // is the direction reversal barrier condition 12 forbids).
    func testDragClampsAtBothEndsOfTheAxis() {
        let camera = makeCamera()
        let travel = camera.config.travelPerPlace
        drag(camera, by: -5000)
        XCTAssertEqual(camera.offset, -travel, accuracy: 1e-12)
        camera.consume(.panChanged(translation: 5000))
        XCTAssertEqual(camera.offset, travel, accuracy: 1e-12)
    }

    // A hesitant half-swipe is free: it costs exactly nothing, including
    // nothing in accumulated position error.
    func testDragThenCancelReturnsExactlyToTheOrigin() {
        let camera = makeCamera()
        drag(camera, by: -260)
        camera.consume(.cancelToRest)
        runSettle(camera)
        XCTAssertEqual(camera.offset, 0, "a spring-back must land exactly, not nearly")
        XCTAssertEqual(camera.place, .field)
    }

    // MARK: - Direction → destination (the one mapping)

    func testDirectionMapsToDestinationInExactlyOneTable() {
        let camera = makeCamera()
        XCTAssertEqual(camera.destination(from: .journal, moving: .up), .field)
        XCTAssertEqual(camera.destination(from: .field, moving: .up), .sky)
        XCTAssertEqual(camera.destination(from: .sky, moving: .down), .field)
        XCTAssertEqual(camera.destination(from: .field, moving: .down), .journal)
        // The ends. The axis clamps; it does not wrap.
        XCTAssertEqual(camera.destination(from: .sky, moving: .up), .sky)
        XCTAssertEqual(camera.destination(from: .journal, moving: .down), .journal)
    }

    func testCommitUpFromTheFieldArrivesInTheSky() {
        let camera = makeCamera()
        drag(camera, by: -120)
        camera.consume(.commit(.up, velocity: -1200))
        // `place` flips at commit, not on arrival: the sim must stop the
        // instant she has decided to leave (04 §5, W07).
        XCTAssertEqual(camera.place, .sky)
        let audit = runSettle(camera)
        XCTAssertEqual(camera.offset, -camera.config.travelPerPlace, accuracy: 1e-12)
        XCTAssertFalse(audit.overshot)
    }

    func testCommitUpFromTheSkyGoesNowhereBeyondIt() {
        let camera = makeCamera()
        drag(camera, by: -120)
        camera.consume(.commit(.up, velocity: -1200))
        runSettle(camera)

        drag(camera, by: -200)
        camera.consume(.commit(.up, velocity: -2400))
        XCTAssertEqual(camera.place, .sky, "there is nothing above the sky")
        runSettle(camera)
        XCTAssertEqual(camera.offset, -camera.config.travelPerPlace, accuracy: 1e-12)
    }

    func testCommitDownFromTheJournalGoesNowhereBeyondIt() {
        let camera = makeCamera()
        drag(camera, by: 120)
        camera.consume(.commit(.down, velocity: 1200))
        runSettle(camera)
        XCTAssertEqual(camera.place, .journal)

        drag(camera, by: 200)
        camera.consume(.commit(.down, velocity: 2400))
        XCTAssertEqual(camera.place, .journal, "there is nothing below the journal")
        runSettle(camera)
        XCTAssertEqual(camera.offset, camera.config.travelPerPlace, accuracy: 1e-12)
    }

    func testCommitThatHasAlreadyArrivedRestsImmediately() {
        let camera = makeCamera()
        // She dragged the whole way with her finger and then flicked.
        drag(camera, by: -camera.config.travelPerPlace * screenHeight)
        camera.consume(.commit(.up, velocity: -1800))
        XCTAssertTrue(camera.isAtRest, "nothing left to travel, so nothing to animate")
        XCTAssertEqual(camera.offset, -camera.config.travelPerPlace, accuracy: 1e-12)
    }

    // MARK: - Invariant E: a commit resolves from POSITION, not from intent

    // R-ARCH blocker 1, and the failure it prevents, which is a direction
    // reversal at the end of the largest flow event in the app.
    //
    // She is parked in the sky. She drags with her finger all the way down
    // past the field to the journal — a perfectly ordinary long swipe, well
    // inside what the arbiter emits — and flicks downward at the end. The
    // place of record is still `.sky`, because that is where the camera
    // BELONGS; the camera itself is a whole place below the field.
    //
    // Resolving the destination from `place` sent her back UP to the field,
    // against her finger, from below it. Resolving from `nearestPlace` sends
    // her where she is going.
    func testCommitAfterATransitDragResolvesFromPosition() {
        let camera = makeCamera()
        drag(camera, by: -200)
        camera.consume(.commit(.up, velocity: -1688))
        runSettle(camera)
        XCTAssertEqual(camera.place, .sky)

        drag(camera, by: 1200)                  // sky → past the field
        XCTAssertGreaterThan(camera.offset, 0, "the finger carried her below the field")
        XCTAssertEqual(camera.nearestPlace, .journal)
        XCTAssertEqual(camera.place, .sky, "…while the place of record is still the sky")

        let released = camera.offset
        camera.consume(.commit(.down, velocity: 1200))
        XCTAssertEqual(camera.place, .journal,
                       "a downward commit from below the field goes to the journal")

        let audit = runSettle(camera)
        XCTAssertGreaterThan(audit.target, released, "the settle must continue downward")
        XCTAssertFalse(audit.reversed, "resolving from `place` would have reversed her here")
        XCTAssertEqual(camera.offset, camera.config.travelPerPlace, accuracy: 1e-12)
    }

    // BARRIER CONDITION 10, the per-commit travel cap. Because destinations
    // resolve from position, the naive distance to a neighbouring place can
    // reach 1.5 places — more than one screen height of world on one flick.
    // The cap stops the commit at the place she is nearest instead.
    func testNoSingleCommitTravelsMoreThanOnePlace() {
        let camera = makeCamera()
        drag(camera, by: -200)
        camera.consume(.commit(.up, velocity: -1688))
        for _ in 0..<4 { camera.step(dt: frame) }

        // Caught early, between the field and the sky, and flicked back down.
        camera.consume(.panBegan)
        camera.consume(.panChanged(translation: 120))
        let released = camera.offset
        XCTAssertEqual(camera.nearestPlace, .field)
        let uncapped = abs(camera.restOffset(of: .journal) - released)
        XCTAssertGreaterThan(uncapped, camera.config.travelPerPlace,
                             "the uncapped answer really would have been over-long")

        camera.consume(.commit(.down, velocity: 1400))
        XCTAssertEqual(camera.place, .field, "one place per commit; the next flick continues")
        let audit = runSettle(camera)
        XCTAssertLessThanOrEqual(audit.distance,
                                 camera.config.maxTransitPerCommit * camera.config.travelPerPlace + 1e-9)
        XCTAssertEqual(camera.offset, 0, accuracy: 1e-12)
    }

    // MARK: - Barrier condition 12: the settle never overshoots

    // Every start position on the axis × both directions × a velocity sweep
    // that runs past the arbiter's own clamp, because the camera must be safe
    // even if the arbiter is one day wrong. A direction reversal at the end of
    // a large-field flow event is a substantial vestibular provocation, so
    // "did it ever move backwards" is asserted frame by frame, not just at the
    // end. The per-commit travel cap is asserted here too, on every settle in
    // the sweep.
    func testSettleNeverOvershootsAcrossTheVelocitySweep() {
        let starts: [CGFloat] = [-0.75, -0.4, -0.11, 0, 0.11, 0.4, 0.75]
        let velocities: [CGFloat] = [0, 300, 900, 1688, 2400, 6000]
        var settles = 0

        for start in starts {
            for direction in [WorldDirection.up, .down] {
                for speed in velocities {
                    let camera = makeCamera()
                    drag(camera, by: start * screenHeight)
                    let signed = direction == .up ? -speed : speed
                    camera.consume(.commit(direction, velocity: signed))
                    guard !camera.isAtRest else { continue }
                    let audit = runSettle(camera)
                    settles += 1
                    let label = "start \(start) \(direction) v\(speed)"
                    XCTAssertFalse(audit.reversed, "settle reversed direction — \(label)")
                    XCTAssertFalse(audit.overshot, "settle passed its destination — \(label)")
                    XCTAssertEqual(audit.finalOffset, audit.target, accuracy: 1e-12,
                                   "settle did not land exactly — \(label)")
                    XCTAssertLessThanOrEqual(audit.distance,
                                             camera.config.maxTransitPerCommit * camera.config.travelPerPlace + 1e-9,
                                             "one commit travelled more than one place — \(label)")
                }
            }
        }
        XCTAssertGreaterThan(settles, 50, "the sweep should actually be sweeping")
    }

    // The same guarantee for the two unseeded settles.
    func testUnseededSettlesNeverOvershoot() {
        for start in stride(from: CGFloat(-0.75), through: 0.75, by: 0.15) {
            for outcome in [InputOutcome.cancelToRest, .settleToNearest] {
                let camera = makeCamera()
                drag(camera, by: start * screenHeight)
                camera.consume(outcome)
                guard !camera.isAtRest else { continue }
                let audit = runSettle(camera)
                XCTAssertFalse(audit.reversed, "reversed from \(start) on \(outcome)")
                XCTAssertFalse(audit.overshot, "overshot from \(start) on \(outcome)")
                XCTAssertEqual(audit.finalOffset, audit.target, accuracy: 1e-12)
            }
        }
    }

    func testArrivalIsExactAndStaysPut() {
        let camera = makeCamera()
        drag(camera, by: -150)
        camera.consume(.commit(.up, velocity: -1500))
        runSettle(camera)
        let arrived = camera.offset
        for _ in 0..<600 { camera.step(dt: frame) }
        XCTAssertEqual(camera.offset, arrived, "an arrived camera keeps arriving at nothing")
        XCTAssertEqual(camera.dragProgress, 0, accuracy: 1e-12)
        XCTAssertEqual(camera.flow, 0, "and it is not still reporting motion")
    }

    // MARK: - Barrier condition 10: the optical-flow ceiling

    // The world may never slide faster than `maxOpticalFlow` screen heights
    // per second — on the 844 pt reference screen, 2.0 sh/s = 1688 pt/s — at
    // any instant of any SETTLE, at any seeded velocity, including seeds well
    // past the arbiter's clamp. (Finger-coupled motion is deliberately exempt
    // and documented as such on `Config.maxOpticalFlow`; this is the bound on
    // motion the camera generates on its own.)
    func testSettlePeakOpticalFlowNeverExceedsTheCeiling() {
        let camera0 = makeCamera()
        let ceiling = camera0.config.maxOpticalFlow
        var worst: CGFloat = 0

        for start in [CGFloat(-0.75), -0.4, 0, 0.4, 0.75] {
            for direction in [WorldDirection.up, .down] {
                for speed in [CGFloat(300), 1688, 2400, 6000, 20_000] {
                    let camera = makeCamera()
                    drag(camera, by: start * screenHeight)
                    camera.consume(.commit(direction, velocity: direction == .up ? -speed : speed))
                    guard !camera.isAtRest else { continue }
                    let audit = runSettle(camera)
                    worst = max(worst, audit.peakFlow)
                    XCTAssertLessThanOrEqual(audit.peakFlow, ceiling + 1e-9,
                                             "peak flow \(audit.peakFlow) sh/s from \(start) \(direction) v\(speed)")
                }
            }
        }
        XCTAssertGreaterThan(worst, ceiling * 0.9,
                             "the sweep never approached the ceiling, so it is not testing it")
    }

    // 04 §5 fixes the settle at 300–650 ms. The band is asserted only for
    // commits the arbiter can actually produce (past its ~11% distance gate,
    // within its velocity clamp) and that have somewhere left to travel —
    // beyond that range the optical-flow ceiling deliberately outranks the
    // band and the settle is allowed to be slower.
    func testReachableCommitSettlesStayInsideTheCommittedBand() {
        let camera0 = makeCamera()
        for start in [CGFloat(-0.7), -0.4, -0.11, 0.11, 0.4, 0.7] {
            for direction in [WorldDirection.up, .down] {
                let signed: CGFloat = direction == .up ? -1 : 1
                guard signed * start >= 0.11 else { continue }   // the distance gate
                for speed in [CGFloat(300), 900, 1688, 2400] {   // the arbiter's range
                    let camera = makeCamera()
                    drag(camera, by: start * screenHeight)
                    camera.consume(.commit(direction, velocity: signed * speed))
                    let audit = runSettle(camera)
                    // One frame of slack at each end: the duration here is
                    // counted in whole frames, not read off the state machine.
                    XCTAssertGreaterThanOrEqual(audit.duration, camera0.config.minSettleDuration - frame)
                    XCTAssertLessThanOrEqual(audit.duration, camera0.config.maxSettleDuration + frame)
                }
            }
        }
    }

    func testStalledFrameCannotTeleportTheWorld() {
        let camera = makeCamera()
        drag(camera, by: -150)
        camera.consume(.commit(.up, velocity: -1688))
        let before = camera.offset
        camera.step(dt: 5.0)   // a breakpoint, a resumed app, a dropped second
        XCTAssertFalse(camera.isAtRest, "a stall must not complete the move in one frame")
        let moved = abs(camera.offset - before)
        XCTAssertLessThan(moved, camera.config.maxOpticalFlow * CGFloat(camera.config.maxStep) + 1e-9)
    }

    // MARK: - Barrier condition 14: flow, and the named threshold

    // Flow is zero at rest, and during a settle it is exactly the per-frame
    // delta the vestibular audit measures — the same number, not a model of
    // it. The finger's own motion is accounted to the frame that carries it,
    // so the settle is measured after one clean frame has absorbed the drag.
    func testFlowMatchesTheAuditedPerFrameDelta() {
        let camera = makeCamera()
        for _ in 0..<5 { camera.step(dt: frame) }
        XCTAssertEqual(camera.flow, 0, "a camera at rest is not sliding")

        drag(camera, by: -150)
        camera.step(dt: frame)                 // this frame carries the finger
        camera.consume(.commit(.up, velocity: -1688))

        var previous = camera.offset
        var frames = 0
        var peak: CGFloat = 0
        while !camera.isAtRest && frames < 10_000 {
            camera.step(dt: frame)
            frames += 1
            let delta = abs(camera.offset - previous) / CGFloat(frame)
            XCTAssertEqual(camera.flow, delta, accuracy: 1e-12,
                           "flow disagreed with the audited delta on frame \(frames)")
            peak = max(peak, delta)
            previous = camera.offset
        }
        XCTAssertGreaterThan(peak, 1.5, "the settle should have been a real move")
        XCTAssertLessThanOrEqual(peak, camera.config.maxOpticalFlow + 1e-9)

        camera.step(dt: frame)
        XCTAssertEqual(camera.flow, 0, "and it stops reporting motion once it has stopped")
    }

    // Flow is valid during a drag too: her finger slid the world, and the
    // frame that delivered it says so. (This is the motion the ceiling
    // deliberately does not bound — see `Config.maxOpticalFlow`.)
    func testFlowAnswersTheFingerDuringADrag() {
        let camera = makeCamera()
        camera.step(dt: frame)
        drag(camera, by: -200)
        camera.step(dt: frame)
        XCTAssertEqual(camera.flow, (200 / screenHeight) / CGFloat(frame), accuracy: 1e-9)
        XCTAssertTrue(camera.exceedsTransitFlow)

        camera.step(dt: frame)   // finger still down, not moving
        XCTAssertEqual(camera.flow, 0, accuracy: 1e-12)
        XCTAssertFalse(camera.exceedsTransitFlow)
    }

    // The threshold is what W05 dims the light with, so it must be a single
    // clean transit: on for the body of the move, off once the world is
    // arriving, and never flickering in between.
    func testExceedsTransitFlowIsOneCleanTransitPerSettle() {
        let camera = makeCamera()
        XCTAssertFalse(camera.exceedsTransitFlow)
        drag(camera, by: -200)
        camera.step(dt: frame)
        camera.consume(.commit(.up, velocity: -1688))

        var states: [Bool] = []
        var frames = 0
        while !camera.isAtRest && frames < 10_000 {
            camera.step(dt: frame)
            frames += 1
            states.append(camera.exceedsTransitFlow)
        }
        XCTAssertTrue(states.first ?? false, "the light should take turns while she travels")
        XCTAssertFalse(states.last ?? true, "…and be back before she lands")
        var flips = 0
        for index in 1..<states.count where states[index] != states[index - 1] { flips += 1 }
        XCTAssertEqual(flips, 1, "the attenuation must not flicker")
    }

    // MARK: - Interruptibility

    // INVARIANT B. Every move is interruptible: a touch during any settle
    // catches the camera exactly where it is and holds it there.
    func testGrabMidSettleFreezesTheCameraExactly() {
        let camera = makeCamera()
        drag(camera, by: -150)
        camera.consume(.commit(.up, velocity: -1688))
        for _ in 0..<12 { camera.step(dt: frame) }

        camera.consume(.panBegan)
        let caught = camera.offset
        XCTAssertLessThan(caught, 0, "the grab should have caught it mid-flight, not before it left")
        XCTAssertGreaterThan(caught, -camera.config.travelPerPlace,
                             "…and not after it arrived")
        for _ in 0..<60 { camera.step(dt: frame) }
        XCTAssertEqual(camera.offset, caught, "a held camera must not creep")
        XCTAssertEqual(camera.place, .sky, "the grab does not undo her decision")
    }

    // R-SPIKE fix 3, the early half: she caught it just after release, so the
    // move springs home rather than completing.
    func testEarlyTransitGrabReleasedUndecidedSettlesHome() {
        let camera = makeCamera()
        drag(camera, by: -100)
        camera.consume(.commit(.up, velocity: -1400))
        for _ in 0..<6 { camera.step(dt: frame) }
        camera.consume(.panBegan)
        camera.consume(.settleToNearest)
        XCTAssertEqual(camera.place, .field)
        runSettle(camera)
        XCTAssertEqual(camera.offset, 0, accuracy: 1e-12)
    }

    // …and the late half: a near-complete move completes. Throwing it away
    // precisely when she reached out to steady it is the failure this case
    // exists to prevent.
    func testLateTransitGrabReleasedUndecidedCompletesTheMove() {
        let camera = makeCamera()
        drag(camera, by: -100)
        camera.consume(.commit(.up, velocity: -1400))
        for _ in 0..<48 { camera.step(dt: frame) }
        camera.consume(.panBegan)
        camera.consume(.settleToNearest)
        XCTAssertEqual(camera.place, .sky)
        runSettle(camera)
        XCTAssertEqual(camera.offset, -camera.config.travelPerPlace, accuracy: 1e-12)
    }

    // A tie must never be resolved into a move she did not ask for.
    func testSettleToNearestPrefersTheCurrentPlaceOnATie() {
        let camera = makeCamera()
        drag(camera, by: -camera.config.travelPerPlace / 2 * screenHeight)
        camera.consume(.settleToNearest)
        XCTAssertEqual(camera.place, .field)
        runSettle(camera)
        XCTAssertEqual(camera.offset, 0, accuracy: 1e-12)
    }

    // `.cancelToRest` mid-transit means the system took the touch away, not
    // that she changed her mind: the camera keeps the destination it was
    // already committed to.
    func testCancelDuringTransitReturnsToThePlaceOfRecord() {
        let camera = makeCamera()
        drag(camera, by: -120)
        camera.consume(.commit(.up, velocity: -1400))
        for _ in 0..<20 { camera.step(dt: frame) }
        camera.consume(.panBegan)
        camera.consume(.panChanged(translation: 60))
        camera.consume(.cancelToRest)
        runSettle(camera)
        XCTAssertEqual(camera.place, .sky)
        XCTAssertEqual(camera.offset, -camera.config.travelPerPlace, accuracy: 1e-12)
    }

    // MARK: - Barrier condition 11: Reduce Motion

    func testReduceMotionProducesZeroTranslationWhileDragging() {
        let camera = makeCamera(reduceMotion: true)
        drag(camera, by: -200)
        XCTAssertEqual(camera.offset, 0, "RM must translate nothing, ever")
        // …and the control must not feel dead: the crossfade still answers.
        let expected = (200 / screenHeight) / camera.config.travelPerPlace
        XCTAssertEqual(camera.opacity(of: .sky), expected, accuracy: 1e-12)
        XCTAssertEqual(camera.opacity(of: .field), 1 - expected, accuracy: 1e-12)
        XCTAssertEqual(camera.transition.from, .field)
        XCTAssertEqual(camera.transition.to, .sky)
    }

    func testReduceMotionCrossfadeIsProportionalAndClamped() {
        let camera = makeCamera(reduceMotion: true)
        drag(camera, by: -100)
        let half = camera.opacity(of: .sky)
        camera.consume(.panChanged(translation: -200))
        XCTAssertEqual(camera.opacity(of: .sky), half * 2, accuracy: 1e-12, "proportional to the finger")
        camera.consume(.panChanged(translation: -9000))
        XCTAssertEqual(camera.opacity(of: .sky), 1, accuracy: 1e-12, "clamped at one place-unit")
        XCTAssertEqual(camera.opacity(of: .field), 0, accuracy: 1e-12)
        camera.consume(.panChanged(translation: 9000))
        XCTAssertEqual(camera.opacity(of: .journal), 1, accuracy: 1e-12)
        XCTAssertEqual(camera.offset, 0)
    }

    // `dragProgress` is kept as the raw signed value, and it is NOT the
    // crossfade: it is measured from `place`, which flips at the commit. This
    // test pins what it is, so nobody mistakes it for what it is not.
    func testDragProgressIsTheRawSignedDistanceFromThePlaceOfRecord() {
        let camera = makeCamera(reduceMotion: true)
        drag(camera, by: -200)
        XCTAssertEqual(camera.dragProgress,
                       (-200 / screenHeight) / camera.config.travelPerPlace,
                       accuracy: 1e-12)
        camera.consume(.panChanged(translation: -9000))
        XCTAssertEqual(camera.dragProgress, -1, accuracy: 1e-12)
    }

    // Under RM the whole transition is a crossfade: zero translation at every
    // single frame, while the crossfade runs continuously to 1.
    func testReduceMotionProducesZeroTranslationAcrossAWholeCommit() {
        let camera = makeCamera(reduceMotion: true)
        camera.consume(.commit(.up, velocity: -2400))
        XCTAssertEqual(camera.place, .sky)
        XCTAssertEqual(camera.opacity(of: .field), 1, accuracy: 1e-12,
                       "a commit from rest starts one whole place away")

        var previous = opacities(camera)
        var frames = 0
        while !camera.isAtRest && frames < 10_000 {
            camera.step(dt: frame)
            frames += 1
            let now = opacities(camera)
            XCTAssertEqual(camera.offset, 0, "RM translated on frame \(frames)")
            XCTAssertGreaterThanOrEqual(now.sky, previous.sky - 1e-12,
                                        "the crossfade must not run backwards")
            XCTAssertLessThanOrEqual(now.field, previous.field + 1e-12)
            previous = now
        }
        XCTAssertEqual(camera.opacity(of: .sky), 1, accuracy: 1e-12)
        XCTAssertEqual(camera.opacity(of: .field), 0, accuracy: 1e-12)
    }

    // R-ARCH minor 10. Under RM nothing translates, so the optical-flow
    // ceiling has nothing to bound — and applying it anyway pushed the
    // crossfade past the committed 300–650 ms band, making the accessible
    // path the slow one.
    func testReduceMotionCommitStaysInsideTheCommittedBandWhileTheCeilingWouldNot() {
        let motion = makeCamera()
        motion.consume(.commit(.up, velocity: -2400))
        let motionDuration = runSettle(motion).duration
        XCTAssertGreaterThan(motionDuration, motion.config.maxSettleDuration + frame,
                             "with translation, the ceiling deliberately outranks the band")

        let reduced = makeCamera(reduceMotion: true)
        reduced.consume(.commit(.up, velocity: -2400))
        let reducedDuration = runSettle(reduced).duration
        XCTAssertGreaterThanOrEqual(reducedDuration, reduced.config.minSettleDuration - frame)
        XCTAssertLessThanOrEqual(reducedDuration, reduced.config.maxSettleDuration + frame)
    }

    // MARK: - The transition, across the seams

    // R-ARCH blockers 2 & 3, found independently by the chair and by Keiko.
    //
    // The crossfade used to ride on `dragProgress`, whose reference point
    // (`place`) MOVES at the commit instant — so the number inverted its
    // meaning mid-transition and no test crossed that seam. This one crosses
    // it: one continuous gesture, drag → commit → settle, sampled on every
    // event and every frame, asserting the two things a crossfade must be.
    func testTransitionCrossesTheCommitSeamContinuouslyAndMonotonically() {
        let camera = makeCamera(reduceMotion: true)
        camera.consume(.panBegan)

        var previous = opacities(camera)
        var largestStep: CGFloat = 0

        for step in 1...8 {
            camera.consume(.panChanged(translation: CGFloat(step) * -20))
            let now = opacities(camera)
            XCTAssertEqual(camera.transition.from, .field)
            XCTAssertEqual(camera.transition.to, .sky)
            XCTAssertGreaterThanOrEqual(now.sky, previous.sky - 1e-12)
            largestStep = max(largestStep, abs(now.sky - previous.sky))
            previous = now
        }

        // THE SEAM. `place` flips here and the camera does not move, so
        // nothing on screen may change at all.
        camera.consume(.commit(.up, velocity: -1400))
        let atSeam = opacities(camera)
        XCTAssertEqual(atSeam.sky, previous.sky, accuracy: 1e-12,
                       "the commit itself must be invisible to the crossfade")
        XCTAssertEqual(atSeam.field, previous.field, accuracy: 1e-12)
        XCTAssertEqual(camera.transition.from, .field, "…and the pair must not flip under it")
        XCTAssertEqual(camera.transition.to, .sky)
        previous = atSeam

        var frames = 0
        while !camera.isAtRest && frames < 10_000 {
            camera.step(dt: frame)
            frames += 1
            let now = opacities(camera)
            XCTAssertEqual(camera.offset, 0, "still RM: nothing may translate")
            XCTAssertGreaterThanOrEqual(now.sky, previous.sky - 1e-12,
                                        "the arriving place must never fade back out — frame \(frames)")
            XCTAssertLessThanOrEqual(now.field, previous.field + 1e-12)
            XCTAssertEqual(now.sky + now.field, 1, accuracy: 1e-12, "two places, one crossfade")
            XCTAssertEqual(now.journal, 0, "and the third is not in it")
            largestStep = max(largestStep, abs(now.sky - previous.sky))
            previous = now
        }

        XCTAssertEqual(camera.opacity(of: .sky), 1, accuracy: 1e-12)
        XCTAssertLessThan(largestStep, 0.05,
                          "a step this large is a cut, not a fade — the seam has reopened")
    }

    // The other seam: an undecided release springs back, so the pair reverses.
    // Per-place opacity must still be continuous through it, and must then run
    // monotonically the other way.
    func testTransitionCrossesTheSpringBackSeamContinuously() {
        let camera = makeCamera(reduceMotion: true)
        camera.consume(.panBegan)
        for step in 1...8 { camera.consume(.panChanged(translation: CGFloat(step) * -20)) }

        var previous = opacities(camera)
        XCTAssertGreaterThan(previous.sky, 0.2, "she is visibly on her way")

        camera.consume(.cancelToRest)
        let atSeam = opacities(camera)
        XCTAssertEqual(atSeam.sky, previous.sky, accuracy: 1e-12,
                       "the release itself must be invisible to the crossfade")
        XCTAssertEqual(camera.transition.to, .field, "…and the field is now the arriving place")
        previous = atSeam

        var frames = 0
        while !camera.isAtRest && frames < 10_000 {
            camera.step(dt: frame)
            frames += 1
            let now = opacities(camera)
            XCTAssertLessThanOrEqual(now.sky, previous.sky + 1e-12,
                                     "the sky must fade back out monotonically — frame \(frames)")
            previous = now
        }
        XCTAssertEqual(camera.opacity(of: .field), 1, accuracy: 1e-12)
        XCTAssertEqual(camera.opacity(of: .sky), 0, accuracy: 1e-12)
    }

    // Invariant B, in the crossfade: catching a moving camera must not be
    // visible either.
    func testGrabMidSettleDoesNotDisturbTheCrossfade() {
        let camera = makeCamera(reduceMotion: true)
        drag(camera, by: -120)
        camera.consume(.commit(.up, velocity: -1400))
        for _ in 0..<20 { camera.step(dt: frame) }

        let before = opacities(camera)
        camera.consume(.panBegan)
        let after = opacities(camera)
        XCTAssertEqual(after.sky, before.sky, accuracy: 1e-12)
        XCTAssertEqual(after.field, before.field, accuracy: 1e-12)

        let released = opacities(camera)
        camera.consume(.settleToNearest)
        XCTAssertEqual(opacities(camera).sky, released.sky, accuracy: 1e-12)
    }

    // A long gesture that crosses a place centre re-anchors the pair. The pair
    // changing is correct — she is between two different places now — and the
    // per-place opacities stay continuous through it.
    func testTransitionRepairsItselfWhenTheGestureCrossesAPlace() {
        let camera = makeCamera(reduceMotion: true)
        drag(camera, by: -2000)                     // pinned to the sky end
        camera.consume(.commit(.up, velocity: -1688))
        runSettle(camera)
        XCTAssertEqual(camera.opacity(of: .sky), 1, accuracy: 1e-12)

        camera.consume(.panBegan)
        var previous = opacities(camera)
        var largestStep: CGFloat = 0
        var sawTheJournalArrive = false
        for step in 1...130 {
            camera.consume(.panChanged(translation: CGFloat(step) * 10))
            let now = opacities(camera)
            largestStep = max(largestStep,
                              max(abs(now.sky - previous.sky),
                                  max(abs(now.field - previous.field), abs(now.journal - previous.journal))))
            XCTAssertEqual(now.sky + now.field + now.journal, 1, accuracy: 1e-12,
                           "the world is always exactly one screenful of places")
            if now.journal > 0 { sawTheJournalArrive = true }
            previous = now
        }
        XCTAssertTrue(sawTheJournalArrive, "she crossed the field and kept going")
        XCTAssertLessThan(largestStep, 0.05, "crossing a place must not cut")
    }

    // MARK: - Barrier condition 13: repeated spring-backs damp

    // FOUR identical rocking attempts as fast as she can make them. Each must
    // be BOTH shorter (smaller excursion) and slower (longer settle), and the
    // damping must not RESET — which is R-ARCH major 4: the window used to be
    // stamped at the START of each spring-back, and since each damped return
    // is deliberately made longer, the third return alone outlasted the 1 s
    // window and the fourth attempt sprang back to full, undamped travel. It
    // takes four attempts to see it, so this test makes four.
    func testRepeatedSpringBacksDampAndDoNotReset() {
        let camera = makeCamera()

        func rock() -> (excursion: CGFloat, duration: TimeInterval) {
            drag(camera, by: -260)
            let excursion = abs(camera.offset)
            camera.consume(.cancelToRest)
            let audit = runSettle(camera)
            return (excursion, audit.duration)
        }

        let first = rock()
        let second = rock()
        let third = rock()
        let fourth = rock()

        XCTAssertLessThan(second.excursion, first.excursion * 0.9, "the second attempt must travel less")
        XCTAssertGreaterThan(second.duration, first.duration * 1.2, "the second return must be slower")
        XCTAssertLessThan(third.excursion, second.excursion, "and it keeps damping")
        XCTAssertGreaterThan(third.duration, second.duration)

        // The one that used to fail.
        XCTAssertLessThanOrEqual(fourth.excursion, third.excursion,
                                 "damping reset on the fourth rapid attempt")
        XCTAssertGreaterThanOrEqual(fourth.duration, third.duration)
        XCTAssertLessThan(fourth.excursion, first.excursion * 0.5,
                          "a fourth rapid attempt must still be damped, not fresh")

        // Damping attenuates the camera, never the arbiter: the gates are
        // measured in finger points, so a damped drag still commits.
        camera.consume(.commit(.up, velocity: -1688))
        XCTAssertEqual(camera.place, .sky, "damping must never make navigation harder")
    }

    // …and it forgives. A pause longer than the window means she is not
    // rocking, she is just using the world again.
    func testSpringBackDampingRecoversAfterTheWindow() {
        let camera = makeCamera()

        drag(camera, by: -260)
        let firstExcursion = abs(camera.offset)
        camera.consume(.cancelToRest)
        let firstDuration = runSettle(camera).duration

        // Idle past the oscillation window, measured from ARRIVAL.
        for _ in 0..<Int(1.2 * 120) { camera.step(dt: frame) }

        drag(camera, by: -260)
        let secondExcursion = abs(camera.offset)
        camera.consume(.cancelToRest)
        let secondDuration = runSettle(camera).duration

        XCTAssertEqual(secondExcursion, firstExcursion, accuracy: 1e-12)
        XCTAssertEqual(secondDuration, firstDuration, accuracy: 1e-9)
    }

    // R-ARCH major 5. Only an UNDECIDED release back to the place the camera
    // already belonged to is a spring-back. A commit is a decision, and
    // decisions must never arm the damping — otherwise the world gets slower
    // and shorter the more confidently she uses it, which is the opposite of
    // what condition 13 is for.
    //
    // The case that matters most is the one fix 1 makes common: a transit grab
    // released with a decisive flick in the SAME direction, whose destination
    // therefore equals the place of record.
    func testConfidentNavigationNeverArmsTheDamping() {
        let camera = makeCamera()
        drag(camera, by: -200)
        camera.consume(.commit(.up, velocity: -1688))
        for _ in 0..<12 { camera.step(dt: frame) }

        camera.consume(.panBegan)
        camera.consume(.panChanged(translation: -40))
        XCTAssertEqual(camera.place, .sky)
        camera.consume(.commit(.up, velocity: -1688))   // destination == place, but decided
        XCTAssertEqual(camera.place, .sky)
        runSettle(camera)

        // A drag beginning immediately afterwards must be 1:1 with her finger.
        drag(camera, by: 200)
        XCTAssertEqual(camera.offset,
                       -camera.config.travelPerPlace + 200 / screenHeight,
                       accuracy: 1e-12,
                       "a decided move armed the anti-oscillation damping")
    }

    // MARK: - Config changes

    // R-ARCH minor 10. `config` is settable only through `apply(_:)`, which
    // re-clamps the axis and rebuilds the settle in flight — no jump in
    // position, no settle left aiming at an offset that no longer exists.
    func testApplyRebuildsTheSettleInFlightWithoutAJump() {
        let camera = makeCamera()
        drag(camera, by: -100)
        camera.consume(.commit(.up, velocity: -1400))
        for _ in 0..<20 { camera.step(dt: frame) }
        let caught = camera.offset

        var tighter = WorldCamera.Config.default
        tighter.travelPerPlace = 0.5
        camera.apply(tighter)

        XCTAssertEqual(camera.offset, caught, accuracy: 1e-12, "a tuning change must not teleport her")
        XCTAssertFalse(camera.isAtRest, "…nor abandon the move she is in")
        let audit = runSettle(camera)
        XCTAssertFalse(audit.reversed)
        XCTAssertFalse(audit.overshot)
        XCTAssertEqual(camera.offset, -0.5, accuracy: 1e-12, "it lands on the NEW rest offset")
    }

    func testApplyReclampsARestingCameraOntoTheNewAxis() {
        let camera = makeCamera()
        drag(camera, by: -200)
        camera.consume(.commit(.up, velocity: -1688))
        runSettle(camera)
        XCTAssertEqual(camera.offset, -0.75, accuracy: 1e-12)

        var tighter = WorldCamera.Config.default
        tighter.travelPerPlace = 0.5
        camera.apply(tighter)

        XCTAssertEqual(camera.offset, -0.5, accuracy: 1e-12, "the sky moved; she moved with it")
        XCTAssertTrue(camera.isAtRest)
        XCTAssertEqual(camera.place, .sky)
        XCTAssertEqual(camera.opacity(of: .sky), 1, accuracy: 1e-12)
    }

    // MARK: - Resolution independence

    // The axis is normalized, so a rotation, a Split View resize, or a
    // different device changes what a screen height is worth without moving
    // the camera through the world.
    func testOffsetIsResolutionIndependent() {
        let camera = makeCamera()
        drag(camera, by: -0.4 * screenHeight)
        camera.consume(.commit(.up, velocity: -1688))
        runSettle(camera)
        let normalized = camera.offset

        camera.viewHeight = 1366   // iPad, mid-session
        XCTAssertEqual(camera.offset, normalized, "the world position is not measured in points")
        XCTAssertEqual(camera.place, .sky)
    }
}
