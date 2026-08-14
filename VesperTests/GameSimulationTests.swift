import XCTest
import CoreGraphics
@testable import Vesper

// Behavior tests for the pure simulation. These pin the gameplay tuning
// contract in docs/BUILD_PLAN.md: if a refactor changes how seeding, taps,
// chains, or completion behave, something here should go red.
final class GameSimulationTests: XCTestCase {

    private let screen = CGSize(width: 390, height: 844)

    private func makeSim(seed: UInt64 = 42) -> GameSimulation {
        let sim = GameSimulation(seed: seed)
        sim.layout(size: screen)
        return sim
    }

    private func orb(at pos: CGPoint, r: CGFloat, fortune: Bool = false) -> Orb {
        var o = Orb(pos: pos, vel: .zero, r: r, baseR: r,
                    paintIndex: 0, phase: 0)
        o.spawn = 1
        o.isFortune = fortune
        return o
    }

    // MARK: - Seeding

    func testSeedingCreatesValidField() {
        let sim = makeSim()
        XCTAssertTrue(GameConfig.orbCountRange.contains(sim.orbs.count),
                      "orb count \(sim.orbs.count) outside \(GameConfig.orbCountRange)")
        for o in sim.orbs {
            XCTAssertTrue(GameConfig.orbRadiusRange.contains(o.baseR))
            XCTAssertGreaterThanOrEqual(o.pos.x, o.baseR + GameConfig.edgeInset)
            XCTAssertLessThanOrEqual(o.pos.x, screen.width - o.baseR - GameConfig.edgeInset)
            XCTAssertGreaterThanOrEqual(o.pos.y, o.baseR + GameConfig.spawnTopInset)
            XCTAssertLessThanOrEqual(o.pos.y, screen.height - o.baseR - GameConfig.edgeInset)
            XCTAssertTrue(o.alive)
        }
        XCTAssertEqual(sim.orbs.filter(\.isFortune).count, 1,
                       "exactly one orb should carry the fortune")
    }

    func testSameSeedProducesIdenticalField() {
        let a = makeSim(seed: 7)
        let b = makeSim(seed: 7)
        XCTAssertEqual(a.orbs.count, b.orbs.count)
        for (x, y) in zip(a.orbs, b.orbs) {
            XCTAssertEqual(x.pos, y.pos)
            XCTAssertEqual(x.baseR, y.baseR)
            XCTAssertEqual(x.paintIndex, y.paintIndex)
            XCTAssertEqual(x.isFortune, y.isFortune)
        }
    }

    // MARK: - Taps

    func testTapOnOrbPopsExactlyOne() {
        let sim = makeSim()
        let target = sim.orbs[0]
        let events = sim.tap(at: target.pos)

        XCTAssertEqual(sim.popCount, 1)
        XCTAssertEqual(sim.orbs.filter { !$0.alive }.count, 1)
        guard case .popped(_, let chained)? = events.first else {
            return XCTFail("expected a popped event, got \(events)")
        }
        XCTAssertFalse(chained, "a direct tap is not a chained pop")
    }

    func testTapWithinToleranceHits() {
        let sim = makeSim()
        sim.replaceOrbs([orb(at: CGPoint(x: 200, y: 400), r: 20)])
        sim.tap(at: CGPoint(x: 200 + 20 + GameConfig.tapTolerance - 1, y: 400))
        XCTAssertEqual(sim.popCount, 1, "tap inside the tolerance halo should pop")
    }

    func testFarTapPopsNothing() {
        let sim = makeSim()
        sim.replaceOrbs([orb(at: CGPoint(x: 200, y: 400), r: 20)])
        let events = sim.tap(at: CGPoint(x: 200, y: 400 + 20 + GameConfig.tapTolerance + 2))
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(sim.popCount, 0)
    }

    func testTapsIgnoredAfterCompletion() {
        let sim = makeSim()
        sim.replaceOrbs([orb(at: CGPoint(x: 200, y: 400), r: 20)])
        sim.tap(at: CGPoint(x: 200, y: 400))
        XCTAssertTrue(sim.completed)
        let events = sim.tap(at: CGPoint(x: 200, y: 400))
        XCTAssertTrue(events.isEmpty, "field is cleared; taps should do nothing")
    }

    // MARK: - Chain reactions

    func testShockwavePopsNeighbor() {
        let sim = makeSim()
        sim.replaceOrbs([
            orb(at: CGPoint(x: 200, y: 400), r: 30),
            orb(at: CGPoint(x: 260, y: 400), r: 20),
        ])
        sim.tap(at: CGPoint(x: 200, y: 400))
        XCTAssertEqual(sim.popCount, 1)

        var chainedEvents: [GameEvent] = []
        for _ in 0..<120 where !sim.completed {
            chainedEvents += sim.step(dt: 1.0 / 60.0)
        }
        XCTAssertEqual(sim.popCount, 2, "the ring should detonate the neighbor")
        XCTAssertTrue(sim.completed)

        let sawChainedPop = chainedEvents.contains {
            if case .popped(_, let chained) = $0 { return chained }
            return false
        }
        XCTAssertTrue(sawChainedPop, "the second pop should be marked as chained")
    }

