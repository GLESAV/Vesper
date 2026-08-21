import XCTest
@testable import Vesper

// The sky's placement, which W08 made load-bearing.
//
// While the map was pruned every three days it was never more than a couple
// of generations tall, so nothing here could go wrong in a way anyone would
// see. Now that history accrues forever, this layout is the ONLY thing
// bounding what the sky draws — "the road disappears behind" is produced
// here, by windowing, rather than in the store by deletion.
final class SkyLayoutTests: XCTestCase {

    private let size = CGSize(width: 393, height: 852)   // iPhone 16
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// A straight walked path `generations` deep, each stone played a day
    /// apart so the oldest are genuinely settled.
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

    /// The sky AS SHE ARRIVES IN IT — scroll at rest, which is the growing
    /// tip (see `SkyScroll.swift`). Every test in this file is about the
    /// screenful she is handed; what happens when she scrolls away from it is
    /// `SkyScrollTests`.
    private func layout(_ stones: [MapStone], now: Date) -> SkyLayout {
        SkyLayout(stones: stones, activeID: stones.last?.id, anchorID: stones.last?.id,
                  now: now, size: size, scroll: 0)
    }

    // MARK: - The window

    // THE FAILURE W08 WOULD OTHERWISE HAVE SHIPPED. The ceiling used to be
    // `starRadius` (~11 pt), so a tall map drew stars under the status bar and
    // behind the Dynamic Island, where a 44 pt target is not reliably
    // tappable. Pruning hid it by keeping every map short; accrual would have
    // exposed it within a few weeks of ordinary play.
    func testNoStarIsEverDrawnAboveTheSkysCeilingHoweverLongThePathIs() {
        for generations in [2, 8, 20, 60, 200] {
            let stones = path(generations)
            let sky = layout(stones, now: epoch.addingTimeInterval(TimeInterval(generations) * 86_400))
            XCTAssertFalse(sky.stars.isEmpty, "\(generations) generations placed nothing at all")
            for star in sky.stars {
                XCTAssertGreaterThanOrEqual(
                    star.center.y, SkyLayout.topInset,
                    "a star at y=\(star.center.y) is under the status bar (\(generations) generations)"
                )
                XCTAssertLessThanOrEqual(
                    star.center.y, size.height - SkyLayout.bottomInset,
                    "a star is under the foot whisper's target"
                )
            }
        }
    }

    // Windowing must never cost her the place she is standing, or the roads
    // she can actually take next — those are what the map leads with.
    func testTheAnchorAndTheNewestGenerationAreAlwaysOnScreen() {
        for generations in [2, 20, 200] {
            let stones = path(generations)
            let sky = layout(stones, now: epoch.addingTimeInterval(TimeInterval(generations) * 86_400))
            let newest = stones.map(\.generation).max()!
            XCTAssertTrue(sky.stars.contains { $0.stone.generation == newest },
                          "the newest generation fell out of the window (\(generations))")
            XCTAssertTrue(sky.stars.contains { $0.isAnchor },
                          "the anchor fell out of the window (\(generations))")
        }
    }

    // Stars stay separately tappable at every depth. The layout used to
    // compress the row gap to fit and stop at the touch target; since the sky
    // scrolls it does not compress at all, and the gap is simply constant —
    // which is a stronger version of the same guarantee.
    func testStarsStaySeparatelyTappableAtEveryDepth() {
        for generations in [2, 8, 20, 60, 200] {
            let sky = layout(path(generations),
                             now: epoch.addingTimeInterval(TimeInterval(generations) * 86_400))
            XCTAssertGreaterThanOrEqual(sky.rowSpacing, SkyLayout.minimumSeparation,
                                        "rows compressed below the touch target (\(generations))")
        }
    }

    // MARK: - Settling

    // The visible consequence of W08: the old part of a long path is drawn as
    // the map's memory rather than not drawn at all.
    func testAnOldPathIsDrawnAsTraceRatherThanNotDrawn() {
        let stones = path(12)
        let sky = layout(stones, now: epoch.addingTimeInterval(40 * 24 * 60 * 60))
        XCTAssertTrue(sky.stars.contains { $0.isSettled },
                      "a 40-day-old path had no settled stars — the trace is missing")
        XCTAssertTrue(sky.roads.contains { $0.tier == .settled },
                      "the walked road left no constellation line behind it")
    }

    // Settling is a reading of the stone's dates, never a write. Two layouts
    // over the same stones at different times must differ only in settling.
    func testSettlingIsDerivedAndNeverMutatesTheMap() {
        let stones = path(6)
        let fresh = layout(stones, now: epoch.addingTimeInterval(60))
        let old = layout(stones, now: epoch.addingTimeInterval(400 * 24 * 60 * 60))

        XCTAssertEqual(fresh.stars.map(\.stone.id), old.stars.map(\.stone.id),
                       "the set of stones on screen changed with the clock alone")
        XCTAssertTrue(old.stars.allSatisfy(\.isSettled),
                      "400 days on, every one of these should be trace")
        XCTAssertFalse(fresh.stars.contains(where: \.isSettled),
                       "nothing settles a minute into the journey")
    }

