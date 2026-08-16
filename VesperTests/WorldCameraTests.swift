import XCTest
import CoreGraphics
@testable import Vesper

// Proof for the pure camera (DELIVERY_ROADMAP W01, gate R-ARCH). Every one of
// Amara Osei's vestibular barrier conditions from R-SPIKE (§7.10–14) is a
// named pass condition at R-ARCH, so every one of them is pinned here as a
// deterministic test rather than as a claim in a comment:
//
//   10  travel constant, peak optical-flow ceiling, a bounded commit
//       → testSettlePeakOpticalFlowNeverExceedsTheCeiling
//       → testTheCameraIsTheOnlyVelocityCeiling (W05a)
//       → testNoSingleCommitTravelsMoreThanTheStatedBound
//       → testGatedCommitTravelIsContinuousAcrossAPlaceCentre
//   11  Reduce Motion = zero translation, drag still gives feedback
//       → testReduceMotionProducesZeroTranslation*
//   12  monotone, non-overshooting settle at EVERY seeded velocity
//       → testSettleNeverOvershootsAcrossTheVelocitySweep
//   13  repeated spring-backs damp, keep damping, and a commit ends the
//       sequence
//       → testRepeatedSpringBacksDampAndDoNotReset
//       → testReturnThenCommitThenADragIsOneToOneWithHerFinger
//       → testDampingDoesNotCompoundAcrossAnInterveningCommit
//       → testLateTransitGrabReleasedUndecidedIsNotASpringBack
//       → testACommitCaughtAtOnceAndReleasedUndecidedIsASpringBack
//   14  a named speed threshold the light can take turns with, in BOTH
//       motion modes
//       → testFlowMatchesTheAuditedPerFrameDelta, testExceedsTransitFlow*
//       → testIsTransitioningAnswersInBothMotionModes
//
// And the invariants the architecture rests on:
//
//   never moves unasked    → testStepWithoutInputNeverMoves
//   always interruptible   → testGrabMidSettleFreezesTheCameraExactly
//   resolves from position → testCommitAfterATransitDragResolvesFromPosition
//   one continuous fade    → testTransitionCrossesTheCommitSeam*
//
// And W05c, the end-of-axis acknowledgement — a gated flick used to produce
// nothing visible at all, and the light that answers it may not cost anything
// the rest of this file proves:
//
//   the defect closed     → testAGatedFlickAtTheEndOfTheAxisIsAcknowledged
//   invariant G           → testTheAcknowledgementNeverLeavesTheCameraNotAtRest
//                         → testTheTapIsNeverSwallowedByAnAcknowledgement
//   the ends, and only    → testOnlyTheEndsOfTheAxisAcknowledge
//   exactly zero, always  → testTheAcknowledgementDecaysToExactlyZeroAndParks
//   frame-rate & stalls   → testTheAcknowledgementIsFrameRateIndependent
//   condition 11          → testTheAcknowledgementIsIdenticalUnderReduceMotion
//   condition 13's shape  → testRepeatedFlicksAtTheCeilingDampAndNeverPump
//                         → testACommitThatTravelsEndsTheAcknowledgementSequence
//   the two questions     → testIsIdleAndIsAtRestAreDifferentQuestions
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

    // BARRIER CONDITION 10, the per-commit travel BOUND. Because destinations
    // resolve from position, one commit can put up to 1.5 places of world on
    // screen: half a place of transit grab, plus the place she asked for. That
    // is the stated bound (`Config.maxTransitPerCommit`), and what makes it
    // safe is the ceiling on the RATE — the long transit takes longer, it does
    // not go faster.
    func testNoSingleCommitTravelsMoreThanTheStatedBound() {
        let camera = makeCamera()
        drag(camera, by: -200)
        camera.consume(.commit(.up, velocity: -1688))
        for _ in 0..<4 { camera.step(dt: frame) }

        // Caught early, between the field and the sky, and flicked back down.
        camera.consume(.panBegan)
        camera.consume(.panChanged(translation: 120))
        let released = camera.offset
        XCTAssertEqual(camera.nearestPlace, .field)
        XCTAssertGreaterThan(abs(camera.restOffset(of: .journal) - released),
                             camera.config.travelPerPlace,
                             "this really is a longer-than-one-place transit")

        camera.consume(.commit(.down, velocity: 1400))
        XCTAssertEqual(camera.place, .journal,
                       "she asked to go down from the field she is nearest, and she goes")
        let audit = runSettle(camera)
        XCTAssertLessThanOrEqual(audit.distance,
                                 camera.config.maxTransitPerCommit * camera.config.travelPerPlace + 1e-9)
        XCTAssertLessThanOrEqual(audit.peakFlow, camera.config.maxOpticalFlow + 1e-9,
                                 "the bound on distance is only safe because the rate is bounded")
        XCTAssertEqual(camera.offset, camera.config.travelPerPlace, accuracy: 1e-12)
    }

    // R-ARCH#2 blocker 2. The bound used to be a GATE measured from the live
    // axis position, so it flipped as the camera crossed a place centre: one
    // pixel above the field an upward flick travelled a whole place, one pixel
    // below it the same flick measured over the cap, fell back to the place she
    // was already standing on, and travelled almost nothing. A commit that has
    // passed every gate the arbiter has must always visibly move the world, and
    // which side of a centre the camera happened to stop on must not decide
    // anything.
    func testGatedCommitTravelIsContinuousAcrossAPlaceCentre() {
        let reference = makeCamera()
        let travel = reference.config.travelPerPlace
        let bound = reference.config.maxTransitPerCommit * travel
        var smallest = CGFloat.greatestFiniteMagnitude

        for tick in -30...30 {
            let start = CGFloat(tick) * 0.005          // ±0.15 either side of the field
            for direction in [WorldDirection.up, .down] {
                let camera = makeCamera()
                drag(camera, by: start * screenHeight)
                XCTAssertEqual(camera.nearestPlace, .field)

                let expected: Place = direction == .up ? .sky : .journal
                let velocity: CGFloat = direction == .up ? -1688 : 1688
                camera.consume(.commit(direction, velocity: velocity))
                XCTAssertEqual(camera.place, expected,
                               "the destination flipped at the place centre — start \(start)")

                let audit = runSettle(camera)
                smallest = min(smallest, audit.distance)
                XCTAssertGreaterThan(audit.distance, travel * 0.5,
                                     "a fully gated commit travelled almost nothing — start \(start) \(direction)")
                XCTAssertLessThanOrEqual(audit.distance, bound + 1e-9,
                                         "over the stated bound — start \(start) \(direction)")
            }
        }
        XCTAssertGreaterThan(smallest, travel * 0.5,
                             "the sweep should have crossed the centre without a collapse")
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
    // any instant of any SETTLE, at any seeded velocity. Since W05a the
    // arbiter no longer clamps release velocity, so the seeds well past
    // 2400 pt/s in this sweep are not hypothetical any more: 6000 pt/s is an
    // ordinary whip flick and the arbiter now reports it as measured.
    // (Finger-coupled motion is deliberately exempt and documented as such on
    // `Config.maxOpticalFlow`; this is the bound on motion the camera
    // generates on its own.)
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

    // W05a — THE UNIFICATION ITSELF, as a property rather than as a comment.
    //
    // There used to be two ceilings on one physical quantity: the arbiter
    // clamped release velocity to 2400 pt/s and this camera clamped seeded
    // speed to 2.0 screen heights per second. Two numbers in units that cannot
    // be compared without knowing the view height. The arbiter's is gone, so
    // this camera is now the sole authority, and "sole authority" means it
    // must be TOTAL over the seeds it can be handed — not merely correct over
    // the ones a well-behaved arbiter used to send.
    //
    // Four things are asserted, at every start position and both directions:
    //
    //   * every seed from a dead-stop release to ten times the ceiling
    //     produces a settle that is bounded, monotone, non-overshooting and
    //     lands exactly;
    //   * every seed AT OR ABOVE the ceiling produces the IDENTICAL
    //     trajectory, frame for frame. That is what makes the removal of the
    //     upstream clamp a no-op wherever it used to bite: 1688, 2400 and
    //     16880 pt/s are one behaviour, not three;
    //   * a non-finite seed is read as no seed at all, so nonsense arriving
    //     from an untrusted layer makes the world slower, never faster;
    //   * a zero seed still settles, calmly, and still lands.
    func testTheCameraIsTheOnlyVelocityCeiling() {
        let reference = makeCamera()
        // The ceiling expressed back in the arbiter's own units, on the
        // reference screen: 2.0 sh/s × 844 pt = 1688 pt/s.
        let ceilingInPoints = reference.config.maxOpticalFlow * screenHeight

        // Frame-by-frame offsets of a whole settle, so two seeds can be
        // compared as trajectories and not merely as endpoints.
        func trajectory(start: CGFloat, _ direction: WorldDirection, _ velocity: CGFloat) -> [CGFloat] {
            let camera = makeCamera()
            drag(camera, by: start * screenHeight)
            camera.consume(.commit(direction, velocity: direction == .up ? -velocity : velocity))
            var offsets: [CGFloat] = [camera.offset]
            var steps = 0
            while !camera.isAtRest && steps < 10_000 {
                camera.step(dt: frame)
                steps += 1
                offsets.append(camera.offset)
            }
            XCTAssertTrue(camera.isAtRest, "settle did not converge")
            return offsets
        }

        for start in [CGFloat(-0.75), -0.4, -0.11, 0, 0.11, 0.4, 0.75] {
            for direction in [WorldDirection.up, .down] {
                // 0 is a release with no flick behind it; the others bracket
                // the ceiling from below, at it, and ten times past it.
                for velocity in [CGFloat(0), 300, ceilingInPoints, 2400, ceilingInPoints * 10] {
                    let camera = makeCamera()
                    drag(camera, by: start * screenHeight)
                    camera.consume(.commit(direction, velocity: direction == .up ? -velocity : velocity))
                    guard !camera.isAtRest else { continue }
                    let audit = runSettle(camera)
                    let label = "start \(start) \(direction) v\(velocity)"
                    XCTAssertLessThanOrEqual(audit.peakFlow, reference.config.maxOpticalFlow + 1e-9,
                                             "peak flow \(audit.peakFlow) sh/s — \(label)")
                    XCTAssertFalse(audit.reversed, "settle reversed — \(label)")
                    XCTAssertFalse(audit.overshot, "settle overshot — \(label)")
                    XCTAssertEqual(audit.finalOffset, audit.target, accuracy: 1e-12,
                                   "settle did not land exactly — \(label)")
                }

                // Saturation. Above the ceiling the seed stops meaning
                // anything, which is precisely why the arbiter no longer needs
                // to pre-round it.
                let atCeiling = trajectory(start: start, direction, ceilingInPoints)
                for velocity in [ceilingInPoints, 2400, CGFloat(6000), ceilingInPoints * 10] {
                    let faster = trajectory(start: start, direction, velocity)
                    XCTAssertEqual(faster.count, atCeiling.count,
                                   "v\(velocity) took a different number of frames than the ceiling")
                    for (i, offset) in faster.enumerated() where i < atCeiling.count {
                        XCTAssertEqual(offset, atCeiling[i], accuracy: 1e-12,
                                       "v\(velocity) diverged from the ceiling on frame \(i)")
                    }
                }
            }
        }

        // A seed that is not a number is not a request for speed. It settles
        // as an unseeded release does — the long, calm end of the band — and
        // it emphatically does not produce a duration the ease would read as
        // "already complete", i.e. a teleport.
        for nonsense in [CGFloat.infinity, .nan] {
            let camera = makeCamera()
            drag(camera, by: -0.4 * screenHeight)
            camera.consume(.commit(.up, velocity: -nonsense))
            XCTAssertFalse(camera.isAtRest, "a nonsense seed must not complete the settle instantly")
            let audit = runSettle(camera)
            XCTAssertLessThanOrEqual(audit.peakFlow, reference.config.maxOpticalFlow + 1e-9)
            XCTAssertFalse(audit.overshot)
            XCTAssertFalse(audit.reversed)
            XCTAssertEqual(audit.finalOffset, audit.target, accuracy: 1e-12)

            let unseeded = makeCamera()
            drag(unseeded, by: -0.4 * screenHeight)
            unseeded.consume(.commit(.up, velocity: 0))
            let calm = runSettle(unseeded)
            XCTAssertEqual(audit.duration, calm.duration, accuracy: 1e-12,
                           "a non-finite seed must settle exactly as an unseeded release does")
        }
    }

    // 04 §5 fixes the settle at 300–650 ms. The band is asserted only for
    // commits the arbiter can actually produce (past its ~11% distance gate)
    // and that have somewhere left to travel — beyond that range the
    // optical-flow ceiling deliberately outranks the band and the settle is
    // allowed to be slower.
    //
    // The velocity list runs past 2400 since W05a: the arbiter no longer
    // clamps, so "what the arbiter can produce" is now whatever a hand can do.
    // It changes nothing, and that is the point — every seed at or above the
    // ceiling settles identically (testTheCameraIsTheOnlyVelocityCeiling), so
    // the band the navigation is committed to did not move when the upstream
    // clamp was deleted.
    func testReachableCommitSettlesStayInsideTheCommittedBand() {
        let camera0 = makeCamera()
        for start in [CGFloat(-0.7), -0.4, -0.11, 0.11, 0.4, 0.7] {
            for direction in [WorldDirection.up, .down] {
                let signed: CGFloat = direction == .up ? -1 : 1
                guard signed * start >= 0.11 else { continue }   // the distance gate
                for speed in [CGFloat(300), 900, 1688, 2400, 6000] {
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

    // R-ARCH#2 minor 6. Condition 14 must have an answer in BOTH motion modes.
    // Under Reduce Motion nothing translates, so `flow` is identically zero and
    // `exceedsTransitFlow` can never be true — yet two whole places are
    // crossfading through each other, and the light should take its turn there
    // exactly as it does during a translating transit. `isTransitioning` is the
    // one question W05 and the renderer ask.
    func testIsTransitioningAnswersInBothMotionModes() {
        for reduced in [false, true] {
            let camera = makeCamera(reduceMotion: reduced)
            XCTAssertFalse(camera.isTransitioning, "RM \(reduced): a resting camera is not in transit")

            drag(camera, by: -200)
            camera.step(dt: frame)
            camera.consume(.commit(.up, velocity: -1688))

            var states: [Bool] = []
            var frames = 0
            while !camera.isAtRest && frames < 10_000 {
                camera.step(dt: frame)
                frames += 1
                states.append(camera.isTransitioning)
            }
            XCTAssertTrue(states.first ?? false,
                          "RM \(reduced): the light should take turns while she travels")
            XCTAssertFalse(states.last ?? true,
                           "RM \(reduced): …and be back before she lands")
            var flips = 0
            for index in 1..<states.count where states[index] != states[index - 1] { flips += 1 }
            XCTAssertEqual(flips, 1, "RM \(reduced): the attenuation must not flicker")
            XCTAssertFalse(camera.isTransitioning,
                           "RM \(reduced): an arrived camera is not in transit")
        }
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

    // R-ARCH#2 major 5. A settle can begin MORE THAN ONE PLACE from its
    // destination: parked in the sky, her finger carries the camera all the way
    // down to the journal, and then the system takes the touch away — so the
    // camera returns to the sky from two places below it.
    //
    // The pair used to be anchored to a NEIGHBOUR OF THE DESTINATION, which is
    // the right place only while the camera is less than one place away. From
    // the journal it named the journal as the ARRIVING place for the whole
    // first half of the move: the crossfade brightened the place she was
    // leaving, then re-resolved at the field centre. Anchoring to the bracket
    // the camera is actually in — the same re-anchoring `.panBegan` does —
    // makes `to` the arriving place throughout.
    func testTransitionNamesTheArrivingPlaceFromMoreThanOnePlaceAway() {
        let camera = makeCamera(reduceMotion: true)
        drag(camera, by: -5000)
        camera.consume(.commit(.up, velocity: -2400))
        runSettle(camera)
        XCTAssertEqual(camera.place, .sky)

        camera.consume(.panBegan)
        camera.consume(.panChanged(translation: 5000))    // all the way to the journal
        camera.consume(.cancelToRest)                     // …and the touch is taken away
        XCTAssertEqual(camera.place, .sky, "the camera returns to the place it belongs to")

        var previousSky = camera.opacity(of: .sky)
        var largestStep: CGFloat = 0
        var frames = 0
        while !camera.isAtRest && frames < 10_000 {
            camera.step(dt: frame)
            frames += 1
            XCTAssertNotEqual(camera.transition.to, .journal,
                              "the pair named the place she is leaving as the arriving one — frame \(frames)")
            let sky = camera.opacity(of: .sky)
            XCTAssertGreaterThanOrEqual(sky, previousSky - 1e-12,
                                        "the sky must arrive monotonically — frame \(frames)")
            largestStep = max(largestStep, abs(sky - previousSky))
            previousSky = sky
        }
        XCTAssertEqual(camera.opacity(of: .sky), 1, accuracy: 1e-12)
        XCTAssertEqual(camera.opacity(of: .journal), 0, accuracy: 1e-12)
        XCTAssertLessThan(largestStep, 0.05, "crossing two places must not cut")
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

    // R-ARCH#2 blocker 1, and the Director's ruling: A COMMIT ENDS A ROCKING
    // SEQUENCE. The damping's two halves used to be cleared only by a
    // genuinely idle `oscillationWindow`, so a hesitant half-swipe that sprang
    // back — which legitimately arms it — poisoned the drag AFTER the next
    // completed move. She swipes, changes her mind, then goes somewhere on
    // purpose, and the world no longer follows her thumb, for no reason she
    // can see or undo.
    func testReturnThenCommitThenADragIsOneToOneWithHerFinger() {
        let camera = makeCamera()

        drag(camera, by: -260)
        camera.consume(.cancelToRest)
        runSettle(camera)                                // a real spring-back

        camera.consume(.commit(.up, velocity: -1688))    // …and then she decides
        runSettle(camera)
        XCTAssertEqual(camera.place, .sky)

        drag(camera, by: 200)
        XCTAssertEqual(camera.offset,
                       -camera.config.travelPerPlace + 200 / screenHeight,
                       accuracy: 1e-12,
                       "damping leaked across a completed commit")
    }

    // …and it does not merely fail to arm: an intervening decisive commit
    // RESETS the gain, so a rock after it starts from 1:1 again rather than
    // resuming a decayed sequence she has already left.
    func testDampingDoesNotCompoundAcrossAnInterveningCommit() {
        let camera = makeCamera()

        func rock() -> CGFloat {
            let home = camera.restOffset(of: camera.place)
            drag(camera, by: -260)
            let excursion = abs(camera.offset - home)
            camera.consume(.cancelToRest)
            runSettle(camera)
            return excursion
        }

        let first = rock()
        let second = rock()
        XCTAssertLessThan(second, first * 0.9, "two rapid returns must damp")

        camera.consume(.commit(.up, velocity: -1688))
        runSettle(camera)
        XCTAssertEqual(camera.place, .sky)

        drag(camera, by: 260)
        let afterTheCommit = abs(camera.offset - camera.restOffset(of: .sky))
        XCTAssertEqual(afterTheCommit, 260 / screenHeight, accuracy: 1e-12,
                       "the gain compounded across a decisive commit instead of being reset by it")
        XCTAssertEqual(afterTheCommit, first, accuracy: 1e-12,
                       "…and it is exactly the undamped excursion, not merely a larger one")
    }

    // R-ARCH#2 major 4, THE FALSE POSITIVE. A late transit grab released
    // undecided COMPLETES the move — the world ends a whole place from where
    // her finger landed. Nothing sprang back, so nothing may damp. Classifying
    // by comparing the destination with the place of record called this a
    // return (they are equal here) and slowed her next drag for finishing a
    // move.
    func testLateTransitGrabReleasedUndecidedIsNotASpringBack() {
        let camera = makeCamera()
        drag(camera, by: -100)
        camera.consume(.commit(.up, velocity: -1400))
        for _ in 0..<48 { camera.step(dt: frame) }

        camera.consume(.panBegan)
        XCTAssertGreaterThan(camera.offset, -camera.config.travelPerPlace,
                             "the grab should have caught it before it landed")
        camera.consume(.settleToNearest)
        XCTAssertEqual(camera.place, .sky, "a late catch completes the move")
        runSettle(camera)

        drag(camera, by: 200)
        XCTAssertEqual(camera.offset,
                       -camera.config.travelPerPlace + 200 / screenHeight,
                       accuracy: 1e-12,
                       "completing a move armed the anti-oscillation damping")
    }

    // …and THE FALSE NEGATIVE, which is the one that lets a real oscillation
    // through. She flicks up, catches it at once, and lets go without asking
    // for anything: the world goes back to exactly where her finger landed.
    // That is a spring-back, and repeating it is the low-frequency rocking
    // condition 13 exists to decay — but its destination (`.field`) differs
    // from the place of record (`.sky`), so the old classifier called it a
    // fresh move and damped nothing at all.
    func testACommitCaughtAtOnceAndReleasedUndecidedIsASpringBack() {
        let camera = makeCamera()
        camera.consume(.commit(.up, velocity: -2400))
        XCTAssertEqual(camera.place, .sky)

        camera.consume(.panBegan)                        // caught before a frame ran
        camera.consume(.panChanged(translation: -40))
        camera.consume(.settleToNearest)
        XCTAssertEqual(camera.place, .field, "the world is going back where it started")
        runSettle(camera)
        XCTAssertEqual(camera.offset, 0, accuracy: 1e-12)

        drag(camera, by: -260)
        XCTAssertEqual(abs(camera.offset),
                       (260 / screenHeight) * camera.config.dragDampingFactor,
                       accuracy: 1e-12,
                       "a real spring-back did not arm the damping")
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

    // R-ARCH#2 minor 7. `offset` steps by the entire axis position the instant
    // Reduce Motion is written, and `flow` is measured against the previous
    // frame's `offset` — so without re-seeding that reference the next frame
    // reports a phantom transit of tens of screen heights per second over a
    // world that did not move, and every consumer of condition 14 dims for a
    // frame because the host flipped a setting.
    func testTogglingReduceMotionDoesNotReportAPhantomTransit() {
        let camera = makeCamera()
        drag(camera, by: -200)
        camera.step(dt: frame)
        XCTAssertTrue(camera.exceedsTransitFlow, "her finger really did move the world")

        camera.reduceMotion = true
        camera.step(dt: frame)
        XCTAssertEqual(camera.flow, 0, accuracy: 1e-12,
                       "the world did not slide; the translation stopped existing")
        XCTAssertFalse(camera.exceedsTransitFlow)

        camera.reduceMotion = false
        camera.step(dt: frame)
        XCTAssertEqual(camera.flow, 0, accuracy: 1e-12, "…and the same on the way back")
    }

    // The same one-frame discontinuity on the other host write: `apply(_:)`
    // re-clamps the axis, which can move `offset` a fifth of a screen without
    // a frame passing. A tuning change is not a transit.
    func testApplyDoesNotReportAPhantomTransit() {
        let camera = makeCamera()
        drag(camera, by: -600)
        camera.step(dt: frame)

        var tighter = WorldCamera.Config.default
        tighter.travelPerPlace = 0.5
        camera.apply(tighter)
        camera.step(dt: frame)
        XCTAssertEqual(camera.flow, 0, accuracy: 1e-12,
                       "a tuning change must not dim the light")
    }

    // `dragProgress` is guarded exactly as `transition` is: a degenerate world
    // answers calmly instead of handing out an infinity or a NaN.
    func testDragProgressIsFiniteInADegenerateWorld() {
        let camera = makeCamera()
        var degenerate = WorldCamera.Config.default
        degenerate.travelPerPlace = 0
        camera.apply(degenerate)
        XCTAssertEqual(camera.dragProgress, 0)
        XCTAssertEqual(camera.opacity(of: .field), 1)
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

    // MARK: - W05c: the end of the axis, answered

    // A trace of the acknowledgement, sampled on every frame from the one it
    // is armed on to the one it goes out on. Everything a gated flick is
    // allowed to touch is sampled beside it, because the whole risk of this
    // feature is that it touches something.
    private struct AckTrace {
        var level: [CGFloat] = []
        var atRest: [Bool] = []
        var idle: [Bool] = []
        var offset: [CGFloat] = []
        var flow: [CGFloat] = []
        var transiting: [Bool] = []
        var frames = 0

        var peak: CGFloat { level.max() ?? 0 }
        var worstStep: CGFloat {
            guard level.count > 1 else { return 0 }
            var worst: CGFloat = 0
            for i in 1..<level.count { worst = max(worst, abs(level[i] - level[i - 1])) }
            return worst
        }
    }

    // Steps until the camera has nothing left to step — `isIdle`, not
    // `isAtRest`, which is the distinction this whole section exists to make.
    private func traceAcknowledgement(_ camera: WorldCamera,
                                      dt: TimeInterval? = nil,
                                      limit: Int = 10_000) -> AckTrace {
        let step = dt ?? frame
        var trace = AckTrace()
        func sample() {
            trace.level.append(camera.acknowledgementLevel)
            trace.atRest.append(camera.isAtRest)
            trace.idle.append(camera.isIdle)
            trace.offset.append(camera.offset)
            trace.flow.append(camera.flow)
            trace.transiting.append(camera.isTransitioning)
        }
        sample()
        while !camera.isIdle && trace.frames < limit {
            camera.step(dt: step)
            trace.frames += 1
            sample()
        }
        XCTAssertTrue(camera.isIdle, "the acknowledgement did not finish within \(limit) frames")
        return trace
    }

    // Parks the camera at rest in `place`, with nothing left burning.
    private func park(_ camera: WorldCamera, at place: Place) {
        guard place != camera.place else { return }
        camera.consume(.commit(place.rawValue < camera.place.rawValue ? .up : .down, velocity: 0))
        runSettle(camera)
        while !camera.isIdle { camera.step(dt: frame) }
        XCTAssertEqual(camera.place, place)
    }

    // THE DEFECT, CLOSED. She is at the sky and flicks upward. The gesture
    // passes both of the arbiter's commit gates and arrives here as a real
    // `.commit`; the axis clamps, so the destination is the place she is
    // already standing in and the camera does not move a pixel. Before W05c
    // that was the whole of it — she asked and the world did not answer, which
    // is the same class of defect as a swallowed tap.
    func testAGatedFlickAtTheEndOfTheAxisIsAcknowledged() {
        for (place, direction) in [(Place.sky, WorldDirection.up), (.journal, .down)] {
            let camera = makeCamera()
            park(camera, at: place)
            XCTAssertNil(camera.edgeAcknowledgement, "nothing should be lit before she asks")

            let before = camera.offset
            camera.consume(.commit(direction, velocity: 2400))

            XCTAssertFalse(camera.isIdle,
                           "\(place): the world must wake up to run the envelope, or the pause "
                           + "predicate leaves it frozen at zero")
            camera.step(dt: frame)
            let answer = camera.edgeAcknowledgement
            XCTAssertNotNil(answer, "\(place): the world did not answer a gated flick")
            XCTAssertEqual(answer?.edge, direction,
                           "\(place): the light must be at the edge she tried to travel toward")
            XCTAssertGreaterThan(answer?.level ?? 0, 0)
            XCTAssertEqual(camera.offset, before, "the acknowledgement is light, not movement")
            XCTAssertEqual(camera.place, place, "she is still where she was")
        }
    }

    // INVARIANT G, and the single most important test in this section. The
    // acknowledgement writes no position and no place, so `isAtRest` is
    // bit-identical to what it would have been — which is what keeps
    // `WorldModel.simActive` right, which is what keeps a touch-down on the
    // field a pop. A light that could swallow a tap would be a far worse
    // defect than the silence it replaced.
    func testTheAcknowledgementNeverLeavesTheCameraNotAtRest() {
        for reduced in [false, true] {
            let camera = makeCamera(reduceMotion: reduced)
            park(camera, at: .sky)
            camera.consume(.commit(.up, velocity: 6000))

            XCTAssertTrue(camera.isAtRest,
                          "RM \(reduced): the camera reported motion for a world that is standing "
                          + "still — this is the frame that costs her the next tap")
            let trace = traceAcknowledgement(camera)

            XCTAssertGreaterThan(trace.frames, 30, "the envelope was too short to prove anything")
            for (i, rest) in trace.atRest.enumerated() {
                XCTAssertTrue(rest, "RM \(reduced): frame \(i) claimed the world was moving")
            }
            for value in trace.offset {
                XCTAssertEqual(value, trace.offset[0], "RM \(reduced): the world translated")
            }
            for value in trace.flow {
                XCTAssertEqual(value, 0, "RM \(reduced): the acknowledgement produced optical flow")
            }
            for value in trace.transiting {
                XCTAssertFalse(value, "RM \(reduced): a still world claimed to be in transit, so "
                               + "condition 14 would have dimmed it")
            }
        }
    }

    // The same property said the way it is actually spent: `simActive` is
    // `isAtRest && place == .field`, so the question is whether the field is
    // live on the frame she lands, WITH a glow still burning.
    //
    // The geometry is deliberately tightened so the journey home is shorter
    // than the envelope — at the shipped tuning the light always goes out
    // first, and a test that passes by timing coincidence proves nothing.
    func testTheTapIsNeverSwallowedByAnAcknowledgement() {
        for reduced in [false, true] {
            let camera = makeCamera(reduceMotion: reduced)
            var tight = WorldCamera.Config.default
            tight.travelPerPlace = 0.10
            camera.apply(tight)

            park(camera, at: .sky)
            camera.consume(.commit(.up, velocity: 2400))
            for _ in 0..<22 { camera.step(dt: frame) }
            XCTAssertEqual(camera.acknowledgementLevel, 1, accuracy: 1e-12,
                           "RM \(reduced): the glow should be at its peak here")

            camera.consume(.commit(.down, velocity: 2400))
            runSettle(camera)

            XCTAssertGreaterThan(camera.acknowledgementLevel, 0,
                                 "RM \(reduced): the glow finished before the landing — this test "
                                 + "would then prove nothing")
            XCTAssertTrue(camera.isAtRest && camera.place == .field,
                          "RM \(reduced): THE TAP WAS SWALLOWED — `simActive` is false on the "
                          + "frame the camera landed at the field")
            while !camera.isIdle {
                camera.step(dt: frame)
                XCTAssertTrue(camera.isAtRest && camera.place == .field,
                              "RM \(reduced): the field went dead part-way through the fade")
            }
        }
    }

    // The axis end is distinguished from EVERY other commit, which is the
    // requirement — not "a commit whose destination equals its origin", which
    // the per-commit cap can also produce and which means something completely
    // different ("not that far in one go", not "there is nothing there").
    func testOnlyTheEndsOfTheAxisAcknowledge() {
        for (place, direction) in [(Place.field, WorldDirection.up), (.field, .down),
                                   (.sky, .down), (.journal, .up)] {
            let camera = makeCamera()
            park(camera, at: place)
            camera.consume(.commit(direction, velocity: 1500))
            camera.step(dt: frame)
            XCTAssertNil(camera.edgeAcknowledgement,
                         "\(place) \(direction): a commit that travels must not light the edge")
            XCTAssertFalse(camera.isAtRest, "\(place) \(direction): …and it must travel")
        }
    }

    // A drag off the end followed by a flick back at it is BOTH: there is real
    // distance to cover, and she still asked for somewhere that does not
    // exist. The world answers with movement AND with light, and lands exactly
    // on the end.
    func testADragOffTheEndFollowedByAGatedFlickBothTravelsAndAcknowledges() {
        let camera = makeCamera()
        park(camera, at: .sky)
        drag(camera, by: 0.1 * screenHeight)          // downward, off the sky
        XCTAssertEqual(camera.offset, -0.65, accuracy: 1e-9)

        camera.consume(.commit(.up, velocity: -2400))
        camera.step(dt: frame)
        XCTAssertNotNil(camera.edgeAcknowledgement, "the axis still clamped, so it still answers")
        XCTAssertFalse(camera.isAtRest, "…and there was real distance to travel")

        while !camera.isIdle { camera.step(dt: frame) }
        XCTAssertEqual(camera.offset, -0.75, accuracy: 1e-12, "she is back at the end of the world")
        XCTAssertEqual(camera.acknowledgementLevel, 0)
    }

    // EXACTLY zero — not "small", not "within a pixel" — and it stays there.
    // A paused frame left holding a fraction of a glow is a world that has
    // stopped with the lights half on.
    func testTheAcknowledgementDecaysToExactlyZeroAndParks() {
        let camera = makeCamera()
        park(camera, at: .sky)
        camera.consume(.commit(.up, velocity: 2400))
        let trace = traceAcknowledgement(camera)

        XCTAssertEqual(trace.level.last, 0, "the envelope must end on the literal zero")
        XCTAssertEqual(camera.acknowledgementLevel, 0)
        XCTAssertNil(camera.edgeAcknowledgement)
        XCTAssertTrue(camera.isIdle)
        for _ in 0..<600 { camera.step(dt: frame) }
        XCTAssertEqual(camera.acknowledgementLevel, 0, "…and stay there for as long as she leaves it")
        XCTAssertTrue(camera.isIdle, "a parked envelope must let the world pause")
    }

    // Frame-rate independence in the sense every other clock in this file has
    // it: the level is a function of accumulated STEPPED time, so the whole
    // envelope takes the same wall-clock at 30, 60 and 120 Hz to within one
    // frame quantum — and a stalled frame is absorbed by `maxStep` rather than
    // completing the envelope in one step.
    func testTheAcknowledgementIsFrameRateIndependent() {
        var durations: [TimeInterval] = []
        for rate in [TimeInterval(1.0 / 120), 1.0 / 60, 1.0 / 30] {
            let camera = makeCamera()
            park(camera, at: .sky)
            camera.consume(.commit(.up, velocity: 2400))
            let trace = traceAcknowledgement(camera, dt: rate)
            durations.append(TimeInterval(trace.frames) * rate)
            XCTAssertEqual(trace.peak, 1, accuracy: 1e-12,
                           "\(rate): the peak must not depend on the frame rate")
            XCTAssertEqual(trace.level.last, 0)
            print("[W05c] \(1 / rate) Hz: \(trace.frames) frames, "
                  + "\(String(format: "%.4f", durations.last!)) s")
        }
        let nominal = WorldCamera.Config.default.acknowledgementRise
            + WorldCamera.Config.default.acknowledgementFall
        for (index, duration) in durations.enumerated() {
            let rate = [1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0][index]
            // One frame quantum, plus a hair for the floating-point
            // arithmetic — the three rates land EXACTLY one quantum off the
            // nominal, which is the best a sampled ramp can do and the same
            // quality the settle's own `s = elapsed / duration` has.
            XCTAssertLessThan(abs(duration - nominal), rate + 1e-6,
                              "the envelope's duration drifted by more than one frame at "
                              + "\(1 / rate) Hz")
        }

        // A stall. The world is paused at the sky, so the first frame after
        // the flick carries however long she sat there — clamped to `maxStep`,
        // exactly as a resumed settle's first frame is, and by the same line.
        let stalled = makeCamera()
        park(stalled, at: .sky)
        stalled.consume(.commit(.up, velocity: 2400))
        stalled.step(dt: 90)
        XCTAssertEqual(stalled.acknowledgementLevel,
                       CGFloat(WorldCamera.Config.default.maxStep
                               / WorldCamera.Config.default.acknowledgementRise),
                       accuracy: 1e-12,
                       "a 90 s stall must advance the envelope by one clamped step and no more")
        XCTAssertLessThan(stalled.acknowledgementLevel, 0.3,
                          "…which is under a third of the way up, on the one frame where the "
                          + "light is least noticeable anyway")
        let trace = traceAcknowledgement(stalled)
        XCTAssertEqual(trace.level.last, 0, "a stall must not leave a residue")
    }

    // BARRIER CONDITION 11, in the form this cue takes it: there is no Reduce
    // Motion branch anywhere in the envelope, so the two paths are not merely
    // equivalent, they are the same code producing the same numbers. Compared
    // frame by frame rather than in aggregate, because "the same" is the claim.
    func testTheAcknowledgementIsIdenticalUnderReduceMotion() {
        var traces: [[CGFloat]] = []
        for reduced in [false, true] {
            let camera = makeCamera(reduceMotion: reduced)
            park(camera, at: .sky)
            camera.consume(.commit(.up, velocity: 2400))
            traces.append(traceAcknowledgement(camera).level)
        }
        XCTAssertEqual(traces[0].count, traces[1].count,
                       "the two motion modes ran the envelope for different lengths of time")
        for (index, value) in traces[0].enumerated() {
            XCTAssertEqual(value, traces[1][index], accuracy: 0,
                           "frame \(index): Reduce Motion changed the acknowledgement")
        }
    }

    // BARRIER CONDITION 13'S SHAPE ON THE SECOND SEQUENCE. Rocking the ceiling
    // must not build the light up: each rapid re-attempt is smaller, the whole
    // sequence is bounded by the first one's peak, and the floor means the
    // fifth flick still gets an answer rather than the silence this feature
    // exists to end.
    func testRepeatedFlicksAtTheCeilingDampAndNeverPump() {
        for gap in [1, 12, 30, 60, 120] {
            let camera = makeCamera()
            park(camera, at: .sky)
            var levels: [CGFloat] = []
            for _ in 0..<6 {
                camera.consume(.commit(.up, velocity: 6000))
                for _ in 0..<gap {
                    camera.step(dt: frame)
                    levels.append(camera.acknowledgementLevel)
                }
            }
            while !camera.isIdle {
                camera.step(dt: frame)
                levels.append(camera.acknowledgementLevel)
            }
            let peak = levels.max() ?? 0
            XCTAssertLessThanOrEqual(Double(peak), 1,
                                     "gap \(gap): six flicks pumped the light past its bound")
            XCTAssertGreaterThanOrEqual(Double(levels.min() ?? 0), 0,
                                        "gap \(gap): the level went negative")
            XCTAssertEqual(camera.acknowledgementLevel, 0, "gap \(gap): residue after the storm")
            XCTAssertTrue(camera.isAtRest, "gap \(gap): rocking the ceiling moved the world")
            print("[W05c] six flicks \(gap) frames apart: peak \(String(format: "%.3f", Double(peak)))")
        }

        // The damping is visible where it matters — a second flick a
        // comfortable moment after the first is quieter, and a flick after a
        // genuinely idle window is not.
        let camera = makeCamera()
        park(camera, at: .sky)
        camera.consume(.commit(.up, velocity: 6000))
        let first = traceAcknowledgement(camera)
        camera.consume(.commit(.up, velocity: 6000))
        let second = traceAcknowledgement(camera)
        XCTAssertLessThan(Double(second.peak), Double(first.peak) - 0.1,
                          "an immediate re-attempt must be quieter than the first")
        XCTAssertGreaterThanOrEqual(Double(second.peak),
                                    Double(WorldCamera.Config.default.acknowledgementDampingFloor),
                                    "…but never so quiet that she is back to being ignored")

        for _ in 0..<Int(2.0 / frame) { camera.step(dt: frame) }
        camera.consume(.commit(.up, velocity: 6000))
        let forgiven = traceAcknowledgement(camera)
        XCTAssertEqual(forgiven.peak, 1, accuracy: 1e-12,
                       "one idle window and the world answers in full again")
    }

    // A commit that actually travels ends the sequence, exactly as it ends a
    // rocking sequence: the world has answered her with MOVEMENT, so the next
    // time she does reach an end she gets a whole answer rather than an
    // inherited whisper of one. And the light already burning settles back
    // instead of being cut, which would be the one visible step in the design.
    func testACommitThatTravelsEndsTheAcknowledgementSequence() {
        let camera = makeCamera()
        park(camera, at: .sky)
        camera.consume(.commit(.up, velocity: 6000))
        for _ in 0..<10 { camera.step(dt: frame) }
        let burning = camera.acknowledgementLevel
        XCTAssertGreaterThan(burning, 0)

        camera.consume(.commit(.down, velocity: 6000))
        XCTAssertEqual(camera.acknowledgementLevel, burning,
                       "the commit must not cut the light — it settles back")
        runSettle(camera)
        XCTAssertEqual(camera.place, .field, "the legitimate commit travelled")
        while !camera.isIdle { camera.step(dt: frame) }
        XCTAssertEqual(camera.acknowledgementLevel, 0)

        camera.consume(.commit(.down, velocity: 6000))   // field → journal, travels
        runSettle(camera)
        camera.consume(.commit(.down, velocity: 6000))   // and now the floor
        let answer = traceAcknowledgement(camera)
        XCTAssertEqual(answer.peak, 1, accuracy: 1e-12,
                       "the journeys in between must have ended the damping sequence")
    }

    // THE TWO QUESTIONS, as a test rather than as a comment. This is the whole
    // structural claim of W05c: "the world is moving" and "there is something
    // left to step" are different, and there is a window in which they
    // disagree. If they ever stop disagreeing, either the pause predicate has
    // been narrowed back or the hit-testing gate has been widened, and one of
    // those freezes the glow while the other takes her controls away.
    func testIsIdleAndIsAtRestAreDifferentQuestions() {
        let camera = makeCamera()
        park(camera, at: .sky)
        XCTAssertTrue(camera.isAtRest)
        XCTAssertTrue(camera.isIdle, "at rest with nothing burning, both are true")

        camera.consume(.commit(.up, velocity: 2400))
        XCTAssertTrue(camera.isAtRest,
                      "the world is genuinely standing still — this is what keeps her taps")
        XCTAssertFalse(camera.isIdle,
                       "…and it is asked of the PHASE, not of the level: the envelope is armed "
                       + "but has not been stepped, so a level test would answer 'nothing to do' "
                       + "on exactly the frame whose job is to un-pause the world")

        var disagreed = 0
        while !camera.isIdle {
            camera.step(dt: frame)
            if camera.isAtRest && !camera.isIdle { disagreed += 1 }
            XCTAssertTrue(camera.isAtRest || !camera.isIdle,
                          "`isAtRest` false with `isIdle` true is unrepresentable: the render "
                          + "half must never be weaker than the moving half")
        }
        XCTAssertGreaterThan(disagreed, 30,
                             "the two questions never disagreed, so nothing is being proved")
    }

    // INVARIANT A and INVARIANT D, extended to the light. A camera nobody has
    // touched never glows, and one that does not know its own screen height
    // refuses the acknowledgement along with everything else — a world that
    // answers a gesture it also refused would be worse than either.
    func testAnUntouchedOrUnlaidOutCameraNeverAcknowledges() {
        let idle = makeCamera()
        for _ in 0..<2400 { idle.step(dt: frame) }
        XCTAssertEqual(idle.acknowledgementLevel, 0)
        XCTAssertNil(idle.edgeAcknowledgement)
        XCTAssertTrue(idle.isIdle)

        let unlaidOut = WorldCamera(viewHeight: 0)
        unlaidOut.consume(.commit(.up, velocity: 2400))
        unlaidOut.step(dt: frame)
        XCTAssertEqual(unlaidOut.acknowledgementLevel, 0)
        XCTAssertNil(unlaidOut.edgeAcknowledgement)
        XCTAssertTrue(unlaidOut.isIdle)
    }
}
