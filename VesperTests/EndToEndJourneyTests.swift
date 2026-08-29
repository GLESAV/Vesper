import XCTest
@testable import Vesper

// END TO END — A WHOLE EVENING, NOT ONE CALL.
//
// Every other file in this suite pins one mechanism in isolation. This one
// pins the promises the player experiences over TIME: field after field,
// stone after stone, with the real `GameSimulation` and the real stores
// carrying state forward between them. Slow leaks — a counter that drifts, a
// collection that quietly loses a member, a field that stops being finishable
// once it is big enough — only show up over a horizon, and this is the
// horizon.
//
// ─────────────────────────────────────────────────────────────────────────
// HERMETIC BY CONSTRUCTION, WHICH IS WHY A JOURNEY IS REPRODUCIBLE.
//
// Nothing here touches `ProgressionStore.shared`, `MapStore.shared`,
// `SettingsStore.shared` or `UserDefaults.standard`. Each test builds its own
// three stores over a PRIVATE suite named for a fresh UUID, wiped before the
// first store reads it and again in `tearDown`. Two consequences, and both
// are the point:
//
//   * a journey starts from a genuine fresh install every time, so "twelve
//     fields from empty" means what it says rather than "twelve fields on top
//     of whatever the last test left behind";
//   * these tests can run beside the seven other files that are being written
//     against the same stores without either side seeing the other, in any
//     order, in parallel.
//
// `MapStore` also takes an injected `now:` provider, so nothing below reads
// the wall clock. The 3-day settling is exercised by moving a variable, not
// by waiting three days — and it can be moved BACKWARDS, which no real clock
// allows and which is exactly the case W08's "nothing is ever deleted" has to
// survive.
//
// DETERMINISM. The simulation is driven with fixed seeds, `step(dt:)` and
// taps: no timers, no sleeps, no wall clock, no test-order dependence. Every
// loop carries a hard iteration cap so a regression can only ever fail the
// test, never hang CI.
//
// The ONE input that is not seeded is `MapStore.ensureGenesis`, which draws
// its first stone's seed from `UInt64.random`. So the SHAPE of the Path (how
// many roads a stone opens, which pops sit on it) differs between runs while
// everything asserted below holds for every shape — nothing here asserts an
// exact road count or an exact pop set.
// ─────────────────────────────────────────────────────────────────────────
final class EndToEndJourneyTests: XCTestCase {

    private let fieldSize = CGSize(width: 390, height: 800)

    // MARK: - The hermetic world

