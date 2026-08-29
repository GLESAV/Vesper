import XCTest
@testable import Vesper

// THE SKY SCROLLS, AND ONE GESTURE DOES BOTH THINGS.
//
// Every sign question in this feature is settled by two pure functions —
// `InputArbiter.split` and `SkyScrollMetrics.room` — and this file is where
// they are held to it. The hazard being tested for is not "does it move": it
// is that a vertical drag now means two things on the same axis, and the
// arbiter has to divide one finger between them without ever letting the
// division cost her a pop, a swipe home, or a settle she reached out to
// steady.
@MainActor
final class SkyScrollTests: XCTestCase {

    private let size = CGSize(width: 393, height: 852)   // iPhone 16
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func path(_ generations: Int) -> [MapStone] {
        var stones: [MapStone] = []
        var parent: UUID? = nil
        for g in 0..<generations {
            let id = UUID()
            let played = epoch.addingTimeInterval(TimeInterval(g) * 24 * 60 * 60)
            stones.append(MapStone(id: id, parentID: parent, generation: g, lane: 0.5,
                                   popNumbers: [1], seed: UInt64(g + 1),
                                   createdAt: played, cleared: true, lastPlayedAt: played))
            parent = id
        }
        return stones
    }

    private func layout(_ stones: [MapStone], scroll: CGFloat) -> SkyLayout {
        SkyLayout(stones: stones, activeID: stones.last?.id, anchorID: stones.last?.id,
                  now: epoch.addingTimeInterval(400 * 86_400), size: size, scroll: scroll)
    }

    // MARK: - The metrics

    // A map short enough to fit does not scroll AT ALL, in either direction.
    // This is the common case — every map for its first several generations —
    // and it is what makes the whole feature invisible until it is needed.
    func testAShortTreeHasNothingToScroll() {
        for generations in [1, 2, 3, 4, 5, 6] {
            let m = SkyLayout.metrics(stones: path(generations), size: size)
            XCTAssertEqual(m.maxOffset, 0, accuracy: 0.001,
                           "\(generations) generations should fit on one screen")
            XCTAssertEqual(m.room(.up, at: 0), 0)
            XCTAssertEqual(m.room(.down, at: 0), 0)
        }
    }

    // A tree taller than the screen has exactly as much history to look back
    // through as it has root above the ceiling — no more, and no less.
    func testATallTreeOffersExactlyTheHistoryItHas() {
        let stones = path(12)
        let m = SkyLayout.metrics(stones: path(12), size: size)
        XCTAssertGreaterThan(m.maxOffset, 0, "a 12-generation tree should not fit")

        // At the tip: everything to look back through, nothing to come back to.
        XCTAssertEqual(m.room(.down, at: 0), m.maxOffset, accuracy: 0.001)
        XCTAssertEqual(m.room(.up, at: 0), 0, accuracy: 0.001)

        // At the far end: the mirror image.
        XCTAssertEqual(m.room(.down, at: m.maxOffset), 0, accuracy: 0.001)
        XCTAssertEqual(m.room(.up, at: m.maxOffset), m.maxOffset, accuracy: 0.001)

        // And scrolled all the way back, the root really is on screen.
        let far = layout(stones, scroll: m.maxOffset)
        XCTAssertTrue(far.stars.contains { $0.stone.generation == 0 },
                      "scrolling to the end did not reach the beginning of the path")
    }

    // The cap is what makes "the road disappears behind" true without W08's
    // contract being broken to achieve it. The store keeps every stone; the
    // sky simply stops offering to walk back through all of them.
    func testHistoryIsCappedHoweverLongThePathGets() {
        for generations in [40, 120, 400] {
            let m = SkyLayout.metrics(stones: path(generations), size: size)
            XCTAssertLessThanOrEqual(m.maxOffset, SkyLayout.maximumHistory + 0.001,
                                     "\(generations) generations offered an endless scroll")
            XCTAssertEqual(m.maxOffset, SkyLayout.maximumHistory, accuracy: 0.001,
                           "\(generations) generations should reach the cap")
        }
    }

    // MARK: - Where the tree hangs

