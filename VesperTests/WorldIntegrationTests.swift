import XCTest
import CoreGraphics
import Foundation
@testable import Vesper

// ─────────────────────────────────────────────────────────────────────────────
// THE COMPOSITION, DRIVEN THROUGH THE WIRING THE APP ACTUALLY SHIPS.
//
// Every other world test in this suite holds ONE component still and proves it:
// `WorldCameraTests` the camera, `WorldInputTests` the arbiter, `SkyScrollTests`
// the scroll state and the split, `SkyLayoutTests` the drawn sky,
// `WorldRegressionTests` the camera-and-arbiter pair against the v1.2 tap
// baseline. This file is the one that holds NOTHING still: a real `WorldModel`,
// its real `WorldCamera`, its real `SkyScrollState`, and a real `InputArbiter`
// wired to them through the three closures `WorldView` hands to
// `WorldInputLayer`, driven by touches and frames in the order `WorldInputView`
// and the world's `TimelineView` deliver them.
//
// WHY IT EXISTS. The sky scroll shipped and never ran on a device. The arbiter
// was correct, the camera was correct, the scroll state was correct, the split
// was correct, and every one of those tests passed — because every one of them
// supplied `isCameraAtRest: { true }` or `isFieldAtRest: { true }` from a
// literal. Production supplies neither from a literal. It supplies
//
//     isFieldAtRest:  { model.simActive }        // camera.isAtRest && place == .field
//     isCameraAtRest: { model.cameraResting }    // camera.isAtRest
//     scrollRoom:     { model.placeScrollRoom }  // .none unless resting AT THE SKY
//
// and the shipped defect was that the transit-grab decision read the FIELD
// predicate. At the resting sky that predicate is false, so every touch-down
// armed the camera before the finger had moved a point, `scrollRoom` was never
// queried — it is only ever read on the slop-arming path — and the headline
// feature of the release was unreachable. A constant closure is exactly how
// that hid.
//
// So the one rule this file keeps, everywhere, without exception:
//
//     NO FIXTURE IS EVER A CONSTANT. Every predicate the arbiter asks is a live
//     read of the same `WorldModel` the outcomes are fed back into.
//
// DETERMINISM. No wall-clock, no sleeps, no unseeded randomness, no shared
// mutable state, no order dependence. Time is a fixed `dt` per frame and a
// synthetic monotonic touch timestamp; the scripted session's variety comes
// from `SplitMix64` with a committed seed. Sky metrics are computed from
// synthetic `MapStone` values through `SkyLayout.metrics` — the one definition
// — so no `MapStore` and no `UserDefaults` are involved. Releases inside scroll
// tests are made from a stationary finger, which is what keeps
// `SkyScrollState`'s wall-clock glide out of the measurement entirely.
//
// AND THAT IS ALSO A BOUNDARY. `SkyScrollState.run(_:)` steps the offset from
// an unstructured `Task` that sleeps 16 ms and reads `Date()`, so no assertion
// here can observe what a glide DOES without letting real time pass. Nothing
// in this file waits on a clock: a projected glide is asserted through the pure
// `projectedGlide`, and the behaviour that would need a running one is named as
// unasserted where it arises rather than tested flakily — see
// `testATouchDownReachesThePlaceAheadOfArbitrationAndKeepsHerPlace`.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class WorldIntegrationTests: XCTestCase {

    // MARK: - Geometry, read from the source of truth rather than restated

    private let screen = CGSize(width: 393, height: 852)          // iPhone 16
    private let frameDt: TimeInterval = 1.0 / 120.0

    private var slop: CGFloat { InputArbiter.Config.default.panSlop }
    private var commitDistance: CGFloat {
        screen.height * InputArbiter.Config.default.commitDistanceFraction
    }
    private var deadZone: CGFloat {
        screen.height * InputArbiter.Config.default.edgeDeadZoneFraction
    }

    // Far from any real "now", so nothing that reads a date can vary between
    // runs. Only the stones carry it, and `SkyLayout.metrics` reads only their
    // generations.
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - The world, wired as `WorldView` wires it

    // The composition under test. Every method on it is a transcription of
    // something `WorldInputView` or `WorldView` does, in the order it does it.
    @MainActor
    private final class World {

        let model = WorldModel()
        var arbiter = InputArbiter()

        // THE TWO OBSERVATIONAL HOOKS `WorldView` BINDS BESIDE THE THREE
        // PREDICATES. Neither produces an `InputOutcome` and neither can change
        // what the arbiter decides — which is exactly why a harness is tempted
        // to drop them, and exactly why it must not. `onTouchDown` in
        // particular is called AHEAD of arbitration and is the only thing that
        // stops a coasting sky under a finger that never moves; a harness
        // without it asserts a world where a tap on a gliding sky does nothing,
        // which is the world we just stopped shipping.
        private var onTouchDown: () -> Void = {}
        private var onPointer: (CGPoint?) -> Void = { _ in }

        // What `WorldInputView.layoutSubviews` and `WorldView`'s
        // `GeometryReader` between them establish. Kept together because in
        // production they are two writes of the same screen, and a test that
        // moved only one would be testing a geometry the app cannot have.
        private(set) var size: CGSize

        // Every outcome the input layer has produced since `clearLog()`, in
        // delivery order — the tape `model.handle` was fed.
        private(set) var log: [InputOutcome] = []

        // Two clocks in production, two here: UITouch timestamps and the
        // timeline's dates.
        private(set) var touchClock: TimeInterval = 0
        private var frameDate = Date(timeIntervalSinceReferenceDate: 0)
        private let frameDt: TimeInterval

        init(size: CGSize, frameDt: TimeInterval) {
            self.size = size
            self.frameDt = frameDt

            // H4: the camera refuses every outcome until it knows a screen
            // height (invariant D), so this lands before the first touch —
            // exactly as `WorldView`'s `.onAppear` does.
            model.camera.viewHeight = size.height

            // ── THE PRODUCTION WIRING, TRANSCRIBED FROM WorldView.swift ──
            //
            // Three closures, three DIFFERENT questions, every one of them a
            // live read of `model`. `m` is a local so the closures capture the
            // model rather than the harness — the harness must not become part
            // of what is under test.
            let m = model
            arbiter = InputArbiter(bounds: size,
                                   isFieldAtRest: { m.simActive },
                                   isCameraAtRest: { m.cameraResting },
                                   scrollRoom: { m.placeScrollRoom })
            // The same two lines, from the same construction:
            //     onTouchDown: { model.touchWentDown() }
            //     onPointer:   { game.pointerMoved(to: $0) }
            // (`game` there is `model.game`, hoisted by the view for the
            // observed sub-object; it is the same instance.)
            onTouchDown = { m.touchWentDown() }
            onPointer = { m.game.pointerMoved(to: $0) }

            // One frame before anything happens, so `lastFrameDate` is primed
            // and the first real frame carries a real `dt`. Production gets
            // this from the timeline's first tick.
            advanceOneFrame()
        }

        // MARK: Touches — `WorldInputView`'s handlers, minus UIKit
        //
        // Statement for statement, in order, from `WorldInputView`. Two things
        // it deliberately does NOT model, both stated here rather than left to
        // be discovered:
        //
        //   * MULTI-TOUCH. Production sorts a `Set<UITouch>` by timestamp and
        //     adopts one steering touch (§7.6); every gesture in this file is
        //     one finger, so the sort is the identity and the adoption is
        //     unconditional. The extra-finger policy is `InputArbiter`'s and is
        //     proved in `WorldInputTests`.
        //   * THE LOST-TOUCH RECOVERY. `touchesBegan` opens with
        //     `if arbiter.isTracking && steeringTouch == nil { … cancelled() }`,
        //     which fires only when a weak `UITouch` died under UIKit. There is
        //     no `UITouch` here to lose, and every gesture below terminates in
        //     `up` or `cancel`, so the branch is unreachable rather than
        //     omitted. `willMove(toWindow:)`'s cancel is the same shape.
        //
        // Everything else — including both observational hooks and the exact
        // position of each — is reproduced.

        @discardableResult
        func down(_ p: CGPoint) -> [InputOutcome] {
            // Before anything is arbitrated, unconditionally: a place that is
            // coasting stops here. `touchesBegan` calls this ahead of `began`
            // so that a TAP stops a glide exactly as a drag does.
            onTouchDown()
            let raw = arbiter.began(at: p, timestamp: touchClock)
            // Production reports the pointer after `began` and before `flush`.
            onPointer(p)
            return deliver(raw)
        }

        @discardableResult
        func move(to p: CGPoint, dt: TimeInterval = 1.0 / 60.0) -> [InputOutcome] {
            touchClock += dt
            // One sample per event: coalescing is a fidelity of the digitizer,
            // and `deliver` still collapses the batch the way `flush` does.
            let raw = arbiter.moved(to: p, timestamp: touchClock)
            onPointer(p)
            return deliver(raw)
        }

        @discardableResult
        func up(_ p: CGPoint, dt: TimeInterval = 1.0 / 60.0) -> [InputOutcome] {
            touchClock += dt
            // `touchesEnded` drops the steering touch and reports nil BEFORE it
            // asks the arbiter for the release.
            onPointer(nil)
            return deliver(arbiter.ended(at: p, timestamp: touchClock))
        }

        @discardableResult
        func cancel() -> [InputOutcome] {
            onPointer(nil)
            return deliver(arbiter.cancelled())
        }

        // `touchesMoved`, `touchesEnded` and `touchesCancelled` all funnel
        // through `flush`, which collapses consecutive pan/scroll samples and
        // drops an empty batch. Both matter here: the collapsing is what the
        // model actually sees, and the empty-batch guard is why a sub-slop
        // press never reaches `handle` at all.
        @discardableResult
        private func deliver(_ raw: [InputOutcome]) -> [InputOutcome] {
            var batch: [InputOutcome] = []
            batch.appendCollapsingPanChanges(raw)
            guard !batch.isEmpty else { return [] }
            log += batch
            model.handle(batch)
            return batch
        }

        // MARK: Gestures

        /// A vertical drag, delivered sample by sample. Returns every outcome
        /// the whole gesture produced, in order.
        ///
        /// `stillBeforeRelease` holds the finger at the end point for longer
        /// than the arbiter's velocity window, which makes the measured release
        /// velocity exactly zero — the only way to release without launching
        /// `SkyScrollState`'s wall-clock glide, and therefore the only way a
        /// scroll assertion can be deterministic.
        @discardableResult
        func drag(fromY y0: CGFloat,
                  toY y1: CGFloat,
                  x: CGFloat = 190,
                  steps: Int = 12,
                  dt: TimeInterval = 1.0 / 60.0,
                  stillBeforeRelease: Bool = false) -> [InputOutcome] {
            var out: [InputOutcome] = []
            out += down(CGPoint(x: x, y: y0))
            for i in 1...steps {
                let k = CGFloat(i) / CGFloat(steps)
                out += move(to: CGPoint(x: x, y: y0 + (y1 - y0) * k), dt: dt)
            }
            if stillBeforeRelease { out += hold(at: CGPoint(x: x, y: y1), dt: dt) }
            out += up(CGPoint(x: x, y: y1), dt: dt)
            return out
        }

        /// A finger that stops moving before it lifts. Eight samples span
        /// 0.133 s, comfortably past `velocityWindow` (0.08 s), so the measured
        /// release velocity is exactly zero.
        @discardableResult
        func hold(at p: CGPoint, samples: Int = 8, dt: TimeInterval = 1.0 / 60.0) -> [InputOutcome] {
            var out: [InputOutcome] = []
            for _ in 0..<samples { out += move(to: p, dt: dt) }
            return out
        }

        // MARK: Frames — the world's `TimelineView` closure

        func advanceOneFrame() {
            frameDate = frameDate.addingTimeInterval(frameDt)
            model.advance(at: frameDate)
        }

        func frames(_ n: Int) {
            for _ in 0..<n { advanceOneFrame() }
        }

        /// Runs the frame clock until the camera has nothing left to step — no
        /// settle in flight AND no end-of-axis acknowledgement still fading.
        ///
        /// THE CAP FAILS, IT DOES NOT SHRUG. 20,000 frames is ~166 s of
        /// simulated time against a settle bounded at 0.65 s, so reaching it
        /// means the camera can no longer come to rest — and a loop that
        /// quietly gives up there turns a hang into a mystery a hundred lines
        /// further down.
        @discardableResult
        func runToIdle(limit: Int = 20_000,
                       file: StaticString = #filePath, line: UInt = #line) -> Int {
            var n = 0
            while !model.camera.isIdle && n < limit {
                advanceOneFrame()
                n += 1
            }
            if n >= limit {
                XCTFail("the camera never came to rest in \(limit) frames", file: file, line: line)
            }
            return n
        }

        // MARK: Layout and the map

        /// What `SkyView`'s `.onAppear` / `.onChange(of: map.stones)` does:
        /// tells the scroll state how much sky there is, through the one
        /// definition (`SkyLayout.metrics`).
        func measureSky(_ stones: [MapStone]) {
            model.skyScroll.measure(SkyLayout.metrics(stones: stones, size: size))
        }

        /// A rotation or a Split View resize: `WorldView`'s
        /// `.onChange(of: geo.size.height)` and `WorldInputView.layoutSubviews`,
        /// which are the only two writes a size change makes.
        func resize(to newSize: CGSize) {
            size = newSize
            model.camera.viewHeight = newSize.height
            arbiter.bounds = newSize
        }

        func clearLog() { log.removeAll() }
    }

    private func makeWorld() -> World { World(size: screen, frameDt: frameDt) }

    // MARK: - Synthetic maps

    // A straight path of `generations` stones. Only `generation` reaches
    // `SkyLayout.metrics`, but the whole value is the real type, so a change to
    // it stops this file rather than silently changing what is measured.
    private func path(_ generations: Int) -> [MapStone] {
        var stones: [MapStone] = []
        var parent: UUID?
        for g in 0..<generations {
            let id = UUID()
            let played = epoch.addingTimeInterval(TimeInterval(g) * 86_400)
            stones.append(MapStone(id: id, parentID: parent, generation: g, lane: 0.5,
                                   popNumbers: [1], seed: UInt64(g + 1),
                                   createdAt: played, cleared: true, lastPlayedAt: played))
            parent = id
        }
        return stones
    }

    // On an 852 pt screen `SkyLayout.metrics` yields (g - 1) * 118 - 624 points
    // of history, floored at zero: 7 generations is 84 pt — a sky one ordinary
    // drag can run out — and 12 is 674 pt, a sky no single drag can.
    private var shortSkyPath: [MapStone] { path(7) }
    private var tallSkyPath: [MapStone] { path(12) }

    private func history(_ stones: [MapStone], _ size: CGSize) -> CGFloat {
        SkyLayout.metrics(stones: stones, size: size).maxOffset
    }

    // MARK: - Reading outcome tapes

    private func scrollTranslations(_ o: [InputOutcome]) -> [CGFloat] {
        o.compactMap { if case .scrollChanged(let t) = $0 { return t } else { return nil } }
    }

    private func panTranslations(_ o: [InputOutcome]) -> [CGFloat] {
        o.compactMap { if case .panChanged(let t) = $0 { return t } else { return nil } }
    }

    private func commitDirections(_ o: [InputOutcome]) -> [WorldDirection] {
        o.compactMap { if case .commit(let d, _) = $0 { return d } else { return nil } }
    }

    private func popPoints(_ o: [InputOutcome]) -> [CGPoint] {
        o.compactMap { if case .pop(let p) = $0 { return p } else { return nil } }
    }

    private func hasAnyScroll(_ o: [InputOutcome]) -> Bool {
        o.contains {
            switch $0 {
            case .scrollBegan, .scrollChanged, .scrollEnded: return true
            default: return false
            }
        }
    }

    // The clears in `worldSettled` / `worldQuietened` are queued onto the main
    // queue on purpose (the render pass may never publish), so the flags are
    // only observably at rest after one turn of the run loop. Ours is queued
    // after theirs, so by the time it runs they have already run.
    private func drainMainQueue() {
        let hop = expectation(description: "main-queue hop")
        DispatchQueue.main.async { hop.fulfill() }
        wait(for: [hop], timeout: 5)
    }

    // MARK: - Getting somewhere, always with a real gesture

    // Never `model.handle([.commit(...)])`. The whole point of this file is
    // that the outcomes come out of the arbiter.
    private func travelUp(_ h: World, fromY y0: CGFloat = 620,
                          file: StaticString = #filePath, line: UInt = #line) {
        let out = h.drag(fromY: y0, toY: y0 - 294)
        XCTAssertEqual(commitDirections(out), [.up],
                       "the upward swipe did not commit — the fixture, not the world, is wrong",
                       file: file, line: line)
        h.runToIdle()
        drainMainQueue()
    }

    private func travelDown(_ h: World, fromY y0: CGFloat = 240,
                            file: StaticString = #filePath, line: UInt = #line) {
        let out = h.drag(fromY: y0, toY: y0 + 294)
        XCTAssertEqual(commitDirections(out), [.down],
                       "the downward swipe did not commit — the fixture, not the world, is wrong",
                       file: file, line: line)
        h.runToIdle()
        drainMainQueue()
    }

    /// Puts her at the sky, at rest, with `stones` worth of history measured and
    /// the scroll at the tip — and asserts the state it promises, so every test
    /// that starts here starts from something proved rather than assumed.
    private func atRestingSky(_ h: World, stones: [MapStone],
                              file: StaticString = #filePath, line: UInt = #line) {
        h.measureSky(stones)
        travelUp(h, file: file, line: line)
        XCTAssertEqual(h.model.place, .sky, file: file, line: line)
        XCTAssertEqual(h.model.camera.place, .sky, file: file, line: line)
        XCTAssertTrue(h.model.camera.isAtRest, file: file, line: line)
        XCTAssertTrue(h.model.camera.isIdle, file: file, line: line)
        XCTAssertEqual(h.model.skyScroll.offset, 0, accuracy: 1e-9,
                       "a sky is arrived at on its growing tip", file: file, line: line)
        h.clearLog()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 1. The wiring itself
    // ─────────────────────────────────────────────────────────────────────────

    // THE SHIPPED DEFECT, PINNED AT ITS ROOT.
    //
    // At the resting sky the two rest questions have DIFFERENT answers, and the
    // whole feature lives in the gap between them. `simActive` is false (there
    // is no field under her finger to pop); `cameraResting` is true (nothing is
    // in flight to grab). Wire the grab to the field predicate and the gap
    // closes: every touch-down at the sky becomes a transit grab, the camera
    // arms before her finger has moved a point, and `scrollRoom` — read only on
    // the slop-arming path — is never consulted at all.
    //
    // No component test can see this. It is a property of the three closures
    // together, and it is visible only if they are the closures production
    // passes and the object behind them is a real camera.
    func testAtTheRestingSkyTheFieldPredicateAndTheGrabPredicateDisagree() {
        let h = makeWorld()
        atRestingSky(h, stones: tallSkyPath)

        XCTAssertFalse(h.model.simActive,
                       "`isFieldAtRest` must be false at the sky — there is no field under her "
                       + "finger, and a touch here must never pop an orb she cannot see")
        XCTAssertTrue(h.model.cameraResting,
                      "`isCameraAtRest` must be true at the resting sky — nothing is in flight, "
                      + "so this is a touch on a place at rest and not a grab of a moving world")
        XCTAssertNotEqual(h.model.simActive, h.model.cameraResting,
                          "the two predicates agree at the resting sky, which is exactly the "
                          + "conflation that made the sky scroll unreachable on device")
        XCTAssertFalse(h.model.placeScrollRoom.isEmpty,
                       "the resting sky with 12 generations behind her must offer room")

        // And the consequence, at the only moment it can be observed: a
        // touch-down at the resting sky asks for NOTHING. No pop, no `.panBegan`.
        XCTAssertEqual(h.down(CGPoint(x: 190, y: 300)), [],
                       "touch-down at the resting sky armed the camera — the grab decision is "
                       + "reading the field predicate again")
        XCTAssertTrue(h.model.camera.isAtRest, "a press put the world into `.dragging`")
        XCTAssertFalse(h.model.worldMoving, "a press at a resting place took hit-testing away")
        XCTAssertFalse(h.model.worldAwake, "a press at a resting place woke the frame clock")
        XCTAssertEqual(h.up(CGPoint(x: 190, y: 300)), [],
                       "a touch that never armed has nothing to terminate")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 2. The sky scrolls, and the camera is not even told
    // ─────────────────────────────────────────────────────────────────────────

    // THE HEADLINE, THROUGH THE COMPOSITION. A drag the sky can absorb moves the
    // sky's own content and NOTHING else: the camera is never told there was a
    // gesture, so the world does not travel, does not wake, does not dim, and
    // the published place does not change.
    //
    // `SkyScrollTests` proves the arbiter divides the finger correctly GIVEN a
    // room. This proves production supplies that room at all.
    func testARestingSkyWithHistoryScrollsAndTheCameraIsNeverTold() {
        let h = makeWorld()
        atRestingSky(h, stones: tallSkyPath)
        let tall = history(tallSkyPath, screen)
        XCTAssertEqual(tall, 674, accuracy: 1e-9, "the fixture's sky is not the size assumed")

        let room = h.model.placeScrollRoom
        XCTAssertEqual(room.up, 0, accuracy: 1e-9, "at the tip there is nothing to return to")
        XCTAssertEqual(room.down, tall, accuracy: 1e-9)

        // 360 pt down, well inside the 674 this sky has.
        let out = h.drag(fromY: 200, toY: 560, stillBeforeRelease: true)

        XCTAssertTrue(out.contains(.scrollBegan), "the sky was never offered the drag")
        XCTAssertEqual(scrollTranslations(out).last ?? CGFloat.nan, 360 - slop, accuracy: 1e-9,
                       "the sky absorbed the wrong amount of the finger")
        XCTAssertEqual(h.model.skyScroll.offset, 360 - slop, accuracy: 1e-9,
                       "the scroll outcome never reached the sky's own state")

        XCTAssertFalse(out.contains(.panBegan),
                       "the camera was told about a gesture that never reached it — the world "
                       + "dims and the frame clock wakes for a scroll")
        XCTAssertTrue(panTranslations(out).isEmpty, "the camera was driven by the sky's scroll")
        XCTAssertTrue(commitDirections(out).isEmpty, "scrolling the sky also threw her out of it")
        XCTAssertFalse(out.contains(.cancelToRest),
                       "the camera was sent a terminator for a gesture it never began")

        XCTAssertEqual(h.model.place, .sky)
        XCTAssertEqual(h.model.camera.offset, h.model.camera.restOffset(of: .sky), accuracy: 1e-12,
                       "the world travelled during a scroll")
        XCTAssertFalse(h.model.worldMoving)
        XCTAssertFalse(h.model.worldAwake)

        // And the room the place offers has moved with her, in both directions,
        // still summing to the history it has.
        let after = h.model.placeScrollRoom
        XCTAssertEqual(after.up, 360 - slop, accuracy: 1e-9)
        XCTAssertEqual(after.up + after.down, tall, accuracy: 1e-9)
    }

    // AND THE OTHER HALF, WHICH ONLY THE COMPOSITION CAN SHOW: when the history
    // runs out, the SAME unbroken gesture hands the leftover to the camera and
    // carries her to the field. She never lifts her finger and tries again.
    //
    // The sky here is 84 pt tall, so one 294 pt drag spends 84 on the sky and
    // 200 on the world — past the 93.7 pt commit gate, which sees the LEFTOVER
    // and not the whole finger.
    func testOneUnbrokenGestureRunsTheSkyOutAndThenCarriesHerToTheField() {
        let h = makeWorld()
        atRestingSky(h, stones: shortSkyPath)
        let skyHistory = history(shortSkyPath, screen)
        XCTAssertEqual(skyHistory, 84, accuracy: 1e-9, "the fixture's sky is not the size assumed")

        let out = h.drag(fromY: 150, toY: 444)

        guard let scrollBeganAt = out.firstIndex(of: .scrollBegan) else {
            return XCTFail("the sky was never offered the drag")
        }
        guard let panBeganAt = out.firstIndex(of: .panBegan) else {
            return XCTFail("the camera never picked up the leftover — the gesture died at the end "
                           + "of the sky and she would have to lift her finger and try again")
        }
        XCTAssertLessThan(scrollBeganAt, panBeganAt,
                          "the camera was armed before the place had its first refusal")
        XCTAssertEqual(scrollTranslations(out).last ?? CGFloat.nan, skyHistory, accuracy: 1e-9,
                       "the sky absorbed more or less than the room it had")
        XCTAssertEqual(h.model.skyScroll.offset, skyHistory, accuracy: 1e-9,
                       "the sky did not come to rest at the root of the drawn tree")
        XCTAssertEqual(panTranslations(out).last ?? CGFloat.nan, 294 - slop - skyHistory,
                       accuracy: 1e-9, "the camera was given points the sky had already spent")

        // THE GATES SEE THE LEFTOVER, NOT THE WHOLE FINGER, and the fixture is
        // built so that is the only reason this commits: 200 pt of leftover
        // against a 93.7 pt gate.
        XCTAssertGreaterThan(294 - slop - skyHistory, commitDistance,
                             "the fixture no longer leaves enough leftover to clear the gate")
        XCTAssertEqual(commitDirections(out), [.down], "the gesture did not carry her home")

        // `place` is mirrored at the COMMIT instant, not on arrival.
        XCTAssertEqual(h.model.place, .field)
        XCTAssertEqual(h.model.camera.place, .field)
        XCTAssertTrue(h.model.worldMoving,
                      "the world is travelling and hit-testing was not taken away — a place's "
                      + "controls must not take the touch that is trying to catch the world")
        XCTAssertFalse(h.model.simActive,
                       "the field must stop the instant she has decided to leave it (04 §5)")

        h.runToIdle()
        drainMainQueue()
        XCTAssertTrue(h.model.camera.isAtRest)
        XCTAssertEqual(h.model.place, .field)
        XCTAssertTrue(h.model.simActive, "coming home must start the field again")
        XCTAssertTrue(h.model.placeScrollRoom.isEmpty, "the field must never offer scroll room")
    }

    // ARRIVING AT THE SKY OPENS IT ON THE GROWING TIP; LEAVING IT COSTS HER
    // NOTHING. The stones she can choose next hang off the tip, so a sky still
    // scrolled to where she was reading is a place she arrives in with no star
    // to press — but a glance back at her history on the way out is free.
    //
    // Composed, because the trigger is `WorldModel.handle` noticing `place`
    // change to `.sky`, and the state it resets belongs to a different object.
    func testArrivingAtTheSkyReturnsTheScrollToTheGrowingTip() {
        let h = makeWorld()
        atRestingSky(h, stones: shortSkyPath)
        let skyHistory = history(shortSkyPath, screen)

        // Look back 50 pt along the path (60 pt of finger, less the slop).
        h.drag(fromY: 200, toY: 260, stillBeforeRelease: true)
        XCTAssertEqual(h.model.skyScroll.offset, 50, accuracy: 1e-9)
        h.runToIdle()

        // Leave: 34 pt of sky left, then 250 pt of world.
        let out = h.drag(fromY: 150, toY: 444)
        XCTAssertEqual(commitDirections(out), [.down])
        h.runToIdle()
        drainMainQueue()
        XCTAssertEqual(h.model.place, .field)
        XCTAssertEqual(h.model.skyScroll.offset, skyHistory, accuracy: 1e-9,
                       "leaving the sky threw away where she had got to")

        // Come back.
        travelUp(h)
        XCTAssertEqual(h.model.place, .sky)
        XCTAssertEqual(h.model.skyScroll.offset, 0, accuracy: 1e-9,
                       "she arrived at the sky with no star to press")
        XCTAssertEqual(h.model.placeScrollRoom.up, 0, accuracy: 1e-9)
        XCTAssertEqual(h.model.placeScrollRoom.down, skyHistory, accuracy: 1e-9)
    }

    // A TOUCH-DOWN REACHES THE PLACE BEFORE ANYTHING IS ARBITRATED — AND A TAP
    // IS A TOUCH-DOWN.
    //
    // WHAT THIS IS FOR. The sky's glide used to be caught in
    // `SkyScrollState.began()`, which the model reaches only from
    // `.scrollBegan` — and the arbiter emits that ten points into a drag. So a
    // finger placed on a gliding sky did not freeze it (the content coasted on
    // under her for the first ~10 pt), and a TAP on a gliding sky never stopped
    // it at all, while the star she was pressing kept moving out from under
    // her. Production now fires `WorldInputView.onTouchDown` unconditionally at
    // the top of `touchesBegan`, ahead of `began`, bound by `WorldView` to
    // `WorldModel.touchWentDown()`. The harness reproduces that call in that
    // position; this test is what makes the reproduction mean something.
    //
    // WHAT IS ASSERTED. The precondition — that an ordinary flick from here
    // really would project a glide with somewhere to go and a duration to get
    // there — through the pure `projectedGlide`. Then the hook's own contract,
    // stated as what it must LEAVE ALONE: it may not move the world, arm the
    // camera, add or remove an outcome, wake a flag, or throw away where she
    // was reading. That last one is the mis-wiring most available to a future
    // reader, because `returnToTip()` also cancels a glide and would look like
    // a reasonable thing to call from here.
    //
    // WHAT DELIBERATELY IS NOT, AND WHY. That the glide actually STOPS.
    // `SkyScrollState.run(_:)` steps the offset inside an unstructured `Task`
    // that sleeps 16 ms and reads `Date()`, so the only way to observe "the
    // content did not coast on" is to let real time pass and look again. A
    // sleep on a shared CI simulator is a flake, and a flake in the suite that
    // gates every merge costs more than the assertion is worth. If the glide is
    // ever given an injectable clock, the behavioural half belongs in
    // `SkyScrollTests`, beside the rest of the scroll's proofs.
    func testATouchDownReachesThePlaceAheadOfArbitrationAndKeepsHerPlace() {
        let h = makeWorld()
        atRestingSky(h, stones: tallSkyPath)

        // Look back 240 pt along the path, released from a stationary finger,
        // so nothing is coasting yet and the state she is left in is exact.
        h.drag(fromY: 200, toY: 450, stillBeforeRelease: true)
        let reading = h.model.skyScroll.offset
        XCTAssertEqual(reading, 250 - slop, accuracy: 1e-9)
        XCTAssertGreaterThan(reading, 0, "the fixture never scrolled, so nothing is at stake")

        // THE PRECONDITION, pure and clock-free: from here an ordinary flick
        // has somewhere to coast to and a duration to coast over. That is the
        // thing a touch-down has to be able to catch.
        let flick = h.model.skyScroll.projectedGlide(velocity: -1_400)
        XCTAssertGreaterThan(flick.duration, 0,
                             "a flick from here projects no glide, so there would be nothing for "
                             + "a touch-down to catch and this test would prove nothing")
        XCTAssertLessThan(flick.offset, reading,
                          "the projected glide does not move, so the fixture is degenerate")

        // A TAP. The whole gesture is a touch-down and a release, and at the
        // resting sky it asks the arbiter for nothing at all — which is exactly
        // why arming was too late a place to catch a glide. The touch-down path
        // still ran, and it left every number where it was.
        h.clearLog()
        XCTAssertEqual(h.down(CGPoint(x: 190, y: 300)), [],
                       "a tap at the resting sky asked the arbiter for something")
        XCTAssertEqual(h.model.skyScroll.offset, reading, accuracy: 1e-12,
                       "the touch-down moved the sky's content — the hook is doing more than "
                       + "stopping a glide, and a press on the sky now costs her the place she "
                       + "was reading")
        XCTAssertTrue(h.model.camera.isAtRest, "a press put the world into `.dragging`")
        XCTAssertFalse(h.model.worldMoving, "a press took hit-testing away")
        XCTAssertFalse(h.model.worldAwake, "a press woke the frame clock")
        XCTAssertEqual(h.up(CGPoint(x: 190, y: 300)), [],
                       "a touch that never armed has nothing to terminate")
        XCTAssertEqual(h.model.skyScroll.offset, reading, accuracy: 1e-12,
                       "the release moved the sky's content")

        // The room she has in each direction is untouched, so the next gesture
        // divides exactly as this one would have.
        XCTAssertEqual(h.model.placeScrollRoom.up, reading, accuracy: 1e-9)
        XCTAssertEqual(h.model.placeScrollRoom.up + h.model.placeScrollRoom.down,
                       history(tallSkyPath, screen), accuracy: 1e-9)

        // Idempotent, and reachable exactly as `WorldView` reaches it.
        h.model.touchWentDown()
        h.model.touchWentDown()
        XCTAssertEqual(h.model.skyScroll.offset, reading, accuracy: 1e-12,
                       "`touchWentDown` is not idempotent")
        XCTAssertTrue(h.model.camera.isIdle, "`touchWentDown` woke the camera")
        XCTAssertEqual(h.model.place, .sky)

        // A DRAG's touch-down is the same touch-down, and the drag that follows
        // it still measures from where the content actually is.
        let out = h.drag(fromY: 400, toY: 340, stillBeforeRelease: true)
        XCTAssertTrue(out.contains(.scrollBegan), "the drag never reached the sky")
        XCTAssertFalse(out.contains(.panBegan), "60 pt inside 240 pt of room reached the camera")
        XCTAssertEqual(h.model.skyScroll.offset, reading - (60 - slop), accuracy: 1e-9,
                       "the gesture after a touch-down did not measure from where the sky was")

        // AND AT THE FIELD IT IS THE SAME CALL, made just as unconditionally: a
        // place with nothing coasting has nothing to catch, and the hook must
        // not come between her finger and the pop.
        let f = makeWorld()
        f.measureSky(tallSkyPath)
        let p = CGPoint(x: 190, y: 400)
        XCTAssertEqual(f.down(p), [.pop(p)],
                       "the touch-down hook came between her finger and the pop")
        XCTAssertTrue(f.model.camera.isAtRest)
        XCTAssertEqual(f.model.skyScroll.offset, 0, accuracy: 1e-12,
                       "a touch at the field moved the sky's content")
        XCTAssertEqual(f.up(p), [], "a tap that never armed has nothing to terminate")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 3. The field, and the places that do not scroll
    // ─────────────────────────────────────────────────────────────────────────

    // At the field a touch-down pops and a drag is the gesture it has always
    // been: no scroll outcomes at all, whatever the sky happens to be holding.
    // The sky is deliberately given 674 pt of history first, so the question
    // asked is the real one — does the FIELD offer room — rather than a vacuous
    // one about a sky with nothing in it.
    func testAtTheFieldATouchDownPopsAndADragNeverScrolls() {
        let h = makeWorld()
        h.measureSky(tallSkyPath)
        XCTAssertEqual(h.model.place, .field)
        XCTAssertTrue(h.model.simActive)
        XCTAssertTrue(h.model.placeScrollRoom.isEmpty,
                      "the field offered the sky's room — a drag here would scroll a sky she "
                      + "cannot see, exactly as a touch at the sky would pop a field she cannot")

        let p = CGPoint(x: 190, y: 400)
        XCTAssertEqual(h.down(p), [.pop(p)],
                       "touch-down on the resting field must emit exactly one pop, first "
                       + "(ruling 4 / R-SPIKE §7.1)")
        XCTAssertEqual(h.up(p), [], "a tap that never armed has nothing to terminate")

        h.clearLog()
        let out = h.drag(fromY: 240, toY: 534)
        XCTAssertEqual(popPoints(out).count, 1, "the drag's own touch-down lost its pop")
        XCTAssertFalse(hasAnyScroll(out), "the field produced scroll outcomes")
        XCTAssertTrue(out.contains(.panBegan))
        XCTAssertEqual(commitDirections(out), [.down], "the pop ate the swipe")
        XCTAssertEqual(h.model.skyScroll.offset, 0, accuracy: 1e-9,
                       "a drag on the field moved the sky's content")

        h.runToIdle()
        drainMainQueue()
        XCTAssertEqual(h.model.place, .journal)
        XCTAssertTrue(h.model.placeScrollRoom.isEmpty, "the journal offered the sky's room")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 4. The transit grab
    // ─────────────────────────────────────────────────────────────────────────

    // A GRAB IS A GRAB OF THE WORLD, WHEREVER IT LANDS. She reached out to
    // steady something in flight; every point of that gesture belongs to the
    // camera. It never scrolls the place under her finger — even though
    // `camera.place` here already says `.sky` and the sky is sitting on 84 pt of
    // spent history — and it never pops.
    //
    // TWO INDEPENDENT MECHANISMS AGREE, and the composition is the only place
    // both are live: the arbiter holds `.none` for a transit grab, and
    // `placeScrollRoom` refuses on `camera.isAtRest`. So the second is asserted
    // directly as well, or this test would still pass with one of them broken.
    func testATransitGrabNeverScrollsAndNeverPopsWhereverItLands() {
        let h = makeWorld()
        atRestingSky(h, stones: shortSkyPath)
        let skyHistory = history(shortSkyPath, screen)

        // Run the sky out and commit home, so the settle in flight departs a
        // sky that is still holding a scroll position.
        h.drag(fromY: 150, toY: 444)
        XCTAssertEqual(h.model.skyScroll.offset, skyHistory, accuracy: 1e-9)
        XCTAssertEqual(h.model.camera.place, .field)

        // Ten frames in: the world is genuinely in flight (the shortest settle
        // this camera will run is 0.30 s, or 36 frames at 120 Hz).
        h.frames(10)
        XCTAssertFalse(h.model.camera.isAtRest, "the settle was over before the grab could happen")
        XCTAssertTrue(h.model.worldMoving)
        XCTAssertFalse(h.model.cameraResting)
        XCTAssertTrue(h.model.placeScrollRoom.isEmpty,
                      "a world in flight offered scroll room, so a grab could be eaten by a "
                      + "scroll and the settle she reached out to steady would be lost")

        h.clearLog()
        var out = h.down(CGPoint(x: 190, y: 400))
        XCTAssertEqual(out, [.panBegan],
                       "a grab must arm the camera immediately and emit nothing else — no pop "
                       + "off a field she cannot see, no scroll")

        // 30 pt: past the slop, short of the 93.7 pt commit gate, so this
        // resolves as the UNDECIDED release a scroll could have stolen.
        for i in 1...6 { out += h.move(to: CGPoint(x: 190, y: 400 + CGFloat(i) * 5)) }
        XCTAssertFalse(hasAnyScroll(out), "a transit grab was absorbed by the place under it")
        XCTAssertEqual(h.model.skyScroll.offset, skyHistory, accuracy: 1e-9,
                       "the grab moved the sky's content")
        XCTAssertTrue(popPoints(out).isEmpty, "a grab popped an orb she cannot see")

        out += h.up(CGPoint(x: 190, y: 430))
        XCTAssertTrue(out.contains(.settleToNearest),
                      "a grab has no rest to spring back to — it settles to whichever place is "
                      + "nearer by the camera's own offset")
        XCTAssertTrue(commitDirections(out).isEmpty, "30 pt committed a journey")
        XCTAssertFalse(hasAnyScroll(out), "the release scrolled the place")

        h.runToIdle()
        drainMainQueue()

        // Wherever it landed, the world is consistent — and if it landed back at
        // the sky, that arrival opened on the tip like any other.
        XCTAssertTrue(h.model.camera.isAtRest)
        XCTAssertTrue(h.model.camera.isIdle)
        XCTAssertEqual(h.model.place, h.model.camera.place)
        XCTAssertTrue([Place.sky, .field].contains(h.model.place),
                      "the grab settled somewhere the gesture could not reach")
        XCTAssertEqual(h.model.camera.offset,
                       h.model.camera.restOffset(of: h.model.place), accuracy: 1e-9,
                       "the grab left the world between two places")
        // ── PINNING CURRENT BEHAVIOUR, NOT ENDORSING IT ────────────────────
        //
        // `WorldModel.handle` calls `skyScroll.returnToTip()` whenever the
        // published `place` CHANGES to `.sky`, and `place` is mirrored from
        // `camera.place`, which moves at the COMMIT instant. A
        // `.settleToNearest` that resolves back to the sky is such a change —
        // the commit off the sky had already set `place` to `.field` — so a
        // grab she cancels by settling home to a sky SHE NEVER LEFT throws away
        // her reading position, exactly as a real arrival does.
        //
        // That is arguably wrong (a bounce-back is not an arrival), and it is
        // recorded as a finding rather than fixed here: this file may not touch
        // production. THIS ASSERTION THEREFORE STATES WHAT THE WORLD DOES
        // TODAY. If the bounce-back is ever taught to keep her place, this line
        // is the one that must be updated — expect `skyHistory` in both
        // branches, and delete this note.
        XCTAssertEqual(h.model.skyScroll.offset,
                       h.model.place == .sky ? 0 : skyHistory, accuracy: 1e-9,
                       "an arrival at the sky must open on the tip; anywhere else must leave her "
                       + "reading position alone")
        XCTAssertFalse(h.model.worldMoving)
        XCTAssertFalse(h.model.worldAwake)
        XCTAssertFalse(h.arbiter.isTracking)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 5. The sub-slop symmetry the fix restored
    // ─────────────────────────────────────────────────────────────────────────

    // A PRESS AT A RESTING PLACE IS A PRESS, EVERYWHERE. Under the conflated
    // predicate a 6 pt press at the sky armed the camera, put the world into
    // `.dragging`, dimmed every place and woke the frame clock — while the same
    // press on the field did nothing at all.
    //
    // `WorldRegressionTests` pins this for the camera and arbiter alone. The
    // composition adds the three things only it can see: the place's own
    // content does not move either, the published flags do not latch, and the
    // journal — a place that never had a scroll — behaves identically.
    func testASubSlopPressAtAnyRestingPlaceAsksForNothing() {
        for place in [Place.field, .sky, .journal] {
            let h = makeWorld()
            h.measureSky(tallSkyPath)
            switch place {
            case .field:   break
            case .sky:     travelUp(h)
            case .journal: travelDown(h)
            }
            XCTAssertEqual(h.model.camera.place, place)

            let restingOffset = h.model.camera.offset
            let restingScroll = h.model.skyScroll.offset
            h.clearLog()

            // Downward, 6 pt — inside the 10 pt slop, and toward the journal,
            // where an excursion would have room to show rather than being
            // absorbed by the end of the axis.
            let p = CGPoint(x: 190, y: 420)
            var out = h.down(p)
            out += h.move(to: CGPoint(x: 190, y: 423))
            out += h.move(to: CGPoint(x: 190, y: 426))
            out += h.hold(at: CGPoint(x: 190, y: 426))

            let expected: [InputOutcome] = place == .field ? [.pop(p)] : []
            XCTAssertEqual(out, expected,
                           "a sub-slop press at the resting \(place) asked for something")
            XCTAssertEqual(h.up(CGPoint(x: 190, y: 426)), [],
                           "a touch that never armed had something to terminate")

            XCTAssertEqual(h.model.camera.offset, restingOffset, accuracy: 1e-12,
                           "a 6 pt press at the resting \(place) moved the world")
            XCTAssertEqual(h.model.skyScroll.offset, restingScroll, accuracy: 1e-12,
                           "a 6 pt press at the resting \(place) moved the sky's content")
            XCTAssertEqual(h.model.place, place, "a press changed the place")
            XCTAssertTrue(h.model.camera.isAtRest)
            XCTAssertTrue(h.model.camera.isIdle)
            XCTAssertFalse(h.model.worldMoving, "a press took hit-testing away")
            XCTAssertFalse(h.model.worldAwake, "a press held the frame clock awake")
            XCTAssertFalse(h.arbiter.isTracking, "the press is still being tracked")

            // And nothing appears a frame later either.
            h.frames(30)
            XCTAssertEqual(h.model.camera.offset, restingOffset, accuracy: 1e-12)
            XCTAssertFalse(h.model.worldAwake)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 6. The latches
    // ─────────────────────────────────────────────────────────────────────────

    // `worldMoving` gates hit-testing; `worldAwake` gates the pause predicate. A
    // stuck `worldMoving` takes the place's controls away from her for the rest
    // of the session; a stuck `worldAwake` holds the frame clock running
    // forever. Both are set in the touch handler and cleared on a deferred hop,
    // so what must hold at every observable instant is the IMPLICATION, checked
    // frame by frame across a whole gesture and its settle:
    //
    //     !camera.isAtRest  ⟹  worldMoving        (never pause a moving world)
    //     !camera.isIdle    ⟹  worldAwake         (never freeze a live envelope)
    //     worldMoving       ⟹  worldAwake         (the render half is weaker)
    //
    // and then both return to false, and stay there.
    func testTheLatchesRideAWholeGestureAndReturnToRest() {
        let h = makeWorld()
        h.measureSky(tallSkyPath)
        XCTAssertFalse(h.model.worldMoving)
        XCTAssertFalse(h.model.worldAwake)

        // Sampled at every point of a real gesture, not only at its ends:
        // `.panChanged` arrives at digitizer rate and the flags must be right
        // on every one of them.
        var out = h.down(CGPoint(x: 190, y: 620))
        for i in 1...12 {
            out += h.move(to: CGPoint(x: 190, y: 620 - CGFloat(i) * 24.5))
            assertLatchesConsistent(h, "during the drag, sample \(i)")
        }
        out += h.up(CGPoint(x: 190, y: 620 - 294))
        XCTAssertEqual(commitDirections(out), [.up])
        assertLatchesConsistent(h, "at the commit")
        XCTAssertTrue(h.model.worldMoving, "the commit did not take hit-testing away")
        XCTAssertTrue(h.model.worldAwake, "the commit did not wake the frame clock")

        var frames = 0
        while !h.model.camera.isIdle && frames < 20_000 {
            h.advanceOneFrame()
            frames += 1
            assertLatchesConsistent(h, "settle frame \(frames)")
        }
        XCTAssertLessThan(frames, 20_000, "the camera never came to rest")
        XCTAssertGreaterThan(frames, 30, "the settle was too short to have measured anything")
        XCTAssertTrue(h.model.camera.isAtRest)

        drainMainQueue()
        XCTAssertFalse(h.model.worldMoving,
                       "`worldMoving` stayed latched after arrival — the sky's stars are "
                       + "untappable for the rest of the session")
        XCTAssertFalse(h.model.worldAwake,
                       "`worldAwake` stayed latched after arrival — the frame clock never pauses "
                       + "again and the evening costs battery for nothing")
        XCTAssertEqual(h.model.place, .sky)
        XCTAssertEqual(h.model.place, h.model.camera.place)

        // Idle stays idle: further frames must not re-arm anything.
        h.frames(120)
        drainMainQueue()
        XCTAssertFalse(h.model.worldMoving)
        XCTAssertFalse(h.model.worldAwake)
    }

    // THE CASE THAT PROVES THE TWO FLAGS ARE TWO QUESTIONS, produced by a real
    // gesture rather than a hand-written outcome: a hard flick at the ceiling of
    // the axis. The commit cannot go anywhere, so the settle is zero-length and
    // the camera comes to REST on the same call — `worldMoving` clears on the
    // next frame — and yet an end-of-axis acknowledgement is armed, which is
    // per-frame state that must go on being stepped. If `worldAwake` did not
    // exist, or were derived from `worldMoving`, the world would pause over a
    // live glow and freeze it part-lit.
    //
    // The sky is deliberately short here, so its room is empty and the gesture
    // is the plain one; the subject is what the CAMERA does and that it reaches
    // the model.
    func testAFlickAtTheCeilingWakesTheClockWithoutMovingTheWorld() {
        let h = makeWorld()
        h.measureSky(path(3))                          // a sky with nothing to scroll
        travelUp(h)
        XCTAssertEqual(h.model.place, .sky)
        XCTAssertTrue(h.model.placeScrollRoom.isEmpty, "the fixture's sky has history it should not")

        let restingOffset = h.model.camera.offset
        h.clearLog()
        let out = h.drag(fromY: 620, toY: 326)
        XCTAssertEqual(commitDirections(out), [.up], "the flick at the ceiling did not commit")
        XCTAssertFalse(hasAnyScroll(out), "a sky with no room produced scroll outcomes")

        XCTAssertEqual(h.model.camera.place, .sky, "there is nothing above the sky")
        XCTAssertTrue(h.model.camera.isAtRest,
                      "an axis-gated commit must not put the world into motion")
        XCTAssertFalse(h.model.camera.isIdle, "no acknowledgement was armed at all")

        // `worldMoving` was set by the drag itself and clears on the frame
        // after the camera comes to rest; `worldAwake` must NOT clear with it.
        h.advanceOneFrame()
        drainMainQueue()
        XCTAssertFalse(h.model.worldMoving,
                       "hit-testing is still off after a flick that moved nothing — the sky's "
                       + "stars go dead for a third of a second after every flick at the ceiling")
        XCTAssertTrue(h.model.worldAwake,
                      "the frame clock was allowed to pause, so the acknowledgement will never be "
                      + "stepped and the glow freezes at whatever fraction it had reached")

        var frames = 0
        while !h.model.camera.isIdle && frames < 20_000 {
            h.advanceOneFrame()
            frames += 1
            XCTAssertTrue(h.model.camera.isAtRest, "the acknowledgement translated the world")
            XCTAssertFalse(h.model.worldMoving, "frame \(frames): hit-testing went off again")
            XCTAssertTrue(h.model.worldAwake, "frame \(frames): the clock was paused mid-glow")
            // The place goes on answering throughout: `placeScrollRoom` reads
            // `isAtRest`, which stays true for the whole envelope.
            XCTAssertTrue(h.model.camera.isAtRest && h.model.camera.place == .sky)
        }
        XCTAssertLessThan(frames, 20_000, "the acknowledgement never faded")
        XCTAssertGreaterThan(frames, 10, "the acknowledgement was never stepped")
        XCTAssertEqual(h.model.camera.offset, restingOffset, accuracy: 1e-12,
                       "the acknowledgement moved the world")

        drainMainQueue()
        XCTAssertFalse(h.model.worldAwake, "`worldAwake` stayed latched after the glow faded")
        XCTAssertEqual(h.model.place, .sky)
    }

    private func assertLatchesConsistent(_ h: World, _ moment: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        if !h.model.camera.isAtRest {
            XCTAssertTrue(h.model.worldMoving,
                          "\(moment): the camera is moving and `worldMoving` is false — the pause "
                          + "predicate would have frozen the world mid-settle",
                          file: file, line: line)
        }
        if !h.model.camera.isIdle {
            XCTAssertTrue(h.model.worldAwake,
                          "\(moment): the camera has state left to step and `worldAwake` is false",
                          file: file, line: line)
        }
        if h.model.worldMoving {
            XCTAssertTrue(h.model.worldAwake,
                          "\(moment): `worldMoving` without `worldAwake` — the render half must be "
                          + "strictly weaker, or the clock pauses over a travelling world",
                          file: file, line: line)
        }
        XCTAssertEqual(h.model.place, h.model.camera.place,
                       "\(moment): the published place drifted from the camera",
                       file: file, line: line)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 7. `placeScrollRoom`, over a whole journey
    // ─────────────────────────────────────────────────────────────────────────

    // The room a place offers is `.none` everywhere except a RESTING sky, and
    // both halves of that guard matter. Checked at every frame of a real round
    // trip, because the two moments easiest to get wrong are the frame after a
    // commit — `place` already says `.sky` while the world is still travelling
    // — and the frame after arrival.
    func testPlaceScrollRoomIsOfferedOnlyByARestingSky() {
        let h = makeWorld()
        h.measureSky(shortSkyPath)

        func check(_ moment: String) {
            let room = h.model.placeScrollRoom
            if h.model.camera.isAtRest && h.model.camera.place == .sky {
                XCTAssertEqual(room, h.model.skyScroll.room,
                               "\(moment): the resting sky offered something other than its room")
            } else {
                XCTAssertTrue(room.isEmpty,
                              "\(moment): room offered away from a resting sky (place "
                              + "\(h.model.camera.place), atRest \(h.model.camera.isAtRest))")
            }
        }

        check("at the field, at rest")
        XCTAssertTrue(h.model.placeScrollRoom.isEmpty)

        // Field → sky.
        var out = h.drag(fromY: 620, toY: 326)
        XCTAssertEqual(commitDirections(out), [.up])
        check("the instant of the commit — `place` is already `.sky`, the world is not")
        XCTAssertTrue(h.model.placeScrollRoom.isEmpty,
                      "a world in flight offered the sky's room, so a grab could be eaten")
        var frames = 0
        while !h.model.camera.isIdle && frames < 20_000 {
            h.advanceOneFrame()
            frames += 1
            check("sky-bound frame \(frames)")
        }
        XCTAssertLessThan(frames, 20_000, "the camera never arrived at the sky")
        drainMainQueue()
        check("arrived at the sky")
        XCTAssertFalse(h.model.placeScrollRoom.isEmpty, "the resting sky offered nothing")

        // Sky → field: 84 pt of sky, then 200 pt of world, in one gesture.
        out = h.drag(fromY: 150, toY: 444)
        XCTAssertEqual(commitDirections(out), [.down])
        check("the instant of the downward commit off the sky")
        frames = 0
        while !h.model.camera.isIdle && frames < 20_000 {
            h.advanceOneFrame()
            frames += 1
            check("field-bound frame \(frames)")
        }
        XCTAssertLessThan(frames, 20_000, "the camera never arrived at the field")
        drainMainQueue()
        check("arrived at the field")
        XCTAssertEqual(h.model.place, .field)

        // Field → journal.
        out = h.drag(fromY: 240, toY: 534)
        XCTAssertEqual(commitDirections(out), [.down])
        check("the instant of the downward commit off the field")
        frames = 0
        while !h.model.camera.isIdle && frames < 20_000 {
            h.advanceOneFrame()
            frames += 1
            check("journal-bound frame \(frames)")
        }
        XCTAssertLessThan(frames, 20_000, "the camera never arrived at the journal")
        drainMainQueue()
        check("arrived at the journal")
        XCTAssertEqual(h.model.place, .journal)
        XCTAssertTrue(h.model.placeScrollRoom.isEmpty, "the journal offered the sky's room")
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 8. The sky changes shape under her
    // ─────────────────────────────────────────────────────────────────────────

    // THE SKY MAY NEVER OFFER ROOM IT CANNOT DRAW. `SkyLayout.metrics` is the
    // one definition of how much history there is; the input layer's room and
    // the drawing's window both come from it, so the property to pin is that
    // the room production actually offers is exactly that number, at every map
    // length — including past the cap, where the store still holds every stone
    // (W08: nothing is ever deleted) and the sky simply stops drawing the
    // oldest of them.
    func testTheSkyNeverOffersMoreRoomThanItHasAsTheMapGrows() {
        let h = makeWorld()
        travelUp(h)
        XCTAssertEqual(h.model.place, .sky)

        var previousMax: CGFloat = -1
        for generations in [1, 2, 5, 6, 7, 8, 12, 20, 30, 40, 80] {
            let stones = path(generations)
            h.measureSky(stones)
            let expected = SkyLayout.metrics(stones: stones, size: screen).maxOffset
            let room = h.model.placeScrollRoom

            XCTAssertLessThanOrEqual(expected, SkyLayout.maximumHistory,
                                     "\(generations) generations escaped the history cap")
            XCTAssertEqual(room.up + room.down, expected, accuracy: 1e-9,
                           "\(generations) generations: the room offered is not the history the "
                           + "sky can actually draw")
            XCTAssertGreaterThanOrEqual(room.up, 0)
            XCTAssertGreaterThanOrEqual(room.down, 0)
            XCTAssertGreaterThanOrEqual(h.model.skyScroll.offset, 0)
            XCTAssertLessThanOrEqual(h.model.skyScroll.offset, expected + 1e-9,
                                     "the scroll sits outside the sky it can draw")
            XCTAssertGreaterThanOrEqual(expected, previousMax - 1e-9,
                                        "a longer path offered less history than a shorter one")
            previousMax = expected
        }
    }

    // GROWTH KEEPS HER WHERE SHE WAS READING; A RESIZE ONLY RE-MEASURES AND
    // RE-CLAMPS. Driven through the composition because the values that must
    // stay consistent live in three objects: the arbiter's bounds, the camera's
    // view height, and the scroll's metrics.
    func testTheScrollStaysInsideItsBoundsAsTheMapGrowsAndTheScreenResizes() {
        let h = makeWorld()
        atRestingSky(h, stones: tallSkyPath)
        let tall = history(tallSkyPath, screen)

        // All the way back along the path she has, and no further: the drag is
        // exactly the room, so the camera is never armed and stays at rest.
        h.drag(fromY: 120, toY: 120 + slop + tall, stillBeforeRelease: true)
        XCTAssertEqual(h.model.skyScroll.offset, tall, accuracy: 1e-9,
                       "the drag did not reach the root of the drawn tree")
        XCTAssertTrue(h.model.camera.isAtRest, "the drag spilled into the camera")
        XCTAssertEqual(h.model.place, .sky)

        // A stone arrives while she is looking back: she stays where she was,
        // and the sky simply has more above her.
        let longer = path(20)
        h.measureSky(longer)
        XCTAssertEqual(h.model.skyScroll.offset, tall, accuracy: 1e-9,
                       "growth moved the thing she was looking at out from under her")
        XCTAssertEqual(h.model.placeScrollRoom.up + h.model.placeScrollRoom.down,
                       history(longer, screen), accuracy: 1e-9)

        // Split View: a much shorter window. Everything is re-measured, the
        // offset is re-clamped against it, and the room still matches what can
        // be drawn.
        let small = CGSize(width: 320, height: 420)
        h.resize(to: small)
        h.measureSky(longer)
        let smallMax = SkyLayout.metrics(stones: longer, size: small).maxOffset
        XCTAssertLessThanOrEqual(h.model.skyScroll.offset, smallMax + 1e-9,
                                 "the resize left the scroll outside the sky it can draw")
        XCTAssertGreaterThanOrEqual(h.model.skyScroll.offset, 0)
        XCTAssertEqual(h.model.placeScrollRoom.up + h.model.placeScrollRoom.down,
                       smallMax, accuracy: 1e-9)
        XCTAssertEqual(h.model.camera.viewHeight, small.height,
                       "the camera was not told the world got shorter")

        // A degenerate window — shorter than the two insets — has no band to
        // draw stars in, and must offer nothing rather than phantom room.
        let sliver = CGSize(width: 320, height: 200)
        h.resize(to: sliver)
        h.measureSky(longer)
        XCTAssertTrue(h.model.placeScrollRoom.isEmpty,
                      "a window with nowhere to draw a star still offered scroll room")
        XCTAssertEqual(h.model.skyScroll.offset, 0, accuracy: 1e-9)

        // And the world is still hers afterwards.
        h.resize(to: screen)
        h.measureSky(longer)
        XCTAssertTrue(h.model.camera.isAtRest)
        XCTAssertEqual(h.model.place, .sky)
        XCTAssertFalse(h.model.placeScrollRoom.isEmpty)
        XCTAssertEqual(h.model.placeScrollRoom.up + h.model.placeScrollRoom.down,
                       history(longer, screen), accuracy: 1e-9)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 9. Cancellation leaves nothing behind
    // ─────────────────────────────────────────────────────────────────────────

    // The system takes the touch away mid-scroll (a call arrives). The sky is
    // released — with zero velocity, because there was no release to read a
    // flick from — and the camera, which was never told about this gesture at
    // all, must not be sent a terminator for it. `.dragging` is absorbing, so a
    // spurious `.cancelToRest` here is not a no-op: it starts a settle.
    func testACancelMidScrollReleasesTheSkyAndLeavesTheCameraAlone() {
        let h = makeWorld()
        atRestingSky(h, stones: tallSkyPath)

        var out = h.down(CGPoint(x: 190, y: 200))
        for i in 1...8 { out += h.move(to: CGPoint(x: 190, y: 200 + CGFloat(i) * 30)) }
        XCTAssertTrue(out.contains(.scrollBegan))
        XCTAssertFalse(out.contains(.panBegan))
        let scrolled = h.model.skyScroll.offset
        XCTAssertEqual(scrolled, 240 - slop, accuracy: 1e-9)

        XCTAssertEqual(h.cancel(), [.scrollEnded(velocity: 0)],
                       "a cancelled scroll must release the place and nothing else — a "
                       + "`.cancelToRest` here starts a settle nobody asked for")
        XCTAssertEqual(h.model.skyScroll.offset, scrolled, accuracy: 1e-9,
                       "the cancel coasted the sky on the system's motion rather than hers")
        XCTAssertTrue(h.model.camera.isAtRest)
        XCTAssertTrue(h.model.camera.isIdle)
        XCTAssertFalse(h.model.worldMoving)
        XCTAssertFalse(h.model.worldAwake)
        XCTAssertFalse(h.arbiter.isTracking, "the cancelled touch is still being tracked")

        // A second cancel is idempotent, and the next gesture starts clean and
        // measures from where the sky actually is.
        XCTAssertEqual(h.cancel(), [])
        h.clearLog()
        out = h.drag(fromY: 500, toY: 380, stillBeforeRelease: true)
        XCTAssertTrue(out.contains(.scrollBegan), "the next gesture did not start clean")
        XCTAssertEqual(h.model.skyScroll.offset, scrolled - (120 - slop), accuracy: 1e-9,
                       "the sky did not measure the new gesture from where it had come to rest")
    }

    // The other half: cancelled after the camera HAS been armed. Exactly one
    // terminator for each half, in order — one gesture, two places, both ended
    // — and the camera is not stranded in `.dragging` with no finger on it.
    func testACancelAfterTheSkyRanOutTerminatesBothHalvesExactlyOnce() {
        let h = makeWorld()
        atRestingSky(h, stones: shortSkyPath)
        let skyHistory = history(shortSkyPath, screen)

        var out = h.down(CGPoint(x: 190, y: 150))
        for i in 1...10 { out += h.move(to: CGPoint(x: 190, y: 150 + CGFloat(i) * 20)) }
        XCTAssertTrue(out.contains(.scrollBegan))
        XCTAssertTrue(out.contains(.panBegan), "the leftover never reached the camera")
        XCTAssertEqual(h.model.skyScroll.offset, skyHistory, accuracy: 1e-9)

        XCTAssertEqual(h.cancel(), [.scrollEnded(velocity: 0), .cancelToRest],
                       "a cancelled gesture that reached both halves must end both, in that "
                       + "order, exactly once")
        XCTAssertEqual(h.model.place, .sky, "a cancel changed the place")

        h.runToIdle()
        drainMainQueue()
        XCTAssertTrue(h.model.camera.isAtRest, "the camera was stranded in `.dragging`")
        XCTAssertEqual(h.model.camera.offset, h.model.camera.restOffset(of: .sky), accuracy: 1e-9,
                       "the camera did not spring home")
        XCTAssertEqual(h.model.place, .sky)
        XCTAssertFalse(h.model.worldMoving)
        XCTAssertFalse(h.model.worldAwake)
        XCTAssertEqual(h.model.skyScroll.offset, skyHistory, accuracy: 1e-9,
                       "springing the camera home also threw away her reading position")
        XCTAssertFalse(h.arbiter.isTracking)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - 10. End to end
    // ─────────────────────────────────────────────────────────────────────────

    // A LONG SESSION OF MIXED GESTURES, AND THE WORLD IS CONSISTENT AFTER EVERY
    // ONE OF THEM. Pops, sub-slop presses, scrolls, decisive swipes, drags that
    // die in the edge dead zone, settles interrupted by the next touch, and
    // system cancellations — in a seeded order, with the map growing and the
    // screen resizing underneath her.
    //
    // Everything is checked as an INVARIANT rather than as an expected value:
    // the point is not that a particular gesture does a particular thing (the
    // component tests own that) but that no ORDER of gestures can leave the
    // composition in a state it cannot get out of.
    //
    // COVERAGE IS SCRIPTED, NOT HOPED FOR. Every sixth step of the first
    // quarter runs a fixed sequence — reach the sky, scroll it, leave it, and
    // catch the settle four frames in — so the counters below are guaranteed by
    // construction rather than by the seed happening to be lucky. The map only
    // starts growing afterwards, so that sequence never depends on a sky whose
    // size the fuzz has changed.
    func testAScriptedSessionOfMixedGesturesAlwaysLeavesTheWorldConsistent() {
        let h = makeWorld()
        var stones = shortSkyPath                 // 84 pt of history, from the start
        h.measureSky(stones)

        var rng = SplitMix64(seed: 0x5645_5350_4552_0001)
        var pops = 0, scrolls = 0, commits = 0, grabs = 0, gestures = 0

        // One gesture, its preconditions read live from the same predicates
        // production reads, and every invariant that must hold across it.
        func perform(_ label: String, _ body: () -> [InputOutcome]) {
            let wasFieldAtRest = h.model.simActive
            let wasCameraResting = h.model.cameraResting
            let placeBefore = h.model.place
            h.clearLog()
            let out = body()
            gestures += 1

            // THE POP IS NEVER LOST TO A PAN, AND NEVER STOLEN FROM ONE. It is
            // emitted exactly when the field predicate said so at touch-down —
            // no more (an orb popped on a field she cannot see) and no fewer (a
            // tap eaten because a drag might have followed).
            XCTAssertEqual(popPoints(out).count, wasFieldAtRest ? 1 : 0,
                           "\(label): the field was \(wasFieldAtRest ? "" : "not ")at rest and "
                           + "\(popPoints(out).count) pops were emitted")

            // A gesture is never both. Production never offers scroll room over
            // a poppable field, and this is where that would show.
            XCTAssertFalse(!popPoints(out).isEmpty && hasAnyScroll(out),
                           "\(label): one gesture both popped an orb and scrolled the sky")

            if !wasCameraResting {
                grabs += 1
                XCTAssertFalse(hasAnyScroll(out),
                               "\(label): a transit grab was absorbed by the place under it")
                XCTAssertTrue(popPoints(out).isEmpty, "\(label): a transit grab popped something")
            }

            if hasAnyScroll(out) {
                scrolls += 1
                XCTAssertEqual(placeBefore, .sky,
                               "\(label): a place that is not the sky produced scroll outcomes")
                XCTAssertTrue(wasCameraResting,
                              "\(label): a world in flight produced scroll outcomes")
            }

            pops += popPoints(out).count
            commits += commitDirections(out).count

            XCTAssertFalse(h.arbiter.isTracking,
                           "\(label): the gesture ended and the arbiter is still tracking a touch "
                           + "— every future gesture in this session would be refused")
            assertWorldConsistent(h, "\(label), after the gesture", stones: stones)
        }

        for step in 1...240 {

            if step % 6 == 0 && step <= 60 {
                // ── The scripted interlude ──────────────────────────────────
                h.runToIdle()

                // Reach the sky. At most two ascents (journal → field → sky),
                // each one a guaranteed commit from a place with no room.
                var ascents = 0
                while h.model.camera.place != .sky && ascents < 4 {
                    perform("step \(step) ascent") { h.drag(fromY: 620, toY: 326) }
                    ascents += 1
                    h.runToIdle()
                }
                XCTAssertEqual(h.model.camera.place, .sky, "step \(step): never reached the sky")

                // Scroll it. The sky always has 84 pt, so room is never empty
                // and this always reaches the place rather than the camera.
                perform("step \(step) sky scroll") {
                    h.drag(fromY: 200, toY: 260, stillBeforeRelease: true)
                }
                h.runToIdle()

                // Leave it — 84 pt of sky at most, then 200 pt of world, so the
                // leftover always clears the commit gate.
                perform("step \(step) descent") { h.drag(fromY: 150, toY: 444) }

                // And catch the world four frames into a settle that is at
                // least thirty-six frames long.
                h.frames(4)
                perform("step \(step) transit grab") {
                    var o = h.down(CGPoint(x: 190, y: 400))
                    for i in 1...6 { o += h.move(to: CGPoint(x: 190, y: 400 + CGFloat(i) * 5)) }
                    o += h.up(CGPoint(x: 190, y: 430))
                    return o
                }
                h.runToIdle()

            } else {
                // ── The fuzz ────────────────────────────────────────────────
                //
                // Origins are kept out of the edge dead zone most of the time
                // and deliberately inside it sometimes: a swipe that begins in
                // the zone must still be silent, and silence is a state too.
                let inZone = Int.random(in: 0..<6, using: &rng) == 0
                let y0: CGFloat = inZone
                    ? CGFloat.random(in: 4...(deadZone - 4), using: &rng)
                    : CGFloat.random(in: (deadZone + 20)...(screen.height - deadZone - 20),
                                     using: &rng)
                let x = CGFloat.random(in: 30...(screen.width - 30), using: &rng)
                let kind = Int.random(in: 0..<7, using: &rng)
                let slowDy = CGFloat.random(in: -260...260, using: &rng)
                let fastSign: CGFloat = Bool.random(using: &rng) ? 1 : -1
                let fastDy = fastSign * CGFloat.random(in: 240...420, using: &rng)
                let subSlopDy = CGFloat.random(in: -9...9, using: &rng)
                let cancelDy = CGFloat.random(in: -200...200, using: &rng)

                perform("step \(step) kind \(kind)") {
                    switch kind {
                    case 0:                                    // a tap
                        var o = h.down(CGPoint(x: x, y: y0))
                        o += h.up(CGPoint(x: x, y: y0))
                        return o

                    case 1:                                    // a sub-slop press
                        var o = h.down(CGPoint(x: x, y: y0))
                        o += h.move(to: CGPoint(x: x, y: y0 + subSlopDy))
                        o += h.hold(at: CGPoint(x: x, y: y0 + subSlopDy))
                        o += h.up(CGPoint(x: x, y: y0 + subSlopDy))
                        return o

                    case 2, 3:                                 // a slow drag, no flick
                        let end = min(max(y0 + slowDy, 2), self.screen.height - 2)
                        return h.drag(fromY: y0, toY: end, x: x, steps: 14,
                                      stillBeforeRelease: true)

                    case 4, 5:                                 // a decisive swipe
                        let end = min(max(y0 + fastDy, 2), self.screen.height - 2)
                        return h.drag(fromY: y0, toY: end, x: x, steps: 10)

                    default:                                   // the system takes it away
                        var o = h.down(CGPoint(x: x, y: y0))
                        for i in 1...6 {
                            o += h.move(to: CGPoint(x: x, y: y0 + cancelDy * CGFloat(i) / 6))
                        }
                        o += h.cancel()
                        return o
                    }
                }
            }

            // A random number of frames: sometimes a full settle, sometimes an
            // interruption the next gesture will catch.
            let budget = Int.random(in: 0...90, using: &rng)
            for i in 0..<budget {
                h.advanceOneFrame()
                assertWorldConsistent(h, "step \(step), frame \(i)", stones: stones)
            }

            // AND THE DEFERRED HALF OF THE LATCHES IS LET THROUGH, PERIODICALLY.
            //
            // `worldSettled` and `worldQuietened` CLEAR their flags on a
            // main-queue hop (the render pass may never publish), and nothing
            // else in this loop yields the main actor. Without this the two
            // flags would be set once, early, and never cleared again for the
            // whole session — which would leave every latch implication below
            // vacuously true and quietly turn the longest test in the file into
            // one that cannot see the bug it is named for. It also keeps the
            // backlog of queued clears bounded rather than letting ~14,000
            // frames' worth pile up for one drain at the end.
            if step % 10 == 0 {
                drainMainQueue()
                assertWorldConsistent(h, "step \(step), after the deferred clears", stones: stones)
            }

            // The world changes shape under her from time to time — but never
            // during the scripted quarter, whose distances depend on the sky
            // staying the size it was measured at.
            if step > 60 && step % 17 == 0 {
                stones = path(stones.count + Int.random(in: 1...6, using: &rng))
                h.measureSky(stones)
                assertWorldConsistent(h, "step \(step), after the map grew", stones: stones)
            }
            if step > 60 && step % 43 == 0 {
                let heights: [CGFloat] = [852, 667, 1_024, 420]
                let height = heights[Int.random(in: 0..<heights.count, using: &rng)]
                h.resize(to: CGSize(width: 393, height: height))
                h.measureSky(stones)
                assertWorldConsistent(h, "step \(step), after the resize", stones: stones)
                h.resize(to: screen)
                h.measureSky(stones)
                assertWorldConsistent(h, "step \(step), after the resize back", stones: stones)
            }
        }

        // ── The session ends. Nothing may be stuck. ─────────────────────────
        let tail = h.runToIdle()
        XCTAssertLessThan(tail, 20_000, "the world never came to rest")
        drainMainQueue()

        print("""
        [WorldIntegration] \(gestures) gestures over 240 steps: \(pops) pops, \
        \(scrolls) scrolling gestures, \(commits) commits, \(grabs) transit grabs; \
        \(stones.count) generations of sky at the end
        """)

        XCTAssertGreaterThan(pops, 0, "the session never popped anything")
        XCTAssertGreaterThan(commits, 0, "the session never travelled")
        XCTAssertGreaterThan(scrolls, 0,
                             "the session never scrolled the sky — the feature under test was "
                             + "never exercised at all")
        XCTAssertGreaterThan(grabs, 0, "the session never caught a world in flight")

        XCTAssertTrue(h.model.camera.isAtRest, "the camera did not come to rest")
        XCTAssertTrue(h.model.camera.isIdle, "the camera still has state left to step")
        XCTAssertEqual(h.model.place, h.model.camera.place)
        XCTAssertEqual(h.model.camera.offset,
                       h.model.camera.restOffset(of: h.model.camera.place), accuracy: 1e-9,
                       "the world came to rest between two places")
        XCTAssertFalse(h.model.worldMoving,
                       "`worldMoving` is stuck true — the place's controls are disabled for the "
                       + "rest of the evening")
        XCTAssertFalse(h.model.worldAwake,
                       "`worldAwake` is stuck true — the frame clock will never pause again")
        XCTAssertFalse(h.arbiter.isTracking, "a touch is still armed with no finger on the glass")
        assertWorldConsistent(h, "at the end of the session", stones: stones)
    }

    // Everything that must be true of the composition at every observable
    // instant, whatever happened before it.
    private func assertWorldConsistent(_ h: World, _ moment: String, stones: [MapStone],
                                       file: StaticString = #filePath, line: UInt = #line) {
        // The published place is a mirror of the camera's, written in the touch
        // handler and nowhere else.
        XCTAssertEqual(h.model.place, h.model.camera.place,
                       "\(moment): the published place drifted from the camera",
                       file: file, line: line)

        // The latches never lie in the direction that costs something.
        if !h.model.camera.isAtRest {
            XCTAssertTrue(h.model.worldMoving,
                          "\(moment): the camera is moving and the pause predicate would freeze it",
                          file: file, line: line)
        }
        if !h.model.camera.isIdle {
            XCTAssertTrue(h.model.worldAwake,
                          "\(moment): the camera has state to step and the clock may pause",
                          file: file, line: line)
        }
        if h.model.worldMoving {
            XCTAssertTrue(h.model.worldAwake,
                          "\(moment): `worldMoving` outlived `worldAwake`",
                          file: file, line: line)
        }

        // The sim gate and the input layer's field predicate are ONE predicate,
        // so they cannot drift apart (R-ARCH blocking acceptance).
        XCTAssertEqual(h.model.simActive,
                       h.model.camera.isAtRest && h.model.camera.place == .field,
                       "\(moment): `simActive` drifted from its own definition",
                       file: file, line: line)
        XCTAssertEqual(h.model.cameraResting, h.model.camera.isAtRest,
                       "\(moment): `cameraResting` drifted from the camera",
                       file: file, line: line)

        // The scroll is inside the sky that can actually be drawn.
        let maxOffset = SkyLayout.metrics(stones: stones, size: h.size).maxOffset
        XCTAssertGreaterThanOrEqual(h.model.skyScroll.offset, -1e-9,
                                    "\(moment): the sky scrolled below its own tip",
                                    file: file, line: line)
        XCTAssertLessThanOrEqual(h.model.skyScroll.offset, maxOffset + 1e-9,
                                 "\(moment): the sky scrolled past what it can draw",
                                 file: file, line: line)

        // And room is only ever offered by a resting sky, and only ever the
        // room that sky actually has.
        let room = h.model.placeScrollRoom
        if h.model.camera.isAtRest && h.model.camera.place == .sky {
            XCTAssertEqual(room.up + room.down, maxOffset, accuracy: 1e-6,
                           "\(moment): the resting sky offered room it cannot draw",
                           file: file, line: line)
        } else {
            XCTAssertTrue(room.isEmpty,
                          "\(moment): room was offered away from a resting sky (place "
                          + "\(h.model.camera.place), atRest \(h.model.camera.isAtRest))",
                          file: file, line: line)
        }
    }
}
