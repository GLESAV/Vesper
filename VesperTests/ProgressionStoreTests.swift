import XCTest
@testable import Vesper

// ProgressionStore is where the first product guardrail actually lives.
//
// "Affirming-only" (CLAUDE.md guardrail 1, docs/pop_progression.md) is not a
// mood in the copy — it is an arithmetic property of this one file: every
// number it keeps only ever counts up, and every door it opens stays open. A
// regression here crashes nothing and looks like nothing; it quietly takes
// back something somebody earned, which is the one failure this game is not
// allowed to have. So the tests below are mostly about what CANNOT happen.
//
// EVERY TEST RUNS OVER A PRIVATE SUITE. `ProgressionStore.shared` reads and
// writes `UserDefaults.standard`, which the app, the simulator and several
// other test classes share; a test that touched it would be both flaky (it
// would depend on execution order) and destructive (it would edit whatever
// journey the device is holding). The `init(defaults:)` seam exists for
// exactly this, and nothing here may use `.shared`.
//
// See also DevResetTests, which covers the W24 wipe across all three stores;
// this file is about the store's own contract.
final class ProgressionStoreTests: XCTestCase {

    // MARK: - The suite

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var extraSuites: [String] = []

    override func setUp() {
        super.setUp()
        suiteName = "vesper.tests.progression.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        for suite in extraSuites {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        extraSuites = []
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> ProgressionStore {
        ProgressionStore(defaults: defaults)
    }

    // A store over its own throwaway suite, for the tests that need several
    // independent journeys at once (the threshold sweep runs one store up to
    // a door and another over it).
    private func isolatedStore() -> ProgressionStore {
        let suite = "vesper.tests.progression.\(UUID().uuidString)"
        let suiteDefaults = UserDefaults(suiteName: suite)!
        suiteDefaults.removePersistentDomain(forName: suite)
        extraSuites.append(suite)
        return ProgressionStore(defaults: suiteDefaults)
    }

    // The suite's OWN domain, not `dictionaryRepresentation()`: a suite also
    // searches the app's domain, so the wider reading would see whatever other
    // test classes have written to `.standard` and make these assertions
    // depend on test order.
    private func storedKeys() -> Set<String> {
        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        return Set(domain.keys.filter { $0.hasPrefix("vesper.") })
    }

    // MARK: - The on-disk names

    // Spelled out rather than read back from the store, because these strings
    // are a DATA FORMAT and not an implementation detail. Two of them are
    // pre-1.1 keys deliberately carried over ("vesper.stats.*") so that an
    // existing player's lifetime counters survived that update. Renaming one
    // breaks nothing at runtime — it silently hands every returning player a
    // blank journey, which is the quietest possible way to lose someone's
    // history.
    private static let pointsKey = "vesper.progress.points"
    private static let lifetimePopsKey = "vesper.stats.lifetimePops"
    private static let fieldsClearedKey = "vesper.stats.fieldsCleared"
    private static let fortunesKey = "vesper.progress.fortunes"
    private static let bestChainKey = "vesper.progress.bestChain"
    private static let popCountsKey = "vesper.progress.popCounts"
    private static let featuredKey = "vesper.progress.featured"

    private static let allKeys: Set<String> = [
        pointsKey, lifetimePopsKey, fieldsClearedKey,
        fortunesKey, bestChainKey, popCountsKey, featuredKey,
    ]

    // MARK: - Counters, in one fixed order

    private static let counterNames = [
        "pop points", "lifetime pops", "fields cleared", "fortunes found", "best chain",
    ]

    private func counters(_ store: ProgressionStore) -> [Int] {
        [store.popPoints, store.lifetimePops, store.fieldsCleared,
         store.fortunesFound, store.bestChain]
    }

    private func assertNothingWentDown(_ store: ProgressionStore,
                                       _ what: String,
                                       during body: () -> Void) {
        let before = counters(store)
        body()
        let after = counters(store)
        for (index, name) in Self.counterNames.enumerated() {
            XCTAssertGreaterThanOrEqual(after[index], before[index],
                                        "\(what) made \(name) go down: "
                                        + "\(before[index]) → \(after[index])")
        }
    }

    // MARK: - First run

    // A device that has never played must read as nothing earned rather than
    // as garbage — `integer(forKey:)` on an absent key is 0, and the featured
    // pop must be nil, because a fresh journey drifts through everything it
    // has rather than repeating one pop.
    func testAJourneyThatHasNeverBeenPlayedReadsAsAllZerosAndDrifts() {
        let store = makeStore()
        XCTAssertEqual(counters(store), [0, 0, 0, 0, 0])
        XCTAssertEqual(store.popCounts, [:])
        XCTAssertNil(store.featuredPop, "a fresh journey features nothing; it drifts")
    }

    // Reading is not writing. If merely building the store created its keys,
    // then "has this player ever played" would be unanswerable from disk, and
    // a first launch would leave seven keys behind before an orb was touched.
    func testBuildingAStoreWritesNothing() {
        _ = makeStore()
        XCTAssertTrue(storedKeys().isEmpty,
                      "constructing the store wrote \(storedKeys().sorted()) before "
                      + "the player did anything")
    }

    // MARK: - Affirming-only

    // THE GUARDRAIL ITSELF. Zero, negative and enormous inputs all arrive
    // through the same three doors; none of them may make a number smaller.
    // The negative cases are not hypothetical politeness: a points formula
    // that ever returns a negative (a subtraction gone wrong, a penalty
    // somebody adds "just for balance") would otherwise spend a player's
    // total, and spending is precisely what this game does not do.
    func testNoRecordingOfAnyKindCanMakeANumberGoDown() {
        let store = makeStore()
        assertNothingWentDown(store, "a pop worth nothing") {
            store.recordPop(popNumber: 1, points: 0, chainLength: 0)
        }
        assertNothingWentDown(store, "a generous pop") {
            store.recordPop(popNumber: 2, points: 60, chainLength: 5)
        }
        assertNothingWentDown(store, "a pop with negative points and a negative chain") {
            store.recordPop(popNumber: 2, points: -500, chainLength: -3)
        }
        assertNothingWentDown(store, "a clear with a negative bonus") {
            store.recordClear(bonus: -1000)
        }
        assertNothingWentDown(store, "an enormous pop") {
            store.recordPop(popNumber: 3, points: 1_000_000_000, chainLength: 4)
        }
        assertNothingWentDown(store, "a fortune") {
            store.recordFortune()
        }
        assertNothingWentDown(store, "a short chain after a long one") {
            store.recordPop(popNumber: 3, points: 1, chainLength: 1)
        }

        // and the specific arithmetic behind those inequalities
        XCTAssertEqual(store.popPoints, 60 + 1_000_000_000 + 1,
                       "negative points and a negative bonus must contribute nothing at all")
        XCTAssertEqual(store.lifetimePops, 5, "every pop counts, even a worthless one")
        XCTAssertEqual(store.fieldsCleared, 1)
        XCTAssertEqual(store.fortunesFound, 1)
        XCTAssertEqual(store.bestChain, 5, "the negative chain must not have become the record")
    }

    // bestChain is a keepsake, not a status line: it is the longest cascade
    // ever, so the ordinary case of a modest chain after a great one must
    // leave it standing.
    func testBestChainRemembersTheLongestCascadeAndNotTheLastOne() {
        let store = makeStore()
        store.recordPop(popNumber: 1, points: 10, chainLength: 2)
        XCTAssertEqual(store.bestChain, 2)
        store.recordPop(popNumber: 1, points: 10, chainLength: 9)
        XCTAssertEqual(store.bestChain, 9)
        store.recordPop(popNumber: 1, points: 10, chainLength: 1)
        XCTAssertEqual(store.bestChain, 9, "a quiet field must not overwrite the best chain")
        store.recordPop(popNumber: 1, points: 10, chainLength: 9)
        XCTAssertEqual(store.bestChain, 9, "equalling the record must not disturb it")
    }

    // MARK: - The tallies

    // The per-pop tallies are what the collection page counts. They must be
    // independent (popping a Frost pop cannot advance an Ember's count), and
    // a pop nobody has met must have no entry at all rather than a zero — the
    // collection reads "never met" from the absence.
    func testTalliesAreKeptPerPopAndAlwaysSumToTheLifetimeCount() {
        let store = makeStore()
        for _ in 0..<3 { store.recordPop(popNumber: 12, points: 1, chainLength: 1) }
        for _ in 0..<5 { store.recordPop(popNumber: 40, points: 1, chainLength: 1) }
        store.recordPop(popNumber: 12, points: 1, chainLength: 1)

        XCTAssertEqual(store.popCounts[12], 4)
        XCTAssertEqual(store.popCounts[40], 5)
        XCTAssertNil(store.popCounts[13], "a pop nobody has met must have no tally, not a zero")
        XCTAssertEqual(store.popCounts.values.reduce(0, +), store.lifetimePops,
                       "the tallies and the lifetime count are the same nine pops counted twice; "
                       + "if they disagree one of the two is losing pops")
    }

    // MARK: - Persistence

    // The round trip is the whole point of the store. Note the tallies in
    // particular: they live in memory as [Int: Int] and on disk as
    // [String: Int], so this is the only test that would notice the two
    // conversions drifting apart and every player's collection emptying on
    // the next launch.
    func testEveryRememberedNumberSurvivesAStoreRebuiltOverTheSameDisk() {
        let store = makeStore()
        store.recordPop(popNumber: 4, points: 30, chainLength: 6)
        store.recordPop(popNumber: 4, points: 10, chainLength: 2)
        store.recordPop(popNumber: 9, points: 5, chainLength: 3)
        store.recordClear(bonus: 40)
        store.recordFortune()
        store.recordFortune()
        store.featuredPop = 9

        let reborn = ProgressionStore(defaults: defaults)
        XCTAssertEqual(reborn.popPoints, 85)
        XCTAssertEqual(reborn.lifetimePops, 3)
        XCTAssertEqual(reborn.fieldsCleared, 1)
        XCTAssertEqual(reborn.fortunesFound, 2)
        XCTAssertEqual(reborn.bestChain, 6)
        XCTAssertEqual(reborn.popCounts, [4: 2, 9: 1])
        XCTAssertEqual(reborn.featuredPop, 9)
        XCTAssertEqual(counters(reborn), counters(store),
                       "the rebuilt store disagrees with the one that wrote the disk")
    }

    // The declared list is what the W24 fresh install sweeps. Checked per
    // store, and against literal key names, for two reasons DevResetTests
    // cannot cover: that file is entirely `#if DEBUG` (so in a Release test
    // run nothing checks this at all), and it compares the UNION of three
    // stores' lists, which would still pass if this store's key were declared
    // by the wrong store.
    func testTheDeclaredKeyListIsExactlyTheKeysThisStoreWrites() {
        let store = makeStore()
        store.recordPop(popNumber: 1, points: 5, chainLength: 2)
        store.recordClear(bonus: 10)
        store.recordFortune()
        store.featuredPop = 2

        let written = storedKeys()
        let declared = Set(ProgressionStore.ownedDefaultsKeys)
        XCTAssertEqual(ProgressionStore.ownedDefaultsKeys.count, declared.count,
                       "a key is declared twice: \(ProgressionStore.ownedDefaultsKeys)")
        XCTAssertEqual(written, declared,
                       "declared and written have drifted apart — written but not declared: "
                       + "\(written.subtracting(declared).sorted()); declared but never written: "
                       + "\(declared.subtracting(written).sorted())")
        XCTAssertEqual(declared, Self.allKeys,
                       "a stored key was renamed; every existing player's journey reads as blank")
    }

    // MARK: - The featured pop

    // nil means Drift (every unlocked pop mixed into the field), and nil is
    // written to disk as 0 — so 0 can only ever mean Drift on the way back.
    // The catalogue is numbered 1...100 precisely so that sentinel is free.
    func testTheFeaturedPopRoundTripsAndAStoredZeroMeansDriftNotPopZero() {
        XCTAssertNil(PopCatalog.byNumber[0],
                     "the catalogue has grown a pop #0, which is the drift sentinel on disk")

        let store = makeStore()
        store.featuredPop = 9
        XCTAssertEqual(ProgressionStore(defaults: defaults).featuredPop, 9)

        store.featuredPop = nil
        XCTAssertNil(ProgressionStore(defaults: defaults).featuredPop,
                     "letting a favourite go must survive the next launch")

        store.featuredPop = 0
        XCTAssertNil(ProgressionStore(defaults: defaults).featuredPop,
                     "a stored 0 came back as pop #0, which does not exist")
    }

    // A favourite the player has not earned yet must not decide what the
    // field is made of — the field falls back to Drift, which can only ever
    // contain unlocked pops. Locked content shows a kind hint, never a wall,
    // and never a field of something you cannot have.
    func testTheFieldIsNeverMadeOfAPopThePlayerHasNotEarned() throws {
        let store = makeStore()
        XCTAssertTrue(Set(store.fieldPops()).isSubset(of: store.unlockedNumbers()),
                      "a fresh field offered a locked pop")

        let locked = try XCTUnwrap(PopCatalog.all.first(where: { !store.isUnlocked($0) }),
                                   "every pop is unlocked on a fresh store — nothing left to earn")
        store.featuredPop = locked.number
        XCTAssertFalse(store.fieldPops().contains(locked.number),
                       "a locked favourite became the field")
        XCTAssertEqual(store.fieldPops(), store.unlockedNumbers().sorted(),
                       "a locked favourite must fall back to drifting through what is unlocked")

        // and once a pop IS earned, featuring it means the field is that pop
        store.featuredPop = nil
        store.recordPop(popNumber: 1, points: 100, chainLength: 0)
        let earned = try XCTUnwrap(
            store.unlockedNumbers().subtracting([PopCatalog.classic.number]).min(),
            "100 pop points opened no door at all — the first rung of the ladder has moved")
        store.featuredPop = earned
        XCTAssertEqual(store.fieldPops(), [earned], "a featured pop is the whole field")
    }

    // MARK: - Corruption

    // Defaults are a file other processes can damage, and the store reads
    // them with no schema. None of these may crash on launch, and — the part
    // that is easy to get wrong — one damaged key must not take the healthy
    // ones down with it. Losing a tally is a shame; losing a lifetime counter
    // because of it is the bug.
    func testAnUnreadableTallyIsIgnoredWithoutTakingTheOtherNumbersWithIt() {
        defaults.set(500, forKey: Self.pointsKey)
        defaults.set(4, forKey: Self.fortunesKey)
        defaults.set("not a dictionary at all", forKey: Self.popCountsKey)

        let store = makeStore()
        XCTAssertEqual(store.popCounts, [:], "an unreadable tally must read as no tally")
        XCTAssertEqual(store.popPoints, 500, "one damaged key erased a healthy one")
        XCTAssertEqual(store.fortunesFound, 4)

        store.recordPop(popNumber: 6, points: 10, chainLength: 1)
        let reborn = ProgressionStore(defaults: defaults)
        XCTAssertEqual(reborn.popCounts, [6: 1], "the next pop must repair the tally")
        XCTAssertEqual(reborn.popPoints, 510, "the healthy total must keep counting from where it was")
    }

    // A tally with an entry that is not a pop number keeps the entries that
    // are: a single junk key must not empty somebody's collection page.
    func testATallyWithAJunkEntryKeepsTheEntriesItCanStillRead() {
        defaults.set(["7": 4, "notapopnumber": 3], forKey: Self.popCountsKey)
        let store = makeStore()
        XCTAssertEqual(store.popCounts, [7: 4],
                       "one unreadable entry took the readable ones with it")
    }

    // A word where a number should be reads as nothing earned rather than
    // crashing the launch, the keys either side of it are untouched, and the
    // first honest write puts the key back into a shape that reads.
    func testAWrongTypedCounterReadsAsNothingEarnedAndIsRepairedByTheNextWrite() {
        defaults.set("many", forKey: Self.pointsKey)
        defaults.set(12, forKey: Self.fieldsClearedKey)
        defaults.set("no favourite", forKey: Self.featuredKey)

        let store = makeStore()
        XCTAssertEqual(store.popPoints, 0)
        XCTAssertEqual(store.fieldsCleared, 12, "a neighbouring key was lost to the damaged one")
        XCTAssertNil(store.featuredPop, "an unreadable favourite must read as drift")

        store.recordClear(bonus: 3)
        let reborn = ProgressionStore(defaults: defaults)
        XCTAssertEqual(reborn.popPoints, 3, "the first honest write must repair the key")
        XCTAssertEqual(reborn.fieldsCleared, 13)
        XCTAssertNil(reborn.featuredPop)
    }

    // MARK: - Unlocks

    private enum RuleKind: String, CaseIterable {
        case start, points, totalPops, fieldsCleared, fortunesFound, bestChain
    }

    private func kind(of rule: UnlockRule) -> RuleKind {
        switch rule {
        case .start: return .start
        case .points: return .points
        case .totalPops: return .totalPops
        case .fieldsCleared: return .fieldsCleared
        case .fortunesFound: return .fortunesFound
        case .bestChain: return .bestChain
        }
    }

    private func threshold(of rule: UnlockRule) -> Int {
        switch rule {
        case .start:
            return 0
        case .points(let n), .totalPops(let n), .fieldsCleared(let n),
             .fortunesFound(let n), .bestChain(let n):
            return n
        }
    }

    private func counter(_ store: ProgressionStore, _ kind: RuleKind) -> Int {
        switch kind {
        case .start: return 0
        case .points: return store.popPoints
        case .totalPops: return store.lifetimePops
        case .fieldsCleared: return store.fieldsCleared
        case .fortunesFound: return store.fortunesFound
        case .bestChain: return store.bestChain
        }
    }

    // Raises exactly ONE counter of a fresh store to `value`, through the
    // store's real recording API. Points and chains ride in on a pop, so
    // those two also add a single lifetime pop — far below any totalPops
    // door, which is what keeps the cross-wiring check below honest.
    private func drive(_ store: ProgressionStore, _ kind: RuleKind, to value: Int) {
        let target = max(0, value)
        switch kind {
        case .start:
            break
        case .points:
            if target > 0 { store.recordPop(popNumber: 1, points: target, chainLength: 0) }
        case .totalPops:
            for _ in 0..<target { store.recordPop(popNumber: 1, points: 0, chainLength: 0) }
        case .fieldsCleared:
            for _ in 0..<target { store.recordClear(bonus: 0) }
        case .fortunesFound:
            for _ in 0..<target { store.recordFortune() }
        case .bestChain:
            if target > 0 { store.recordPop(popNumber: 1, points: 0, chainLength: target) }
        }
    }

    // The lowest door of each kind, so the sweep is cheap and so every one of
    // the five rules is actually exercised rather than four of them plus a
    // hundred points doors.
    private func lowestDoorOfEachKind() -> [RuleKind: PopDefinition] {
        var lowest: [RuleKind: PopDefinition] = [:]
        for def in PopCatalog.all where kind(of: def.unlock) != .start {
            let k = kind(of: def.unlock)
            if let held = lowest[k], threshold(of: held.unlock) <= threshold(of: def.unlock) {
                continue
            }
            lowest[k] = def
        }
        return lowest
    }

    // A threshold is a promise about a number: at it the pop is yours, one
    // short of it it is not, and it is THIS counter that decides — not a
    // neighbouring one. An off-by-one here is the difference between "arrives
    // at 100 pop points" being true and being a small lie told to everyone.
    func testEveryKindOfDoorOpensExactlyAtItsThresholdAndReadsItsOwnCounter() {
        let doors = lowestDoorOfEachKind()
        for k in RuleKind.allCases where k != .start {
            XCTAssertNotNil(doors[k],
                            "no pop unlocks on \(k.rawValue) any more — a whole axis of the "
                            + "journey has quietly gone")
        }
        XCTAssertTrue(PopCatalog.all.contains(where: { kind(of: $0.unlock) == .start }),
                      "nothing is unlocked from the start, so a first launch has no pop to play")

        for (k, def) in doors {
            let door = threshold(of: def.unlock)
            XCTAssertGreaterThan(door, 0, "\(def.name): a threshold of \(door) is not a door")

            let below = isolatedStore()
            drive(below, k, to: door - 1)
            XCTAssertEqual(counter(below, k), door - 1,
                           "\(def.name): the test failed to reach \(door - 1) \(k.rawValue)")
            XCTAssertFalse(below.isUnlocked(def),
                           "\(def.name) opened one short of \(door) \(k.rawValue)")

            let at = isolatedStore()
            drive(at, k, to: door)
            XCTAssertEqual(counter(at, k), door,
                           "\(def.name): the test failed to reach \(door) \(k.rawValue)")
            XCTAssertTrue(at.isUnlocked(def),
                          "\(def.name) did not open at \(door) \(k.rawValue), which is what its "
                          + "hint promises: \"\(def.unlock.hint)\"")

            // Cross-wiring: earning THIS counter must not open a door that
            // belongs to another one. Doors the journey genuinely reached on
            // the way are skipped, so this stays a test of the wiring rather
            // than of the catalogue's numbers.
            for (otherKind, other) in doors where otherKind != k {
                guard counter(at, otherKind) < threshold(of: other.unlock) else { continue }
                XCTAssertFalse(at.isUnlocked(other),
                               "\(other.name) opened on \(k.rawValue), but it is a "
                               + "\(otherKind.rawValue) door")
            }
        }
    }

    // MONOTONICITY OF THE COLLECTION — the guardrail again, in the shape it
    // takes for unlocks. Nothing is spent, lost, reset or time-limited, so
    // the set of unlocked pops can only ever grow. This walks a long, ordinary
    // journey and checks after every step that no door closed behind the
    // player and no counter went backwards.
    func testADoorOnceOpenedNeverClosesAgain() {
        let store = makeStore()
        var opened = store.unlockedNumbers()
        var numbers = counters(store)
        let atTheStart = opened

        for step in 0..<40 {
            for i in 0..<10 {
                store.recordPop(popNumber: 1 + (step + i) % 100,
                                points: (step * 7 + i) % 40,
                                chainLength: (step + i) % 9)
            }
            if step % 3 == 0 { store.recordClear(bonus: 25) }
            if step % 5 == 0 { store.recordFortune() }
            // a turn that earns nothing must still not cost anything
            store.recordPop(popNumber: 1, points: 0, chainLength: 0)

            let nowOpen = store.unlockedNumbers()
            XCTAssertTrue(nowOpen.isSuperset(of: opened),
                          "step \(step) closed doors that were already open: "
                          + "\(opened.subtracting(nowOpen).sorted())")
            let nowNumbers = counters(store)
            for (index, name) in Self.counterNames.enumerated() {
                XCTAssertGreaterThanOrEqual(nowNumbers[index], numbers[index],
                                            "step \(step) made \(name) go down")
            }
            opened = nowOpen
            numbers = nowNumbers
        }

        XCTAssertGreaterThan(opened.count, atTheStart.count,
                             "a long journey opened nothing new — this test would pass on a "
                             + "store that never unlocks anything")
        // and every number the collection page shows must be a real pop
        for number in opened {
            XCTAssertNotNil(PopCatalog.byNumber[number],
                            "pop #\(number) is unlocked but is not in the catalogue")
        }
    }

    // MARK: - W24: the fresh install (DEBUG only)

    #if DEBUG
    // DevResetTests exercises this through `DevReset.wipeOwnedDefaults`, which
    // sweeps the whole namespace afterwards and would therefore hide a reset
    // that left its own keys behind. Called on its own, the store must clear
    // both halves itself — and `featuredPop`'s `didSet` must not write its key
    // back after the sweep, which is the one key in the app that can
    // resurrect itself.
    func testResetToFreshInstallEmptiesMemoryAndDiskOnItsOwn() {
        let store = makeStore()
        store.recordPop(popNumber: 5, points: 40, chainLength: 7)
        store.recordClear(bonus: 30)
        store.recordFortune()
        store.featuredPop = 5
        XCTAssertFalse(storedKeys().isEmpty)

        store.resetToFreshInstall()

        XCTAssertEqual(counters(store), [0, 0, 0, 0, 0])
        XCTAssertEqual(store.popCounts, [:])
        XCTAssertNil(store.featuredPop)
        XCTAssertTrue(storedKeys().isEmpty,
                      "keys survived the store's own reset: \(storedKeys().sorted())")

        let reborn = ProgressionStore(defaults: defaults)
        XCTAssertEqual(counters(reborn), [0, 0, 0, 0, 0])
        XCTAssertEqual(reborn.popCounts, [:])
        XCTAssertNil(reborn.featuredPop)
    }
    #endif
}