    // At rest the growing tip is on screen at every depth — that is the whole
    // reason rest is the tip and not the root.
    func testAtRestTheGrowingTipIsAlwaysOnScreen() {
        for generations in [2, 8, 20, 60, 200] {
            let stones = path(generations)
            let sky = layout(stones, scroll: 0)
            let newest = stones.map(\.generation).max()!
            XCTAssertTrue(sky.stars.contains { $0.stone.generation == newest },
                          "the tip fell off screen at \(generations) generations")
        }
    }

    // Scrolling reveals OLDER generations, never newer ones. If this is
    // backwards the sky reads as reversed scrolling and nothing else about the
    // feature can be judged.
    func testScrollingBackRevealsOlderGenerations() {
        let stones = path(20)
        let m = SkyLayout.metrics(stones: stones, size: size)
        let step = m.maxOffset / 4          // small enough that the two overlap
        let atTip = layout(stones, scroll: 0)
        let backABit = layout(stones, scroll: step)

        let tipOldest = atTip.stars.map(\.stone.generation).min()!
        let backOldest = backABit.stars.map(\.stone.generation).min()!
        XCTAssertLessThan(backOldest, tipOldest,
                          "scrolling back showed newer stones, not older ones")

        // And it is a translation, not a re-layout: a stone on both screenfuls
        // has moved DOWN by exactly the scroll.
        let shared = Set(atTip.stars.map(\.stone.id))
            .intersection(backABit.stars.map(\.stone.id))
        XCTAssertFalse(shared.isEmpty, "the two screenfuls do not overlap at all")
        for id in shared {
            let a = atTip.stars.first { $0.stone.id == id }!.center.y
            let b = backABit.stars.first { $0.stone.id == id }!.center.y
            XCTAssertEqual(b - a, step, accuracy: 0.001,
                           "the sky re-laid itself out instead of scrolling")
        }
    }

    // The sky's own collision rules survive scrolling: nothing may be drawn
    // under the status bar or under the foot whisper's target at ANY offset.
    func testNoScrollPositionPutsAStarUnderTheSignage() {
        let stones = path(60)
        let m = SkyLayout.metrics(stones: stones, size: size)
        let bands = FieldLayout(size: size, safeTop: 59, safeBottom: 34, whisperBand: 44)
        for step in 0...20 {
            let sky = layout(stones, scroll: m.maxOffset * CGFloat(step) / 20)
            XCTAssertFalse(sky.stars.isEmpty, "offset \(step) drew an empty sky")
            for star in sky.stars {
                XCTAssertGreaterThanOrEqual(star.center.y - SkyLayout.starRadius, bands.safeTop)
                XCTAssertLessThanOrEqual(star.center.y + SkyLayout.starRadius,
                                         bands.footWhisperTop)
            }
        }
    }

    // Out-of-range offsets cannot draw a sky nobody could have scrolled to.
    func testTheLayoutClampsAnImpossibleScroll() {
        let stones = path(12)
        let m = SkyLayout.metrics(stones: stones, size: size)
        let below = layout(stones, scroll: -5_000)
        let above = layout(stones, scroll: 50_000)
        XCTAssertEqual(below.stars.map(\.center.y), layout(stones, scroll: 0).stars.map(\.center.y))
        XCTAssertEqual(above.stars.map(\.center.y),
                       layout(stones, scroll: m.maxOffset).stars.map(\.center.y))
    }

    // MARK: - The split

    // The two halves always sum back to the finger. Anything else is points
    // invented or lost between her hand and the glass.
    func testTheSplitAlwaysSumsBackToTheFinger() {
        let rooms = [ScrollRoom.none,
                     ScrollRoom(up: 120, down: 0),
                     ScrollRoom(up: 0, down: 300),
                     ScrollRoom(up: 90, down: 400)]
        for room in rooms {
            for t in stride(from: CGFloat(-900), through: 900, by: 7) {
                let (scroll, pan) = InputArbiter.split(translation: t, room: room)
                XCTAssertEqual(scroll + pan, t, accuracy: 0.000_1,
                               "\(room) at \(t) invented or lost points")
                // Neither half may ever oppose the finger.
                XCTAssertTrue(scroll == 0 || (scroll < 0) == (t < 0))
                XCTAssertTrue(pan == 0 || (pan < 0) == (t < 0))
            }
        }
    }

