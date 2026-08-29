import XCTest
@testable import Vesper

// FieldPlan is the whole answer to "what is in this field": the stage curve,
// the growth in depth and on return, and the alternation that decides whether
// a stone is a display, a creature, or neither.
//
// Everything in it is a pure function of (stage, generation, plays) — no
// clock, no RNG, no stored state — so this suite SWEEPS the space rather than
// sampling it, and pins the exact composition rather than its shape. A stage
// that teaches splitters has to contain splitters every time, and a stone has
// to be the same field every evening she returns to it; "on average" is not a
// contract either of those can be built on.
//
// The neighbouring suites cover the neighbouring ground and are deliberately
// not repeated here: FieldMechanicsTests asserts a *seeded* field matches its
// plan and that the mechanics arrive one at a time, FieldDepthTests drives the
// growth curve through the simulation, FireworkTests owns the display share,
// and AnimalPopTests owns where creatures appear. What is pinned below is the
// generation rules themselves, stage by stage and case by case.
final class FieldPlanTests: XCTestCase {

    // MARK: - The curve, exactly

    /// The stage table is a design decision written down as numbers, and the
    /// one thing that can quietly ruin it is a "small tuning tweak" that
    /// nobody sees fail. Every count is pinned literally: an accidental edit
    /// to any cell of the table fails here rather than in someone's evening.
    func testTheStageCurveIsExactlyTheTableItDocumentsAndNothingHasDrifted() {
        // stage: (orbCount, splitters, drifters, generators, splitDepth)
        let table: [(Int, Int, Int, Int, Int)] = [
            (10, 0, 0, 0, 0),   // 0 — plain orbs, as v1.0
            (13, 0, 0, 0, 0),   // 1 — a fuller field
            (13, 2, 0, 0, 1),   // 2 — splitters
            (14, 2, 1, 0, 1),   // 3 — drifters
            (14, 3, 1, 1, 1),   // 4 — generators
            (15, 3, 2, 1, 2),   // 5 — splitters go two deep
            (16, 4, 2, 2, 2),   // 6 — a second generator, the full shape
        ]
        XCTAssertEqual(table.count, FieldPlan.finalStage + 1,
                       "a stage was added to the curve without a row in this table")

        for (stage, row) in table.enumerated() {
            let expected = FieldPlan(orbCount: row.0, splitters: row.1, drifters: row.2,
                                     generators: row.3, splitDepth: row.4)
            XCTAssertEqual(FieldPlan.forStage(stage), expected, "stage \(stage) drifted")
        }
    }

    /// `forStage` knows the stage and nothing else. Shells and creatures
    /// depend on where the field sits on the Path, so they must be absent from
    /// the bare plan and filled in at seed time — a plan that guessed at them
    /// would put a firework on a stone that is not a display.
    func testABarePlanCarriesNoShellsAndNoCreatureUntilItsPlaceOnThePathIsKnown() {
        for stage in -3...(FieldPlan.finalStage + 3) {
            let plan = FieldPlan.forStage(stage)
            XCTAssertEqual(plan.fireworks, 0, "stage \(stage) presumed a display")
            XCTAssertEqual(plan.animals, 0, "stage \(stage) presumed a creature")
        }
    }

    /// Both ends of the curve are clamped, and both clamps matter. Below zero
    /// is a corrupt or migrated stat and must read as a first field rather
    /// than a negative one; past the final stage the field must HOLD, because
    /// a field that never stops growing is a field she cannot finish.
    func testStagesBelowTheFirstAndPastTheLastAreClampedOntoTheCurve() {
        for stage in -20...(-1) {
            XCTAssertEqual(FieldPlan.forStage(stage), FieldPlan.forStage(0),
                           "stage \(stage) fell off the near end of the curve")
        }
        for beyond in 1...40 {
            XCTAssertEqual(FieldPlan.forStage(FieldPlan.finalStage + beyond),
                           FieldPlan.forStage(FieldPlan.finalStage),
                           "the curve kept growing \(beyond) stages past its end")
        }
    }

