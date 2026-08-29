import XCTest
@testable import Vesper

// `PopMapGen` — the pure, seeded generation rules behind The Path
// (docs/pop_map.md). Everything here takes an `inout SplitMix64` and returns
// a value: no store, no clock, no persistence, so it can be swept directly.
//
// MapStoreTests owns the store's behaviour — genesis, roads opening on a first
// clear, settling, persistence — and asserts the single-step lineage. This
// suite sweeps the RULES: what a child inherits and what it may not take, the
// family a road leans toward, the shapes of the three distributions, the banks
// the lanes stay inside, and the lineage held across a walk of many steps.
//
// The distribution tests draw from ONE fixed-seed stream rather than from
// per-seed first draws, so they are exactly as deterministic as every other
// test here: the same numbers every run, on every machine, forever. Their
// sample sizes and bounds are stated at each assertion.
final class PopMapTests: XCTestCase {

    private let everyPop = PopCatalog.all.map(\.number)

    private func freshStore(now: @escaping () -> Date = Date.init) -> MapStore {
        let suite = "vesper.tests.popmap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return MapStore(defaults: defaults, now: now)
    }

    // MARK: - Determinism

    /// A stone carries a seed so the roads ahead of it can be reproduced
    /// exactly — that is what lets the map be persisted as a handful of
    /// numbers, and what makes a stone the same stone every time she looks at
    /// it. Every rule is swept, including `branchedSet`, whose result feeds
    /// the field she then plays.
    func testEveryGenerationRuleIsAPureFunctionOfItsSeed() {
        for seed in UInt64(0)..<80 {
            var a = SplitMix64(seed: seed)
            var b = SplitMix64(seed: seed)

            XCTAssertEqual(PopMapGen.branchCount(using: &a), PopMapGen.branchCount(using: &b),
                           "seed \(seed): road count")
            XCTAssertEqual(PopMapGen.popCount(using: &a), PopMapGen.popCount(using: &b),
                           "seed \(seed): pop count")
            XCTAssertEqual(
                PopMapGen.popSet(unlocked: Array(1...40), locked: Array(41...100),
                                 avoiding: [3, 4, 5], using: &a),
                PopMapGen.popSet(unlocked: Array(1...40), locked: Array(41...100),
                                 avoiding: [3, 4, 5], using: &b),
                "seed \(seed): pop set")
            XCTAssertEqual(
                PopMapGen.branchedSet(inheriting: 7, leaning: .tide,
                                      unlocked: Array(1...40), locked: Array(41...100),
                                      avoiding: [9], using: &a),
                PopMapGen.branchedSet(inheriting: 7, leaning: .tide,
                                      unlocked: Array(1...40), locked: Array(41...100),
                                      avoiding: [9], using: &b),
                "seed \(seed): branched set")
            XCTAssertEqual(PopMapGen.lanes(from: 0.4, count: 3, using: &a),
                           PopMapGen.lanes(from: 0.4, count: 3, using: &b),
                           "seed \(seed): lanes")
        }
    }

    // MARK: - Lineage

    /// THE INVERSION THIS FILE EXISTS TO HOLD DOWN. Children used to be
    /// generated with their parent's pops in `avoiding`, so every step
    /// replaced the whole set: a stone told you nothing about the stone it
    /// came from, and a fork was a coin toss between two random sets rather
    /// than "the ember road or the tide road". The inherited pop must survive
    /// every path through `branchedSet` — visitor or not, leaning or not.
    func testAChildAlwaysKeepsThePopItInheritedAndKeepsItFirst() {
        for seed in UInt64(0)..<200 {
            var rng = SplitMix64(seed: seed)
            let inherited = 1 + Int(seed % 40)
            let set = PopMapGen.branchedSet(inheriting: inherited, leaning: nil,
                                            unlocked: Array(1...40), locked: Array(41...100),
                                            avoiding: [], using: &rng)
            XCTAssertEqual(set.first ?? -1, inherited,
                           "seed \(seed): the inheritance was dropped or displaced")
        }
    }