    // First refusal, and only up to the room: the place absorbs everything it
    // can and the world gets the leftover, never the other way round.
    func testThePlaceGetsFirstRefusalAndOnlyUpToItsRoom() {
        let room = ScrollRoom(up: 100, down: 250)

        // Inside the room, the world does not move at all.
        XCTAssertEqual(InputArbiter.split(translation: -60, room: room).pan, 0)
        XCTAssertEqual(InputArbiter.split(translation: 200, room: room).pan, 0)

        // Past it, the place is full and the rest is the world's.
        let over = InputArbiter.split(translation: 400, room: room)
        XCTAssertEqual(over.scroll, 250, accuracy: 0.000_1)
        XCTAssertEqual(over.pan, 150, accuracy: 0.000_1)

        // A place with no room is the identity — the pre-scroll gesture,
        // unchanged, which is what every place but the sky gets.
        for t in [CGFloat(-500), -1, 0, 1, 500] {
            let (scroll, pan) = InputArbiter.split(translation: t, room: .none)
            XCTAssertEqual(scroll, 0)
            XCTAssertEqual(pan, t)
        }
    }

    // Overshoot and come back: the split unwinds in the order it was spent,
    // with no hysteresis. This is why the room is captured once per gesture
    // and the split is a pure function of the cumulative translation.
    func testBackingUpUnwindsThePanBeforeTheScroll() {
        let room = ScrollRoom(up: 0, down: 200)
        let out = InputArbiter.split(translation: 320, room: room)
        XCTAssertEqual(out.pan, 120, accuracy: 0.000_1)

        // Halfway back: the world has come home and the place is still full.
        let back = InputArbiter.split(translation: 200, room: room)
        XCTAssertEqual(back.pan, 0, accuracy: 0.000_1)
        XCTAssertEqual(back.scroll, 200, accuracy: 0.000_1)

        // All the way back to where it started: nothing anywhere.
        let home = InputArbiter.split(translation: 0, room: room)
        XCTAssertEqual(home.scroll, 0)
        XCTAssertEqual(home.pan, 0)
    }

    // MARK: - The gesture, end to end

    // THE PRODUCTION SHAPE, and that is the point of this fixture. At the
    // resting sky the shipped composition supplies `isFieldAtRest` FALSE (no
    // orb to pop there) and `isCameraAtRest` TRUE (nothing is in flight).
    // The original fixture said `isFieldAtRest: { true }` — a state in which
    // production never offers scroll room — and so the whole suite proved
    // the split's math while never once driving the wiring the app ships.
    // That wiring was broken: the arbiter decided the transit grab from
    // `!isFieldAtRest()`, so every touch at the resting sky armed the camera
    // at touch-down and `scrollRoom` was never queried. These tests now run
    // the shipped shape and would catch that regression.
    private func arbiter(room: ScrollRoom) -> InputArbiter {
        InputArbiter(bounds: size,
                     isFieldAtRest: { false },
                     isCameraAtRest: { true },
                     scrollRoom: { room })
    }

    /// Drags from `from` to `to` over `duration`, in `steps`, and returns
    /// every outcome in order.
    private func drag(_ a: inout InputArbiter, from: CGFloat, to: CGFloat,
                      duration: TimeInterval = 0.30, steps: Int = 12) -> [InputOutcome] {
        var out: [InputOutcome] = []
        out += a.began(at: CGPoint(x: 190, y: from), timestamp: 0)
        for i in 1...steps {
            let k = CGFloat(i) / CGFloat(steps)
            let t = duration * Double(i) / Double(steps)
            out += a.moved(to: CGPoint(x: 190, y: from + (to - from) * k), timestamp: t)
        }
        out += a.ended(at: CGPoint(x: 190, y: to), timestamp: duration)
        return out
    }

    private func commits(_ outcomes: [InputOutcome]) -> [WorldDirection] {
        outcomes.compactMap { if case .commit(let d, _) = $0 { return d } else { return nil } }
    }

    private func lastScroll(_ outcomes: [InputOutcome]) -> CGFloat? {
        outcomes.reversed().compactMap {
            if case .scrollChanged(let t) = $0 { return t } else { return nil }
        }.first
    }