    /// THE CALM GUARANTEE, AT THE PLAN LEVEL. Splitters, drifters and the
    /// creature take an ordinary orb's PLACE (see `GameSimulation.seedField`),
    /// so a stage whose specials filled its own orb count would be a field
    /// with nothing plain in it: no ordinary first touch, and — because the
    /// fortune only ever rides a plain orb on the surface — no fortune either.
    /// The bound is against the SURFACE as well as the count, so whatever
    /// order the shuffle deals them in, something ordinary is on the glass.
    func testEveryStageLeavesOrdinaryOrbsOnTheGlassHoweverDeepTheCurveGoes() {
        for stage in 0...FieldPlan.finalStage {
            let plan = FieldPlan.forStage(stage)
            let specials = plan.splitters + plan.drifters + 1   // +1 for a creature
            XCTAssertLessThan(specials, plan.orbCount,
                              "stage \(stage) has no ordinary orb left in it")
            XCTAssertLessThan(specials, GameConfig.surfaceCapacity,
                              "stage \(stage) could fill the glass with specials alone")
            XCTAssertGreaterThanOrEqual(plan.splitters, 0)
            XCTAssertGreaterThanOrEqual(plan.drifters, 0)
            XCTAssertGreaterThanOrEqual(plan.generators, 0)
            XCTAssertGreaterThanOrEqual(plan.splitDepth, 0)
        }
    }

    /// What "a longer field" actually means is how many pops she makes, not
    /// how many orbs were seeded — a splitter is one orb and several pops.
    /// Pinned exactly per stage, because this is the number the points side
    /// and the "did the field really get longer" argument both rest on.
    func testReachableOrbsCountsEverySplitterGenerationItWillBecome() {
        let expected = [10, 13, 17, 18, 20, 33, 40]
        XCTAssertEqual(expected.count, FieldPlan.finalStage + 1)
        for stage in 0...FieldPlan.finalStage {
            XCTAssertEqual(FieldPlan.forStage(stage).reachableOrbs, expected[stage],
                           "stage \(stage) reachable orbs")
        }

        // A plan with no splitters is exactly its orb count — there is nothing
        // hidden inside a plain field.
        let plain = FieldPlan(orbCount: 9, splitters: 0, drifters: 2,
                              generators: 1, splitDepth: 0)
        XCTAssertEqual(plain.reachableOrbs, 9)

        // …and depth compounds by `splitChildCount`, not by addition.
        let deep = FieldPlan(orbCount: 10, splitters: 1, drifters: 0,
                             generators: 0, splitDepth: 3)
        let c = GameConfig.splitChildCount
        XCTAssertEqual(deep.reachableOrbs, 10 + c + c * c + c * c * c)
    }

    // MARK: - Stage from what she has cleared

    /// Three fields per step is the pace that lands one new idea an evening
    /// rather than three in a first sitting. Swept: the stage never goes
    /// backwards, never jumps two, occupies exactly three cleared-counts per
    /// step, and stops at the final stage forever.
    func testStageAdvancesEveryThreeClearedFieldsAndThenHoldsForever() {
        var occurrences: [Int: Int] = [:]
        var previous = FieldPlan.stage(forFieldsCleared: 0)
        XCTAssertEqual(previous, 0, "her first field is the first field")

        for cleared in 0...80 {
            let s = FieldPlan.stage(forFieldsCleared: cleared)
            XCTAssertGreaterThanOrEqual(s, previous, "the stage went backwards — nothing is ever lost")
            XCTAssertLessThanOrEqual(s - previous, 1, "two ideas arrived at once at \(cleared)")
            XCTAssertLessThanOrEqual(s, FieldPlan.finalStage)
            occurrences[s, default: 0] += 1
            previous = s
        }
        for stage in 0..<FieldPlan.finalStage {
            XCTAssertEqual(occurrences[stage] ?? 0, 3,
                           "stage \(stage) did not last exactly three cleared fields")
        }

        // The last step lands exactly where the pace says it does, and the
        // one before it has not landed yet.
        XCTAssertEqual(FieldPlan.stage(forFieldsCleared: 3 * FieldPlan.finalStage),
                       FieldPlan.finalStage)
        XCTAssertEqual(FieldPlan.stage(forFieldsCleared: 3 * FieldPlan.finalStage - 1),
                       FieldPlan.finalStage - 1)

        // A corrupt or migrated stat must not read as a field below the first.
        for cleared in -50...(-1) {
            XCTAssertEqual(FieldPlan.stage(forFieldsCleared: cleared), 0)
        }
    }

    // MARK: - Displays and creatures: the alternation