    /// The other half of a lineage: a child is never only its parent repeated.
    /// A field always has something she recognises in it AND something she
    /// does not — that is the shape of a good introduction, repeated every
    /// step, forever. Pinned as "more pops than it inherited", which holds for
    /// every seed rather than only most of them.
    func testAChildAlwaysBringsAtLeastOnePopBeyondWhatItInherited() {
        for seed in UInt64(0)..<200 {
            var rng = SplitMix64(seed: seed)
            let set = PopMapGen.branchedSet(inheriting: 3, leaning: nil,
                                            unlocked: Array(1...40), locked: Array(41...100),
                                            avoiding: [], using: &rng)
            XCTAssertGreaterThanOrEqual(set.count, 2, "seed \(seed): the road brought nothing new")
            XCTAssertTrue(set.dropFirst().allSatisfy { $0 != 3 },
                          "seed \(seed): the inheritance was counted twice as novelty")
        }
    }

    /// A stone is 1–3 pops and never the same pop twice — the number the map
    /// screen, the sky's gem silhouettes and the seeded field are all built
    /// around. Held for both generators, since a child comes from
    /// `branchedSet` and the first stone from `popSet`.
    func testAStoneNeverHoldsMoreThanThreePopsAndNeverTheSameOneTwice() {
        for seed in UInt64(0)..<200 {
            var rng = SplitMix64(seed: seed)

            let child = PopMapGen.branchedSet(inheriting: 11, leaning: .ember,
                                              unlocked: Array(1...60), locked: Array(61...100),
                                              avoiding: [], using: &rng)
            XCTAssertTrue((1...3).contains(child.count), "seed \(seed): \(child.count) pops on a child")
            XCTAssertEqual(Set(child).count, child.count, "seed \(seed): a child repeated a pop")

            let first = PopMapGen.popSet(unlocked: Array(1...60), locked: Array(61...100),
                                         avoiding: [], using: &rng)
            XCTAssertTrue((1...3).contains(first.count), "seed \(seed): \(first.count) pops on a stone")
            XCTAssertEqual(Set(first).count, first.count, "seed \(seed): a stone repeated a pop")
        }
    }

    // MARK: - What `avoiding` may and may not hold back

    /// `avoiding` carries what earlier siblings already took, so that two
    /// roads out of one stone genuinely diverge. It must NOT hold back the
    /// inheritance: the parent's pops are the thing being passed down, and
    /// excluding them was exactly the bug that made every step a reshuffle.
    /// The pool here is far larger than the avoided set, so the "nothing left,
    /// take anything" fallback is never the reason a pop appears.
    func testTheAvoidSetHoldsBackNewPopsButNeverTheInheritance() {
        let avoiding = Set(1...20)
        for seed in UInt64(0)..<200 {
            var rng = SplitMix64(seed: seed)
            let inherited = 5   // deliberately inside `avoiding`
            let set = PopMapGen.branchedSet(inheriting: inherited, leaning: nil,
                                            unlocked: Array(1...60), locked: Array(70...100),
                                            avoiding: avoiding, using: &rng)
            XCTAssertEqual(set.first ?? -1, inherited,
                           "seed \(seed): a sibling's avoid-set swallowed the inheritance")
            for pop in set.dropFirst() {
                XCTAssertFalse(avoiding.contains(pop),
                               "seed \(seed): \(pop) was taken by a sibling already")
            }
        }
    }

    /// And where the rules DON'T reach: when everything she owns is already
    /// spoken for, the rule gives way rather than handing back an empty stone.
    /// A stone with no pops on it is a field that cannot be seeded, which is
    /// the one failure this map is not allowed to have.
    func testWhenEverythingIsAlreadySpokenForTheStoneIsStillPlayable() {
        for seed in UInt64(0)..<60 {
            var rng = SplitMix64(seed: seed)

            let first = PopMapGen.popSet(unlocked: [1, 2, 3], locked: [],
                                         avoiding: [1, 2, 3], using: &rng)
            XCTAssertFalse(first.isEmpty, "seed \(seed): a stone with nothing on it")
            XCTAssertTrue(first.allSatisfy { [1, 2, 3].contains($0) },
                          "seed \(seed): a pop arrived from outside the collection")

            let child = PopMapGen.branchedSet(inheriting: 1, leaning: nil,
                                              unlocked: [1, 2, 3], locked: [],
                                              avoiding: [1, 2, 3], using: &rng)
            XCTAssertGreaterThanOrEqual(child.count, 2,
                                        "seed \(seed): a cornered road brought nothing new")
            XCTAssertEqual(Set(child).count, child.count)
        }
    }

