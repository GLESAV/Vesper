import XCTest
@testable import Vesper

// The stage mechanics: splitters, drifters, generators, and the curve that
// introduces them. Driven with fixed seeds and `step(dt:)`, never wall clock.
final class FieldMechanicsTests: XCTestCase {

    private let size = CGSize(width: 390, height: 800)

    private func sim(seed: UInt64 = 42, stage: Int = 0) -> GameSimulation {
        let s = GameSimulation(seed: seed)
        s.layout(size: size)
        s.stage = stage
        s.seedField()
        return s
    }

    /// One orb, exactly where we want it, of exactly the kind we want.
    private func field(_ kinds: [OrbKind], at points: [CGPoint], r: CGFloat = 30) -> [Orb] {
        zip(kinds, points).map { kind, p in
            var o = Orb(pos: p, vel: .zero, r: r, baseR: r,
                        popNumber: PopCatalog.classic.number, variantIndex: 0, phase: 0)
            o.spawn = 1
            o.kind = kind
            return o
        }
    }

    private func run(_ s: GameSimulation, frames: Int) -> [GameEvent] {
        var all: [GameEvent] = []
        for _ in 0..<frames { all += s.step(dt: 1.0 / 60) }
        return all
    }

    // MARK: - The curve

    func testStageZeroIsStillTheGameSheAlreadyKnows() {
        let plan = FieldPlan.forStage(0)
        XCTAssertEqual(plan.splitters, 0)
        XCTAssertEqual(plan.drifters, 0)
        XCTAssertEqual(plan.generators, 0)
        XCTAssertEqual(plan.reachableOrbs, plan.orbCount,
                       "a first field must be plain orbs and nothing else")
    }

    func testEachMechanicArrivesAloneAndInOrder() {
        // Splitters, then drifters, then generators — one new idea per step.
        XCTAssertEqual(FieldPlan.forStage(1).splitters, 0)
        XCTAssertGreaterThan(FieldPlan.forStage(2).splitters, 0)
        XCTAssertEqual(FieldPlan.forStage(2).drifters, 0, "two new ideas in one stage")
        XCTAssertGreaterThan(FieldPlan.forStage(3).drifters, 0)
        XCTAssertEqual(FieldPlan.forStage(3).generators, 0, "two new ideas in one stage")
        XCTAssertGreaterThan(FieldPlan.forStage(4).generators, 0)
    }

