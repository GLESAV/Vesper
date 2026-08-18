import XCTest
@testable import Vesper

// The Path's contract (docs/pop_map.md): one stone to start, clearing opens
// 1–3 roads, each stone carries 1–3 pops distinct from its parent's,
// generation is deterministic per seed, and the road behind fades after
// three days — never the stone you stand on or the roads ahead of it.
final class MapStoreTests: XCTestCase {

    private func freshStore(now: @escaping () -> Date = Date.init) -> MapStore {
        let suite = "vesper.tests.map.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return MapStore(defaults: defaults, now: now)
    }

    // MARK: - Genesis

    func testMapBeginsAsASingleStone() {
        let store = freshStore()
        store.ensureGenesis(unlocked: [1])
        XCTAssertEqual(store.stones.count, 1)
        let genesis = store.stones[0]
        XCTAssertNil(genesis.parentID)
        XCTAssertEqual(genesis.generation, 0)
        XCTAssertFalse(genesis.cleared)
        XCTAssertTrue((1...3).contains(genesis.popNumbers.count))
        XCTAssertNil(store.activeStoneID)
    }

    func testEnsureGenesisIsIdempotent() {
        let store = freshStore()
        store.ensureGenesis(unlocked: [1])
        let first = store.stones[0].id
        store.ensureGenesis(unlocked: [1])
        XCTAssertEqual(store.stones.map(\.id), [first])
    }

    // MARK: - Clearing opens roads

    func testClearingOpensOneToThreeRoadsAhead() {
        let store = freshStore()
        store.ensureGenesis(unlocked: Set(1...20))
        let genesis = store.stones[0]
        store.setActive(genesis.id)

        let roads = store.recordClear(unlocked: Set(1...20))
        XCTAssertTrue((1...3).contains(roads.count))
        for road in roads {
            XCTAssertEqual(road.parentID, genesis.id)
            XCTAssertEqual(road.generation, 1)
            XCTAssertTrue((1...3).contains(road.popNumbers.count))
            XCTAssertTrue((0.08...0.92).contains(road.lane))
            for n in road.popNumbers {
                XCTAssertNotNil(PopCatalog.byNumber[n], "stone pops must exist in the catalog")
            }
        }
        XCTAssertTrue(store.stones.first { $0.id == genesis.id }!.cleared)

        // replaying a cleared stone never duplicates its roads
        XCTAssertTrue(store.recordClear(unlocked: Set(1...20)).isEmpty)
    }

    func testRoadsCarryPopsDistinctFromTheirParent() {
        let store = freshStore()
        store.ensureGenesis(unlocked: Set(1...60))
        let genesis = store.stones[0]
        store.setActive(genesis.id)
        let roads = store.recordClear(unlocked: Set(1...60))
        var seen = Set(genesis.popNumbers)
        for road in roads {
            XCTAssertTrue(seen.isDisjoint(with: road.popNumbers),
                          "each stone's pops are unique against its parent and siblings")
            seen.formUnion(road.popNumbers)
        }
    }

    // MARK: - Generation rules (pure, deterministic)

    func testGenerationIsDeterministicPerSeed() {
        var a = SplitMix64(seed: 7)
        var b = SplitMix64(seed: 7)
        XCTAssertEqual(PopMapGen.branchCount(using: &a), PopMapGen.branchCount(using: &b))
        XCTAssertEqual(
            PopMapGen.popSet(unlocked: Array(1...30), locked: Array(31...100),
                             avoiding: [1, 2], using: &a),
            PopMapGen.popSet(unlocked: Array(1...30), locked: Array(31...100),
                             avoiding: [1, 2], using: &b))
        XCTAssertEqual(PopMapGen.lanes(from: 0.5, count: 2, using: &a),
                       PopMapGen.lanes(from: 0.5, count: 2, using: &b))
    }

    func testPopSetsStayInsideTheRules() {
        for seed in 0..<60 {
            var rng = SplitMix64(seed: UInt64(seed))
            let set = PopMapGen.popSet(unlocked: Array(1...30), locked: Array(31...100),
                                       avoiding: Set(1...10), using: &rng)
            XCTAssertTrue((1...3).contains(set.count))
            XCTAssertEqual(Set(set).count, set.count, "no duplicate pops on one stone")
            for n in set {
                XCTAssertFalse((1...10).contains(n), "avoided pops must not appear")
            }
        }
    }