    /// The calm floor under everything above: with nothing unlocked and
    /// nothing locked, generation still produces the pop the game opens with
    /// rather than an empty stone.
    func testAnEmptyCollectionStillLaysAPlayableRoad() {
        var rng = SplitMix64(seed: 5)
        XCTAssertEqual(PopMapGen.branchedSet(inheriting: nil, leaning: nil,
                                             unlocked: [], locked: [], avoiding: [],
                                             using: &rng),
                       [PopCatalog.classic.number])
    }

    // MARK: - A fork is a choice: the road's family

    /// "One road is the ember road and the other is the tide road, and she can
    /// see that in the sky before she takes either." With no locked book to
    /// draw a visitor from, every pop a road adds must come from the family
    /// that road leans toward — swept across all ten families, because a
    /// preference that only holds for some of them is not a signature.
    func testANewRoadDrawsItsNewPopsFromTheFamilyItLeansToward() {
        for family in PopFamily.allCases {
            let kin = PopCatalog.all.filter { $0.family == family }.map(\.number)
            XCTAssertGreaterThanOrEqual(kin.count, 3,
                                        "\(family.rawValue) is too thin to draw a road from")
            let inherited = PopCatalog.all.first { $0.family != family }!.number

            for seed in UInt64(0)..<40 {
                var rng = SplitMix64(seed: seed)
                let set = PopMapGen.branchedSet(inheriting: inherited, leaning: family,
                                                unlocked: everyPop, locked: [],
                                                avoiding: [], using: &rng)
                for pop in set.dropFirst() {
                    XCTAssertEqual(PopCatalog.definition(for: pop).family, family,
                                   "\(family.rawValue) seed \(seed): pop \(pop) is off the road's family")
                }
            }
        }
    }

    // MARK: - Visitors

    /// A visitor is a pop she has NOT unlocked, met on one stone. Two things
    /// have to be true of it and both are pinned here: it is drawn from the
    /// locked book (never quietly from what she already owns), and there is
    /// never more than one — a stone that was all strangers would be a stone
    /// with nothing of hers on it.
    func testAStoneHostsAtMostOneVisitorAndItComesFromTheLockedBook() {
        let unlocked = Array(1...6)
        let locked = Array(60...90)
        for seed in UInt64(0)..<200 {
            var rng = SplitMix64(seed: seed)

            let first = PopMapGen.popSet(unlocked: unlocked, locked: locked,
                                         avoiding: [], using: &rng)
            XCTAssertLessThanOrEqual(first.filter { locked.contains($0) }.count, 1,
                                     "seed \(seed): a stone of strangers")
            XCTAssertTrue(first.allSatisfy { unlocked.contains($0) || locked.contains($0) },
                          "seed \(seed): a pop from neither book")

            let child = PopMapGen.branchedSet(inheriting: 2, leaning: nil,
                                              unlocked: unlocked, locked: locked,
                                              avoiding: [], using: &rng)
            XCTAssertLessThanOrEqual(child.filter { locked.contains($0) }.count, 1,
                                     "seed \(seed): a road of strangers")
            XCTAssertTrue(child.allSatisfy { unlocked.contains($0) || locked.contains($0) },
                          "seed \(seed): a pop from neither book")
        }
    }

