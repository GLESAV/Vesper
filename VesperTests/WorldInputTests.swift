import XCTest
import CoreGraphics
@testable import Vesper

// Proof for the pure arbitration core (DELIVERY_ROADMAP W03). These tests are
// the part of the spike that does NOT need a device: every ruling in §6 that
// can be stated as "these touches produce these outcomes" is pinned here, so
// R-SPIKE argues about measured latency rather than about whether the rules
// are implemented.
//
// No timing, no rendering, no randomness: timestamps are synthetic and
// monotonic, exactly like GameSimulationTests drives `step(dt:)`.
final class WorldInputTests: XCTestCase {

    private let screen = CGSize(width: 390, height: 844)

    // 844 * 0.11 = 92.84 pt of travel, and 300 pt/s at release.
    private func makeArbiter() -> InputArbiter { InputArbiter(bounds: screen) }

    // MARK: - Gesture helpers

    // One complete vertical gesture: down, `steps` evenly spaced moves, up.
    // Negative dy is upward on screen (toward the sky).
    @discardableResult
    private func swipe(_ a: inout InputArbiter,
                       from start: CGPoint,
                       dy: CGFloat,
                       duration: TimeInterval,
                       steps: Int = 8,
                       onOrb: Bool,
                       at startTime: TimeInterval) -> [InputOutcome] {
        var out = a.began(at: start, timestamp: startTime, onOrb: onOrb)
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
                                 onOrb: true,
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
                             dy: -200, duration: 0.15, onOrb: true, at: 0)
        let expected: [InputOutcome] = [.pop(CGPoint(x: 195, y: 500))]
        XCTAssertEqual(Array(outcomes.prefix(1)), expected,
                       "the pop must be the first outcome of the gesture")
    }

    // MARK: - A pop that is only a pop

    func testTapOnOrbWithNoMovementNeverCommits() {
        var arbiter = makeArbiter()
        let p = CGPoint(x: 195, y: 500)

        let began = arbiter.began(at: p, timestamp: 0, onOrb: true)
        XCTAssertEqual(began, [.pop(p)])

        let ended = arbiter.ended(at: p, timestamp: 0.05)
        XCTAssertEqual(ended, [], "a still finger must produce no camera outcome at all")
        XCTAssertFalse(arbiter.isTracking)
    }

    // A hesitant half-swipe off an orb: the orb pops, the camera springs home,
    // and she goes nowhere. 04 §4 — a hesitant half-swipe is free.
    func testSlowShortDragFromAnOrbPopsAndDoesNotCommit() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -40, duration: 0.9, onOrb: true, at: 0)

        XCTAssertEqual(popCount(outcomes), 1)
        XCTAssertTrue(hasPanBegan(outcomes), "40 pt is past the 10 pt slop, so the camera did follow")
        XCTAssertFalse(hasAnyCommit(outcomes))
        XCTAssertTrue(outcomes.contains(.cancelToRest))
    }

    // MARK: - The two gates, separately

    func testFastFlickFromEmptySpaceCommits() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: 150, duration: 0.10, onOrb: false, at: 0)

        XCTAssertEqual(popCount(outcomes), 0, "empty space never pops")
        XCTAssertEqual(commitCount(outcomes, .down), 1, "downward flick goes to the journal")
    }

    // Distance without velocity: a long, slow drag — a thumb resting and
    // drifting. Both gates are required (04 §4), so this springs home.
    func testLongSlowDragDoesNotCommit() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -200, duration: 3.0, onOrb: false, at: 0)

        XCTAssertFalse(hasAnyCommit(outcomes), "200 pt of travel is not enough without velocity")
        XCTAssertTrue(outcomes.contains(.cancelToRest))
    }

    // Velocity without distance: a fast twitch. Also not a commit.
    func testFastTinyFlickDoesNotCommit() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -30, duration: 0.03, onOrb: false, at: 0)

        XCTAssertFalse(hasAnyCommit(outcomes))
        XCTAssertTrue(outcomes.contains(.cancelToRest))
    }

    // She dragged a long way down, changed her mind, and flicked back up at
    // release. Distance says "journal", velocity says "no". Nothing happens.
    func testDirectionDisagreementBetweenDistanceAndVelocitySpringsHome() {
        var arbiter = makeArbiter()
        let x: CGFloat = 195
        var outcomes = arbiter.began(at: CGPoint(x: x, y: 400), timestamp: 0, onOrb: false)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 480), timestamp: 0.10)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 560), timestamp: 0.20)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 600), timestamp: 0.30)
        outcomes += arbiter.moved(to: CGPoint(x: x, y: 560), timestamp: 0.32)
        outcomes += arbiter.ended(at: CGPoint(x: x, y: 520), timestamp: 0.34)

        XCTAssertFalse(hasAnyCommit(outcomes))
        XCTAssertTrue(outcomes.contains(.cancelToRest))
    }

    // MARK: - Edge dead zones (04 §4)

    func testTopEdgeDeadZoneSuppressesTheCommitButNotThePop() {
        var arbiter = makeArbiter()
        // 10% of 844 is 84.4 pt; y = 40 is inside the top dead zone.
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 40),
                             dy: -200, duration: 0.15, onOrb: true, at: 0)

        XCTAssertEqual(popCount(outcomes), 1, "an orb near the top edge still pops")
        XCTAssertFalse(hasPanBegan(outcomes), "the nav swipe never arms in the dead zone")
        XCTAssertFalse(hasAnyCommit(outcomes))
        XCTAssertFalse(outcomes.contains(.cancelToRest), "nothing moved, so nothing springs home")
    }

    func testBottomEdgeDeadZoneSuppressesTheCommit() {
        var arbiter = makeArbiter()
        // 844 - 84.4 = 759.6; y = 800 is inside the bottom dead zone.
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 800),
                             dy: -200, duration: 0.15, onOrb: false, at: 0)

        XCTAssertFalse(hasAnyCommit(outcomes))
    }

    // A swipe that STARTS in the live area and travels up through the top
    // dead zone must still commit — the zone is judged at touch-down only.
    func testSwipePassingThroughTheTopDeadZoneStillCommits() {
        var arbiter = makeArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 300),
                             dy: -260, duration: 0.15, onOrb: false, at: 0)

        XCTAssertEqual(commitCount(outcomes, .up), 1)
    }

    // MARK: - Ruling 4: a pop is never retracted

    func testCancelledTouchRetractsNothingAlreadyPopped() {
        var arbiter = makeArbiter()
        let p = CGPoint(x: 195, y: 500)

        let began = arbiter.began(at: p, timestamp: 0, onOrb: true)
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
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0, onOrb: true)
        XCTAssertEqual(arbiter.cancelled(), [])
    }

    // MARK: - Pan shaping

    // The camera must start from zero when the pan arms, not jump by the slop.
    func testPanTranslationIsAnchoredPastTheSlop() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0, onOrb: false)
        let moved = arbiter.moved(to: CGPoint(x: 195, y: 470), timestamp: 0.02)

        // 30 pt travelled, 10 pt spent on slop.
        XCTAssertEqual(moved, [.panBegan, .panChanged(translation: -20)])
    }

    func testJitterUnderTheSlopNeverMovesTheCamera() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0, onOrb: true)
        XCTAssertEqual(arbiter.moved(to: CGPoint(x: 196, y: 496), timestamp: 0.01), [])
        XCTAssertEqual(arbiter.moved(to: CGPoint(x: 194, y: 504), timestamp: 0.02), [])
    }

    // One axis, one meaning (04 §4): a horizontal drag belongs to the place,
    // not to the camera.
    func testHorizontalDragNeverArmsTheVerticalPan() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 100, y: 500), timestamp: 0, onOrb: false)
        var outcomes: [InputOutcome] = []
        outcomes += arbiter.moved(to: CGPoint(x: 200, y: 505), timestamp: 0.05)
        outcomes += arbiter.moved(to: CGPoint(x: 300, y: 515), timestamp: 0.10)
        outcomes += arbiter.ended(at: CGPoint(x: 340, y: 520), timestamp: 0.15)

        XCTAssertFalse(hasPanBegan(outcomes))
        XCTAssertFalse(hasAnyCommit(outcomes))
    }

    // MARK: - Extra fingers

    // A second thumb landing on an orb still pops (ruling 4) but must not
    // take the camera away from the finger already steering it.
    func testSecondTouchPopsButDoesNotStealTheCamera() {
        var arbiter = makeArbiter()
        _ = arbiter.began(at: CGPoint(x: 100, y: 500), timestamp: 0, onOrb: false)
        _ = arbiter.moved(to: CGPoint(x: 100, y: 440), timestamp: 0.02)

        let second = CGPoint(x: 300, y: 500)
        XCTAssertEqual(arbiter.began(at: second, timestamp: 0.03, onOrb: true), [.pop(second)])

        // The original finger keeps steering, measured from its own anchor.
        XCTAssertEqual(arbiter.moved(to: CGPoint(x: 100, y: 420), timestamp: 0.04),
                       [.panChanged(translation: -70)])
    }

    // MARK: - Transit policy (04 §5)

    // While the camera is settling, a touch grabs the camera and does not
    // play. Not an exception to ruling 4: off-rest there is no field under
    // her finger to pop.
    func testTouchDuringTransitGrabsTheCameraAndDoesNotPop() {
        var arbiter = makeArbiter()
        arbiter.fieldAtRest = false

        let outcomes = arbiter.began(at: CGPoint(x: 195, y: 500), timestamp: 0, onOrb: true)
        XCTAssertEqual(outcomes, [.panBegan])
        XCTAssertEqual(popCount(outcomes), 0)
    }

    // MARK: - Before layout

    // An arbiter that does not yet know the screen height must never move the
    // camera; the pop, as always, still fires.
    func testUnlaidOutArbiterNeverCommits() {
        var arbiter = InputArbiter()
        let outcomes = swipe(&arbiter, from: CGPoint(x: 195, y: 500),
                             dy: -300, duration: 0.12, onOrb: true, at: 0)

        XCTAssertEqual(popCount(outcomes), 1)
        XCTAssertFalse(hasAnyCommit(outcomes))
    }
}
