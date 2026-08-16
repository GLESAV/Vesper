import XCTest
import CoreGraphics
@testable import Vesper

// Proof for the pure arbitration core (DELIVERY_ROADMAP W03, as amended by
// the R-SPIKE gate log §7). These tests are the part of the spike that does
// NOT need a device: every ruling that can be stated as "these touches
// produce these outcomes" is pinned here, so the gate argues about measured
// latency rather than about whether the rules are implemented.
//
// No timing, no rendering, no randomness: timestamps are synthetic and
// monotonic, exactly like GameSimulationTests drives `step(dt:)`.
final class WorldInputTests: XCTestCase {

    private let screen = CGSize(width: 390, height: 844)

    // 844 * 0.11 = 92.84 pt of travel, and 300 pt/s at release.
    private func makeArbiter() -> InputArbiter { InputArbiter(bounds: screen) }

    // The camera is mid-settle: touch-down grabs it instead of playing.
    private func makeTransitArbiter() -> InputArbiter {
        InputArbiter(bounds: screen, isFieldAtRest: { false })
    }

    // MARK: - Gesture helpers

    // One complete vertical gesture: down, `steps` evenly spaced moves, up.
    // Negative dy is upward on screen (toward the sky).
    @discardableResult
    private func swipe(_ a: inout InputArbiter,
                       from start: CGPoint,
                       dy: CGFloat,
                       duration: TimeInterval,
                       steps: Int = 8,
                       at startTime: TimeInterval) -> [InputOutcome] {
        var out = a.began(at: start, timestamp: startTime)
        for i in 1..<steps {
            let f = CGFloat(i) / CGFloat(steps)
            out += a.moved(to: CGPoint(x: start.x, y: start.y + dy * f),
                           timestamp: startTime + duration * (TimeInterval(i) / TimeInterval(steps)))
        }
        out += a.ended(at: CGPoint(x: start.x, y: start.y + dy),
                       timestamp: startTime + duration)
        return out
    }

    private func popCount(_ outcomes: [InputOutcome]) -> Int {
        outcomes.reduce(into: 0) { n, o in
            if case .pop = o { n += 1 }
        }
    }

    private func commitCount(_ outcomes: [InputOutcome], _ direction: WorldDirection) -> Int {
        outcomes.reduce(into: 0) { n, o in
            if case .commit(let d, _) = o, d == direction { n += 1 }
        }
    }

    private func hasAnyCommit(_ outcomes: [InputOutcome]) -> Bool {
        outcomes.contains { o in
            if case .commit = o { return true }
            return false
        }
    }

    private func commitVelocity(_ outcomes: [InputOutcome]) -> CGFloat? {
        for o in outcomes {
            if case .commit(_, let v) = o { return v }
        }
        return nil
    }

    private func hasPanBegan(_ outcomes: [InputOutcome]) -> Bool {
        outcomes.contains(.panBegan)
    }

    // MARK: - Ruling 6: the case where the two systems collide

    // "20 consecutive swipes begun directly on an orb → 20 pops, 20 camera
    // commits." This is the whole reason the arbiter exists: the pop must
    // never eat the swipe, and the swipe must never eat the pop.
    func testTwentySwipesBegunOnAnOrbProduceTwentyPopsAndTwentyCommits() {
        var arbiter = makeArbiter()
        var pops = 0
        var commits = 0

        for i in 0..<20 {
            let outcomes = swipe(&arbiter,
                                 from: CGPoint(x: 195, y: 500),
                                 dy: -200,
                                 duration: 0.15,
                                 at: TimeInterval(i))

            // Per swipe, not just in aggregate — an aggregate count could hide
            // one gesture firing twice and another firing not at all.
            XCTAssertEqual(popCount(outcomes), 1, "swipe \(i) should pop exactly once")
            XCTAssertEqual(commitCount(outcomes, .up), 1, "swipe \(i) should commit up exactly once")
            XCTAssertFalse(outcomes.contains(.cancelToRest), "swipe \(i) must not spring home")
            XCTAssertFalse(arbiter.isTracking, "swipe \(i) must leave no residual touch state")

            pops += popCount(outcomes)
            commits += commitCount(outcomes, .up)
        }

        XCTAssertEqual(pops, 20)
        XCTAssertEqual(commits, 20)
    }