    func testVisitorsFromTheLockedBookAppearSometimes() {
        var visits = 0
        for seed in 0..<80 {
            var rng = SplitMix64(seed: UInt64(seed))
            let set = PopMapGen.popSet(unlocked: [1, 2, 3], locked: Array(50...60),
                                       avoiding: [], using: &rng)
            if set.contains(where: { $0 >= 50 }) { visits += 1 }
        }
        XCTAssertGreaterThan(visits, 8, "locked visitors should visit now and then")
        XCTAssertLessThan(visits, 70, "…but most stones stay within the collection")
    }

    func testEmptyCollectionStillYieldsAPlayableStone() {
        var rng = SplitMix64(seed: 3)
        let set = PopMapGen.popSet(unlocked: [], locked: [], avoiding: [], using: &rng)
        XCTAssertEqual(set, [PopCatalog.classic.number])
    }

    // MARK: - The road behind settles, and is never removed (W08)

    // The contract `docs/pop_map.md` has always stated and the code did not
    // keep: "no stone or road is ever removed". What stood here asserted the
    // opposite — that the genesis stone and the untaken forks were GONE after
    // three days — because the store deleted them. That was the deletion W08
    // replaced with a settle-state transition.
    func testNothingIsEverRemovedFromTheMapHoweverLongSheIsAway() {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = freshStore(now: { now })
        store.ensureGenesis(unlocked: Set(1...20))
        let genesis = store.stones[0]
        store.setActive(genesis.id)
        let roads = store.recordClear(unlocked: Set(1...20))

        store.setActive(roads[0].id)
        let ahead = store.recordClear(unlocked: Set(1...20))
        let everything = store.stones.map(\.id)

        // A season away, not just the three days that used to empty it.
        now = now.addingTimeInterval(120 * 24 * 60 * 60)
        store.ensureGenesis(unlocked: Set(1...20))

        for id in everything {
            XCTAssertTrue(store.stones.contains { $0.id == id },
                          "a stone left the map — history only accrues (pop_map.md)")
        }
        XCTAssertTrue(store.stones.contains { $0.id == genesis.id },
                      "the first stone of the journey is the one most worth keeping")
        for sibling in roads.dropFirst() {
            XCTAssertTrue(store.stones.contains { $0.id == sibling.id },
                          "an untaken fork stays quietly takeable — nothing can be missed")
        }
        for road in ahead {
            XCTAssertTrue(store.stones.contains { $0.id == road.id })
        }
    }

    // Settling is what replaced the deletion: the same three-day threshold,
    // read rather than enforced. It is derived from the stone's own dates,
    // which is why W08 needed no schema change and no migration.
    func testStonesSettleOnTheSameThresholdThatUsedToDeleteThem() {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = freshStore(now: { now })
        store.ensureGenesis(unlocked: Set(1...20))
        let genesis = store.stones[0]

        XCTAssertFalse(SkyLayout.isSettled(genesis, now: now),
                       "nothing settles inside the window")

        now = now.addingTimeInterval(MapStore.fadeAfter + 60)
        XCTAssertTrue(SkyLayout.isSettled(genesis, now: now),
                      "past the window it is the map's memory — settled, not spent")

        // And settling changes nothing about the stored map.
        XCTAssertTrue(store.stones.contains { $0.id == genesis.id })
    }

    func testFreshStonesAreNotSettled() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = freshStore(now: { now })
        store.ensureGenesis(unlocked: Set(1...20))
        store.setActive(store.stones[0].id)
        let roads = store.recordClear(unlocked: Set(1...20))
        XCTAssertEqual(store.stones.count, 1 + roads.count)
        for stone in store.stones {
            XCTAssertFalse(SkyLayout.isSettled(stone, now: now),
                           "nothing settles inside the three-day window")
        }
    }

    // MARK: - Persistence

    func testMapSurvivesRelaunch() {
        let suite = "vesper.tests.map.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = MapStore(defaults: defaults)
        first.ensureGenesis(unlocked: Set(1...20))
        first.setActive(first.stones[0].id)
        first.recordClear(unlocked: Set(1...20))

        let second = MapStore(defaults: defaults)
        XCTAssertEqual(second.stones.map(\.id), first.stones.map(\.id))
        XCTAssertEqual(second.activeStoneID, first.activeStoneID)
    }
}
