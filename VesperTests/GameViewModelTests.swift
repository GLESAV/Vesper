import XCTest
import Foundation
import CoreGraphics
@testable import Vesper

// The bridge under test: `GameViewModel` is the only place where a pure
// simulation event becomes a number, a note, a card, or a journey. Everything
// downstream of a pop — pop points, the chain whisper, the unlock capsule,
// the done card, the onward sequence — is decided here, and until now none of
// it had a test.
//
// WHAT THESE TESTS ARE ALLOWED TO KNOW. The scoring contract is
// `docs/pop_points.md`, so the rarity bases (10 · 25 · 60 · 150), the size
// factor (×1 … ×1.5), the chain curve (+0.1 per link, capped at ×2), the
// fortune bonus (+50) and the field-clear bonus (+100) are written here as
// LITERALS. Asserting them against the view model's own arithmetic would only
// prove that the expression equals itself; asserting them against the document
// is what makes a silent retune of the economy show up as a red test.
//
// DETERMINISM. Fields are installed exactly (`GameSimulation.replaceOrbs`,
// which also pins the weather to still air), never seeded randomly, and every
// measurement starts from `restart()` — which clears the chain streak, so the
// pop that follows it is always the first link of a fresh chain. Time arrives
// only as `step(dt:)` through `frame(date:size:)`, with synthetic dates.
//
// THE ONE PLACE WALL-CLOCK LEAKS IN, stated so nobody mistakes it for an
// oversight: `noteChainProgress()` measures the chain window with `Date()`
// rather than with simulation time (see the report accompanying this file), so
// the chain the view model sees depends on how fast the machine got from one
// statement to the next.
//
// NO TEST HERE IS ALLOWED TO DEPEND ON THAT. Every chain assertion below is
// one of two kinds. The first holds whatever the runner did — a link never
// pays less than the unchained base and never more than the ×2 ceiling, and
// the whisper, whenever it is raised at all, names the multiplier that was
// paid. The second — the exact curve — is asserted only once the run has
// PROVEN the links landed inside `GameConfig.chainWindow`, by bracketing each
// tap with its own wall-clock reading (`chainProvenUnbroken`). The clock
// therefore decides whether the stronger assertion is owed and never what it
// says: a stalled runner loses coverage, it cannot go red. Nothing anywhere
// in this file waits, sleeps, or holds an expectation open on a real timeout.
//
// SHARED SINGLETONS. The view model reaches `ProgressionStore.shared`,
// `SettingsStore.shared` and `MapStore.shared` directly and is not injectable,
// so NOTHING here asserts an absolute value read from a store — only deltas
// across an operation. The two pieces of shared state these tests do move
// (whether point whispers are on, and which stone she stands on) are saved and
// put back by the test that moved them, in a `defer` taken before the first
// assertion, so a failure restores them exactly as a pass does.
//
// WHAT CANNOT BE PUT BACK is the ledger itself: popping an orb writes to
// `ProgressionStore.shared`, and by design nothing there can be un-counted.
// Every test here therefore leaves the lifetime numbers a little larger, and
// nothing here — or in any other suite — may read them absolutely. Clearing a
// field is the same story on `MapStore.shared`, so any test whose subject is
// not the Path steps off it first (`stepOffThePath`), and the two that clear
// ON the genesis stone rely on `MapStore.recordClear` opening a stone's roads
// only once: repeated CI runs re-clear it, they do not grow it.
//
// NOTHING HERE WIPES `UserDefaults` OR CALLS `resetToFreshInstall`. These are
// the live suites the app itself uses, shared with every other test class, and
// a reset from here would be someone else's random failure.
//
// `@MainActor` mirrors `WorldRegressionTests`, which already constructs a
// `GameViewModel` this way: `restart()` runs `withAnimation` and the event
// path hops the main queue.
@MainActor
final class GameViewModelTests: XCTestCase {

    // MARK: - The reference device and the fixtures

    private let screen = CGSize(width: 390, height: 844)
    private let origin = Date(timeIntervalSinceReferenceDate: 0)

    /// A view model with its field laid out, exactly as the first frame does
    /// it. `dt` is zero on this call, so nothing has moved yet.
    private func makeGame() -> GameViewModel {
        let vm = GameViewModel()
        vm.simActive = true
        vm.frame(date: origin, size: screen)
        XCTAssertFalse(vm.sim.orbs.isEmpty, "the field never seeded — later installs would reseed")
        return vm
    }

    private func makeOrb(at pos: CGPoint,
                         r: CGFloat = GameConfig.orbRadiusRange.lowerBound,
                         pop: Int = PopCatalog.classic.number,
                         fortune: Bool = false,
                         kind: OrbKind = .plain) -> Orb {
        var o = Orb(pos: pos, vel: .zero, r: r, baseR: r,
                    popNumber: pop, variantIndex: 0, phase: 0)
        o.spawn = 1
        o.isFortune = fortune
        o.kind = kind
        return o
    }

    /// A second orb, parked far from everything, so popping the subject does
    /// not also clear the field and fold the +100 into the measurement.
    private var spare: Orb { makeOrb(at: CGPoint(x: 330, y: 780)) }

    /// The points one pop earns, measured through the published surface —
    /// `points(for:sizeNorm:fortune:kind:)` is private, and reaching for it
    /// would test an implementation rather than a promise.
    ///
    /// `restart()` first: it zeroes the session and the chain streak, so this
    /// is always the first link of a chain (multiplier ×1) no matter what the
    /// test did a moment ago or how long the machine took to get here.
    @discardableResult
    private func earned(popping target: Orb, in vm: GameViewModel,
                        file: StaticString = #filePath, line: UInt = #line) -> Int {
        vm.restart()
        vm.sim.replaceOrbs([spare, target])
        let before = vm.sessionPoints
        vm.tap(at: target.pos)
        XCTAssertEqual(vm.sim.popCount, 1,
                       "the tap did not land on the subject orb", file: file, line: line)
        XCTAssertFalse(vm.sim.completed,
                       "the field cleared — the +100 is in this measurement", file: file, line: line)
        return vm.sessionPoints - before
    }