    /// The two spectacles PARTITION the stones from the stage the creature
    /// joins: every field is one or the other, never both and never neither.
    /// Both halves matter. Both would be a shy animal keeping to the edges
    /// while shells go up in the middle — two things asking for the same
    /// attention, and a break's shove pushing the one orb trying to stay put.
    /// Neither would be a plain evening in a part of the Path whose whole
    /// promise is that something is always happening.
    ///
    /// AnimalPopTests asserts the "never both" half; the "never neither" half
    /// and the sweep across every stage are pinned here.
    func testEveryStoneFromTheCreatureStageOnIsADisplayOrACreatureNeverBothNeverNeither() {
        for stage in GameConfig.animalStartStage...FieldPlan.finalStage {
            for generation in 0...120 {
                let display = FieldPlan.isDisplay(stage: stage, generation: generation)
                let creature = FieldPlan.hasAnimal(stage: stage, generation: generation)
                XCTAssertNotEqual(display, creature,
                                  "stage \(stage) gen \(generation): \(display ? "both" : "neither")")
                XCTAssertEqual(FieldPlan.animalCount(stage: stage, generation: generation),
                               creature ? 1 : 0)
            }
        }
    }

    /// Stage 2 is the seam between the two rules: shells have arrived and the
    /// creature has not, so this is the one band of the Path where a stone can
    /// legitimately be quiet. If a change ever moved `animalStartStage` below
    /// the display rule's own start, creatures would appear on every field of
    /// the quiet stages at once — this is the test that would say so.
    func testTheStageBeforeCreaturesHoldsDisplaysAndQuietStonesInTurn() {
        XCTAssertGreaterThan(GameConfig.animalStartStage, 2,
                             "creatures must arrive after the stage that teaches drifters")
        var quiet = 0, displays = 0
        for generation in 0...40 {
            XCTAssertFalse(FieldPlan.hasAnimal(stage: 2, generation: generation),
                           "a creature arrived a stage early")
            if FieldPlan.isDisplay(stage: 2, generation: generation) { displays += 1 } else { quiet += 1 }
        }
        XCTAssertGreaterThan(quiet, 0, "stage 2 never rests")
        XCTAssertGreaterThan(displays, 0, "stage 2 never celebrates")
    }

    /// Alternation, not a roll. Random selection would give four displays in a
    /// row about once in sixteen and the spectacle would become ordinary; a
    /// parity check on the stone's own place makes two in a row impossible.
    /// Swept along every stage's road, which is the sequence she actually
    /// walks — one generation at a time.
    func testDisplaysAlternateStoneByStoneSoTheSpectacleNeverBecomesOrdinary() {
        for stage in 2...FieldPlan.finalStage {
            for generation in 0...120 {
                XCTAssertNotEqual(FieldPlan.isDisplay(stage: stage, generation: generation),
                                  FieldPlan.isDisplay(stage: stage, generation: generation + 1),
                                  "stage \(stage): generations \(generation) and \(generation + 1) match")
            }
        }
    }

    // MARK: - Shells

    /// Off a display there are no shells at all; on one there are at least a
    /// couple, they only ever grow with depth, and they stop at the cap — a
    /// display is a handful of things worth watching, never a firing range.
    func testShellCountIsZeroOffADisplayAndClimbsWithDepthToItsCap() {
        // Spot values, so the formula itself is pinned and not merely bounded.
        XCTAssertEqual(FieldPlan.fireworkCount(stage: 2, generation: 2), 0, "not a display")
        XCTAssertEqual(FieldPlan.fireworkCount(stage: 2, generation: 1), 2)
        XCTAssertEqual(FieldPlan.fireworkCount(stage: 2, generation: 3), 3)
        XCTAssertEqual(FieldPlan.fireworkCount(stage: 2, generation: 11), 5)
        XCTAssertEqual(FieldPlan.fireworkCount(stage: 3, generation: 0), 2)
        XCTAssertEqual(FieldPlan.fireworkCount(stage: 3, generation: 6), 4)

        var lastOnADisplay = 0
        for stage in 0...FieldPlan.finalStage {
            for generation in 0...200 {
                let shells = FieldPlan.fireworkCount(stage: stage, generation: generation)
                guard FieldPlan.isDisplay(stage: stage, generation: generation) else {
                    XCTAssertEqual(shells, 0,
                                   "stage \(stage) gen \(generation) carried shells off a display")
                    continue
                }
                XCTAssertGreaterThanOrEqual(shells, 2, "a display with nothing to watch")
                XCTAssertLessThanOrEqual(shells, GameConfig.maxFireworksPerField,
                                         "stage \(stage) gen \(generation) became a firing range")
                if generation >= 12 {
                    XCTAssertEqual(shells, GameConfig.maxFireworksPerField,
                                   "a deep display should sit at the cap")
                }
                if stage == 2 {
                    XCTAssertGreaterThanOrEqual(shells, lastOnADisplay,
                                                "a deeper display carried fewer shells")
                    lastOnADisplay = shells
                }
            }
        }
        XCTAssertEqual(lastOnADisplay, GameConfig.maxFireworksPerField)
    }

