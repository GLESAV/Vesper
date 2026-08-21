import XCTest
@testable import Vesper

// Fireworks: the one thing on the field that is not a pop.
//
// Most of these assert what a firework may NOT do. It is the loudest, most
// theatrical object in a product whose first rule is no pressure, and the only
// reason that is allowed is that it gates nothing and costs nothing to ignore.
final class FireworkTests: XCTestCase {

    private let size = CGSize(width: 390, height: 800)

    private func sim(stage: Int = 4, generation: Int = 3,
                     seed: UInt64 = 31) -> GameSimulation {
        let s = GameSimulation(seed: seed)
        s.pinnedWeather = .clear
        s.layout(size: size)
        s.stage = stage
        s.generation = generation
        s.seedField()
        return s
    }

    private func display(seed: UInt64 = 31) -> GameSimulation {
        for stage in 2...FieldPlan.finalStage {
            for generation in 0...6 where FieldPlan.isDisplay(stage: stage, generation: generation) {
                let s = sim(stage: stage, generation: generation, seed: seed)
                if !s.fireworks.isEmpty { return s }
            }
        }
        XCTFail("no display field found")
        return sim()
    }

    private func run(_ s: GameSimulation, frames: Int) -> [GameEvent] {
        var all: [GameEvent] = []
        for _ in 0..<frames { all += s.step(dt: 1.0 / 60) }
        return all
    }

    // MARK: - It costs nothing to ignore

    // The whole safety argument. A shell she never touched must not stand
    // between her and the quiet.
    func testAFieldFinishesWithEveryShellUntouched() {
        let s = display()
        XCTAssertFalse(s.fireworks.isEmpty)
        var guardCount = 0
        while !s.completed && guardCount < 20_000 {
            if let orb = s.orbs.first(where: \.alive) { s.tap(at: orb.pos) }
            else { _ = s.step(dt: 1.0 / 60) }
            guardCount += 1
        }
        XCTAssertTrue(s.completed, "unfired shells blocked the field from finishing")
        XCTAssertTrue(s.fireworks.contains { $0.phase == .waiting },
                      "the test never actually left one untouched")
    }

    // A shell must never be counted as a pop, for her or against her.
    func testLaunchingAShellIsNotAPop() {
        let s = display()
        guard let shell = s.fireworks.first(where: { $0.phase == .waiting }) else {
            return XCTFail("no waiting shell")
        }
        let before = s.popCount
        let events = s.tap(at: shell.pos)
        XCTAssertEqual(s.popCount, before, "a shell counted as a pop")
        XCTAssertFalse(events.contains { if case .popped = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .fireworkLaunched = $0 { return true } else { return false } })
    }

    // MARK: - It sows rather than manufactures

    // A shell that created orbs would make the field longer every time she
    // touched one: the more she enjoyed the fireworks, the further away the
    // quiet would get.
    func testABreakNeverAddsToTheFieldsTotal() {
        let s = display()
        let total = s.orbs.count + s.reserve.count
        for shell in s.fireworks where shell.phase == .waiting { s.tap(at: shell.pos) }
        _ = run(s, frames: 400)
        XCTAssertLessThanOrEqual(s.orbs.count + s.reserve.count, total,
                                 "a shell manufactured orbs instead of sowing them")
    }

    func testABreakBringsOrbsUpWhenThereAreSomeBelow() {
        let s = sim(stage: FieldPlan.finalStage, generation: 12)
        guard !s.fireworks.isEmpty, !s.reserve.isEmpty else { return }
        let held = s.reserve.count
        for shell in s.fireworks where shell.phase == .waiting { s.tap(at: shell.pos) }
        _ = run(s, frames: 400)
        XCTAssertLessThan(s.reserve.count, held, "a break sowed nothing")
    }

    // MARK: - It moves the field without making it harder

    func testAShoveNeverPushesAnOrbPastTheSpeedCeiling() {
        let s = display()
        for shell in s.fireworks where shell.phase == .waiting { s.tap(at: shell.pos) }
        _ = run(s, frames: 300)
        let cap = GameConfig.orbMaxSpeed * Weather.clear.speedScale * 1.6
        for orb in s.orbs where orb.alive {
            let speed = (orb.vel.dx * orb.vel.dx + orb.vel.dy * orb.vel.dy).squareRoot()
            XCTAssertLessThanOrEqual(speed, cap + 0.0001, "a break outran the field's ceiling")
        }
    }

    // MARK: - Flight