    /// Roughly a third of stones host one — wonder without FOMO. Too rare and
    /// tomorrow's pops never brush past her; too common and the collection
    /// stops meaning anything.
    ///
    /// 600 draws from one fixed-seed stream. `visitorChance` is 0.35, so the
    /// sampling error is about 0.02; the bound below is ±0.10, five standard
    /// deviations wide, and the stream is fixed — this test cannot flake.
    func testAboutAThirdOfStonesHostAVisitor() {
        var rng = SplitMix64(seed: 4_242)
        let locked = Array(60...90)
        var visited = 0
        let samples = 600
        for _ in 0..<samples {
            let set = PopMapGen.popSet(unlocked: Array(1...6), locked: locked,
                                       avoiding: [], using: &rng)
            if set.contains(where: { locked.contains($0) }) { visited += 1 }
        }
        let share = Double(visited) / Double(samples)
        XCTAssertGreaterThan(share, PopMapGen.visitorChance - 0.10,
                             "visitors have become rare — share \(share)")
        XCTAssertLessThan(share, PopMapGen.visitorChance + 0.10,
                          "visitors have become the norm — share \(share)")
    }

    // MARK: - The shapes of the two rolls

    /// One road 45%, a fork 45%, a rare three-way 10%. The shape is the
    /// design: a fork should be as ordinary as walking on, and a three-way
    /// should be an event. 1,000 draws from one fixed-seed stream; the widest
    /// sampling error here is about 0.016, and the bounds are ±0.08 or wider.
    func testRoadsOpenAsOneOrTwoWithAThreeWayStayingRare() {
        var rng = SplitMix64(seed: 90_210)
        var counts = [0, 0, 0, 0]
        let samples = 1_000
        for _ in 0..<samples {
            let n = PopMapGen.branchCount(using: &rng)
            XCTAssertTrue((1...3).contains(n), "a stone opened \(n) roads")
            counts[n] += 1
        }
        let single = Double(counts[1]) / Double(samples)
        let fork = Double(counts[2]) / Double(samples)
        let threeWay = Double(counts[3]) / Double(samples)

        XCTAssertGreaterThan(single, 0.37, "single roads \(single)")
        XCTAssertLessThan(single, 0.53, "single roads \(single)")
        XCTAssertGreaterThan(fork, 0.37, "forks \(fork)")
        XCTAssertLessThan(fork, 0.53, "forks \(fork)")
        XCTAssertGreaterThan(threeWay, 0.04, "three-ways never happen — \(threeWay)")
        XCTAssertLessThan(threeWay, 0.17, "three-ways are no longer rare — \(threeWay)")
        XCTAssertLessThan(threeWay, single, "the rare case outnumbered the common one")
        XCTAssertLessThan(threeWay, fork, "the rare case outnumbered the common one")
    }

    /// 1–2 pops per stone, rarely 3 (50% / 40% / 10%). Same stream discipline
    /// and the same bounds as the road roll above.
    func testAStoneCarriesOneOrTwoPopsAndRarelyThree() {
        var rng = SplitMix64(seed: 555_555)
        var counts = [0, 0, 0, 0]
        let samples = 1_000
        for _ in 0..<samples {
            let n = PopMapGen.popCount(using: &rng)
            XCTAssertTrue((1...3).contains(n), "a stone asked for \(n) pops")
            counts[n] += 1
        }
        let one = Double(counts[1]) / Double(samples)
        let two = Double(counts[2]) / Double(samples)
        let three = Double(counts[3]) / Double(samples)

        XCTAssertGreaterThan(one, 0.42, "single-pop stones \(one)")
        XCTAssertLessThan(one, 0.58, "single-pop stones \(one)")
        XCTAssertGreaterThan(two, 0.32, "two-pop stones \(two)")
        XCTAssertLessThan(two, 0.48, "two-pop stones \(two)")
        XCTAssertGreaterThan(three, 0.04, "three-pop stones never happen — \(three)")
        XCTAssertLessThan(three, 0.17, "three-pop stones are no longer rare — \(three)")
    }

    // MARK: - Lanes