    // MARK: - Growth: depth along the Path, and on return

    /// A field only ever gets longer, and it stops. Swept across every stage's
    /// own base so the ceiling is checked against the fields that actually
    /// exist: the deepest possible field of the deepest possible stage on her
    /// fourth visit still has to be something she can finish tonight.
    func testAFieldOnlyEverGrowsAndAlwaysStopsInsideTheCeiling() {
        for stage in 0...FieldPlan.finalStage {
            let base = FieldPlan.forStage(stage).orbCount
            for plays in 0...5 {
                var previous = 0
                for generation in 0...60 {
                    let total = FieldPlan.totalOrbs(base: base, generation: generation, plays: plays)
                    XCTAssertGreaterThanOrEqual(total, base,
                                                "stage \(stage) gen \(generation) shrank below its plan")
                    XCTAssertLessThanOrEqual(total, GameConfig.maxFieldOrbs,
                                             "stage \(stage) gen \(generation) plays \(plays) passed the ceiling")
                    XCTAssertGreaterThanOrEqual(total, previous,
                                                "stage \(stage) gen \(generation) was shorter than the step before")
                    previous = total
                }
            }
        }
    }

    /// Returning is a gift, and it stops being one after the third visit —
    /// otherwise coming back to a favourite stone becomes a treadmill. Pinned
    /// as monotonicity plus a plateau, across bases rather than at one.
    func testReturnVisitsOnlyEverAddAndFlattenAfterTheThirdOne() {
        for base in [7, 10, 13, 16, 19] {
            var previous = 0
            for plays in 0..<GameConfig.replayMultipliers.count {
                let total = FieldPlan.totalOrbs(base: base, generation: 0, plays: plays)
                XCTAssertGreaterThanOrEqual(total, previous, "base \(base) visit \(plays) gave less")
                previous = total
            }
            let last = GameConfig.replayMultipliers.count - 1
            let plateau = FieldPlan.totalOrbs(base: base, generation: 0, plays: last)
            for plays in (last + 1)...(last + 30) {
                XCTAssertEqual(FieldPlan.totalOrbs(base: base, generation: 0, plays: plays), plateau,
                               "base \(base) kept growing on visit \(plays) — that is a treadmill")
            }
        }
    }

    /// A negative depth or visit count can only come from a corrupt or
    /// migrated store, and it must read as her first time here — never as a
    /// field smaller than the plan, and never as an index off the front of
    /// `replayMultipliers`.
    func testANegativeDepthOrVisitCountReadsAsHerFirstTimeHere() {
        for base in [7, 12, 19] {
            let first = FieldPlan.totalOrbs(base: base, generation: 0, plays: 0)
            for generation in [-1, -5, -1000] {
                XCTAssertEqual(FieldPlan.totalOrbs(base: base, generation: generation, plays: 0), first)
            }
            for plays in [-1, -5, -1000] {
                XCTAssertEqual(FieldPlan.totalOrbs(base: base, generation: 0, plays: plays), first)
            }
            XCTAssertEqual(FieldPlan.totalOrbs(base: base, generation: -7, plays: -7), first)
        }
    }

    // MARK: - The surface

    /// Growth is in DEPTH, never in crowding: a field small enough to fit is
    /// entirely on the glass with nothing held back, and past that the glass
    /// holds exactly its capacity however deep the field is. And a field with
    /// anything in it always shows her something — a field that seeded orbs
    /// but surfaced none would be an evening that never starts.
    func testNothingWaitsBeneathAFieldSmallEnoughToFitTheGlass() {
        for total in 0...(GameConfig.surfaceCapacity * 8) {
            let surface = FieldPlan.surfaceCount(total: total)
            XCTAssertLessThanOrEqual(surface, total, "more surfaced than the field holds")
            XCTAssertLessThanOrEqual(surface, GameConfig.surfaceCapacity, "the glass crowded")
            if total <= GameConfig.surfaceCapacity {
                XCTAssertEqual(surface, total, "a small field held something back for no reason")
            } else {
                XCTAssertEqual(surface, GameConfig.surfaceCapacity)
            }
            if total > 0 { XCTAssertGreaterThan(surface, 0, "a field with orbs surfaced none") }
        }
    }