    fileprivate final class TestClock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        suiteName = "vesper.tests.e2e.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        clock = nil
        super.tearDown()
    }

    fileprivate struct Stores {
        let progression: ProgressionStore
        let map: MapStore
        let settings: SettingsStore
    }

    /// Three stores over this test's own suite and its own clock. Built by
    /// the same call a relaunch would make, which is what makes the
    /// persistence journey below an honest one.
    private func makeStores() -> Stores {
        let clock = self.clock!
        return Stores(progression: ProgressionStore(defaults: defaults),
                      map: MapStore(defaults: defaults, now: { clock.now }),
                      settings: SettingsStore(defaults: defaults))
    }

    // MARK: - What a journey remembers

    /// One road on the map, as an edge rather than as a stone, so "no road is
    /// ever removed" can be checked as a set relation.
    fileprivate struct Edge: Hashable {
        let parent: UUID
        let child: UUID
    }

    /// Everything the game claims only ever accrues, read at one instant.
    fileprivate struct Ledger {
        var points = 0
        var lifetimePops = 0
        var fieldsCleared = 0
        var fortunes = 0
        var bestChain = 0
        var unlocked: Set<Int> = []
        var stones: Set<UUID> = []
        var roads: Set<Edge> = []
        var plays: [UUID: Int] = [:]
    }

    private func ledger(_ s: Stores) -> Ledger {
        var l = Ledger()
        l.points = s.progression.popPoints
        l.lifetimePops = s.progression.lifetimePops
        l.fieldsCleared = s.progression.fieldsCleared
        l.fortunes = s.progression.fortunesFound
        l.bestChain = s.progression.bestChain
        l.unlocked = s.progression.unlockedNumbers()
        l.stones = Set(s.map.stones.map(\.id))
        l.roads = Set(s.map.stones.compactMap { stone in
            stone.parentID.map { Edge(parent: $0, child: stone.id) }
        })
        l.plays = s.map.plays
        return l
    }

    /// Collects every moment the world went backwards.
    ///
    /// Gathered rather than asserted on the spot: a leak that fires on every
    /// one of five hundred pops would otherwise bury the report under five
    /// hundred identical failures, and the FIRST one is the one worth
    /// reading.
    fileprivate final class JourneyLog {
        private(set) var violations: [String] = []

        func note(_ text: String) {
            if violations.count < 24 { violations.append(text) }
        }

        func compare(_ before: Ledger, _ after: Ledger, at place: String) {
            func fell(_ name: String, _ a: Int, _ b: Int) {
                if b < a { self.note("\(place): \(name) fell \(a) → \(b)") }
            }
            fell("pop points", before.points, after.points)
            fell("lifetime pops", before.lifetimePops, after.lifetimePops)
            fell("fields cleared", before.fieldsCleared, after.fieldsCleared)
            fell("fortunes found", before.fortunes, after.fortunes)
            fell("best chain", before.bestChain, after.bestChain)

            let lostPops = before.unlocked.subtracting(after.unlocked)
            if !lostPops.isEmpty {
                note("\(place): unlocked pops were lost: \(lostPops.sorted())")
            }
            let lostStones = before.stones.subtracting(after.stones)
            if !lostStones.isEmpty {
                note("\(place): \(lostStones.count) stone(s) left the map")
            }
            let lostRoads = before.roads.subtracting(after.roads)
            if !lostRoads.isEmpty {
                note("\(place): \(lostRoads.count) road(s) left the map")
            }
            for (id, plays) in before.plays where (after.plays[id] ?? 0) < plays {
                note("\(place): a stone's play count fell \(plays) → \(after.plays[id] ?? 0)")
            }
        }
    }

    // MARK: - Playing one field, the way the view model does

    fileprivate struct FieldRecord {
        var index: Int
        var stage: Int
        var generation: Int
        var plays: Int
        /// Orbs this field was seeded with, surface and reserve together and
        /// generators excluded — the number the growth curves produce.
        var seededTotal: Int
        var seededGenerators: Int
        var taps = 0
        var frames = 0
        var iterations = 0
        var completed = false
        var roadsOpened = 0
        var longestChain = 0
        var weather: Weather = .clear
    }

    /// The scoring in `docs/pop_points.md`, mirrored here because
    /// `GameViewModel.points(for:sizeNorm:fortune:kind:)` is `private` and
    /// `@testable` does not reach it. NOTHING BELOW ASSERTS AGAINST THIS
    /// FUNCTION — it exists only so the journey feeds the store plausible
    /// numbers; every assertion is about what the store then does with them.
    private func pointsForPop(_ orb: Orb, chainLength: Int) -> Int {
        let def = PopCatalog.definition(for: orb.popNumber)
        let range = GameConfig.orbRadiusRange
        let sizeNorm = Double((orb.baseR - range.lowerBound) / (range.upperBound - range.lowerBound))
        var value = Double(def.rarity.pointValue) * (1 + 0.5 * sizeNorm)
        value *= min(1 + 0.1 * Double(max(0, chainLength - 1)), 2.0)
        if case .animal = orb.kind { value *= GameConfig.animalPointsMultiplier }
        if orb.isFortune { value += 50 }
        return Int(value.rounded())
    }

    /// Seeds the field the stone she is standing on describes, plays it to
    /// completion, and records everything into the stores exactly where
    /// `GameViewModel` records it.
    ///
    /// `framesBetweenTaps` is 55 — a shade over `GameConfig.chainWindow` at
    /// 60 fps — so two of her OWN taps are never counted as one cascade,
    /// while the chained pops a shockwave sets off in the frames after a tap
    /// still are. That is a player tapping about once a second, which is what
    /// the chain window was tuned against.
    @discardableResult
    private func playField(_ stores: Stores,
                           index: Int,
                           seed: UInt64,
                           log: JourneyLog,
                           framesBetweenTaps: Int = 55,
                           iterationLimit: Int = 1_200,
                           onFrame: ((GameSimulation) -> Void)? = nil) -> FieldRecord {

        // Exactly `GameViewModel.applyFieldPops()`: a field seeds from the
        // stone she stands on, its stage rides on lifetime fields cleared,
        // and its depth on where the stone sits and how often she has been
        // here.
        let stone = stores.map.activeStone
        let sim = GameSimulation(seed: seed)
        sim.layout(size: fieldSize)
        sim.availablePops = stone?.popNumbers ?? stores.progression.fieldPops()
        sim.stage = FieldPlan.stage(forFieldsCleared: stores.progression.fieldsCleared)
        sim.generation = stone?.generation ?? 0
        sim.plays = stone.map { stores.map.plays[$0.id] ?? 0 } ?? 0
        sim.seedField()

        var record = FieldRecord(
            index: index,
            stage: sim.stage,
            generation: sim.generation,
            plays: sim.plays,
            seededTotal: sim.orbs.count + sim.reserve.count - sim.plan.generators,
            seededGenerators: sim.plan.generators)
        record.weather = sim.weather

        var chain = 0
        var lastPopAt: TimeInterval?
        var seconds: TimeInterval = 0
        var before = ledger(stores)

        func absorb(_ events: [GameEvent]) {
            for event in events {
                switch event {
                case .popped(let orb, _):
                    if let last = lastPopAt, seconds - last < GameConfig.chainWindow {
                        chain += 1
                    } else {
                        chain = 1
                    }
                    lastPopAt = seconds
                    record.longestChain = max(record.longestChain, chain)
                    stores.progression.recordPop(popNumber: orb.popNumber,
                                                 points: pointsForPop(orb, chainLength: chain),
                                                 chainLength: chain)

                case .fortuneRevealed:
                    stores.progression.recordFortune()

                case .cleared:
                    stores.progression.recordClear(bonus: 100)
                    if stores.map.activeStoneID != nil {
                        let opened = stores.map.recordClear(
                            unlocked: stores.progression.unlockedNumbers())
                        record.roadsOpened = opened.count
                    }

                default:
                    break
                }
                // EVERY event, not only the recording ones. A shell breaking,
                // a generator closing and an orb rising must all leave every
                // counter exactly where they found it, and the only way to
                // know that is to look after each of them.
                let after = ledger(stores)
                log.compare(before, after, at: "field \(index)")
                before = after
            }
        }

        let dt = 1.0 / 60.0
        while !sim.completed && record.iterations < iterationLimit {
            record.iterations += 1
            if let target = sim.orbs.first(where: { $0.alive }) {
                absorb(sim.tap(at: target.pos))
                record.taps += 1
            }
            for _ in 0..<framesBetweenTaps {
                absorb(sim.step(dt: dt))
                seconds += dt
                record.frames += 1
                onFrame?(sim)
                if sim.completed { break }
            }
        }
        record.completed = sim.completed
        return record
    }

    /// Takes the first road ahead, the way the onward sequence does when
    /// there is one road and the way a tap on a star does when there is a
    /// fork.
    private func stepOnward(_ stores: Stores) {
        guard let currentID = stores.map.activeStoneID else { return }
        if let next = stores.map.roads(from: currentID).first {
            stores.map.setActive(next.id)
        }
    }

    /// Fastest anything of this kind is ever allowed to travel, from the
    /// three ceilings the simulation actually applies.
    private func speedCeiling(for orb: Orb, weather: Weather) -> CGFloat {
        let air = GameConfig.orbMaxSpeed * weather.speedScale * 1.6
        switch orb.kind {
        case .animal:
            // A startle is a briefly raised ceiling that decays with the
            // dart itself; `animalStartleSpeed` is the top of it.
            return GameConfig.animalStartleSpeed
        case .drifter:
            return max(air, GameConfig.evadeMaxSpeed)
        default:
            return air
        }
    }

    // MARK: - Fresh install to a dozen fields

    // The evening the product actually promises: open the app on a phone
    // that has never run it, and play field after field. The stage climbs on
    // the documented cadence, every field is finishable at every stage, and
    // the run never stalls.
    func testAFreshInstallPlaysADozenFieldsWithoutStallingAndTheStageClimbsThreeFieldsAtATime() {
        let stores = makeStores()
        XCTAssertEqual(stores.progression.fieldsCleared, 0, "this is not a fresh install")
        XCTAssertEqual(stores.progression.unlockedNumbers(), Set([PopCatalog.classic.number]),
                       "a first launch has exactly the classic pop and nothing else")

        stores.map.ensureGenesis(unlocked: stores.progression.unlockedNumbers())
        XCTAssertEqual(stores.map.stones.count, 1, "the map begins as one dot")
        stores.map.setActive(stores.map.stones[0].id)

        let log = JourneyLog()
        var records: [FieldRecord] = []
        for field in 0..<12 {
            let record = playField(stores, index: field, seed: 4_100 &+ UInt64(field), log: log)
            XCTAssertTrue(record.completed,
                          "field \(field + 1) (stage \(record.stage), generation "
                          + "\(record.generation), \(record.seededTotal) orbs) never finished")
            XCTAssertLessThan(record.iterations, 1_200,
                              "field \(field + 1) ran to the guard — the journey stalled")
            records.append(record)
            stepOnward(stores)
        }

        // THE CADENCE, as a literal table rather than as the same expression
        // that produced it: three fields at each step, so a new idea lands
        // about once an evening (FieldPlan.stage's own promise).
        XCTAssertEqual(records.map(\.stage), [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3],
                       "the stage did not climb one step per three cleared fields")

        // Each first clear opened at least one road and she took it, so the
        // twelve fields are twelve consecutive generations of the Path.
        XCTAssertEqual(records.map(\.generation), Array(0..<12),
                       "the journey did not walk twelve steps along the Path")
        for record in records {
            XCTAssertTrue((1...3).contains(record.roadsOpened),
                          "field \(record.index + 1) opened \(record.roadsOpened) roads")
            XCTAssertEqual(record.plays, 0, "no stone was replayed in this journey")
        }

        // A field gets LONGER as she goes and never grows past the cap that
        // keeps it finishable.
        for (a, b) in zip(records, records.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.seededTotal, a.seededTotal,
                                        "field \(b.index + 1) was shorter than the one before it")
        }
        XCTAssertGreaterThan(records.last!.seededTotal, records.first!.seededTotal,
                             "twelve steps along the Path produced no growth at all")
        for record in records {
            XCTAssertLessThanOrEqual(record.seededTotal, GameConfig.maxFieldOrbs,
                                     "field \(record.index + 1) grew past the cap")
        }

        XCTAssertEqual(stores.progression.fieldsCleared, 12)
        XCTAssertEqual(log.violations, [], "the journey went backwards")
    }

    // MARK: - Unlocks only ever arrive

    // Guardrail 1, over a whole evening. The collection is DERIVED from
    // counters that only rise, so an unlock cannot be lost — but "cannot" is
    // an argument about the code, and this is the measurement: the unlocked
    // set is read after every single event of a twelve-field journey and must
    // never lose a member.
    func testNoUnlockIsEverLostAcrossAWholeJourneyAndTheCollectionOnlyGrows() {
        let stores = makeStores()
        stores.map.ensureGenesis(unlocked: stores.progression.unlockedNumbers())
        stores.map.setActive(stores.map.stones[0].id)

        let log = JourneyLog()
        let opening = stores.progression.unlockedNumbers()
        var samples: [Set<Int>] = [opening]

        for field in 0..<12 {
            let record = playField(stores, index: field, seed: 7_700 &+ UInt64(field), log: log)
            XCTAssertTrue(record.completed, "field \(field + 1) never finished")
            samples.append(stores.progression.unlockedNumbers())
            stepOnward(stores)
        }

        for (earlier, later) in zip(samples, samples.dropFirst()) {
            XCTAssertTrue(earlier.isSubset(of: later),
                          "pops left the collection: \(earlier.subtracting(later).sorted())")
        }
        XCTAssertEqual(log.violations, [], "something in the journey was taken away")

        let closing = samples.last!
        XCTAssertTrue(opening.isSubset(of: closing))
        XCTAssertGreaterThan(closing.count, opening.count,
                             "twelve fields opened nothing new — the ladder is unreachable "
                             + "through ordinary play")

        // The early ladder pays off in the first evening, exactly where the
        // catalogue says it will: five cleared fields opens #008, three
        // fortunes opens #006.
        XCTAssertGreaterThanOrEqual(stores.progression.fieldsCleared, 5)
        XCTAssertTrue(closing.contains(8), "twelve cleared fields did not open #008")
        XCTAssertGreaterThanOrEqual(stores.progression.fortunesFound, 3)
        XCTAssertTrue(closing.contains(6), "the fortunes she found did not open #006")

        // At most one fortune rides a field, so she can never have found more
        // fortunes than she has cleared fields.
        XCTAssertLessThanOrEqual(stores.progression.fortunesFound,
                                 stores.progression.fieldsCleared,
                                 "more fortunes than fields — a field held two")
        XCTAssertGreaterThanOrEqual(stores.progression.fortunesFound, 8,
                                    "most fields should carry a fortune; almost none did")
    }

    // The catalogue declares each pop's door and the store answers it. Pinned
    // per rule KIND, at the exact threshold, from a store that has nothing
    // else in it — the six rules are the whole of §3 of pop_progression.md.
    func testTheEarlyLadderFiresAtExactlyTheThresholdsTheCatalogueDeclares() {
        // #002 · points(100)
        do {
            let store = ProgressionStore(defaults: defaults)
            XCTAssertFalse(store.isUnlocked(PopCatalog.definition(for: 2)))
            store.recordPop(popNumber: 1, points: 99, chainLength: 1)
            XCTAssertEqual(store.popPoints, 99)
            XCTAssertFalse(store.isUnlocked(PopCatalog.definition(for: 2)),
                           "#002 opened a point early")
            store.recordPop(popNumber: 1, points: 1, chainLength: 1)
            XCTAssertEqual(store.popPoints, 100)
            XCTAssertTrue(store.isUnlocked(PopCatalog.definition(for: 2)),
                          "#002 did not open on its own threshold")
            XCTAssertFalse(store.isUnlocked(PopCatalog.definition(for: 3)),
                           "#003 (250) opened at 100")
        }
        defaults.removePersistentDomain(forName: suiteName)

        // #004 · totalPops(150)
        do {
            let store = ProgressionStore(defaults: defaults)
            for _ in 0..<149 { store.recordPop(popNumber: 1, points: 0, chainLength: 1) }
            XCTAssertEqual(store.lifetimePops, 149)
            XCTAssertFalse(store.isUnlocked(PopCatalog.definition(for: 4)))
            store.recordPop(popNumber: 1, points: 0, chainLength: 1)
            XCTAssertTrue(store.isUnlocked(PopCatalog.definition(for: 4)))
        }
        defaults.removePersistentDomain(forName: suiteName)

        // #006 · fortunesFound(3)
        do {
            let store = ProgressionStore(defaults: defaults)
            store.recordFortune()
            store.recordFortune()
            XCTAssertFalse(store.isUnlocked(PopCatalog.definition(for: 6)))
            store.recordFortune()
            XCTAssertTrue(store.isUnlocked(PopCatalog.definition(for: 6)))
        }
        defaults.removePersistentDomain(forName: suiteName)

        // #008 · fieldsCleared(5)
        do {
            let store = ProgressionStore(defaults: defaults)
            for _ in 0..<4 { store.recordClear(bonus: 0) }
            XCTAssertFalse(store.isUnlocked(PopCatalog.definition(for: 8)))
            store.recordClear(bonus: 0)
            XCTAssertTrue(store.isUnlocked(PopCatalog.definition(for: 8)))
        }
        defaults.removePersistentDomain(forName: suiteName)

        // #010 · bestChain(4) — and a shorter chain afterwards never closes it
        do {
            let store = ProgressionStore(defaults: defaults)
            store.recordPop(popNumber: 1, points: 0, chainLength: 3)
            XCTAssertFalse(store.isUnlocked(PopCatalog.definition(for: 10)))
            store.recordPop(popNumber: 1, points: 0, chainLength: 4)
            XCTAssertTrue(store.isUnlocked(PopCatalog.definition(for: 10)))
            store.recordPop(popNumber: 1, points: 0, chainLength: 1)
            XCTAssertEqual(store.bestChain, 4, "best chain is a record, not a reading")
            XCTAssertTrue(store.isUnlocked(PopCatalog.definition(for: 10)),
                          "a quiet tap took a pop back off her")
        }
    }

    // The ladder itself only ever climbs: inside each rule the thresholds
    // rise strictly with the pop number, so walking the catalogue in order is
    // walking it in the order it opens. The three SECRETS are excepted
    // deliberately — they are out of order on purpose (#050 asks for a chain
    // of 10 while #066 asks for 8), which is what makes them secrets rather
    // than the next rung.
    func testWithinEachRuleTheLadderNeverStepsBackwards() {
        var lastPoints = 0, lastTotalPops = 0, lastFields = 0, lastFortunes = 0, lastChain = 0
        var counted = 0

        for def in PopCatalog.all.sorted(by: { $0.number < $1.number }) {
            if def.rarity == .secret { continue }
            func climbs(_ name: String, _ previous: inout Int, _ next: Int) {
                XCTAssertGreaterThan(next, previous,
                                     "#\(def.number) asks for \(next) \(name) after "
                                     + "an earlier pop asked for \(previous)")
                previous = next
                counted += 1
            }
            switch def.unlock {
            case .start: break
            case .points(let n): climbs("points", &lastPoints, n)
            case .totalPops(let n): climbs("pops", &lastTotalPops, n)
            case .fieldsCleared(let n): climbs("fields", &lastFields, n)
            case .fortunesFound(let n): climbs("fortunes", &lastFortunes, n)
            case .bestChain(let n): climbs("chain", &lastChain, n)
            }
        }

        XCTAssertGreaterThan(counted, 90, "almost nothing was checked — the walk found no rules")
        XCTAssertEqual(PopCatalog.all.filter { $0.rarity == .secret }.count, 3,
                       "the exception above is for the three secrets and only those")
        XCTAssertEqual(PopCatalog.all.filter { if case .start = $0.unlock { return true }
                                               else { return false } }.count, 1,
                       "exactly one pop is there from the start")
    }

    // MARK: - Nothing is ever spent

    // GUARDRAIL 1, MEASURED. Not "no code path subtracts" as a reading of the
    // source, but: play a long evening and watch every number after every
    // event. There must be no route through the game that reduces any of
    // them.
    func testNothingIsEverSpentAcrossAnEntireEvening() {
        let stores = makeStores()
        stores.map.ensureGenesis(unlocked: stores.progression.unlockedNumbers())
        stores.map.setActive(stores.map.stones[0].id)

        let log = JourneyLog()
        var previous = ledger(stores)

        for field in 0..<10 {
            // Every third field is a return to the stone she just cleared —
            // a replay is the one action that most looks like it ought to
            // cost something, and it is the one that must cost nothing.
            let record = playField(stores, index: field, seed: 2_300 &+ UInt64(field), log: log)
            XCTAssertTrue(record.completed, "field \(field + 1) never finished")

            let now = ledger(stores)
            XCTAssertGreaterThan(now.points, previous.points,
                                 "a whole field earned nothing — every pop must pay")
            XCTAssertGreaterThan(now.lifetimePops, previous.lifetimePops)
            XCTAssertEqual(now.fieldsCleared, previous.fieldsCleared + 1)
            previous = now

            // Every third field she stays where she is, so the next one is a
            // return to a stone she has already cleared.
            if field % 3 != 2 { stepOnward(stores) }
        }

        XCTAssertEqual(log.violations, [], "something was spent, lost or reset")

        // And the store itself refuses to go down even when it is handed a
        // negative. There is no wallet, so there is nothing to debit.
        let before = ledger(stores)
        stores.progression.recordPop(popNumber: PopCatalog.classic.number,
                                     points: -5_000, chainLength: 1)
        stores.progression.recordClear(bonus: -5_000)
        XCTAssertGreaterThanOrEqual(stores.progression.popPoints, before.points,
                                    "a negative amount reduced the lifetime total")
        XCTAssertEqual(stores.progression.lifetimePops, before.lifetimePops + 1)
        XCTAssertEqual(stores.progression.fieldsCleared, before.fieldsCleared + 1)
        XCTAssertEqual(stores.progression.bestChain, before.bestChain,
                       "a short chain lowered the record")
        XCTAssertTrue(before.unlocked.isSubset(of: stores.progression.unlockedNumbers()),
                      "the negative closed a door that was already open")
    }

    // MARK: - The map grows and never shrinks (W08)

    // The Path's half of the same promise. First clears open roads, replays
    // open none, and across the whole journey — including the stones she
    // walked away from and the forks she never took — nothing is removed.
    func testTheMapOnlyEverGrowsAndAReplayOpensNoNewRoads() {
        let stores = makeStores()
        stores.map.ensureGenesis(unlocked: stores.progression.unlockedNumbers())
        let genesisID = stores.map.stones[0].id
        stores.map.setActive(genesisID)

        let log = JourneyLog()
        var everSeenStones = Set<UUID>(stores.map.stones.map(\.id))
        var everSeenRoads = Set<Edge>()
        var untakenForks = Set<UUID>()

        for field in 0..<8 {
            let currentID = stores.map.activeStoneID!
            let stonesBefore = stores.map.stones.count
            let alreadyCleared = stores.map.stones.first { $0.id == currentID }!.cleared

            let record = playField(stores, index: field, seed: 5_500 &+ UInt64(field), log: log)
            XCTAssertTrue(record.completed, "field \(field + 1) never finished")

            if alreadyCleared {
                XCTAssertEqual(record.roadsOpened, 0,
                               "a replay opened \(record.roadsOpened) new roads")
                XCTAssertEqual(stores.map.stones.count, stonesBefore,
                               "a replay laid new stones")
            } else {
                XCTAssertTrue((1...3).contains(record.roadsOpened),
                              "a first clear opened \(record.roadsOpened) roads")
                XCTAssertEqual(stores.map.stones.count, stonesBefore + record.roadsOpened,
                               "the roads that opened are not the stones that appeared")
            }

            let now = ledger(stores)
            XCTAssertTrue(everSeenStones.isSubset(of: now.stones), "a stone left the map")
            XCTAssertTrue(everSeenRoads.isSubset(of: now.roads), "a road left the map")
            everSeenStones.formUnion(now.stones)
            everSeenRoads.formUnion(now.roads)

            // Every third field she stays where she is, so the next one is a
            // return to a stone she has already cleared. Every fork she walks
            // past is remembered, to be checked at the end.
            let roads = stores.map.roads(from: currentID)
            untakenForks.formUnion(roads.dropFirst().map(\.id))
            let staying = (field % 3 == 2) || roads.isEmpty
            if !staying { stores.map.setActive(roads[0].id) }
        }

        XCTAssertEqual(log.violations, [], "the map went backwards")
        XCTAssertTrue(everSeenStones.isSubset(of: Set(stores.map.stones.map(\.id))),
                      "a stone that once existed is gone")
        XCTAssertTrue(stores.map.stones.contains { $0.id == genesisID },
                      "the first stone of the journey is the one most worth keeping")

        // A road she did not take is still there and still walkable — the
        // difference between a branching path and a skill tree.
        for fork in untakenForks {
            XCTAssertTrue(stores.map.stones.contains { $0.id == fork },
                          "an untaken fork left the map")
            stores.map.setActive(fork)
            XCTAssertEqual(stores.map.activeStoneID, fork,
                           "an untaken fork is no longer walkable")
        }

        // The play counter is a tally of visits, and a replayed stone was
        // visited more than once.
        let replayed = stores.map.plays.filter { $0.value > 1 }
        XCTAssertFalse(replayed.isEmpty, "no stone was replayed — the replay half is untested")
        for (_, plays) in stores.map.plays {
            XCTAssertGreaterThan(plays, 0, "a stone was cleared zero times but has a tally")
        }
    }

    // MARK: - A replayed stone is bigger, and still bounded

    // "Second visit is twice the field, third and beyond is three times", and
    // then it holds steady — because a field that grows without end is a
    // field she cannot finish, and finishing is the point.
    //
    // Driven entirely through the real play counter: nothing here sets
    // `plays` by hand, it is whatever `MapStore.recordClear` has counted.
    func testAReplayedStoneIsBiggerButStillBoundedAndStillFinishable() {
        let stores = makeStores()
        stores.map.ensureGenesis(unlocked: stores.progression.unlockedNumbers())
        let genesisID = stores.map.stones[0].id
        stores.map.setActive(genesisID)

        let log = JourneyLog()
        var visits: [FieldRecord] = []
        for visit in 0..<5 {
            let record = playField(stores, index: visit, seed: 9_100 &+ UInt64(visit), log: log)
            XCTAssertTrue(record.completed,
                          "visit \(visit + 1) to the same stone (\(record.seededTotal) orbs) "
                          + "could not be finished")
            visits.append(record)
        }

        XCTAssertEqual(visits.map(\.plays), [0, 1, 2, 3, 4],
                       "the play counter did not count her visits")
        XCTAssertEqual(stores.map.plays[genesisID], 5)

        // The first three visits share a stage (three cleared fields is where
        // the stage first moves), so only the replay multiplier differs — and
        // it is exactly [1, 2, 3].
        XCTAssertEqual(Array(visits.prefix(3)).map(\.stage), [0, 0, 0],
                       "the stage moved mid-comparison; the multipliers are not isolated")
        XCTAssertEqual(visits[1].seededTotal, visits[0].seededTotal * 2,
                       "a second visit should be twice the field")
        XCTAssertEqual(visits[2].seededTotal, visits[0].seededTotal * 3,
                       "a third visit should be three times the field")

        // Visits four and five share a stage too, and by then the multiplier
        // has stopped growing: the same stone, the same field.
        XCTAssertEqual(visits[3].stage, visits[4].stage)
        XCTAssertEqual(visits[3].seededTotal, visits[4].seededTotal,
                       "the replay multiplier kept climbing past its last step")

        for visit in visits {
            XCTAssertLessThanOrEqual(visit.seededTotal, GameConfig.maxFieldOrbs,
                                     "a replay grew past the cap that keeps a field finishable")
        }
        XCTAssertTrue((1...3).contains(visits[0].roadsOpened),
                      "the first clear did not open the Path")
        for visit in visits.dropFirst() {
            XCTAssertEqual(visit.roadsOpened, 0,
                           "visit \(visit.index + 1) opened a road — replays open none")
        }
        XCTAssertEqual(log.violations, [])
    }

    // The largest field the growth curves can build — the cap itself — with
    // every mechanic on it. If anything is ever unfinishable, it is this.
    func testTheDeepestFieldTheGameCanBuildIsStillFinishable() {
        let sim = GameSimulation(seed: 31)
        sim.layout(size: fieldSize)
        sim.stage = FieldPlan.finalStage
        sim.generation = 40
        sim.plays = 2
        sim.availablePops = Array(1...30)
        sim.seedField()

        let total = sim.orbs.count + sim.reserve.count - sim.plan.generators
        XCTAssertEqual(total, GameConfig.maxFieldOrbs,
                       "generation 40 with two replays behind it should sit at the cap")
        XCTAssertLessThanOrEqual(sim.orbs.count,
                                 GameConfig.surfaceCapacity + sim.plan.generators,
                                 "the cap-sized field crowded the glass instead of going deep")

        var iterations = 0
        while !sim.completed && iterations < 6_000 {
            iterations += 1
            if let target = sim.orbs.first(where: { $0.alive }) {
                sim.tap(at: target.pos)
            }
            for _ in 0..<20 {
                sim.step(dt: 1.0 / 60)
                if sim.completed { break }
            }
        }
        XCTAssertTrue(sim.completed, "the biggest field the game can build cannot be finished")
        XCTAssertLessThan(iterations, 6_000, "it finished only by exhausting the guard")
        XCTAssertTrue(sim.reserve.isEmpty, "a cleared field still had orbs waiting below it")
    }

    // MARK: - The calm holds throughout

    // At no point in a journey does an orb outrun the ceilings, drift off the
    // glass, or leave the field in a state that cannot be finished. Sampled
    // on EVERY frame of six whole fields — the failures this is looking for
    // are the ones that last a frame and a half.
    func testTheCalmHoldsOnEveryFrameOfAJourney() {
        let stores = makeStores()
        stores.map.ensureGenesis(unlocked: stores.progression.unlockedNumbers())
        stores.map.setActive(stores.map.stones[0].id)

        let log = JourneyLog()
        var tooFast: [String] = []
        var offGlass: [String] = []
        var stranded = 0
        var framesWatched = 0

        for field in 0..<6 {
            let record = playField(stores, index: field, seed: 6_600 &+ UInt64(field), log: log) { sim in
                framesWatched += 1
                for orb in sim.orbs where orb.alive {
                    let speed = (orb.vel.dx * orb.vel.dx + orb.vel.dy * orb.vel.dy).squareRoot()
                    let ceiling = self.speedCeiling(for: orb, weather: sim.weather)
                    if speed > ceiling + 0.0001, tooFast.count < 8 {
                        tooFast.append("\(orb.kind) reached \(speed) in \(sim.weather) "
                                       + "(ceiling \(ceiling))")
                    }
                    if orb.pos.x < 0 || orb.pos.x > self.fieldSize.width
                        || orb.pos.y < 0 || orb.pos.y > self.fieldSize.height,
                       offGlass.count < 8 {
                        offGlass.append("\(orb.kind) drifted to \(orb.pos)")
                    }
                }
                // NOTHING LEFT AND NOT FINISHED is the one state a field must
                // never reach: no orb to tap, nothing waiting below, and no
                // done card — a quiet screen she cannot leave.
                if sim.aliveCount == 0 && sim.reserve.isEmpty && !sim.completed {
                    stranded += 1
                }
            }
            XCTAssertTrue(record.completed, "field \(field + 1) never finished")
        }

        XCTAssertGreaterThan(framesWatched, 800, "hardly any frames were watched")
        XCTAssertGreaterThan(stores.progression.lifetimePops, 80,
                             "six fields set fewer than eighty orbs free — nothing was watched")
        XCTAssertEqual(tooFast, [], "the field outran its ceiling")
        XCTAssertEqual(offGlass, [], "an orb left the glass")
        XCTAssertEqual(stranded, 0,
                       "the field emptied without ever declaring itself clear — "
                       + "\(stranded) frames with nothing to do and no way out")
        XCTAssertEqual(log.violations, [], "a counter ran backwards during the journey")
    }

    // MARK: - Persistence across a relaunch

    // The evening ends, the app is killed, and it opens again tomorrow. Every
    // counter, every stone, every road, every play count and the featured pop
    // must be exactly what she left — read by stores built the same way a
    // cold launch builds them, over the same defaults.
    func testEveryCounterStoneRoadAndPlayCountSurvivesARelaunch() {
        let first = makeStores()
        first.map.ensureGenesis(unlocked: first.progression.unlockedNumbers())
        first.map.setActive(first.map.stones[0].id)

        let log = JourneyLog()
        for field in 0..<6 {
            let record = playField(first, index: field, seed: 8_800 &+ UInt64(field), log: log)
            XCTAssertTrue(record.completed, "field \(field + 1) never finished")
            if field % 2 == 1 { stepOnward(first) }
        }
        XCTAssertEqual(log.violations, [])

        // She also chose a pop to sit with before closing the app.
        let chosen = first.progression.unlockedNumbers().sorted().last!
        first.progression.featuredPop = chosen
        first.settings.soundEnabled = false

        XCTAssertGreaterThan(first.progression.popPoints, 0, "nothing was earned to persist")
        XCTAssertGreaterThan(first.map.stones.count, 1, "no map was built to persist")

        // The relaunch.
        let second = makeStores()

        XCTAssertEqual(second.progression.popPoints, first.progression.popPoints)
        XCTAssertEqual(second.progression.lifetimePops, first.progression.lifetimePops)
        XCTAssertEqual(second.progression.fieldsCleared, first.progression.fieldsCleared)
        XCTAssertEqual(second.progression.fortunesFound, first.progression.fortunesFound)
        XCTAssertEqual(second.progression.bestChain, first.progression.bestChain)
        XCTAssertEqual(second.progression.popCounts, first.progression.popCounts,
                       "the per-pop tallies are the diary; they must survive whole")
        XCTAssertEqual(second.progression.featuredPop, chosen,
                       "the pop she chose to sit with was forgotten overnight")
        XCTAssertEqual(second.progression.unlockedNumbers(),
                       first.progression.unlockedNumbers(),
                       "the collection is derived from the counters, so it must land identically")
        XCTAssertFalse(second.settings.soundEnabled)

        // The map, stone by stone. Dates are deliberately not compared — the
        // JSON round-trip of a `Date` is not the subject here; the shape of
        // the Path is.
        XCTAssertEqual(second.map.stones.map(\.id), first.map.stones.map(\.id),
                       "stones were lost or reordered by the relaunch")
        XCTAssertEqual(second.map.stones.map(\.parentID), first.map.stones.map(\.parentID),
                       "the roads between the stones did not survive")
        XCTAssertEqual(second.map.stones.map(\.generation), first.map.stones.map(\.generation))
        XCTAssertEqual(second.map.stones.map(\.popNumbers), first.map.stones.map(\.popNumbers))
        XCTAssertEqual(second.map.stones.map(\.seed), first.map.stones.map(\.seed),
                       "a stone's seed is what makes its roads reproducible")
        XCTAssertEqual(second.map.stones.map(\.cleared), first.map.stones.map(\.cleared))
        XCTAssertEqual(second.map.activeStoneID, first.map.activeStoneID,
                       "she came back somewhere other than where she was standing")
        XCTAssertEqual(second.map.plays, first.map.plays,
                       "the play counts drive the replay multiplier and must survive")

        // And the very next thing a launch does is safe: genesis does not lay
        // a second first stone over a map that already exists.
        let before = second.map.stones.map(\.id)
        second.map.ensureGenesis(unlocked: second.progression.unlockedNumbers())
        XCTAssertEqual(second.map.stones.map(\.id), before,
                       "a relaunch laid a new genesis over an existing Path")

        // Tomorrow's field is the stone she left off on, at the depth she
        // left it at.
        let resumed = playField(second, index: 99, seed: 8_899, log: log)
        XCTAssertTrue(resumed.completed)
        XCTAssertEqual(resumed.generation, second.map.activeStone?.generation)
        // Six cleared fields, three fields to a step: stage two, resumed from
        // the counter that persisted rather than from anything in memory.
        XCTAssertEqual(resumed.stage, 2,
                       "the stage did not resume from the counters that persisted")
    }

    // MARK: - The 3-day settling, on an injected clock

    // Settling is a READING of the stone's own dates against the clock, never
    // a write — which is why W08 needed no schema and no migration, and why
    // a stone that settles is still there, still playable and still drawn.
    func testAStoneSettlesOnTheThresholdAndIsNeverDestroyedByAnyClock() {
        // Three days, stated as the number the design doc states rather than
        // as the expression the constant is written with.
        XCTAssertEqual(MapStore.fadeAfter, 259_200, accuracy: 0.5,
                       "the settle window is documented as three days")

        let stores = makeStores()
        stores.map.ensureGenesis(unlocked: stores.progression.unlockedNumbers())
        let genesisID = stores.map.stones[0].id
        stores.map.setActive(genesisID)

        let log = JourneyLog()
        var record = playField(stores, index: 0, seed: 3_300, log: log)
        XCTAssertTrue(record.completed)
        stepOnward(stores)
        record = playField(stores, index: 1, seed: 3_301, log: log)
        XCTAssertTrue(record.completed)

        let everything = stores.map.stones.map(\.id)
        XCTAssertGreaterThan(everything.count, 2, "not enough Path to settle")
        let genesis = stores.map.stones.first { $0.id == genesisID }!
        let touched = genesis.lastPlayedAt ?? genesis.createdAt

        // ONE SECOND EITHER SIDE OF THE THRESHOLD.
        XCTAssertFalse(SkyLayout.isSettled(genesis,
                                           now: touched.addingTimeInterval(MapStore.fadeAfter - 1)),
                       "a stone settled a second before the window closed")
        XCTAssertTrue(SkyLayout.isSettled(genesis,
                                          now: touched.addingTimeInterval(MapStore.fadeAfter + 1)),
                      "a stone was still bright a second after the window closed")

        // A SEASON AWAY. The store is rebuilt over the same defaults with the
        // clock far in the future, which is what a return after a holiday
        // actually is.
        clock.now = clock.now.addingTimeInterval(200 * 24 * 60 * 60)
        let returned = makeStores()
        returned.map.ensureGenesis(unlocked: returned.progression.unlockedNumbers())
        XCTAssertEqual(returned.map.stones.map(\.id), everything,
                       "a season away cost her stones — history only accrues")

        // A settled stone is STILL PLAYABLE. Nothing about settling touches
        // reachability, so the oldest stone on the map can be walked back to
        // and cleared again.
        returned.map.setActive(genesisID)
        XCTAssertEqual(returned.map.activeStoneID, genesisID,
                       "a settled stone could not be stepped onto")
        let replay = playField(returned, index: 2, seed: 3_302, log: log)
        XCTAssertTrue(replay.completed, "a settled stone's field could not be finished")
        XCTAssertEqual(replay.roadsOpened, 0, "a replay of a settled stone opened new roads")
        XCTAssertEqual(Set(returned.map.stones.map(\.id)), Set(everything),
                       "replaying a settled stone changed what the map holds")

        // AND ITS ROAD IS STILL DRAWN. `SkyLayout` is what the sky renders
        // from; a settled road that came back as nothing would be the trace
        // being a lie about the map.
        let sky = SkyLayout(stones: returned.map.stones,
                            activeID: returned.map.activeStoneID,
                            anchorID: returned.map.anchorStone?.id,
                            now: clock.now,
                            size: fieldSize)
        XCTAssertEqual(sky.stars.count, returned.map.stones.count,
                       "a stone the store still holds was not placed in the sky")
        let expectedRoads = returned.map.stones.filter { $0.parentID != nil }.count
        XCTAssertEqual(sky.roads.count, expectedRoads,
                       "a road between two stones the sky is drawing was not drawn")
        XCTAssertTrue(sky.roads.contains { $0.tier == .settled },
                      "after a season nothing reads as trace")

        // THE CLOCK GOES BACKWARDS. A device whose time is corrected, a
        // timezone crossed, a manual change — none of it may destroy
        // anything, and a stone simply stops reading as settled.
        clock.now = Date(timeIntervalSince1970: 0)
        let rewound = makeStores()
        rewound.map.ensureGenesis(unlocked: rewound.progression.unlockedNumbers())
        XCTAssertEqual(rewound.map.stones.map(\.id), everything,
                       "winding the clock backwards destroyed part of the Path")
        XCTAssertFalse(SkyLayout.isSettled(genesis, now: clock.now),
                       "a stone from the future reads as settled")
        rewound.map.setActive(genesisID)
        XCTAssertEqual(rewound.map.activeStoneID, genesisID,
                       "a stone became unplayable because the clock moved")
        XCTAssertEqual(log.violations, [])
    }

    // Settling changes what the sky LEADS WITH, never what the map holds —
    // the whole of the W08 argument, checked as one before-and-after.
    func testSettlingChangesHowTheMapLooksAndNothingAboutWhatItHolds() {
        let stores = makeStores()
        stores.map.ensureGenesis(unlocked: stores.progression.unlockedNumbers())
        stores.map.setActive(stores.map.stones[0].id)

        let log = JourneyLog()
        XCTAssertTrue(playField(stores, index: 0, seed: 1_200, log: log).completed)
        stepOnward(stores)
        XCTAssertTrue(playField(stores, index: 1, seed: 1_201, log: log).completed)

        let fresh = SkyLayout(stones: stores.map.stones,
                              activeID: stores.map.activeStoneID,
                              anchorID: stores.map.anchorStone?.id,
                              now: clock.now,
                              size: fieldSize)
        XCTAssertFalse(fresh.roads.contains { $0.tier == .settled },
                       "something settled inside the three-day window")

        let later = clock.now.addingTimeInterval(MapStore.fadeAfter + 60)
        let settled = SkyLayout(stones: stores.map.stones,
                                activeID: stores.map.activeStoneID,
                                anchorID: stores.map.anchorStone?.id,
                                now: later,
                                size: fieldSize)

        XCTAssertEqual(settled.stars.map(\.stone.id), fresh.stars.map(\.stone.id),
                       "the sky dropped a star as the days passed")
        XCTAssertEqual(settled.roads.count, fresh.roads.count,
                       "the sky dropped a road as the days passed")
        XCTAssertTrue(settled.stars.contains { $0.isSettled },
                      "three days passed and nothing became the map's memory")
        XCTAssertEqual(Set(stores.map.stones.map(\.id)),
                       Set(fresh.stars.map(\.stone.id)),
                       "drawing the sky changed the store")
    }
}
