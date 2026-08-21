import XCTest
@testable import Vesper

// Depth, growth, and the onward sequence.
//
// The field is an aerial view of something with depth: only a fixed number of
// orbs are on the glass at once and the rest wait below, rising as room is
// made. That separation is what lets a field grow along the Path and on
// return without ever looking busier.
final class FieldDepthTests: XCTestCase {

    private let size = CGSize(width: 390, height: 800)

    private func sim(generation: Int = 0, plays: Int = 0,
                     stage: Int = 0, seed: UInt64 = 21) -> GameSimulation {
        let s = GameSimulation(seed: seed)
        s.pinnedWeather = .clear
        s.layout(size: size)
        s.stage = stage
        s.generation = generation
        s.plays = plays
        s.seedField()
        return s
    }

    // MARK: - The surface never crowds

    func testTheGlassNeverHoldsMoreThanItsSurfaceCapacity() {
        for generation in [0, 3, 8, 20, 60] {
            for plays in [0, 1, 5] {
                let s = sim(generation: generation, plays: plays, stage: FieldPlan.finalStage)
                XCTAssertLessThanOrEqual(
                    s.orbs.count, GameConfig.surfaceCapacity + FieldPlan.forStage(FieldPlan.finalStage).generators,
                    "generation \(generation), plays \(plays) crowded the glass")
            }
        }
    }

    func testAFieldPastTheSurfaceCapacityKeepsTheRestUnderneath() {
        let s = sim(generation: 10, stage: FieldPlan.finalStage)
        XCTAssertFalse(s.reserve.isEmpty, "a deep field kept nothing in reserve")
    }

    // MARK: - Growth

    func testEachStepAlongThePathIsALongerField() {
        var previous = 0
        for generation in 0...6 {
            let total = FieldPlan.totalOrbs(base: 12, generation: generation, plays: 0)
            XCTAssertGreaterThan(total, previous, "generation \(generation) was not longer")
            previous = total
        }
    }

    // Compounding growth has to stop somewhere. 1.2x per generation reaches
    // 38x by generation twenty and 5,000x by fifty; a field that cannot be
    // finished in an evening is not a bigger field, it is a broken one.
    func testGrowthIsCappedSoAFieldStaysFinishable() {
        for generation in [30, 80, 400] {
            let total = FieldPlan.totalOrbs(base: 16, generation: generation, plays: 2)
            XCTAssertLessThanOrEqual(total, GameConfig.maxFieldOrbs,
                                     "generation \(generation) grew past the cap")
        }
    }

    func testReturningToAClearedStoneGivesHerMoreOfIt() {
        let first = FieldPlan.totalOrbs(base: 12, generation: 0, plays: 0)
        let second = FieldPlan.totalOrbs(base: 12, generation: 0, plays: 1)
        let third = FieldPlan.totalOrbs(base: 12, generation: 0, plays: 2)
        XCTAssertEqual(second, first * 2, "a second visit should be twice the field")
        XCTAssertEqual(third, first * 3, "a third visit should be three times")
        XCTAssertEqual(FieldPlan.totalOrbs(base: 12, generation: 0, plays: 9), third,
                       "growth on return stops at three — it is not a treadmill")
    }

    // MARK: - Rising, not arriving

    func testAnOrbRisesIntoTheRoomAPopJustMade() {
        let s = sim(generation: 10, stage: FieldPlan.finalStage)
        guard let target = s.orbs.first(where: \.alive) else { return XCTFail("empty field") }
        let held = s.reserve.count

        let events = s.tap(at: target.pos)

        XCTAssertTrue(events.contains { if case .rose = $0 { return true } else { return false } },
                      "nothing came up into the gap")
        XCTAssertEqual(s.reserve.count, held - 1)
        // It arrives at the bottom of its rise, not at full size.
        let risen = s.orbs.filter(\.alive).min { $0.spawn < $1.spawn }
        XCTAssertEqual(risen?.spawn ?? 1, 0, accuracy: 0.001,
                       "it appeared already surfaced — that reads as teleporting in")
    }

    func testRisingIsSlowEnoughToReadAsRising() {
        // Four times slower than the old spawn curve, which is the whole
        // difference between rising and appearing.
        XCTAssertGreaterThan(GameConfig.riseFrames, 40)
        XCTAssertLessThan(1 / GameConfig.riseFrames, GameConfig.spawnGrowth,
                          "an orb reaching the surface faster than it spawns is a pop-in")
    }

    func testAnOrbSurfacesNearTheGapAndNotAtTheEdge() {
        let s = sim(generation: 10, stage: FieldPlan.finalStage)
        guard let target = s.orbs.first(where: \.alive) else { return XCTFail("empty field") }
        let where_ = target.pos
        s.tap(at: where_)
        guard let risen = s.orbs.last, risen.spawn < 0.2 else { return XCTFail("nothing rose") }
        let dx = risen.pos.x - where_.x, dy = risen.pos.y - where_.y
        XCTAssertLessThan((dx * dx + dy * dy).squareRoot(), 90,
                          "it surfaced away from the room she made")
    }

    // MARK: - The field still ends

    func testADeepFieldIsNotFinishedUntilTheDepthIsEmpty() {
        let s = sim(generation: 12, stage: FieldPlan.finalStage)
        // Clear the surface once; the field must not call itself done.
        for orb in s.orbs.filter(\.alive) { s.tap(at: orb.pos) }
        if !s.reserve.isEmpty {
            XCTAssertFalse(s.completed, "a field with orbs still underneath called itself clear")
        }
    }

    func testEvenTheDeepestFieldCanBeFinished() {
        for generation in [0, 6, 20, 100] {
            let s = sim(generation: generation, stage: FieldPlan.finalStage)
            var guardCount = 0
            while !s.completed && guardCount < 20_000 {
                if let target = s.orbs.first(where: \.alive) { s.tap(at: target.pos) }
                else { _ = s.step(dt: 1.0 / 60) }
                guardCount += 1
            }
            XCTAssertTrue(s.completed, "a generation-\(generation) field could not be finished")
        }
    }

    func testAFieldStillHoldsEveryOrbItWasGiven() {
        let s = sim(generation: 8, stage: 0)
        let total = s.orbs.count + s.reserve.count
        var popped = 0
        var guardCount = 0
        while !s.completed && guardCount < 20_000 {
            if let target = s.orbs.first(where: \.alive) {
                s.tap(at: target.pos)
                popped += 1
            } else { _ = s.step(dt: 1.0 / 60) }
            guardCount += 1
        }
        // Splitters make more than they were, so popped >= total is the bound
        // that matters: nothing in the reserve was ever quietly dropped.
        XCTAssertGreaterThanOrEqual(popped, total,
                                    "orbs went missing between the reserve and the surface")
    }
}