    /// And the two together: for every field the curve can actually produce,
    /// something is on the glass to touch and the whole of it fits inside the
    /// ceiling. This is the "it can always be finished" claim stated where it
    /// is decided, before any simulation is involved.
    func testEveryFieldTheCurveCanProduceOpensWithSomethingToTouch() {
        for stage in 0...FieldPlan.finalStage {
            let plan = FieldPlan.forStage(stage)
            for generation in [0, 1, 5, 20, 100, 10_000] {
                for plays in [0, 1, 2, 9] {
                    let total = FieldPlan.totalOrbs(base: plan.orbCount,
                                                    generation: generation, plays: plays)
                    let surface = FieldPlan.surfaceCount(total: total)
                    XCTAssertGreaterThan(surface, 0,
                                         "stage \(stage) gen \(generation) opened empty")
                    XCTAssertLessThanOrEqual(total, GameConfig.maxFieldOrbs)
                    XCTAssertGreaterThanOrEqual(total, plan.splitters + plan.drifters + plan.animals,
                                                "the plan's own kinds did not fit in its field")
                }
            }
        }
    }

    // MARK: - The same stone is the same field

    /// The Path stops meaning anything if a stone is a display on Tuesday and
    /// not on Wednesday. Every one of these is a pure function of its
    /// arguments — no clock, no RNG, no stored state — so calling them again
    /// must give the same field back, whatever has happened in between.
    ///
    /// Written as a walk RECORDED and then WALKED AGAIN, rather than as each
    /// function called twice inside one assertion. Two calls side by side are
    /// a tautology a compiler may fold into one, and they would go on passing
    /// even if these grew a cache or reached for a clock; a whole evening of
    /// other fields in between is what makes the second walk a real question.
    func testTheSameStoneIsTheSameFieldEveryTimeSheReturnsToIt() {
        // One field, flattened to numbers so nothing new has to be declared:
        // the plan, where it sits, and what it grows to on every visit.
        func fingerprint(stage: Int, generation: Int) -> [Int] {
            let plan = FieldPlan.forStage(stage)
            let total = FieldPlan.totalOrbs(base: 13, generation: generation, plays: 0)
            let display: Int = FieldPlan.isDisplay(stage: stage, generation: generation) ? 1 : 0
            let creature: Int = FieldPlan.hasAnimal(stage: stage, generation: generation) ? 1 : 0
            var out: [Int] = [plan.orbCount, plan.splitters, plan.drifters,
                              plan.generators, plan.splitDepth, plan.fireworks,
                              plan.animals, plan.reachableOrbs]
            out.append(display)
            out.append(creature)
            out.append(FieldPlan.fireworkCount(stage: stage, generation: generation))
            out.append(FieldPlan.animalCount(stage: stage, generation: generation))
            out.append(FieldPlan.stage(forFieldsCleared: generation))
            out.append(FieldPlan.surfaceCount(total: total))
            for plays in 0...3 {
                out.append(FieldPlan.totalOrbs(base: 13, generation: generation, plays: plays))
            }
            return out
        }

        var firstWalk: [[Int]] = []
        for stage in 0...FieldPlan.finalStage {
            for generation in 0...30 {
                firstWalk.append(fingerprint(stage: stage, generation: generation))
            }
        }

        // Everything else the curve can produce, in between, so the second
        // walk is not reading anything back out of a warm register.
        for stage in -5...(FieldPlan.finalStage + 5) {
            for generation in 31...120 { _ = fingerprint(stage: stage, generation: generation) }
        }

        var index = 0
        for stage in 0...FieldPlan.finalStage {
            for generation in 0...30 {
                XCTAssertEqual(fingerprint(stage: stage, generation: generation), firstWalk[index],
                               "stage \(stage) gen \(generation) came back a different field")
                index += 1
            }
        }
        XCTAssertEqual(index, firstWalk.count)
    }
}