    private func firstPop(_ rarity: PopRarity,
                          file: StaticString = #filePath, line: UInt = #line) -> PopDefinition? {
        guard let def = PopCatalog.all.first(where: { $0.rarity == rarity }) else {
            XCTFail("the catalog has no \(rarity.rawValue) pop to score with", file: file, line: line)
            return nil
        }
        return def
    }

    /// Steps her off the Path for the duration of one test, and returns where
    /// she was so the test can put her back.
    ///
    /// Clearing a field while a stone is active writes to the REAL shared map
    /// — and nothing on that map is ever deleted (W08) — so tests whose
    /// subject is not the Path clear their fields off it.
    private func stepOffThePath() -> UUID? {
        let saved = MapStore.shared.activeStoneID
        MapStore.shared.setActive(nil)
        return saved
    }

    /// Whether the chain the view model saw can be PROVEN unbroken.
    ///
    /// `noteChainProgress()` reads `Date()` from inside the tap, so the gap it
    /// measured between links k and k+1 is bounded above by the span from just
    /// before tap k to just after tap k+1. `marks` holds one instant taken
    /// immediately before each tap plus one taken after the last, so if every
    /// two-tap span came in under `GameConfig.chainWindow`, then every gap the
    /// view model itself measured did too — whatever the machine was doing in
    /// between, and without this test ever having to see `lastPopAt`.
    ///
    /// A bound, never a wait: this reads a clock that has already run and asks
    /// a question about the past.
    private func chainProvenUnbroken(_ marks: [Date]) -> Bool {
        guard marks.count > 2 else { return true }
        for k in 0..<(marks.count - 2) {
            if marks[k + 2].timeIntervalSince(marks[k]) >= GameConfig.chainWindow {
                return false
            }
        }
        return true
    }

    /// Events produced inside `frame(date:size:)` are applied on the next
    /// main-queue hop (the publishing-during-view-update hazard), so a test
    /// that wants to see them has to let the queue turn over.
    ///
    /// NOT A WAIT ON THE CLOCK. The main queue is FIFO, so every block the
    /// frames already enqueued runs before this one does; the timeout is a
    /// backstop against a wedged queue, never a delay this test is counting
    /// on. Delayed work (`asyncAfter`) is deliberately NOT observed this way —
    /// see the onward tests.
    private func hopTheMainQueue() {
        let hop = expectation(description: "deferred events applied")
        DispatchQueue.main.async { hop.fulfill() }
        wait(for: [hop], timeout: 2)
    }

    // MARK: - The scoring formula, one factor at a time

    // rarityBase. The first term of `points = rarityBase × sizeFactor ×
    // chainMultiplier (+ bonuses)`: at the smallest size, on the first pop of
    // a field, with no fortune and no creature, every other factor is 1 and
    // what lands in `sessionPoints` is the rarity base itself. This is the
    // one place the four numbers in docs/pop_points.md §2 are checked against
    // the game rather than against each other.
    func testEachRaritysBaseValueIsTheOneTheScoringDocumentPromises() {
        let promised: [PopRarity: Int] = [.common: 10, .uncommon: 25, .rare: 60, .secret: 150]
        let vm = makeGame()
        for (rarity, base) in promised {
            guard let def = firstPop(rarity) else { continue }
            let orb = makeOrb(at: CGPoint(x: 90, y: 220),
                              r: GameConfig.orbRadiusRange.lowerBound, pop: def.number)
            XCTAssertEqual(earned(popping: orb, in: vm), base,
                           "a \(rarity.rawValue) pop (#\(def.number) \(def.name)) at the smallest "
                           + "size, unchained, must be worth exactly its rarity base")
        }
    }

    // sizeFactor. Multiplicative on the rarity base and spanning exactly
    // ×1 … ×1.5 across the orb radius range — checked at both ends of the
    // range and on two different rarities, because a size factor that were
    // added rather than multiplied would still pass at one rarity.
    func testAnOrbsSizeMultipliesItsWorthByOneToOneAndAHalf() {
        guard let common = firstPop(.common), let rare = firstPop(.rare) else { return }
        let vm = makeGame()
        let smallest = GameConfig.orbRadiusRange.lowerBound
        let largest = GameConfig.orbRadiusRange.upperBound
        let where_ = CGPoint(x: 90, y: 220)

        XCTAssertEqual(earned(popping: makeOrb(at: where_, r: smallest, pop: common.number), in: vm), 10,
                       "the smallest common orb is the rarity base, unscaled")
        XCTAssertEqual(earned(popping: makeOrb(at: where_, r: largest, pop: common.number), in: vm), 15,
                       "the largest orb must be worth ×1.5, not ×1 and not ×2")
        XCTAssertEqual(earned(popping: makeOrb(at: where_, r: smallest, pop: rare.number), in: vm), 60,
                       "the smallest rare orb is the rarity base, unscaled")
        XCTAssertEqual(earned(popping: makeOrb(at: where_, r: largest, pop: rare.number), in: vm), 90,
                       "the size factor must scale the rarity base, not add a flat amount to it")
    }