    // THE HEADLINE. A drag the sky can absorb scrolls the sky and does NOT
    // throw her out of it — and the camera is never even told there was a
    // gesture, so the world does not dim, wake or travel behind it.
    func testADragTheSkyCanAbsorbScrollsAndDoesNotLeaveTheSky() {
        var a = arbiter(room: ScrollRoom(up: 0, down: 600))

        // Touch-down at the resting sky asks for nothing: no pop (there is no
        // field under her finger) and no grab (nothing is in flight). The
        // regression this pins: the conflated predicate armed the camera
        // right here, before the finger had moved a point.
        XCTAssertEqual(a.began(at: CGPoint(x: 190, y: 200), timestamp: 0), [])
        _ = a.ended(at: CGPoint(x: 190, y: 200), timestamp: 0.05)

        let out = drag(&a, from: 200, to: 560)          // 360 pt down, well inside 600

        XCTAssertTrue(out.contains { if case .scrollBegan = $0 { return true }; return false })
        XCTAssertEqual(lastScroll(out) ?? 0, 350, accuracy: 0.001)   // 360 less the slop
        XCTAssertTrue(commits(out).isEmpty, "scrolling the sky also left it")
        XCTAssertFalse(out.contains { if case .panBegan = $0 { return true }; return false },
                       "the camera was told about a gesture that never reached it")
        XCTAssertFalse(out.contains { if case .cancelToRest = $0 { return true }; return false },
                       "the camera was sent a terminator for a gesture it never began")
        XCTAssertTrue(out.contains { if case .scrollEnded = $0 { return true }; return false })
    }

    // AND THE OTHER HALF: one unbroken gesture walks the sky back to its root
    // and then carries her out of it. She never has to lift and try again.
    func testOneGestureScrollsToTheEndAndThenTravels() {
        var a = arbiter(room: ScrollRoom(up: 0, down: 120))
        let out = drag(&a, from: 120, to: 700)          // 580 pt: 120 of sky, then 450 of world

        XCTAssertEqual(lastScroll(out) ?? 0, 120, accuracy: 0.001, "the sky did not fill up")
        XCTAssertTrue(out.contains { if case .panBegan = $0 { return true }; return false },
                      "the camera never picked up the leftover")
        XCTAssertEqual(commits(out), [.down], "the gesture did not carry her home")
    }

    // The distance gate sees the LEFTOVER. A drag that only just runs the sky
    // out has not asked to leave it, however far her finger travelled.
    func testRunningTheSkyOutByAHairDoesNotCommit() {
        // 11% of 852 is ~94 pt, so 40 pt of leftover cannot commit.
        var a = arbiter(room: ScrollRoom(up: 0, down: 400))
        let out = drag(&a, from: 100, to: 550)          // 450 pt: 400 sky + 40 leftover
        XCTAssertEqual(lastScroll(out) ?? 0, 400, accuracy: 0.001)
        XCTAssertTrue(commits(out).isEmpty, "40 pt past the end of the sky left it")
        XCTAssertTrue(out.contains { if case .cancelToRest = $0 { return true }; return false },
                      "the camera was left mid-drag with nothing to end it")
    }

    // A place with no room behaves EXACTLY as it did before this feature
    // existed — no scroll outcomes at all, and the commit unchanged.
    func testAPlaceWithNoRoomIsTheGestureItAlwaysWas() {
        var a = arbiter(room: .none)
        let out = drag(&a, from: 700, to: 200)          // 500 pt up, fast
        XCTAssertEqual(commits(out), [.up])
        XCTAssertFalse(out.contains {
            switch $0 {
            case .scrollBegan, .scrollChanged, .scrollEnded: return true
            default: return false
            }
        }, "a place with no room produced scroll outcomes")
    }

    // A TRANSIT GRAB IS A GRAB OF THE WORLD. Every point of it belongs to the
    // camera, however much room the place would have offered at rest: she
    // reached out to steady something in flight, and a scroll that ate that
    // gesture would eat the settle with it.
    func testATransitGrabIsNeverScrolled() {
        var a = InputArbiter(bounds: size,
                             isFieldAtRest: { false },
                             isCameraAtRest: { false },
                             scrollRoom: { ScrollRoom(up: 800, down: 800) })
        // Deliberately short of the commit gates (11% of 852 is ~94 pt), so
        // what this asserts is the UNDECIDED release — the case where a
        // scroll, if one had been allowed to eat the gesture, would have
        // stolen a settle she reached out to steady.
        let out = drag(&a, from: 400, to: 430, duration: 0.5)
        XCTAssertFalse(out.contains {
            switch $0 {
            case .scrollBegan, .scrollChanged, .scrollEnded: return true
            default: return false
            }
        }, "a transit grab was absorbed by the place")
        XCTAssertTrue(out.contains { if case .panBegan = $0 { return true }; return false })
        XCTAssertTrue(out.contains { if case .settleToNearest = $0 { return true }; return false })
    }