    func testDistantOrbSurvivesShockwave() {
        let sim = makeSim()
        // maxR for r=20 is 110 + 20*2.6 = 162; keep the neighbor beyond it
        sim.replaceOrbs([
            orb(at: CGPoint(x: 80, y: 600), r: 20),
            orb(at: CGPoint(x: 80, y: 600 - 200), r: 20),
        ])
        sim.tap(at: CGPoint(x: 80, y: 600))
        for _ in 0..<240 {
            sim.step(dt: 1.0 / 60.0)
        }
        XCTAssertEqual(sim.popCount, 1, "an orb beyond the ring's reach must survive")
        XCTAssertFalse(sim.completed)
    }

    // MARK: - Completion & events

    func testClearedEventFiresOnceWithTotal() {
        let sim = makeSim()
        sim.replaceOrbs([
            orb(at: CGPoint(x: 100, y: 300), r: 20),
            orb(at: CGPoint(x: 300, y: 700), r: 20),
        ])
        var clearedTotals: [Int] = []
        var events = sim.tap(at: CGPoint(x: 100, y: 300))
        events += sim.tap(at: CGPoint(x: 300, y: 700))
        for _ in 0..<120 {
            events += sim.step(dt: 1.0 / 60.0)
        }
        for event in events {
            if case .cleared(let total) = event { clearedTotals.append(total) }
        }
        XCTAssertEqual(clearedTotals, [2], "cleared should fire exactly once, with the total")
    }

    func testFortuneEventFiresForFortuneOrb() {
        let sim = makeSim()
        sim.replaceOrbs([
            orb(at: CGPoint(x: 100, y: 300), r: 20, fortune: true),
        ])
        let events = sim.tap(at: CGPoint(x: 100, y: 300))
        let sawFortune = events.contains {
            if case .fortuneRevealed = $0 { return true }
            return false
        }
        XCTAssertTrue(sawFortune)
    }

    // MARK: - Restart

    func testRestartResetsAndReseeds() {
        let sim = makeSim()
        sim.tap(at: sim.orbs[0].pos)
        XCTAssertEqual(sim.popCount, 1)

        sim.restart()
        XCTAssertEqual(sim.popCount, 0)
        XCTAssertFalse(sim.completed)
        XCTAssertFalse(sim.started)
        XCTAssertTrue(sim.particles.isEmpty)
        XCTAssertTrue(sim.rings.isEmpty)
        XCTAssertTrue(GameConfig.orbCountRange.contains(sim.orbs.count))
        XCTAssertTrue(sim.orbs.allSatisfy(\.alive))
    }

    // MARK: - Budgets & robustness

    func testParticleCapIsNeverExceeded() {
        let sim = makeSim()
        // a dense cluster so everything chains, spawning maximal particles
        var cluster: [Orb] = []
        for i in 0..<30 {
            cluster.append(orb(at: CGPoint(x: 120 + CGFloat(i % 6) * 30,
                                           y: 300 + CGFloat(i / 6) * 30), r: 34))
        }
        sim.replaceOrbs(cluster)
        sim.tap(at: cluster[0].pos)
        XCTAssertLessThanOrEqual(sim.particles.count, GameConfig.particleCap)
        for _ in 0..<300 {
            sim.step(dt: 1.0 / 60.0)
            XCTAssertLessThanOrEqual(sim.particles.count, GameConfig.particleCap)
        }
        // Only the tapped orb's ring arms the chain (echo rings from chained
        // pops are visual only, as in v1.0), so the far corner of the cluster
        // survives — but everything within the first ring's reach cascades.
        XCTAssertGreaterThanOrEqual(sim.popCount, 15,
                                    "orbs within the ring's reach should cascade")
    }

    func testHugeFrameGapIsClamped() {
        let sim = makeSim()
        // e.g. app was backgrounded for a minute — one clamped step, no explosion
        sim.step(dt: 60)
        for o in sim.orbs {
            XCTAssertGreaterThanOrEqual(o.pos.x, 0)
            XCTAssertLessThanOrEqual(o.pos.x, screen.width)
            XCTAssertGreaterThanOrEqual(o.pos.y, 0)
            XCTAssertLessThanOrEqual(o.pos.y, screen.height)
        }
    }

    func testOrbsStayInBoundsOverLongRun() {
        let sim = makeSim(seed: 99)
        for _ in 0..<3600 { // one simulated minute
            sim.step(dt: 1.0 / 60.0)
        }
        for o in sim.orbs where o.alive {
            XCTAssertGreaterThanOrEqual(o.pos.x, o.r - 0.5)
            XCTAssertLessThanOrEqual(o.pos.x, screen.width - o.r + 0.5)
            XCTAssertGreaterThanOrEqual(o.pos.y, o.r + GameConfig.fieldTopInset - 0.5)
            XCTAssertLessThanOrEqual(o.pos.y, screen.height - o.r + 0.5)
        }
    }

    func testZeroDtIsANoOp() {
        let sim = makeSim()
        let before = sim.orbs.map(\.pos)
        let events = sim.step(dt: 0)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(sim.orbs.map(\.pos), before)
    }
}