    func testFieldsGetLongerWithStageAndThenHoldSteady() {
        let reachable = (0...FieldPlan.finalStage).map { FieldPlan.forStage($0).reachableOrbs }
        for (a, b) in zip(reachable, reachable.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b, a, "a later stage produced a shorter field")
        }
        XCTAssertGreaterThan(reachable.last!, reachable.first!,
                             "the whole point of the curve is a longer field")
        // Past the final stage nothing grows: a field must stay finishable.
        XCTAssertEqual(FieldPlan.forStage(FieldPlan.finalStage),
                       FieldPlan.forStage(FieldPlan.finalStage + 50))
    }

    func testStageAdvancesSlowlyEnoughToLandOneIdeaAnEvening() {
        XCTAssertEqual(FieldPlan.stage(forFieldsCleared: 0), 0)
        XCTAssertEqual(FieldPlan.stage(forFieldsCleared: 2), 0)
        XCTAssertEqual(FieldPlan.stage(forFieldsCleared: 3), 1)
        XCTAssertEqual(FieldPlan.stage(forFieldsCleared: 10_000), FieldPlan.finalStage)
        XCTAssertEqual(FieldPlan.stage(forFieldsCleared: -5), 0, "never below the first field")
    }

    func testAFieldIsSeededToItsPlanExactlyNotOnAverage() {
        for stage in 0...FieldPlan.finalStage {
            let s = sim(seed: UInt64(stage) &+ 7, stage: stage)
            let plan = FieldPlan.forStage(stage)
            var splitters = 0, drifters = 0, generators = 0, animals = 0
            // SURFACE AND RESERVE TOGETHER. A field is deeper than the glass
            // now: past `surfaceCapacity` the rest of it waits below, so
            // counting only what is on screen counts a fraction of the field
            // and the plan looks unmet when it is not.
            for o in s.orbs + s.reserve {
                switch o.kind {
                case .splitter: splitters += 1
                case .drifter: drifters += 1
                case .generator: generators += 1
                case .animal: animals += 1
                case .plain: break
                }
            }
            XCTAssertEqual(splitters, plan.splitters, "stage \(stage) splitters")
            XCTAssertEqual(drifters, plan.drifters, "stage \(stage) drifters")
            XCTAssertEqual(generators, plan.generators, "stage \(stage) generators")
            // An animal depends on the field's place on the Path as well as
            // its stage, so the seeded plan is the authority here rather than
            // `forStage` — and it takes an ordinary orb's place, which is why
            // the totals below are unchanged by it.
            XCTAssertEqual(animals, s.plan.animals, "stage \(stage) animals")
            XCTAssertLessThanOrEqual(animals, 1, "stage \(stage) held more than one animal")
            XCTAssertEqual(s.orbs.count + s.reserve.count,
                           plan.orbCount + plan.generators, "stage \(stage) total")
        }
    }

    func testEveryStagePlanStaysInsideTheFieldEnvelope() {
        for stage in 0...FieldPlan.finalStage {
            let plan = FieldPlan.forStage(stage)
            XCTAssertTrue(GameConfig.orbCountRange.contains(plan.orbCount + plan.generators),
                          "stage \(stage) seeds outside the documented envelope")
        }
    }

    // MARK: - Splitters

    func testASplitterBecomesChildrenAndTheFieldIsNotOverYet() {
        let s = GameSimulation(seed: 1)
        s.layout(size: size)
        s.replaceOrbs(field([.splitter(remaining: 1)], at: [CGPoint(x: 200, y: 400)]))

        let events = s.tap(at: CGPoint(x: 200, y: 400))

        XCTAssertTrue(events.contains { if case .split = $0 { return true } else { return false } })
        XCTAssertEqual(s.aliveCount, GameConfig.splitChildCount, "children should be on the field")
        XCTAssertFalse(s.completed,
                       "the last orb was a splitter — the field just became more of itself")
        XCTAssertFalse(events.contains { if case .cleared = $0 { return true } else { return false } })
    }

    func testSplittingRunsExactlyAsDeepAsTheStageSays() {
        let s = GameSimulation(seed: 2)
        s.layout(size: size)
        s.replaceOrbs(field([.splitter(remaining: 2)], at: [CGPoint(x: 200, y: 400)]))

        s.tap(at: CGPoint(x: 200, y: 400))          // → 2 children, still splitters
        XCTAssertTrue(s.orbs.filter(\.alive).allSatisfy {
            if case .splitter(let r) = $0.kind { return r == 1 } else { return false }
        })

        // Pop every child; each becomes plain grandchildren.
        for child in s.orbs.filter(\.alive) { s.tap(at: child.pos) }
        let living = s.orbs.filter(\.alive)
        XCTAssertEqual(living.count, GameConfig.splitChildCount * GameConfig.splitChildCount)
        XCTAssertTrue(living.allSatisfy { $0.kind == .plain }, "depth ran past what the stage set")
    }

    func testChildrenStayComfortablyTappable() {
        let s = GameSimulation(seed: 3)
        s.layout(size: size)
        let parentR = GameConfig.orbRadiusRange.lowerBound
        s.replaceOrbs(field([.splitter(remaining: 2)], at: [CGPoint(x: 200, y: 400)], r: parentR))
        s.tap(at: CGPoint(x: 200, y: 400))
        for child in s.orbs.filter(\.alive) { s.tap(at: child.pos) }

        // Even the smallest grandchild of the smallest parent must be a
        // target, not a precision test.
        for orb in s.orbs.filter(\.alive) {
            XCTAssertGreaterThan(orb.baseR + GameConfig.tapTolerance, 22,
                                 "a grandchild got too small to be a comfortable target")
        }
    }

    func testChildrenAreBornInsideTheField() {
        let s = GameSimulation(seed: 4)
        s.layout(size: size)
        // A splitter jammed into the corner: children must not be born outside.
        s.replaceOrbs(field([.splitter(remaining: 2)], at: [CGPoint(x: 5, y: 5)]))
        s.tap(at: CGPoint(x: 5, y: 5))
        for child in s.orbs.filter(\.alive) {
            XCTAssertGreaterThanOrEqual(child.pos.x, 0)
            XCTAssertLessThanOrEqual(child.pos.x, size.width)
            XCTAssertGreaterThanOrEqual(child.pos.y, 0)
            XCTAssertLessThanOrEqual(child.pos.y, size.height)
        }
    }

    // MARK: - Drifters (the anti-frustration contract)

    func testADrifterAlwaysSurrendersToAFingerThatComesClose() {
        let s = GameSimulation(seed: 5)
        s.layout(size: size)
        let start = CGPoint(x: 200, y: 400)
        s.replaceOrbs(field([.drifter], at: [start]))

        // A finger inside the surrender radius, held there for a long time.
        s.pointer = CGPoint(x: start.x + GameConfig.evadeSurrenderRadius - 6, y: start.y)
        let before = s.orbs[0].pos
        _ = run(s, frames: 120)

        XCTAssertEqual(s.orbs[0].pos.x, before.x, accuracy: 0.001,
                       "a drifter ran from a finger that was already on it")
        XCTAssertEqual(s.orbs[0].pos.y, before.y, accuracy: 0.001)

        XCTAssertFalse(s.tap(at: s.orbs[0].pos).isEmpty, "a cornered drifter must still pop")
    }

    func testADrifterCanNeverOutrunAFinger() {
        let s = GameSimulation(seed: 6)
        s.layout(size: size)
        s.replaceOrbs(field([.drifter], at: [CGPoint(x: 200, y: 400)]))
        s.pointer = CGPoint(x: 140, y: 400)
        _ = run(s, frames: 600)

        let v = s.orbs[0].vel
        let speed = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        XCTAssertLessThanOrEqual(speed, GameConfig.evadeMaxSpeed + 0.0001,
                                 "a drifter exceeded its speed ceiling")
        XCTAssertLessThan(GameConfig.evadeMaxSpeed, 1.0,
                          "the ceiling must stay far below a moving thumb")
    }

    func testADrifterIgnoresAFingerThatIsNowhereNearIt() {
        let s = GameSimulation(seed: 7)
        s.layout(size: size)
        s.replaceOrbs(field([.drifter], at: [CGPoint(x: 200, y: 400)]))
        s.pointer = CGPoint(x: 200, y: 400 + GameConfig.evadeRadius + 40)
        let before = s.orbs[0].pos
        _ = run(s, frames: 60)
        XCTAssertEqual(s.orbs[0].pos.y, before.y, accuracy: 0.001)
    }

    func testADrifterWithNoFingerAtAllBehavesLikeAnyOtherOrb() {
        let s = GameSimulation(seed: 8)
        s.layout(size: size)
        s.replaceOrbs(field([.drifter], at: [CGPoint(x: 200, y: 400)]))
        s.pointer = nil
        let before = s.orbs[0].pos
        _ = run(s, frames: 60)
        XCTAssertEqual(s.orbs[0].pos.x, before.x, accuracy: 0.001)
    }

    func testACorneredDrifterSettlesInsteadOfFightingTheWall() {
        let s = GameSimulation(seed: 9)
        s.layout(size: size)
        let corner = CGPoint(x: 30, y: GameConfig.fieldTopInset + 30)
        s.replaceOrbs(field([.drifter], at: [corner]))
        // Finger just outside the surrender radius, pushing it into the corner.
        s.pointer = CGPoint(x: corner.x + 60, y: corner.y + 60)
        _ = run(s, frames: 300)

        let v = s.orbs[0].vel
        let speed = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        XCTAssertLessThan(speed, GameConfig.evadeMaxSpeed * 0.9,
                          "a cornered drifter should ease off, not vibrate against the wall")
    }

    // MARK: - Generators

    func testAGeneratorMakesOrbsWhileItIsOpen() {
        let s = GameSimulation(seed: 10)
        s.layout(size: size)
        let gen = Generator(closing: .quota(remaining: 3), interval: 30)
        s.replaceOrbs(field([.generator(gen)], at: [CGPoint(x: 200, y: 400)]))

        let events = run(s, frames: 200)
        let emitted = events.filter { if case .emitted = $0 { return true } else { return false } }
        XCTAssertEqual(emitted.count, 3, "a quota generator gave the wrong number of orbs")
    }

    func testAQuotaGeneratorClosesWhenItIsSpentAndTheFieldCanThenFinish() {
        let s = GameSimulation(seed: 11)
        s.layout(size: size)
        let gen = Generator(closing: .quota(remaining: 2), interval: 20)
        s.replaceOrbs(field([.generator(gen)], at: [CGPoint(x: 200, y: 400)]))

        let events = run(s, frames: 200)
        XCTAssertTrue(events.contains { if case .generatorClosed = $0 { return true } else { return false } })
        XCTAssertFalse(s.orbs.contains { if case .generator = $0.kind { return $0.alive } else { return false } })

        // Everything it made is still poppable, and popping it all ends the field.
        for orb in s.orbs.filter(\.alive) { s.tap(at: orb.pos) }
        XCTAssertTrue(s.completed, "a field with a spent generator must still be finishable")
    }

    func testASettlingGeneratorClosesOnItsOwnAndCostsHerNothing() {
        let s = GameSimulation(seed: 12)
        s.layout(size: size)
        let gen = Generator(closing: .settles(remaining: 100), interval: 40)
        s.replaceOrbs(field([.generator(gen)], at: [CGPoint(x: 200, y: 400)]))

        let events = run(s, frames: 400)
        XCTAssertTrue(events.contains { if case .generatorClosed = $0 { return true } else { return false } })
        // Nothing was popped by the settling itself: the pop count is only
        // ever what she did.
        XCTAssertEqual(s.popCount, 0, "settling must never count as a pop, for or against her")
    }

    func testATapsGeneratorGivesOnEveryPressAndPopsOnTheLast() {
        let s = GameSimulation(seed: 13)
        s.layout(size: size)
        let at = CGPoint(x: 200, y: 400)
        let gen = Generator(closing: .taps(remaining: 3), interval: 10_000)  // never by interval
        s.replaceOrbs(field([.generator(gen)], at: [at]))

        // First two presses give an orb and leave it open.
        for press in 1...2 {
            let events = s.tap(at: at)
            XCTAssertTrue(events.contains { if case .emitted(_, let byTap) = $0 { return byTap } else { return false } },
                          "press \(press) gave nothing")
            XCTAssertFalse(events.contains { if case .popped = $0 { return true } else { return false } },
                           "press \(press) popped it early")
            XCTAssertEqual(s.popCount, 0)
        }

        // The third press is the reward: it pops.
        let last = s.tap(at: at)
        XCTAssertTrue(last.contains { if case .popped = $0 { return true } else { return false } })
        XCTAssertEqual(s.popCount, 1)
    }

    func testAGeneratorNeverCrowdsTheScreen() {
        let s = GameSimulation(seed: 14)
        s.layout(size: size)
        let gen = Generator(closing: .settles(remaining: 100_000), interval: 1)
        s.replaceOrbs(field([.generator(gen)], at: [CGPoint(x: 200, y: 400)]))

        _ = run(s, frames: 2_000)
        XCTAssertLessThanOrEqual(s.aliveCount, GameConfig.activeOrbCeiling,
                                 "the calm-guard let the field crowd")
    }

    // MARK: - Nothing here breaks the guarantees the field already had

    func testAFieldOfEveryKindStillFinishes() {
        for seed in UInt64(1)...12 {
            let s = sim(seed: seed, stage: FieldPlan.finalStage)
            // Pop everything, repeatedly: splitters make children, generators
            // make orbs, and a tapped generator needs several presses.
            var guardCount = 0
            while !s.completed && guardCount < 4_000 {
                if let target = s.orbs.first(where: \.alive) {
                    s.tap(at: target.pos)
                } else {
                    _ = s.step(dt: 1.0 / 60)
                }
                guardCount += 1
            }
            XCTAssertTrue(s.completed, "seed \(seed): a full-stage field could not be finished")
        }
    }

    func testTheFieldIsStillDeterministicForASeed() {
        let a = sim(seed: 99, stage: FieldPlan.finalStage)
        let b = sim(seed: 99, stage: FieldPlan.finalStage)
        XCTAssertEqual(a.orbs.map(\.pos.x), b.orbs.map(\.pos.x))
        XCTAssertEqual(a.orbs.map(\.kind), b.orbs.map(\.kind))

        _ = run(a, frames: 300)
        _ = run(b, frames: 300)
        XCTAssertEqual(a.orbs.map(\.pos.x), b.orbs.map(\.pos.x))
        XCTAssertEqual(a.aliveCount, b.aliveCount)
    }

    func testTheFortuneNeverRidesAGeneratorOrASplitter() {
        for stage in 0...FieldPlan.finalStage {
            for seed in UInt64(1)...6 {
                let s = sim(seed: seed &* 31 &+ UInt64(stage), stage: stage)
                for orb in s.orbs where orb.isFortune {
                    XCTAssertEqual(orb.kind, .plain,
                                   "a fortune landed on a \(orb.kind) at stage \(stage)")
                }
            }
        }
    }
}