    // MARK: - The tree grows downward (the axis flip)

    // What this replaced: the NEWEST stone was pinned to the bottom edge and
    // everything older climbed away above it, so the map slid upward as she
    // played and the beginning of her journey drifted off the ceiling.
    // Progression moved up and away — the opposite of growth.
    //
    // AMENDED BY THE SCROLL, IN ITS SECOND HALF ONLY. "Older is above newer"
    // is the axis and it is unconditional. "The root hangs from the ceiling"
    // was only ever true because the layout squashed every map into one
    // screenful; now that the sky scrolls, it is true exactly while the tree
    // FITS, and a taller tree hangs by its tip from the foot instead — with
    // the root above the ceiling, which is precisely the history there is to
    // scroll back through. Both cases are asserted rather than one being
    // dropped, because the interesting failure is the layout picking the
    // wrong one of the two.
    func testTheOldestVisibleGenerationSitsAtTheTop() {
        for generations in [2, 5, 12] {
            let stones = path(generations)
            let sky = layout(stones, now: epoch.addingTimeInterval(TimeInterval(generations) * 86_400))
            let byGeneration = Dictionary(grouping: sky.stars, by: \.stone.generation)
            let oldestShown = byGeneration.keys.min()!
            let newestShown = byGeneration.keys.max()!
            let yOldest = byGeneration[oldestShown]!.first!.center.y
            let yNewest = byGeneration[newestShown]!.first!.center.y
            XCTAssertLessThan(yOldest, yNewest,
                              "the tree is upside down at \(generations) generations")

            if SkyLayout.metrics(stones: stones, size: size).maxOffset == 0 {
                XCTAssertEqual(yOldest, SkyLayout.topInset, accuracy: 0.5,
                               "a tree that fits is not hanging from the top")
                XCTAssertEqual(oldestShown, 0,
                               "a tree that fits should be showing its root")
            } else {
                // Pinned by the tip instead. The topmost row on screen is the
                // first one that cleared the ceiling, so it is within one row
                // gap of it — anything more would be a band of wasted sky.
                XCTAssertGreaterThanOrEqual(yOldest, SkyLayout.topInset)
                XCTAssertLessThan(yOldest, SkyLayout.topInset + sky.rowSpacing,
                                  "a gap opened under the ceiling at \(generations)")
                XCTAssertEqual(yNewest, size.height - SkyLayout.bottomInset, accuracy: 0.5,
                               "the tip is not resting on the foot")
            }
        }
    }

    // A young map should be a sapling at the top with room to grow into,
    // not two stones huddled at the bottom of an empty sky.
    func testAYoungMapHangsFromTheTopWithRoomBeneathIt() {
        let sky = layout(path(2), now: epoch.addingTimeInterval(2 * 86_400))
        for star in sky.stars {
            XCTAssertLessThan(star.center.y, size.height / 2,
                              "a two-stone map should sit high, with room to grow")
        }
    }

    // The growing tip must stay in view however deep the path gets, or she
    // loses the one stone she is actually standing on.
    func testTheNewestGenerationIsAlwaysOnScreenAsTheTreeGrows() {
        for generations in [2, 8, 20, 60, 200] {
            let stones = path(generations)
            let sky = layout(stones, now: epoch.addingTimeInterval(TimeInterval(generations) * 86_400))
            let newest = stones.map(\.generation).max()!
            XCTAssertTrue(sky.stars.contains { $0.stone.generation == newest },
                          "the growing tip fell off screen at \(generations) generations")
        }
    }

    // Branches taper: thick at the trunk, fine at the tips. That taper is
    // most of what makes this read as grown rather than as a flowchart.
    func testBranchesTaperFromTrunkToTip() {
        let sky = layout(path(10), now: epoch.addingTimeInterval(10 * 86_400))
        guard sky.roads.count > 2 else { return XCTFail("no branches to measure") }
        let first = sky.roads.first!.width
        let last = sky.roads.last!.width
        XCTAssertGreaterThan(first, last, "the trunk is no thicker than the twigs")
        for road in sky.roads {
            XCTAssertGreaterThan(road.width, 0)
            XCTAssertLessThanOrEqual(road.width, 4)
        }
    }

    // MARK: - No collisions in the sky either

    // The sky's own signage is the foot whisper ("the field"); a star under
    // it would have its tap taken, exactly as on the gameplay screen.
    func testNoStarCanReachTheFootWhispersTarget() {
        for generations in [2, 8, 20, 60, 200] {
            let sky = layout(path(generations),
                             now: epoch.addingTimeInterval(TimeInterval(generations) * 86_400))
            let bands = FieldLayout(size: size, safeTop: 59, safeBottom: 34, whisperBand: 44)
            for star in sky.stars {
                XCTAssertLessThanOrEqual(star.center.y + SkyLayout.starRadius,
                                         bands.footWhisperTop,
                                         "a star reached the foot whisper at \(generations)")
                XCTAssertGreaterThanOrEqual(star.center.y - SkyLayout.starRadius,
                                            bands.safeTop,
                                            "a star climbed under the status bar")
            }
        }
    }
}