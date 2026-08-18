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

    private func layout(_ stones: [MapStone], now: Date) -> SkyLayout {
        SkyLayout(stones: stones, activeID: stones.last?.id, anchorID: stones.last?.id,
                  now: now, size: size)
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

    // Stars stay separately tappable at every depth: the layout compresses to
    // the touch target and then stops, windowing instead of piling up.
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
}