    // The pop is emitted at touch-DOWN (ruling 3), before any pan exists —
    // so it is first in the outcome stream, every time.
    func testPopIsEmittedBeforeThePanEverBegins() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -200, duration: 0.15, at: 0)
        let expected: [InputOutcome] = [.pop(CGPoint(x: 195, y: 500))]
        XCTAssertEqual(Array(outcomes.prefix(1)), expected,
                       "the pop must be the first outcome of the gesture")
    }

    // MARK: - §7.1: no hit test in the input layer

    // Every touch-down on a resting field reports a pop, wherever it lands.
    // GameSimulation.tap is the single authority on what an orb is and
    // returns no events on a miss, so an empty-space touch costs one call.
    // A second copy of the hit test here could only ever subtract pops.
    func testEveryTouchDownAtRestReportsAPopWhereverItLands() {
        var arbiter = makeArbiter()
        let empty = CGPoint(x: 12, y: 640)

        XCTAssertEqual(arbiter.began(at: empty, timestamp: 0), [.pop(empty)])
        XCTAssertEqual(arbiter.ended(at: empty, timestamp: 0.04), [])
    }

    // MARK: - A pop that is only a pop

    func testTouchWithNoMovementNeverCommits() {
        var arbiter = makeArbiter()
        let p = CGPoint(x: 195, y: 500)

        let began = arbiter.began(at: p, timestamp: 0)
        XCTAssertEqual(began, [.pop(p)])

        let ended = arbiter.ended(at: p, timestamp: 0.05)
        XCTAssertEqual(ended, [], "a still finger must produce no camera outcome at all")
        XCTAssertFalse(arbiter.isTracking)
    }

    // A hesitant half-swipe: the touch pops, the camera springs home, and she
    // goes nowhere. 04 §4 — a hesitant half-swipe is free.
    func testSlowShortDragPopsAndDoesNotCommit() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -40, duration: 0.9, at: 0)

        XCTAssertEqual(popCount(outcomes), 1)
        XCTAssertTrue(hasPanBegan(outcomes), "40 pt is past the 10 pt slop, so the camera did follow")
        XCTAssertFalse(hasAnyCommit(outcomes))
        XCTAssertTrue(outcomes.contains(.cancelToRest))
    }

    // MARK: - The two gates, separately

    func testFastFlickCommits() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: 150, duration: 0.10, at: 0)

        XCTAssertEqual(popCount(outcomes), 1, "touch-down at rest always reports a pop (§7.1)")
        XCTAssertEqual(commitCount(outcomes, .down), 1, "downward flick goes to the journal")
    }

    // Distance without velocity: a long, slow drag — a thumb resting and
    // drifting. Both gates are required (04 §4), so this springs home.
    func testLongSlowDragDoesNotCommit() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -200, duration: 3.0, at: 0)

        XCTAssertFalse(hasAnyCommit(outcomes), "200 pt of travel is not enough without velocity")
        XCTAssertTrue(outcomes.contains(.cancelToRest))
    }

    // Velocity without distance: a fast twitch. Also not a commit.
    func testFastTinyFlickDoesNotCommit() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -30, duration: 0.03, at: 0)

        XCTAssertFalse(hasAnyCommit(outcomes))
        XCTAssertTrue(outcomes.contains(.cancelToRest))
    }

    // She dragged a long way down, changed her mind, and flicked back up at
    // release. Distance says "journal", velocity says "no". Nothing happens.
    func testDirectionDisagreementBetweenDistanceAndVelocitySpringsHome() {
        var arbiter = makeArbiter()
        let x: CGFloat = 195
        var outcomes = arbiter.began(at: CGPoint(x: x, y: 400), timestamp: 0)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 480), timestamp: 0.10)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 560), timestamp: 0.20)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 600), timestamp: 0.30)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 560), timestamp: 0.32)
        outcomes += arbiter.ended(at: CGPoint(x: x, y: 520), timestamp: 0.34)

        XCTAssertFalse(hasAnyCommit(outcomes))
        XCTAssertTrue(outcomes.contains(.cancelToRest))
    }

    // MARK: - §7.6: the thumb stall

    // She flicks hard, then rests her thumb on the glass for a quarter second
    // before lifting. The flick is over; she is holding, not throwing. The
    // camera must not be launched by a velocity measured a stall ago.
    func testFlickFollowedByAStillHoldDoesNotCommit() {
        var arbiter = makeArbiter()
        let x: CGFloat = 195
        var outcomes = arbiter.began(at: CGPoint(x: x, y: 500), timestamp: 0)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 470), timestamp: 0.02)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 430), timestamp: 0.04)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 390), timestamp: 0.06)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 350), timestamp: 0.08)
        // 150 pt travelled — well past the 92.84 pt distance gate — at
        // ~1875 pt/s. Then the finger stops dead for 250 ms and lifts.
        outcomes += arbiter.ended(at: CGPoint(x: x, y: 350), timestamp: 0.33)

        XCTAssertEqual(popCount(outcomes), 1)
        XCTAssertTrue(hasPanBegan(outcomes), "the camera followed her thumb the whole way")
        XCTAssertFalse(hasAnyCommit(outcomes), "a finger that stopped moving is not a flick")
        XCTAssertTrue(outcomes.contains(.cancelToRest))
    }

    // Velocity is measured over `velocityWindow` of history, not over a fixed
    // number of samples, so a 120 Hz digitizer and a 60 Hz one report the
    // same flick (§7.6 — samples are retained by time).
    func testVelocityIsMeasuredOverTheWindowNotTheSampleCount() {
        var coarse = makeArbiter()
        var dense = makeArbiter()

        let coarseOutcomes = swipe(&coarse, from: CGPoint(x: 195, y: 500),
                                   dy: -200, duration: 0.15, steps: 8, at: 0)
        let denseOutcomes = swipe(&dense, from: CGPoint(x: 195, y: 500),
                                  dy: -200, duration: 0.15, steps: 18, at: 0)

        guard let slow = commitVelocity(coarseOutcomes),
              let fast = commitVelocity(denseOutcomes) else {
            XCTFail("both sample rates must commit the same gesture")
            return
        }
        XCTAssertEqual(slow, fast, accuracy: 60,
                       "sample rate must not change the measured release velocity")
    }

    // MARK: - §7.5: the velocity ceiling

    // The arbiter must never hand the camera a number the camera is not
    // allowed to honour: a 6000 pt/s whip arrives clamped, sign intact.
    func testReleaseVelocityIsClampedToTheCeiling() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -300, duration: 0.05, at: 0)

        XCTAssertEqual(commitCount(outcomes, .up), 1)
        guard let v = commitVelocity(outcomes) else {
            XCTFail("expected a commit")
            return
        }
        // 300 pt in 50 ms is 6000 pt/s at the finger; the camera is handed
        // 2400, sign intact (negative is upward, toward the sky).
        XCTAssertEqual(v, -InputArbiter.Config.default.maxCommitVelocity,
                       "a whip-fast flick commits at the ceiling, still negative (upward)")
    }

    // An ordinary swipe is nowhere near the ceiling and passes through
    // untouched — the clamp must not flatten normal feel.
    func testOrdinaryFlickIsNotClamped() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -200, duration: 0.15, at: 0)

        guard let v = commitVelocity(outcomes) else {
            XCTFail("expected a commit")
            return
        }
        XCTAssertEqual(v, -1333.33, accuracy: 1)
        XCTAssertLessThan(abs(v), InputArbiter.Config.default.maxCommitVelocity)
    }

    // MARK: - Edge dead zones (04 §4, scoped by §7.4)

    func testTopEdgeDeadZoneSuppressesTheCommitButNotThePop() {
        var arbiter = makeArbiter()
        // 10% of 844 is 84.4 pt; y = 40 is inside the top dead zone.
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 40),
                             dy: -200, duration: 0.15, at: 0)

        XCTAssertEqual(popCount(outcomes), 1, "a touch near the top edge still pops")
        XCTAssertFalse(hasPanBegan(outcomes), "the nav swipe never arms in the dead zone at rest")
        XCTAssertFalse(hasAnyCommit(outcomes))
        XCTAssertFalse(outcomes.contains(.cancelToRest), "nothing moved, so nothing springs home")
    }

    func testBottomEdgeDeadZoneSuppressesTheCommit() {
        var arbiter = makeArbiter()
        // 844 - 84.4 = 759.6; y = 800 is inside the bottom dead zone.
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 800),
                             dy: -200, duration: 0.15, at: 0)

        XCTAssertFalse(hasAnyCommit(outcomes))
    }

    // A swipe that STARTS in the live area and travels up through the top
    // dead zone must still commit — the zone is judged at touch-down only.
    func testSwipePassingThroughTheTopDeadZoneStillCommits() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 300),
                             dy: -260, duration: 0.15, at: 0)

        XCTAssertEqual(commitCount(outcomes, .up), 1)
    }

    // §7.4. The dead zone scopes COMMITS, not catches. Mid-settle, a thumb
    // landing low — the most natural one-handed reach there is — must still
    // catch the camera. Before this ruling it produced total silence while
    // the camera kept flying, which breaks "every move is interruptible".
    func testTouchInTheBottomDeadZoneDuringTransitStillGrabsTheCamera() {
        var arbiter = makeTransitArbiter()
        let outcomes = arbiter.began(at: CGPoint(x: 195, y: 800), timestamp: 0)

        XCTAssertEqual(outcomes, [.panBegan])
    }

    // ...and that catch, released, still may not commit from the dead zone —
    // but it is never silence either: the camera settles to the nearer place.
    func testDeadZoneTransitGrabReleasesToSettleNotToACommit() {
        var arbiter = makeTransitArbiter()
        var outcomes = arbiter.began(at: CGPoint(x: 195, y: 800), timestamp: 0)
        outcomes += arbiter.moved(to: CGPoint(x: 195, y: 700), timestamp: 0.04)
        outcomes += arbiter.moved(to: CGPoint(x: 195, y: 620), timestamp: 0.08)
        outcomes += arbiter.ended(at: CGPoint(x: 195, y: 620), timestamp: 0.09)

        // The camera tracked her finger the whole 180 pt (a grab has no slop),
        // and then landed somewhere instead of falling silent.
        XCTAssertEqual(outcomes, [.panBegan,
                                  .panChanged(translation: -100),
                                  .panChanged(translation: -180),
                                  .settleToNearest])
        XCTAssertFalse(hasAnyCommit(outcomes), "the OS keeps everything the dead zone gave it")
    }

    // MARK: - Ruling 4: a pop is never retracted

    func testCancelledTouchRetractsNothingAlreadyPopped() {
        var arbiter = makeArbiter()
        let p = CGPoint(x: 195, y: 500)

        let began = arbiter.began(at: p, timestamp: 0)
        XCTAssertEqual(began, [.pop(p)], "the pop is delivered at touch-down and is final")

        let moved = arbiter.moved(to: CGPoint(x: 195, y: 440), timestamp: 0.05)
        XCTAssertTrue(hasPanBegan(moved))

        let cancelled = arbiter.cancelled()
        XCTAssertEqual(cancelled, [.cancelToRest],
                       "cancellation only springs the camera home; the pop stands")
        XCTAssertEqual(popCount(cancelled), 0)
        XCTAssertFalse(arbiter.isTracking)
    }

    func testCancelBeforeAnyPanEmitsNothing() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0)
        XCTAssertEqual(arbiter.cancelled(), [])
    }

    // MARK: - Pan shaping

    // The camera must start from zero when the pan arms, not jump by the slop.
    func testPanTranslationIsAnchoredPastTheSlop() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0)
        let moved = arbiter.moved(to: CGPoint(x: 195, y: 470), timestamp: 0.02)

        // 30 pt travelled, 10 pt spent on slop.
        XCTAssertEqual(moved, [.panBegan, .panChanged(translation: -20)])
    }

    func testJitterUnderTheSlopNeverMovesTheCamera() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0)
        XCTAssertEqual(arbiter.moved(to: CGPoint(x: 196, y: 496), timestamp: 0.01), [])
        XCTAssertEqual(arbiter.moved(to: CGPoint(x: 194, y: 504), timestamp: 0.02), [])
    }

    // One axis, one meaning (04 §4): a horizontal drag belongs to the place,
    // not to the camera.
    func testHorizontalDragNeverArmsTheVerticalPan() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 100, y: 500), timestamp: 0)
        var outcomes: [InputOutcome] = []
        outcomes += arbiter.moved(to: CGPoint(x: 200, y: 505), timestamp: 0.05)
        outcomes += arbiter.moved(to: CGPoint(x: 300, y: 515), timestamp: 0.10)
        outcomes += arbiter.ended(at: CGPoint(x: 340, y: 520), timestamp: 0.15)

        XCTAssertFalse(hasPanBegan(outcomes))
        XCTAssertFalse(hasAnyCommit(outcomes))
    }

    // MARK: - Extra fingers

    // A second thumb still pops (ruling 4) but must not take the camera away
    // from the finger already steering it.
    func testSecondTouchPopsButDoesNotStealTheCamera() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 100, y: 500), timestamp: 0)
        _ = arbiter.moved(to: CGPoint(x: 100, y: 440), timestamp: 0.02)

        let second = CGPoint(x: 300, y: 500)
        XCTAssertEqual(arbiter.began(at: second, timestamp: 0.03), [.pop(second)])

        // The original finger keeps steering, measured from its own anchor.
        XCTAssertEqual(arbiter.moved(to: CGPoint(x: 100, y: 420), timestamp: 0.04),
                       [.panChanged(translation: -70)])
    }

    // MARK: - Transit policy (04 §5, §7.2, §7.3)

    // While the camera is settling, a touch grabs the camera and does not
    // play. Not an exception to ruling 4: off-rest there is no field under
    // her finger to pop.
    func testTouchDuringTransitGrabsTheCameraAndDoesNotPop() {
        var arbiter = makeTransitArbiter()

        let outcomes = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0)
        XCTAssertEqual(outcomes, [.panBegan])
        XCTAssertEqual(popCount(outcomes), 0)
    }

    // §7.3. She caught a moving camera and let go without deciding anything.
    // `.cancelToRest` would throw away a move that may be 90% complete; the
    // camera settles to whichever place is nearer by its own offset instead.
    // The arbiter does not know that offset and must not guess.
    func testTransitGrabReleasedUndecidedSettlesToNearest() {
        var arbiter = makeTransitArbiter()
        var outcomes = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0)
        // Sub-slop movement — a steadying thumb, not a gesture. A grab has no
        // slop, so the camera does track those 4 pt.
        outcomes += arbiter.moved(to: CGPoint(x: 195, y: 496), timestamp: 0.05)
        outcomes += arbiter.ended(at: CGPoint(x: 195, y: 496), timestamp: 0.10)

        XCTAssertEqual(outcomes, [.panBegan, .panChanged(translation: -4), .settleToNearest])
        XCTAssertFalse(outcomes.contains(.cancelToRest), "there is no rest to go back to")
    }

    // A grab that IS decisive still commits normally: catching the camera and
    // flicking it onward is a real gesture, not an interruption.
    func testDecisiveTransitGrabStillCommits() {
        var arbiter = makeTransitArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -200, duration: 0.15, at: 0)

        XCTAssertEqual(popCount(outcomes), 0, "off-rest there is no field to pop")
        XCTAssertEqual(commitCount(outcomes, .up), 1)
    }

    // The system taking the touch away mid-grab (a call arrives) settles the
    // same way: the camera is stranded at an arbitrary offset and must land
    // somewhere sensible rather than snap back to where it started.
    func testCancelledTransitGrabSettlesToNearest() {
        var arbiter = makeTransitArbiter()
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0)
        XCTAssertEqual(arbiter.cancelled(), [.settleToNearest])
    }

    // §7.2. `isFieldAtRest` is a closure queried at every touch-down, not a
    // value pushed in through updateUIView. SwiftUI's update pass is not
    // ordered against UIKit touch delivery, so a pushed copy is stale for
    // about a frame at each end of a settle — and being wrong there costs a
    // pop. Here the state flips between two gestures with no setter call.
    func testFieldAtRestIsQueriedLiveAtEachTouchDown() {
        var atRest = true
        var arbiter = InputArbiter(bounds: screen, isFieldAtRest: { atRest })

        let p = CGPoint(x: 195, y: 500)
        XCTAssertEqual(arbiter.began(at: p, timestamp: 0), [.pop(p)])
        _ = arbiter.ended(at: p, timestamp: 0.04)

        atRest = false
        XCTAssertEqual(arbiter.began(at: p, timestamp: 0.10), [.panBegan],
                       "the settle started; the very next touch grabs instead of popping")
        _ = arbiter.ended(at: p, timestamp: 0.14)

        atRest = true
        XCTAssertEqual(arbiter.began(at: p, timestamp: 0.20), [.pop(p)],
                       "the field came to rest; play re-arms with no push from the view")
    }

    // MARK: - §7.6: one camera write per event

    // The coalesced-touch loop feeds every sample to the arbiter (velocity
    // fidelity) but the camera is written at most once per event, so the
    // intermediate translations collapse to the last one.
    func testConsecutivePanChangesCollapseToTheLastValue() {
        var batch: [InputOutcome] = []
        batch.appendCollapsingPanChanges([.panBegan,
                                          .panChanged(translation: -10),
                                          .panChanged(translation: -20)])
        batch.appendCollapsingPanChanges([.panChanged(translation: -30)])

        XCTAssertEqual(batch, [.panBegan, .panChanged(translation: -30)])
    }

    // Only consecutive runs collapse. A pop between two moves is a real
    // boundary and the order it establishes survives.
    func testCollapsingPreservesPopsAndTheirOrder() {
        let p = CGPoint(x: 195, y: 500)
        var batch: [InputOutcome] = []
        batch.appendCollapsingPanChanges([.panChanged(translation: -10),
                                          .pop(p),
                                          .panChanged(translation: -20),
                                          .panChanged(translation: -30)])

        XCTAssertEqual(batch, [.panChanged(translation: -10),
                               .pop(p),
                               .panChanged(translation: -30)])
    }

    // MARK: - Before layout

    // An arbiter that does not yet know the screen height must never move the
    // camera; the pop, as always, still fires.
    func testUnlaidOutArbiterNeverCommits() {
        var arbiter = InputArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -300, duration: 0.12, at: 0)

        XCTAssertEqual(popCount(outcomes), 1)
        XCTAssertFalse(hasAnyCommit(outcomes))
    }

    // MARK: - Liveness: every dropped touch terminates the camera's state

    // The finding these pin down: `.dragging` is absorbing under an EMPTY
    // input sequence — the camera leaves it only when a further outcome
    // arrives. So the host paths that drop a touch without an `ended`
    // (leaving the window; recovering in `touchesBegan` when the arbiter
    // still believes it is steering but the UITouch is gone) must not be
    // silent. Both now flush `cancelled()`, and these tests fix what
    // `cancelled()` owes them in each state the arbiter can be dropped from.

    // Dropped mid-drag from rest: exactly one terminating outcome, and the
    // arbiter is left clean. Anything less strands the camera mid-drag with
    // no finger on the glass and nothing left that could ever end it.
    func testCancelWhileDraggingEmitsExactlyOneTerminatingOutcome() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0)
        _ = arbiter.moved(to: CGPoint(x: 195, y: 440), timestamp: 0.02)
        _ = arbiter.moved(to: CGPoint(x: 195, y: 380), timestamp: 0.04)
        XCTAssertTrue(arbiter.isTracking)

        let cancelled = arbiter.cancelled()

        XCTAssertEqual(cancelled, [.cancelToRest],
                       "a drag dropped by the host must end, not hang")
        XCTAssertEqual(cancelled.count, 1, "one terminating outcome, never two")
        XCTAssertFalse(arbiter.isTracking, "the dropped touch must leave no residue")
    }

    // ...even when the drag had already travelled far enough and fast enough
    // to satisfy both commit gates. A cancel is not a release: she never let
    // go, so nothing is committed — but it still terminates.
    func testCancelOfACommitWorthyDragTerminatesWithoutCommitting() {
        var arbiter = makeArbiter()
        let x: CGFloat = 195
        _ = arbiter.began(at: CGPoint(x: x, y: 500), timestamp: 0)
        _ = arbiter.moved(to: CGPoint(x: x, y: 440), timestamp: 0.02)
        _ = arbiter.moved(to: CGPoint(x: x, y: 380), timestamp: 0.04)
        _ = arbiter.moved(to: CGPoint(x: x, y: 320), timestamp: 0.06)

        let cancelled = arbiter.cancelled()

        XCTAssertFalse(hasAnyCommit(cancelled), "a cancel is not a release")
        XCTAssertEqual(cancelled, [.cancelToRest])
    }

    // Dropped at rest with nothing armed: silence is correct here, and it is
    // the ordinary case — the view leaves the window with no finger on it.
    // An unconditional `.cancelToRest` would spring a camera that was never
    // moved, and (worse) fire on every teardown.
    func testCancelAtRestWithNothingArmedEmitsNothing() {
        var arbiter = makeArbiter()

        // No touch at all — plain view teardown.
        XCTAssertEqual(arbiter.cancelled(), [])

        // A touch-down that only ever popped.
        let p = CGPoint(x: 195, y: 500)
        XCTAssertEqual(arbiter.began(at: p, timestamp: 0), [.pop(p)])
        XCTAssertEqual(arbiter.cancelled(), [],
                       "a bare touch-down is a pop and nothing else")
        XCTAssertFalse(arbiter.isTracking)

        // A touch that jittered under the slop never armed a pan either.
        _ = arbiter.began(at: p, timestamp: 0.20)
        XCTAssertEqual(arbiter.moved(to: CGPoint(x: 196, y: 496), timestamp: 0.22), [])
        XCTAssertEqual(arbiter.cancelled(), [],
                       "sub-slop jitter armed nothing, so there is nothing to terminate")
    }

    // Dropped during a transit grab: `.settleToNearest`, never `.cancelToRest`
    // (§7.3). A grab arms at touch-down and has no rest to spring back to, so
    // this state is droppable with a pan armed even when her finger never
    // moved — which is precisely the stranding case.
    func testCancelDuringATransitGrabSettlesToNearest() {
        var arbiter = makeTransitArbiter()
        XCTAssertEqual(arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0), [.panBegan])
        _ = arbiter.moved(to: CGPoint(x: 195, y: 470), timestamp: 0.03)

        let cancelled = arbiter.cancelled()

        XCTAssertEqual(cancelled, [.settleToNearest])
        XCTAssertFalse(cancelled.contains(.cancelToRest), "a grab has no rest to return to")
        XCTAssertFalse(arbiter.isTracking)
    }

    // The host may drop the same touch twice — `willMove(toWindow:)` followed
    // by the `touchesBegan` recovery, or a cancel that arrives after either.
    // The first call terminates; the rest are silent. A second terminating
    // outcome would settle the camera out from under whatever came next.
    func testCancelIsIdempotent() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0)
        _ = arbiter.moved(to: CGPoint(x: 195, y: 430), timestamp: 0.02)

        XCTAssertEqual(arbiter.cancelled(), [.cancelToRest])
        XCTAssertEqual(arbiter.cancelled(), [], "only the first drop terminates")
        XCTAssertEqual(arbiter.cancelled(), [])
    }

    // And a cancel leaves the arbiter genuinely clean, not merely quiet: the
    // next gesture must behave exactly as if the dropped one never happened.
    // This is the other half of the recovery branch's job — it clears the
    // stale tracking state so navigation is not dead for the rest of the
    // session.
    func testGestureAfterACancelBehavesNormally() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0)
        _ = arbiter.moved(to: CGPoint(x: 195, y: 430), timestamp: 0.02)
        XCTAssertEqual(arbiter.cancelled(), [.cancelToRest])

        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -200, duration: 0.15, at: 1)

        XCTAssertEqual(popCount(outcomes), 1)
        XCTAssertEqual(commitCount(outcomes, .up), 1,
                       "the arbiter must adopt the next touch as if nothing was dropped")
        XCTAssertFalse(arbiter.isTracking)
    }
}