    func testAShellIsOnlyTappableWhileItWaits() {
        let s = display()
        guard let shell = s.fireworks.first(where: { $0.phase == .waiting }) else {
            return XCTFail("no waiting shell")
        }
        s.tap(at: shell.pos)
        _ = run(s, frames: 8)
        // In flight now: tapping where it is must do nothing to it.
        let inFlight = s.fireworks.filter { if case .rising = $0.phase { return true } else { return false } }
        for flying in inFlight {
            let events = s.tap(at: flying.pos)
            XCTAssertFalse(events.contains { if case .fireworkLaunched = $0 { return true } else { return false } },
                           "a shell in flight was re-launched")
        }
    }

    func testEveryShellBreaksAndLeavesSmoke() {
        let s = display()
        for shell in s.fireworks where shell.phase == .waiting { s.tap(at: shell.pos) }
        let events = run(s, frames: 400)
        XCTAssertTrue(events.contains { if case .fireworkBurst = $0 { return true } else { return false } })
        XCTAssertFalse(s.smoke.isEmpty, "a break left no smoke")
        XCTAssertTrue(s.fireworks.allSatisfy { $0.phase == .spent }, "a shell never broke")
    }

    // Smoke has to accumulate, or it is an effect rather than a display.
    func testSmokeStacksAndThenClears() {
        let s = display()
        for shell in s.fireworks where shell.phase == .waiting { s.tap(at: shell.pos) }
        _ = run(s, frames: 300)
        let gathered = s.smoke.count
        XCTAssertGreaterThan(gathered, GameConfig.smokePuffsPerBurst,
                             "smoke from several shells did not gather")
        XCTAssertLessThanOrEqual(s.smoke.count, GameConfig.smokeCap)

        _ = run(s, frames: 4_000)
        XCTAssertTrue(s.smoke.isEmpty, "smoke never cleared")
    }

    // MARK: - The catalog

    func testAboutHalfOfFieldsCarryShells() {
        var displays = 0, total = 0
        for stage in 0...FieldPlan.finalStage {
            for generation in 0...24 {
                total += 1
                if FieldPlan.isDisplay(stage: stage, generation: generation) { displays += 1 }
            }
        }
        let share = Double(displays) / Double(total)
        XCTAssertGreaterThan(share, 0.3, "displays are too rare — share \(share)")
        XCTAssertLessThan(share, 0.55, "displays are too common — share \(share)")
    }

    // A stone must be the same field every time she returns to it, or The
    // Path stops meaning anything.
    func testWhetherAFieldIsADisplayIsStableForAStone() {
        for stage in 0...FieldPlan.finalStage {
            for generation in 0...20 {
                let a = FieldPlan.isDisplay(stage: stage, generation: generation)
                let b = FieldPlan.isDisplay(stage: stage, generation: generation)
                XCTAssertEqual(a, b)
            }
        }
    }

    func testTheFirstEveningsAreQuiet() {
        for generation in 0...20 {
            XCTAssertFalse(FieldPlan.isDisplay(stage: 0, generation: generation))
            XCTAssertFalse(FieldPlan.isDisplay(stage: 1, generation: generation))
        }
    }

    func testEveryShellIsStructurallyDistinctFromEveryOther() {
        for a in FireworkCatalog.all {
            for b in FireworkCatalog.all where a.id != b.id {
                // Colour alone is not a different firework.
                let same = a.kind == b.kind && a.hang == b.hang
                    && a.bloom == b.bloom && a.whirr == b.whirr
                XCTAssertFalse(same, "\(a.name) and \(b.name) differ only in paint")
            }
        }
    }

    func testTheCatalogIsWellFormed() {
        XCTAssertEqual(Set(FireworkCatalog.all.map(\.id)).count, FireworkCatalog.all.count)
        XCTAssertEqual(Set(FireworkCatalog.all.map(\.name)).count, FireworkCatalog.all.count)
        for d in FireworkCatalog.all {
            XCTAssertFalse(d.name.isEmpty)
            XCTAssertFalse(d.flavor.isEmpty, "\(d.name) needs a flavour line")
            XCTAssertFalse(d.paints.isEmpty)
            XCTAssertGreaterThan(d.hang, 0)
            XCTAssertTrue((150...600).contains(d.whirr), "\(d.name) whirrs at \(d.whirr)")
            for paint in d.paints {
                for c in [paint.fill.r, paint.fill.g, paint.fill.b,
                          paint.glow.r, paint.glow.g, paint.glow.b] {
                    XCTAssertTrue((0...1).contains(c))
                    XCTAssertLessThanOrEqual(c, 0.97, "\(d.name) is brighter than the ink cap")
                }
            }
        }
    }

    func testEveryBreakPatternIsUsed() {
        let used = Set(FireworkCatalog.all.map(\.kind))
        XCTAssertEqual(used.count, FireworkKind.allCases.count,
                       "an unused shell shape is a shape that should not exist")
    }

    func testEveryFamilyHasSeveralShellsToDrawFrom() {
        for family in PopFamily.allCases {
            XCTAssertGreaterThanOrEqual(FireworkCatalog.forFamily(family).count, 3,
                                        "\(family) displays would repeat")
        }
    }