    /// Roads spread to either side of the stone they leave, and they are
    /// clamped to the banks so the map can never draw a stone off the water —
    /// including when the parent is already pressed against an edge, or when a
    /// corrupt lane arrives from an old store.
    func testRoadsSpreadToEitherSideOfTheirParentAndStayInsideTheBanks() {
        let banks = 0.08...0.92
        for parent in [-3.0, 0.0, 0.08, 0.5, 0.92, 1.0, 4.0] {
            for count in 1...3 {
                for seed in UInt64(0)..<40 {
                    var rng = SplitMix64(seed: seed)
                    let lanes = PopMapGen.lanes(from: parent, count: count, using: &rng)
                    XCTAssertEqual(lanes.count, count, "parent \(parent) count \(count)")
                    for lane in lanes {
                        XCTAssertTrue(banks.contains(lane),
                                      "parent \(parent) count \(count) seed \(seed): lane \(lane) is off the water")
                    }
                }
            }
        }

        // From mid-map, where no clamping can happen, the spread is readable:
        // a single road stays near its parent, a fork straddles it, and a
        // three-way keeps one road running straight on.
        for seed in UInt64(0)..<80 {
            var rng = SplitMix64(seed: seed)
            let one = PopMapGen.lanes(from: 0.5, count: 1, using: &rng)
            XCTAssertLessThanOrEqual(abs(one[0] - 0.5), 0.16 + 1e-9,
                                     "seed \(seed): a single road wandered")

            let fork = PopMapGen.lanes(from: 0.5, count: 2, using: &rng)
            XCTAssertLessThan(fork[0], 0.5, "seed \(seed): a fork's left road went right")
            XCTAssertGreaterThan(fork[1], 0.5, "seed \(seed): a fork's right road went left")

            let three = PopMapGen.lanes(from: 0.5, count: 3, using: &rng)
            XCTAssertLessThan(three[0], three[1], "seed \(seed): a three-way crossed itself")
            XCTAssertLessThan(three[1], three[2], "seed \(seed): a three-way crossed itself")
            XCTAssertLessThanOrEqual(abs(three[1] - 0.5), 0.05 + 1e-9,
                                     "seed \(seed): the middle road did not run straight on")
        }
    }

    // MARK: - Walking the Path

    /// The rules above, held across a walk rather than at one step. Generation
    /// counts up by exactly one per stone, every road stays on the water at
    /// every depth, no two stones anywhere on the map share a seed (a repeat
    /// would make two different places generate identical futures), and the
    /// lineage — something of the parent on every child — survives all the way
    /// down. MapStoreTests asserts these one step out of genesis; what is
    /// added here is that nothing decays over the depth she actually walks.
    func testWalkingThePathKeepsTheLineageAndTheBanksAtEveryDepth() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let unlocked = Set(1...60)
        let store = freshStore(now: { fixed })
        store.ensureGenesis(unlocked: unlocked)

        var current = store.stones[0]
        var seeds: Set<UInt64> = [current.seed]
        XCTAssertEqual(current.generation, 0)

        for step in 1...8 {
            store.setActive(current.id)
            let roads = store.recordClear(unlocked: unlocked)
            XCTAssertFalse(roads.isEmpty, "step \(step): the path stopped")

            for road in roads {
                XCTAssertEqual(road.parentID, current.id, "step \(step): an orphaned road")
                XCTAssertEqual(road.generation, current.generation + 1,
                               "step \(step): generation did not count up by one")
                XCTAssertTrue((0.08...0.92).contains(road.lane),
                              "step \(step): lane \(road.lane) is off the water")
                XCTAssertTrue((1...3).contains(road.popNumbers.count), "step \(step)")
                XCTAssertEqual(Set(road.popNumbers).count, road.popNumbers.count,
                               "step \(step): a stone repeated a pop")
                XCTAssertFalse(Set(road.popNumbers).intersection(current.popNumbers).isEmpty,
                               "step \(step): \(road.popNumbers) shares nothing with \(current.popNumbers)")
                for n in road.popNumbers {
                    XCTAssertNotNil(PopCatalog.byNumber[n], "step \(step): pop \(n) is not in the catalog")
                }
                XCTAssertTrue(seeds.insert(road.seed).inserted,
                              "step \(step): two stones on the map share a seed")
            }
            current = roads[0]
        }

        XCTAssertEqual(current.generation, 8, "eight steps did not reach the eighth generation")
    }
}