    // RULING 4 IS UNTOUCHED. The pop still comes first, unconditionally, and
    // no amount of scroll room can suppress it. This is a mechanism-level
    // property (production never offers scroll room over a poppable field),
    // so it gets its own both-at-rest fixture rather than the sky-shaped one.
    func testScrollRoomNeverCostsAPop() {
        var a = InputArbiter(bounds: size,
                             isFieldAtRest: { true },
                             isCameraAtRest: { true },
                             scrollRoom: { ScrollRoom(up: 800, down: 800) })
        let out = drag(&a, from: 400, to: 700)
        guard case .pop = out.first else {
            return XCTFail("the pop was not emitted first, or at all")
        }
    }

    // Consecutive scroll samples collapse to the newest, exactly as pan
    // samples do — and the two never collapse into each other.
    func testScrollSamplesCollapseButNotAcrossPanSamples() {
        var batch: [InputOutcome] = []
        batch.appendCollapsingPanChanges([.scrollChanged(translation: 1),
                                          .scrollChanged(translation: 2),
                                          .scrollChanged(translation: 3)])
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch, [.scrollChanged(translation: 3)])

        batch.appendCollapsingPanChanges([.panChanged(translation: 9),
                                          .scrollChanged(translation: 4)])
        XCTAssertEqual(batch, [.scrollChanged(translation: 3),
                               .panChanged(translation: 9),
                               .scrollChanged(translation: 4)])
    }

    // MARK: - The state

    func testTheStateTracksTheGestureAndStaysInBounds() {
        let state = SkyScrollState()
        state.measure(SkyScrollMetrics(history: 500))
        XCTAssertEqual(state.offset, 0, "a sky opens on the tip")

        state.began()
        state.scrolled(by: 200)
        XCTAssertEqual(state.offset, 200, accuracy: 0.001)
        state.scrolled(by: 9_000)
        XCTAssertEqual(state.offset, 500, accuracy: 0.001, "the state ran past its own end")
        state.scrolled(by: -9_000)
        XCTAssertEqual(state.offset, 0, accuracy: 0.001)
    }

    // A flick coasts, and coasts in the direction of the finger.
    func testAFlickGlidesAndStaysInBounds() {
        let state = SkyScrollState()
        state.measure(SkyScrollMetrics(history: 900))
        state.began()
        state.scrolled(by: 300)

        let glide = state.ended(velocity: 1_200)        // a downward flick
        XCTAssertGreaterThan(glide.offset, 300, "the flick did not carry")
        XCTAssertGreaterThan(glide.duration, 0)
        XCTAssertLessThanOrEqual(glide.duration, SkyScrollState.glideDuration)

        // And it can never coast out of bounds.
        state.began()
        let far = state.ended(velocity: 40_000)
        XCTAssertEqual(far.offset, 900, accuracy: 0.001)

        // A release that was already still does not animate at all.
        let still = state.projectedGlide(velocity: 0)
        XCTAssertEqual(still.duration, 0)
    }

    // Growth keeps her at the tip; a scroll she chose is only re-clamped.
    func testMeasuringKeepsHerWhereSheWasAndTheTipWhereItIs() {
        let state = SkyScrollState()
        state.measure(SkyScrollMetrics(history: 400))
        state.began()
        state.scrolled(by: 400)
        XCTAssertEqual(state.offset, 400, accuracy: 0.001)

        // The tree grows: her offset is measured from the tip and survives.
        state.measure(SkyScrollMetrics(history: 900))
        XCTAssertEqual(state.offset, 400, accuracy: 0.001)

        // The tree is shorter than her offset (a smaller screen, say): clamped.
        state.measure(SkyScrollMetrics(history: 150))
        XCTAssertEqual(state.offset, 150, accuracy: 0.001)

        // And arriving always opens on the tip.
        state.returnToTip()
        XCTAssertEqual(state.offset, 0)
    }
}