    // MARK: - The fuse

    // A firework you tap and watch leave is a button. A firework whose fuse
    // you light and then hurry along is a thing you are doing.
    func testATouchLightsTheFuseRatherThanLaunchingTheShell() {
        let s = display()
        guard let shell = s.fireworks.first(where: { $0.phase == .waiting }) else {
            return XCTFail("no waiting shell")
        }
        let events = s.tap(at: shell.pos)
        XCTAssertTrue(events.contains { if case .fuseLit = $0 { return true } else { return false } })
        XCTAssertFalse(events.contains { if case .fireworkLaunched = $0 { return true } else { return false } },
                       "the shell flew before its fuse burned")
    }

    func testTappingTheCordIsTheSameAsTappingTheShell() {
        let s = display()
        _ = run(s, frames: 4)   // let the rope settle into place
        guard let index = s.fireworks.firstIndex(where: { $0.phase == .waiting }),
              s.fireworks[index].fuseNodes.count > 2 else {
            return XCTFail("no fuse to touch")
        }
        // The far end of the cord, as far from the shell as it gets.
        let tail = s.fireworks[index].fuseNodes.last!
        let events = s.tap(at: tail)
        XCTAssertTrue(events.contains { if case .fuseLit = $0 { return true } else { return false } },
                      "the cord was not a target")
    }

    func testTappingABurningFuseHurriesIt() {
        let s = display()
        guard let index = s.fireworks.firstIndex(where: { $0.phase == .waiting }) else {
            return XCTFail("no waiting shell")
        }
        s.tap(at: s.fireworks[index].pos)
        _ = run(s, frames: 2)
        guard case .fuse(let before) = s.fireworks[index].phase else {
            return XCTFail("the fuse is not burning")
        }
        s.tap(at: s.fireworks[index].pos)
        guard case .fuse(let after) = s.fireworks[index].phase else {
            return XCTFail("the fuse stopped burning")
        }
        XCTAssertGreaterThan(after, before + GameConfig.fuseTapBoost * 0.5,
                             "tapping the cord did not hurry it")
    }

    // Left alone it still goes. Hurrying is an option, never a requirement —
    // otherwise a firework would be the one thing here that needs work.
    func testAFuseLeftAloneBurnsDownAndLaunchesByItself() {
        let s = display()
        guard let index = s.fireworks.firstIndex(where: { $0.phase == .waiting }) else {
            return XCTFail("no waiting shell")
        }
        s.tap(at: s.fireworks[index].pos)
        let events = run(s, frames: 600)
        XCTAssertTrue(events.contains { if case .fireworkLaunched = $0 { return true } else { return false } },
                      "an untouched fuse never reached the shell")
    }

    func testShortAndLongFusesBothExist() {
        let lengths = Set(FireworkCatalog.all.map(\.fuse))
        XCTAssertGreaterThan(lengths.count, 3, "every fuse is the same length")
        XCTAssertLessThan(lengths.min()!, 60, "no shell is lit-and-gone")
        XCTAssertGreaterThan(lengths.max()!, 140, "no shell makes you wait")
    }

    // The cord is a rope, not a decal: it has slack, and it keeps moving
    // after the shell has stopped.
    func testTheFuseHangsAndTrailsRatherThanStickingToTheShell() {
        let s = display()
        _ = run(s, frames: 30)
        guard let shell = s.fireworks.first, shell.fuseNodes.count > 2 else {
            return XCTFail("no rope")
        }
        // Node 0 is pinned to the shell; the rest must not be on top of it.
        XCTAssertEqual(shell.fuseNodes[0].x, shell.pos.x, accuracy: 0.5)
        XCTAssertEqual(shell.fuseNodes[0].y, shell.pos.y, accuracy: 0.5)
        let tail = shell.fuseNodes.last!
        let dx = tail.x - shell.pos.x, dy = tail.y - shell.pos.y
        XCTAssertGreaterThan((dx * dx + dy * dy).squareRoot(), 20,
                             "the cord collapsed onto the shell")
    }

    func testTheRopeStaysTogetherUnderAShove() {
        let s = display()
        for shell in s.fireworks where shell.phase == .waiting { s.tap(at: shell.pos) }
        _ = run(s, frames: 600)
        for shell in s.fireworks where shell.fuseNodes.count > 1 {
            for k in 0..<(shell.fuseNodes.count - 1) {
                let a = shell.fuseNodes[k], b = shell.fuseNodes[k + 1]
                let d = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
                XCTAssertLessThan(d, GameConfig.fuseSegmentLength * 3,
                                  "the rope stretched apart")
                XCTAssertFalse(d.isNaN, "the rope went unstable")
            }
        }
    }
}