    // fortuneBonus. +50, and — the part worth pinning — ADDED after the size
    // factor rather than multiplied by it. A largest-orb fortune is 15 + 50,
    // not (10 + 50) × 1.5, and the difference between those two readings is
    // the difference between a gift and a jackpot.
    func testTheFortuneBonusIsFiftyFlatAndIsAddedAfterTheSizeFactorRatherThanScaledByIt() {
        guard let common = firstPop(.common) else { return }
        let vm = makeGame()
        let where_ = CGPoint(x: 90, y: 220)

        XCTAssertEqual(earned(popping: makeOrb(at: where_,
                                               r: GameConfig.orbRadiusRange.lowerBound,
                                               pop: common.number, fortune: true), in: vm),
                       10 + 50, "a fortune adds 50 to the pop it was hiding in")
        XCTAssertEqual(earned(popping: makeOrb(at: where_,
                                               r: GameConfig.orbRadiusRange.upperBound,
                                               pop: common.number, fortune: true), in: vm),
                       15 + 50, "the fortune bonus must not be scaled by the orb's size")
    }

    // The creature's multiplier — additive-only in spirit and multiplicative
    // in arithmetic (GameConfig.animalPointsMultiplier). It is read from the
    // tuning constant rather than written as a literal because it is a tuning
    // knob rather than a documented economy term; what is pinned here is that
    // it is applied at all, that it scales the base, and that meeting a
    // creature is never worth LESS than the same orb would have been.
    func testACreatureIsWorthItsMultiplierMoreThanTheSameOrbWouldHaveBeen() {
        guard let common = firstPop(.common) else { return }
        let vm = makeGame()
        let where_ = CGPoint(x: 90, y: 220)
        let r = GameConfig.orbRadiusRange.lowerBound

        let plain = earned(popping: makeOrb(at: where_, r: r, pop: common.number), in: vm)
        let creature = earned(popping: makeOrb(at: where_, r: r, pop: common.number,
                                               kind: .animal(AnimalPop(shape: .rabbit,
                                                                       health: 1, shyness: 0))),
                              in: vm)
        XCTAssertEqual(creature,
                       Int((Double(plain) * GameConfig.animalPointsMultiplier).rounded()),
                       "a creature must be worth the animal multiplier times the orb it stands in for")
        XCTAssertGreaterThan(creature, plain,
                             "the taps that did not finish it must never make it worth less")
    }

    // The field-clear bonus: +100 flat, on top of the pop that finished the
    // field, banked to the lifetime total in the same breath. And the half
    // that matters more — it is paid ONCE. A second touch on a field that is
    // already quiet must find nothing to award.
    func testClearingTheFieldPaysOneHundredOnceAndNeverAgain() {
        let saved = stepOffThePath()
        defer { MapStore.shared.setActive(saved) }

        let vm = makeGame()
        let last = makeOrb(at: CGPoint(x: 140, y: 300))
        vm.restart()
        vm.sim.replaceOrbs([last])

        let pointsBefore = vm.progression.popPoints
        let clearedBefore = vm.progression.fieldsCleared
        vm.tap(at: last.pos)
        vm.cancelOnward()

        XCTAssertTrue(vm.sim.completed, "the last orb did not finish the field")
        XCTAssertEqual(vm.sessionPoints, 10 + 100,
                       "the clear bonus is 100 on top of the pop that earned it")
        XCTAssertEqual(vm.progression.popPoints - pointsBefore, 110,
                       "the same 110 must reach the lifetime total")
        XCTAssertEqual(vm.progression.fieldsCleared - clearedBefore, 1)
        XCTAssertTrue(Verses.all.contains(vm.closingVerse),
                      "the done card's verse must come from the written set")
        XCTAssertFalse(vm.showDone,
                       "the card is revealed a beat later, never in the same instant as the pop")

        let banked = vm.sessionPoints
        vm.tap(at: last.pos)                      // where the last orb was
        vm.tap(at: CGPoint(x: 300, y: 600))       // and somewhere it never was
        XCTAssertEqual(vm.sessionPoints, banked,
                       "a quiet field must not pay the clear bonus a second time")
    }

    // MARK: - The chain

    // The window and its threshold. Two pops in quick succession are a pair,
    // not a chain: the whisper only appears at `chainNoteThreshold`, and when
    // it does, the number it says is the number that was scored — the doc's
    // "what the player sees and what they earn are one number".
    //
    // The deltas are the chain curve itself: ×1, ×1.1, ×1.2 on a base of 10.
    func testTheChainWhisperAppearsAtTheThirdLinkAndSaysTheNumberThatWasScored() {
        XCTAssertEqual(GameConfig.chainNoteThreshold, 3,
                       "this test is written against a threshold of three")
        let vm = makeGame()
        let field = (0..<5).map { makeOrb(at: CGPoint(x: 60 + 120 * CGFloat($0 % 3),
                                                      y: 200 + 140 * CGFloat($0 / 3))) }
        vm.restart()
        vm.sim.replaceOrbs(field)

        var deltas: [Int] = []
        var marks: [Date] = []
        var running = vm.sessionPoints
        for (k, orb) in field.prefix(3).enumerated() {
            marks.append(Date())
            vm.tap(at: orb.pos)
            deltas.append(vm.sessionPoints - running)
            running = vm.sessionPoints
            if k < 2 {
                XCTAssertNil(vm.chainNote,
                             "a chain of \(k + 1) is under the threshold and must stay silent")
            }
        }
        marks.append(Date())

        // TRUE WHATEVER THE MACHINE DID, and the heart of the promise: the
        // whisper can only be raised at all when all three links landed, and
        // all three links landing IS the curve. So the note and the money can
        // be held to each other without either of them being held to a clock.
        if let note = vm.chainNote {
            XCTAssertEqual(note, "chain of 3", "the whisper named a chain the field had not made")
            XCTAssertEqual(deltas, [10, 11, 12],
                           "the multiplier the whisper announces and the multiplier that was paid "
                           + "must be the same number")
        } else {
            XCTAssertEqual(deltas.first, 10, "the first link of any chain is unchained, at ×1")
            for (k, d) in deltas.enumerated() {
                XCTAssertTrue((10...12).contains(d),
                              "link \(k + 1) paid \(d): three links on a base of 10 span 10…12")
            }
        }

        // AND NOT VACUOUS, on any machine that got through three taps inside
        // the window — which is the only machine the whisper is provably owed
        // on. If this one stalled past it, the branch above is all that is
        // honestly provable, and it is what proves it.
        if chainProvenUnbroken(marks) {
            XCTAssertEqual(vm.chainNote, "chain of 3",
                           "three pops landed inside the chain window and nothing was whispered")
            XCTAssertEqual(deltas, [10, 11, 12],
                           "the chain curve is +0.1 per link on a base of 10")
        }
    }

