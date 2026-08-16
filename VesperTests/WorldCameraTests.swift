import XCTest
import CoreGraphics
@testable import Vesper

// Proof for the pure camera (DELIVERY_ROADMAP W01, gate R-ARCH). Every one of
// Amara Osei's vestibular barrier conditions from R-SPIKE (§7.10–13) is a
// named pass condition at R-ARCH, so every one of them is pinned here as a
// deterministic test rather than as a claim in a comment:
//
//   10  travel constant + peak optical-flow ceiling
//       → testSettlePeakOpticalFlowNeverExceedsTheCeiling
//   11  Reduce Motion = zero translation, drag still gives feedback
//       → testReduceMotionProducesZeroTranslation*
//   12  monotone, non-overshooting settle at EVERY seeded velocity
//       → testSettleNeverOvershootsAcrossTheVelocitySweep
//   13  repeated spring-backs damp
//       → testRepeatedSpringBacksDamp
//
// And the two invariants the architecture rests on:
//
//   never moves unasked   → testStepWithoutInputNeverMoves
//   always interruptible  → testGrabMidSettleFreezesTheCameraExactly
//
// No timing, no rendering, no randomness: `dt` is synthetic and fixed, exactly
// as GameSimulationTests drives the sim.
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

    // MARK: - Rest and the no-move-unasked invariant

    func testStartsOnTheFieldCentred() {
        let camera = makeCamera()
        XCTAssertEqual(camera.place, .field)
        XCTAssertEqual(camera.offset, 0)
        XCTAssertTrue(camera.isAtRest)
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

    // MARK: - Barrier condition 12: the settle never overshoots

    // Every start position on the axis × both directions × a velocity sweep
    // that runs past the arbiter's own clamp, because the camera must be safe
    // even if the arbiter is one day wrong. A direction reversal at the end of
    // a large-field flow event is a substantial vestibular provocation, so
    // "did it ever move backwards" is asserted frame by frame, not just at the
    // end.
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
    }

    // MARK: - Barrier condition 10: the optical-flow ceiling

    // The world may never slide faster than `maxOpticalFlow` screen heights
    // per second — on the 844 pt reference screen, 2.0 sh/s = 1688 pt/s —
    // at any instant of any settle, at any seeded velocity, including seeds
    // well past the arbiter's clamp.
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
        // …and the control must not feel dead: the drag still answers.
        let expected = (-200 / screenHeight) / camera.config.travelPerPlace
        XCTAssertEqual(camera.dragProgress, expected, accuracy: 1e-12)
        XCTAssertNotEqual(camera.dragProgress, 0)
    }

    func testReduceMotionDragProgressIsProportionalAndClamped() {
        let camera = makeCamera(reduceMotion: true)
        drag(camera, by: -100)
        let half = camera.dragProgress
        camera.consume(.panChanged(translation: -200))
        XCTAssertEqual(camera.dragProgress, half * 2, accuracy: 1e-12, "proportional to the finger")
        camera.consume(.panChanged(translation: -9000))
        XCTAssertEqual(camera.dragProgress, -1, accuracy: 1e-12, "clamped at one place-unit")
        camera.consume(.panChanged(translation: 9000))
        XCTAssertEqual(camera.dragProgress, 1, accuracy: 1e-12)
        XCTAssertEqual(camera.offset, 0)
    }

    // Under RM the whole transition is a crossfade: zero translation at every
    // single frame, while `dragProgress` eases from ±1 to 0 so the view has
    // something continuous to fade with.
    func testReduceMotionProducesZeroTranslationAcrossAWholeCommit() {
        let camera = makeCamera(reduceMotion: true)
        camera.consume(.commit(.up, velocity: -2400))
        XCTAssertEqual(camera.place, .sky)
        XCTAssertEqual(camera.dragProgress, 1, accuracy: 1e-12,
                       "a commit from rest starts one whole place away")

        var previous = camera.dragProgress
        var frames = 0
        while !camera.isAtRest && frames < 10_000 {
            camera.step(dt: frame)
            frames += 1
            XCTAssertEqual(camera.offset, 0, "RM translated on frame \(frames)")
            XCTAssertLessThanOrEqual(camera.dragProgress, previous + 1e-12,
                                     "the crossfade must not run backwards")
            previous = camera.dragProgress
        }
        XCTAssertEqual(camera.dragProgress, 0, accuracy: 1e-12)
    }

    // MARK: - Barrier condition 13: repeated spring-backs damp

    // Two identical rocking attempts inside the oscillation window. The second
    // return must be BOTH shorter (smaller excursion) and slower (longer
    // settle), so a re-attempt cannot build a low-frequency vertical
    // oscillation out of her own repeated input.
    func testRepeatedSpringBacksDamp() {
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

        XCTAssertLessThan(second.excursion, first.excursion * 0.9, "the second attempt must travel less")
        XCTAssertGreaterThan(second.duration, first.duration * 1.2, "the second return must be slower")
        XCTAssertLessThan(third.excursion, second.excursion, "and it keeps damping")
        XCTAssertGreaterThan(third.duration, second.duration)
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

        // Idle past the oscillation window.
        for _ in 0..<Int(1.2 * 120) { camera.step(dt: frame) }

        drag(camera, by: -260)
        let secondExcursion = abs(camera.offset)
        camera.consume(.cancelToRest)
        let secondDuration = runSettle(camera).duration

        XCTAssertEqual(secondExcursion, firstExcursion, accuracy: 1e-12)
        XCTAssertEqual(secondDuration, firstDuration, accuracy: 1e-9)
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