    // The cap. Thirteen pops inside the window: the multiplier climbs by a
    // tenth a link and then SATURATES at ×2 and stays there — which is what
    // keeps a cascade a pleasure rather than a thing to optimise.
    //
    // The bound is asserted separately from the curve on purpose: the bound
    // holds whatever the machine's timing did (a broken window only ever
    // lowers a delta), so a failure there is a failure of the cap itself. The
    // curve is the same numbers said exactly, and is claimed only once the
    // run has proven the links landed inside the window.
    func testTheChainMultiplierSaturatesAtTwiceAndNeverClimbsPastIt() {
        let vm = makeGame()
        let field = (0..<14).map { makeOrb(at: CGPoint(x: 60 + 120 * CGFloat($0 % 3),
                                                       y: 140 + 120 * CGFloat($0 / 3))) }
        vm.restart()
        vm.sim.replaceOrbs(field)

        var deltas: [Int] = []
        var marks: [Date] = []
        var running = vm.sessionPoints
        for orb in field.prefix(13) {
            marks.append(Date())
            vm.tap(at: orb.pos)
            deltas.append(vm.sessionPoints - running)
            running = vm.sessionPoints
        }
        marks.append(Date())

        XCTAssertFalse(vm.sim.completed, "the field cleared — a +100 is inside these deltas")
        for (k, d) in deltas.enumerated() {
            XCTAssertGreaterThanOrEqual(d, 10,
                                        "link \(k + 1) paid \(d): below the unchained base of 10, "
                                        + "so something is subtracting")
            XCTAssertLessThanOrEqual(d, 20,
                                     "link \(k + 1) paid \(d): the ×2 cap on a base of 10 is 20")
        }
        if chainProvenUnbroken(marks) {
            XCTAssertEqual(deltas, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 20, 20],
                           "the chain curve is +0.1 per link to a hard ceiling of ×2")
        }
    }

    // The window closes. `restart()` forgets the streak, so the first pop of
    // the next field is a first link again — otherwise a field cleared in a
    // cascade would hand its multiplier to the field after it, and the number
    // would stop meaning "this cascade".
    func testANewFieldStartsAFreshChainRatherThanInheritingTheLastOnes() {
        let vm = makeGame()
        let field = (0..<4).map { makeOrb(at: CGPoint(x: 60 + 110 * CGFloat($0), y: 240)) }
        vm.restart()
        vm.sim.replaceOrbs(field)
        var marks: [Date] = []
        for orb in field.prefix(3) {
            marks.append(Date())
            vm.tap(at: orb.pos)
        }
        marks.append(Date())
        if chainProvenUnbroken(marks) {
            XCTAssertNotNil(vm.chainNote, "three quick pops should have raised the whisper")
        }
        // The rest holds either way: whatever streak the taps above built —
        // three links or none — `restart()` must forget it.

        let subject = makeOrb(at: CGPoint(x: 90, y: 220))
        XCTAssertEqual(earned(popping: subject, in: vm), 10,
                       "the first pop after a restart is unchained, at ×1")
        XCTAssertNil(vm.chainNote, "restart must clear the chain whisper with the streak")
    }

    // MARK: - Affirming-only

    // GUARDRAIL 1, as an arithmetic property rather than a policy: across a
    // scripted evening — misses, pops, creatures, fortunes, clears and
    // restarts — no lifetime number ever gets smaller, and inside a field the
    // session total never gets smaller either. There is no input that spends,
    // decays or resets anything.
    //
    // Only deltas are asserted; the absolute values belong to whatever the
    // simulator has played before this test ran.
    func testNoNumberEverGoesDownAcrossPopsMissesFortunesClearsAndRestarts() {
        let saved = stepOffThePath()
        defer { MapStore.shared.setActive(saved) }

        let vm = makeGame()
        let start = Ledger(vm.progression)
        var last = start

        for field in 0..<3 {
            vm.restart()
            var orbs = (0..<4).map { makeOrb(at: CGPoint(x: 70 + 100 * CGFloat($0), y: 260)) }
            orbs[1].isFortune = true
            orbs[2].kind = .animal(AnimalPop(shape: .fox, health: 1, shyness: 0))
            vm.sim.replaceOrbs(orbs)

            // A miss pays nothing, and takes nothing.
            var session = vm.sessionPoints
            vm.tap(at: CGPoint(x: 8, y: 8))
            XCTAssertEqual(vm.sessionPoints, session, "field \(field): a miss must cost nothing")
            assertNothingWentDown(from: last, to: Ledger(vm.progression), "field \(field), after a miss")
            last = Ledger(vm.progression)

            for (k, orb) in orbs.enumerated() {
                vm.tap(at: orb.pos)
                XCTAssertGreaterThanOrEqual(vm.sessionPoints, session,
                                            "field \(field), pop \(k): the session total went down")
                session = vm.sessionPoints
                let now = Ledger(vm.progression)
                assertNothingWentDown(from: last, to: now, "field \(field), pop \(k)")
                last = now
            }
            vm.cancelOnward()
            XCTAssertTrue(vm.sim.completed, "field \(field) did not finish")
        }

        let end = Ledger(vm.progression)
        assertNothingWentDown(from: start, to: end, "the whole evening")
        XCTAssertGreaterThan(end.points, start.points, "an evening of play earned nothing at all")
        XCTAssertEqual(end.pops - start.pops, 12, "twelve orbs were let go")
        XCTAssertEqual(end.cleared - start.cleared, 3)
        XCTAssertEqual(end.fortunes - start.fortunes, 3, "each field hid exactly one fortune")
    }

    /// The lifetime numbers, as one readable row.
    private struct Ledger {
        let points: Int, pops: Int, cleared: Int, fortunes: Int, bestChain: Int
        init(_ p: ProgressionStore) {
            points = p.popPoints
            pops = p.lifetimePops
            cleared = p.fieldsCleared
            fortunes = p.fortunesFound
            bestChain = p.bestChain
        }
    }

    private func assertNothingWentDown(from was: Ledger, to now: Ledger, _ what: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(now.points, was.points, "\(what): pop points went down",
                                    file: file, line: line)
        XCTAssertGreaterThanOrEqual(now.pops, was.pops, "\(what): lifetime pops went down",
                                    file: file, line: line)
        XCTAssertGreaterThanOrEqual(now.cleared, was.cleared, "\(what): fields cleared went down",
                                    file: file, line: line)
        XCTAssertGreaterThanOrEqual(now.fortunes, was.fortunes, "\(what): fortunes went down",
                                    file: file, line: line)
        XCTAssertGreaterThanOrEqual(now.bestChain, was.bestChain, "\(what): the best chain went down",
                                    file: file, line: line)
    }

    // MARK: - Taps, the counter, and restart

    // The plainest wiring in the file, and the one everything else rests on:
    // a tap goes to the simulation, and what the simulation says came back is
    // what the published state shows. A touch on nothing is not a pop — it
    // must not start the field, move the counter, or pay.
    func testATapReachesTheSimulationAndOnlyARealPopMovesThePublishedState() {
        // The second pop finishes the field, so this one clears off the Path.
        let saved = stepOffThePath()
        defer { MapStore.shared.setActive(saved) }

        let vm = makeGame()
        let orb = makeOrb(at: CGPoint(x: 140, y: 300))
        vm.restart()
        vm.sim.replaceOrbs([spare, orb])

        vm.tap(at: CGPoint(x: 8, y: 8))
        XCTAssertEqual(vm.count, 0, "a miss moved the counter")
        XCTAssertFalse(vm.started, "a miss started the field")
        XCTAssertEqual(vm.sessionPoints, 0, "a miss paid points")

        vm.tap(at: orb.pos)
        XCTAssertEqual(vm.count, vm.sim.popCount, "the counter must mirror the simulation")
        XCTAssertEqual(vm.count, 1)
        XCTAssertTrue(vm.started)
        XCTAssertGreaterThan(vm.sessionPoints, 0)

        vm.tap(at: spare.pos)
        XCTAssertEqual(vm.count, vm.sim.popCount)
        XCTAssertEqual(vm.count, 2)
        vm.cancelOnward()
    }

    // `restart()` puts the field and everything the field said back to
    // nothing — a new breath, not a continuation. The edge counters are the
    // deliberate exception and are checked with the onward sequence below.
    func testRestartReseedsTheFieldAndTakesTheCardTheWhispersAndTheSessionWithIt() {
        let saved = stepOffThePath()
        defer { MapStore.shared.setActive(saved) }

        let vm = makeGame()
        var orb = makeOrb(at: CGPoint(x: 140, y: 300))
        orb.isFortune = true
        vm.restart()
        vm.sim.replaceOrbs([orb])
        vm.tap(at: orb.pos)
        vm.cancelOnward()

        XCTAssertTrue(vm.showFortune, "the fortune orb should have spoken")
        XCTAssertTrue(vm.sim.completed)
        XCTAssertGreaterThan(vm.sessionPoints, 0)

        vm.restart()

        XCTAssertEqual(vm.count, 0, "the counter did not reset")
        XCTAssertFalse(vm.started, "the field still thinks it has been touched")
        XCTAssertEqual(vm.sessionPoints, 0, "the session total carried over into the new field")
        XCTAssertFalse(vm.showDone, "the done card survived the restart")
        XCTAssertFalse(vm.showFortune, "the fortune survived the restart")
        XCTAssertNil(vm.chainNote)
        XCTAssertNil(vm.pathNote)
        XCTAssertFalse(vm.renderingPaused, "a fresh field must not start paused")

        XCTAssertEqual(vm.sim.popCount, 0, "the simulation was not restarted")
        XCTAssertFalse(vm.sim.completed)
        XCTAssertFalse(vm.sim.orbs.isEmpty, "the restart left an empty field")
        XCTAssertTrue(vm.sim.orbs.allSatisfy(\.alive), "the restart kept the popped orbs")
    }

    // MARK: - The frame clock

    // `renderingPaused` gates the frame clock, so it has to be exactly the
    // simulation's own quiescence and never an approximation of it: too eager
    // and the field freezes with particles still in the air, too slow and a
    // finished field burns battery forever.
    //
    // Followed across the whole arc of a field — alive, finished but still
    // moving, quiet, and alive again after a restart.
    func testRenderingPausesExactlyWhenTheSimulationGoesQuietAndNotOneFrameSooner() {
        let saved = stepOffThePath()
        defer { MapStore.shared.setActive(saved) }

        let vm = makeGame()
        var t = origin
        for _ in 0..<10 {
            t = t.addingTimeInterval(1.0 / 60.0)
            vm.frame(date: t, size: screen)
        }
        hopTheMainQueue()
        XCTAssertFalse(vm.sim.isQuiescent, "a field with orbs on it is never quiescent")
        XCTAssertFalse(vm.renderingPaused, "the clock stopped over a live field")

        let last = makeOrb(at: CGPoint(x: 140, y: 300))
        vm.restart()
        vm.sim.replaceOrbs([last])
        vm.tap(at: last.pos)
        vm.cancelOnward()

        // Finished, but the burst is still in the air.
        for _ in 0..<5 {
            t = t.addingTimeInterval(1.0 / 60.0)
            vm.frame(date: t, size: screen)
        }
        hopTheMainQueue()
        XCTAssertFalse(vm.sim.isQuiescent, "the particles from the last pop are still alive")
        XCTAssertFalse(vm.renderingPaused,
                       "the clock stopped while the last burst was still on the glass")

        // Twenty seconds of simulated time: every effect has faded.
        for _ in 0..<1_200 {
            t = t.addingTimeInterval(1.0 / 60.0)
            vm.frame(date: t, size: screen)
        }
        hopTheMainQueue()
        XCTAssertTrue(vm.sim.isQuiescent, "the field never went quiet — this test proves nothing")
        XCTAssertTrue(vm.renderingPaused, "a quiet field must stop the frame clock")

        vm.restart()
        XCTAssertFalse(vm.renderingPaused,
                       "the clock must be running again the instant a new field exists")

        // AND IT MUST STILL BE RUNNING A QUEUE TURN LATER. `frame(date:size:)`
        // defers its write to `renderingPaused`, so a pause computed on the
        // old field and applied after the new one exists would freeze a live
        // field permanently — the flag is what `TimelineView(paused:)` reads,
        // and a paused timeline never calls `frame` again to correct it. Every
        // frame this test scheduled was drained above, so nothing is owed;
        // this says so out loud rather than leaving it to be inferred.
        hopTheMainQueue()
        XCTAssertFalse(vm.renderingPaused,
                       "a deferred pause from the old field landed on the new one and froze it")
    }

    // MARK: - What the field says out loud

    // The field is one direct-interaction region, so anything that has to be
    // SAID about it is said in this label — and the creature is the one thing
    // on the glass that earns a mention, including which phase it is in.
    func testTheFieldsLabelNamesTheCreatureOnItAndSaysWhichPhaseItIsIn() {
        let vm = makeGame()
        vm.restart()

        vm.sim.replaceOrbs([makeOrb(at: CGPoint(x: 140, y: 300))])
        XCTAssertEqual(vm.fieldAccessibilityLabel, Strings.fieldA11y,
                       "a field of plain orbs says only what the field is")

        vm.sim.replaceOrbs([makeOrb(at: CGPoint(x: 140, y: 300)),
                            makeOrb(at: CGPoint(x: 260, y: 500),
                                    kind: .animal(AnimalPop(shape: .rabbit, health: 2, shyness: 1)))])
        let shy = vm.fieldAccessibilityLabel
        XCTAssertTrue(shy.hasPrefix(Strings.fieldA11y),
                      "the creature is added to the field's label, not substituted for it")
        XCTAssertTrue(shy.contains("balloon rabbit"), "the label must name the creature: \(shy)")
        XCTAssertTrue(shy.contains("keeping to the edges"),
                      "someone who cannot see it keeping to the edges must be told: \(shy)")

        vm.sim.replaceOrbs([makeOrb(at: CGPoint(x: 260, y: 500),
                                    kind: .animal(AnimalPop(shape: .rabbit, health: 2, shyness: 0)))])
        XCTAssertTrue(vm.fieldAccessibilityLabel.contains("out in the open"),
                      "the label must follow the creature out of its shy phase")
    }

    // MARK: - Layout and the pointer

    // The bands are the only thing `applyFieldBands` may touch. It runs on
    // rotation and on a Dynamic Type change, and a version of it that also
    // reseeded would throw away the field she was in the middle of.
    func testApplyingFieldBandsMovesTheInsetsAndNothingElse() {
        let vm = makeGame()
        let field = (0..<3).map { makeOrb(at: CGPoint(x: 80 + 110 * CGFloat($0), y: 300)) }
        vm.restart()
        vm.sim.replaceOrbs(field)
        vm.tap(at: field[0].pos)

        let positions = vm.sim.orbs.map(\.pos)
        let alive = vm.sim.orbs.map(\.alive)
        let count = vm.count

        vm.applyFieldBands(top: 137, bottom: 91)

        XCTAssertEqual(vm.sim.topInset, 137)
        XCTAssertEqual(vm.sim.bottomInset, 91)
        XCTAssertEqual(vm.sim.orbs.map(\.pos), positions, "the field moved when only a band changed")
        XCTAssertEqual(vm.sim.orbs.map(\.alive), alive, "an orb changed state on a layout pass")
        XCTAssertEqual(vm.count, count, "the counter moved on a layout pass")
    }

    // The pointer is reported for the drifters to ease away from, and it is
    // reported ALONGSIDE the arbiter, never through it. What is pinned here
    // is the plumbing: what the input layer says is what the simulation sees,
    // including the lifted finger.
    func testThePointerIsHandedStraightToTheSimulationAndClearedWhenSheLetsGo() {
        let vm = makeGame()
        let counter = vm.count

        vm.pointerMoved(to: CGPoint(x: 210, y: 420))
        XCTAssertEqual(vm.sim.pointer, CGPoint(x: 210, y: 420))

        vm.pointerMoved(to: CGPoint(x: 211, y: 419))
        XCTAssertEqual(vm.sim.pointer, CGPoint(x: 211, y: 419))

        vm.pointerMoved(to: nil)
        XCTAssertNil(vm.sim.pointer, "a lifted finger must leave nothing behind for the drifters")
        XCTAssertEqual(vm.count, counter, "reporting a touch position popped something")
    }

    // MARK: - The fortune

    // The words are drawn from the written set and they rise FROM THE ORB —
    // the anchor is the popped orb's own position, which is what makes the
    // fortune read as having come out of the thing she just let go rather
    // than as a message arriving in the middle of the screen.
    func testAFortuneSpeaksAWrittenLineFromExactlyWhereTheOrbWas() {
        let vm = makeGame()
        let where_ = CGPoint(x: 173, y: 388)
        let orb = makeOrb(at: where_, fortune: true)
        vm.restart()
        vm.sim.replaceOrbs([spare, orb])

        let fortunesBefore = vm.progression.fortunesFound
        vm.tap(at: where_)

        XCTAssertTrue(vm.showFortune, "the fortune never appeared")
        XCTAssertTrue(Fortunes.messages.contains(vm.fortuneText),
                      "the fortune said something that is not in the written set: \(vm.fortuneText)")
        XCTAssertEqual(vm.fortuneAnchor, where_, "the words must rise from the orb that carried them")
        XCTAssertEqual(vm.progression.fortunesFound - fortunesBefore, 1,
                       "one fortune found must count exactly once")

        vm.dismissFortune()
        XCTAssertFalse(vm.showFortune, "dismissing the fortune left it on screen")
    }

    // MARK: - Point whispers

    // The immediate layer of the feedback stack: the `+12` that drifts up from
    // the pop is the SAME number that was banked — one concept, one number —
    // and it rises from just above the orb. Turning the whisper off silences
    // the display and nothing else: the points still accrue, exactly as
    // docs/pop_points.md §3 promises.
    func testThePointWhisperSaysWhatWasEarnedAndTurningItOffCostsNothing() {
        let savedWhispers = SettingsStore.shared.pointWhispersEnabled
        defer { SettingsStore.shared.pointWhispersEnabled = savedWhispers }

        let vm = makeGame()
        let orb = makeOrb(at: CGPoint(x: 140, y: 300), r: GameConfig.orbRadiusRange.upperBound)

        SettingsStore.shared.pointWhispersEnabled = true
        let paid = earned(popping: orb, in: vm)
        guard let note = vm.sim.notes.last else {
            return XCTFail("no point whisper was left in the field")
        }
        XCTAssertEqual(note.text, "+\(paid)",
                       "the whisper and the session line must be the same number")
        XCTAssertEqual(note.pos.x, orb.pos.x, accuracy: 0.001,
                       "the whisper must rise in the popped orb's own column")
        XCTAssertLessThan(note.pos.y, orb.pos.y, "the whisper must rise from above the orb")

        SettingsStore.shared.pointWhispersEnabled = false
        let quiet = earned(popping: orb, in: vm)
        XCTAssertTrue(vm.sim.notes.isEmpty, "point whispers are off and one was drawn anyway")
        XCTAssertEqual(quiet, paid, "silencing the whisper must not change what she earns")
    }

    // MARK: - Unlocks

    // The unlock capsule is an EDGE: it appears when the unlocked set grows,
    // and it names only what is new. `knownUnlocked` is taken in `init`, so a
    // view model built after an unlock must never re-announce it — which is
    // the case this test spends most of its time in, because by the time the
    // suite runs the collection is usually not moving.
    //
    // Written as an equivalence rather than as a fixed expectation because
    // lifetime totals are shared state: whether this particular pop crosses a
    // threshold depends on everything the simulator has played before.
    //
    // BUT AN EQUIVALENCE ALONE WAS VACUOUS, and that is worth saying plainly.
    // On almost every run one ordinary pop crosses no threshold at all, so
    // only the "nothing new" side is ever exercised — and a view model that
    // had lost `checkUnlocks` entirely would sail through it. So the
    // collection is first put ONE POP SHORT of its next points threshold, and
    // the pop under test is the one that crosses it. The equivalence stays,
    // for the run where the arrangement cannot be made.
    //
    // THE REACH INTO THE SHARED STORE IS THE SAME KIND OF WRITE EVERY OTHER
    // TEST HERE MAKES BY POPPING, and it is bounded on both sides: it only
    // ever adds, and it stops one point below the nearest threshold, so it
    // can unlock nothing by itself. Nothing about it is ever asserted
    // absolutely.
    func testTheUnlockCapsuleAppearsExactlyWhenTheCollectionGrowsAndNamesOnlyWhatIsNew() {
        let progression = ProgressionStore.shared
        let nextThreshold: Int? = PopCatalog.all.compactMap { def -> Int? in
            guard case .points(let n) = def.unlock, n > progression.popPoints else { return nil }
            return n
        }.min()
        if let threshold = nextThreshold {
            progression.recordPop(popNumber: PopCatalog.classic.number,
                                  points: threshold - 1 - progression.popPoints,
                                  chainLength: 0)
        }

        // AFTER the arrangement, never before: `knownUnlocked` is taken in
        // `init`, and a view model built first would have watched the ledger
        // move behind its back.
        let vm = makeGame()
        let orb = makeOrb(at: CGPoint(x: 140, y: 300))
        vm.restart()
        vm.sim.replaceOrbs([spare, orb])

        let before = vm.progression.unlockedNumbers()
        let noteBefore = vm.unlockNote
        vm.tap(at: orb.pos)
        let after = vm.progression.unlockedNumbers()
        let fresh = after.subtracting(before)

        XCTAssertTrue(before.isSubset(of: after), "the collection lost a pop — it may only grow")
        if nextThreshold != nil {
            XCTAssertFalse(fresh.isEmpty,
                           "this pop was arranged to cross a points threshold and unlocked "
                           + "nothing — the capsule below would have been proved by nothing")
        }
        if fresh.isEmpty {
            XCTAssertEqual(vm.unlockNote, noteBefore,
                           "nothing new was found, so the capsule must not appear — a view model "
                           + "must never announce what it already knew at init")
        } else {
            XCTAssertNotNil(vm.unlockNote, "a pop was unlocked and nothing was said about it")
            if fresh.count == 1, let only = fresh.first {
                XCTAssertEqual(vm.unlockNote, "new pop · \(PopCatalog.definition(for: only).name)",
                               "the capsule must name the pop that was actually found")
            } else {
                XCTAssertEqual(vm.unlockNote, "\(fresh.count) new pops found")
            }
        }
    }

    // MARK: - The Path

    // A field is made of the stone she stands on, and of the collection when
    // she steps off it. Also the stage: what a field is MADE of grows with
    // fields cleared, never with anything she has to choose.
    func testAFieldIsSeededFromTheStoneSheStandsOnAndFromTheCollectionWhenSheLeavesIt() {
        let saved = MapStore.shared.activeStoneID
        defer { MapStore.shared.setActive(saved) }

        let vm = makeGame()
        guard let stone = vm.map.stones.first else {
            return XCTFail("init must have laid the genesis stone")
        }

        vm.playStone(stone)
        XCTAssertEqual(vm.map.activeStoneID, stone.id, "playing a stone must be standing on it")
        XCTAssertEqual(vm.sim.availablePops, stone.popNumbers,
                       "the field must be made of the stone's own pops")
        XCTAssertEqual(vm.sim.generation, stone.generation,
                       "how deep the field goes comes from where the stone is on the Path")
        XCTAssertEqual(vm.sim.stage, FieldPlan.stage(forFieldsCleared: vm.progression.fieldsCleared),
                       "the stage must ride on fields cleared")
        XCTAssertTrue(vm.sim.orbs.allSatisfy { stone.popNumbers.contains($0.popNumber) },
                      "an orb was dealt from outside the stone's pops")
        XCTAssertEqual(vm.count, 0, "stepping onto a stone starts a new field")
        XCTAssertFalse(vm.started)

        vm.leavePath()
        XCTAssertNil(vm.map.activeStoneID, "leaving the path must leave no stone active")
        XCTAssertEqual(vm.sim.availablePops, vm.progression.fieldPops(),
                       "off the path the field is the collection")
        XCTAssertEqual(vm.sim.generation, 0, "free play is not anywhere on the Path")
    }

    // Clearing on the Path opens the roads ahead and says so — and says it
    // only when roads actually opened. A REPLAY opens nothing new, and a
    // replay that still whispered "the path continues" would be the map
    // promising a road that is not there.
    func testClearingOnThePathAnnouncesOnlyTheRoadsThatActuallyOpened() {
        let saved = MapStore.shared.activeStoneID
        defer { MapStore.shared.setActive(saved) }

        let vm = makeGame()
        guard let stone = vm.map.stones.first else {
            return XCTFail("init must have laid the genesis stone")
        }
        vm.playStone(stone)

        let roadsBefore = vm.map.roads(from: stone.id).count
        let last = makeOrb(at: CGPoint(x: 140, y: 300))
        vm.sim.replaceOrbs([last])
        vm.tap(at: last.pos)
        vm.cancelOnward()
        let opened = vm.map.roads(from: stone.id).count - roadsBefore

        XCTAssertTrue(vm.sim.completed)
        XCTAssertGreaterThanOrEqual(opened, 0, "roads may only ever be added")
        switch opened {
        case 0:
            XCTAssertNil(vm.pathNote,
                         "a replay opens no roads, so the path must not claim it continues")
        case 1:
            XCTAssertEqual(vm.pathNote, "the path continues")
        default:
            XCTAssertEqual(vm.pathNote, "the path forks — \(opened) roads ahead")
        }
    }

    // MARK: - The onward sequence

    // The sequence is delayed work by design, and the two conditions that keep
    // it from being a shove are stated in the view model itself. What is
    // observable synchronously — and asserted here — is the part that would
    // break the promise soonest: the world must NOT already be travelling in
    // the instant the field goes quiet. The done card and its verse are hers
    // first.
    //
    // AND `restart()` ASKS FOR NOTHING ON ITS OWN. The sequence calls it from
    // inside the step onto the next stone, so a `restart()` that touched
    // either counter would either fire a journey nobody asked for or swallow
    // the one already in flight.
    //
    // WHAT THIS TEST DOES NOT PROVE, said rather than implied: that a
    // counter already RAISED survives the restart. Nothing raises it
    // synchronously — `skyRequest` moves only from a work item scheduled
    // `GameConfig.onwardToSkyDelay` (3.4 s) out — and this file does not wait
    // on a clock for anything. The half that is reachable is asserted; the
    // half that would need a real timeout is left to the world suites rather
    // than faked with a sleep.
    func testAClearedFieldDoesNotTravelInTheSameInstantAndARestartAsksForNothing() {
        let saved = stepOffThePath()
        defer { MapStore.shared.setActive(saved) }

        let vm = makeGame()
        XCTAssertEqual(vm.skyRequest, 0, "a new world has made no journeys")
        XCTAssertEqual(vm.fieldRequest, 0)

        let last = makeOrb(at: CGPoint(x: 140, y: 300))
        vm.restart()
        vm.sim.replaceOrbs([last])
        vm.tap(at: last.pos)

        XCTAssertTrue(vm.sim.completed)
        XCTAssertEqual(vm.skyRequest, 0,
                       "the world rose to the sky in the same instant the field went quiet — "
                       + "the done card was never hers")
        XCTAssertEqual(vm.fieldRequest, 0, "the world stepped onward before it had even risen")

        vm.cancelOnward()
        hopTheMainQueue()
        XCTAssertEqual(vm.skyRequest, 0, "a cancelled sequence left something on the queue")
        XCTAssertEqual(vm.fieldRequest, 0)

        vm.restart()
        XCTAssertEqual(vm.skyRequest, 0, "a restart asked the world to rise")
        XCTAssertEqual(vm.fieldRequest, 0, "a restart asked the world to step onward")
        XCTAssertFalse(vm.showDone)
    }
}
