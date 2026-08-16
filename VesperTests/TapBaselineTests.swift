import XCTest
import CoreGraphics
@testable import Vesper

// W20a — the v1.2 tap-success baseline.
//
// docs/gdd/DELIVERY_ROADMAP.md gates the One World build on "tap success
// within 2% of the v1.2 baseline" (ruling 15). This file *is* that baseline:
// it measures, through the pure simulation and before any world code exists,
// what fraction of realistically-placed touches actually pop an orb in v1.2.
//
// Everything here is deterministic — fixed seeds, no wall-clock, no rendering,
// and `step(dt:)` is never called, so orb radii stay at `baseR` and no chain
// reaction can confuse a tap with a shockwave. The number is reproducible on
// any machine, which is the whole point: a gate phrased "within 2% of the
// baseline" is unmeasurable until the baseline is a committed number.
//
// Note for whoever runs W20: the input model changes (v1.2 pops on touch-up,
// W03 pops on touch-down — ruling 3). This harness measures *resolution*, not
// latency: given where a thumb lands, does a pop happen. That question is
// identical under both input models, which is why this number survives the
// rewrite and can be compared like-for-like.
final class TapBaselineTests: XCTestCase {

    // MARK: - The committed baseline

    /// **THE BASELINE.** Other gates compare against this number.
    ///
    /// Do not "fix" a red measurement by editing this constant: a change here
    /// means tap resolution itself moved, which is exactly what this gate
    /// exists to catch. If a gameplay change genuinely intends to move it,
    /// re-derive it (below), change it in its own commit, and say so.
    ///
    /// It is a *computed* number, not an observed one. Under the v1.2 rule
    /// (`hit iff distance <= orb.r + GameConfig.tapTolerance`), an orb radius
    /// uniform over 18...34 and the fixed offset grid in `offsetDistances`,
    /// the expected success rate is exact arithmetic:
    ///
    ///     offset (pt)   pops iff r >=   P(pop)   trials
    ///     0 (centre)    any r           1         1
    ///     4 … 28        any r           1         5 x 4 = 20
    ///     33            21              13/16     4
    ///     38            26               8/16     4
    ///     41            29               5/16     4
    ///     ---------------------------------------------------
    ///     expected pops = 1 + 20 + 4 * (26/16) = 27.5 of 33 trials
    ///                   = 0.83333…  ->  committed as 0.8333
    ///
    /// `testCommittedBaselineMatchesItsDerivation` re-derives this from
    /// `GameConfig`, so a tuning change to `tapTolerance` or `orbRadiusRange`
    /// fails loudly here instead of quietly moving the gate underneath W20.
    static let v12TapSuccessBaseline = 0.8333

    /// Tolerance on the measured rate, in absolute rate (1.5 percentage points).
    ///
    /// The measurement is deterministic, but it samples a *finite* number of
    /// random radii, so it lands near — not on — the population expectation.
    /// Per orb the success count is `21 + 4h`, where `h` counts the three
    /// partial-credit offsets; `h` has sd 1.11, so the per-orb rate has
    /// sd 4.44/33 = 0.135. Over the ~1,560 orbs these seeds produce, the
    /// standard error is ~0.0034 — this tolerance is ~4.4 standard errors,
    /// wide enough never to flake and far too tight to hide a behavior change.
    static let baselineTolerance = 0.015

    // MARK: - Trial grid

    /// A portrait iPhone field, matching `GameSimulationTests`.
    private static let fieldSize = CGSize(width: 390, height: 844)

    /// 120 fixed seeds. More seeds shrink the sampling error; the committed
    /// baseline itself is seed-count independent (it is the population
    /// expectation), so this can be tuned for runtime without moving the gate.
    private static let baselineSeeds: [UInt64] = (1...120).map { UInt64($0) }

    /// Thumb-offset magnitudes in points, from a dead-centre hit out past the
    /// point where nothing can be hit. The v1.2 halo is `r + 12`, i.e. 30…46 pt
    /// wide depending on orb size, so 4…28 always land, 33/38/41 land only on
    /// progressively larger orbs, and the grid straddles the tolerance edge
    /// rather than sitting on it (an offset exactly on a boundary would make
    /// the result depend on last-ulp float behavior).
    ///
    /// 41 pt is also the largest offset that is guaranteed to stay on screen:
    /// seeding keeps every orb centre at least `r + edgeInset` = 42 pt from the
    /// left/right/bottom edges and `r + spawnTopInset` from the top, so no
    /// trial point is a touch the device could not physically deliver.
    private static let offsetDistances: [CGFloat] = [4, 10, 16, 22, 28, 33, 38, 41]

    /// Four axis-aligned directions. Success depends only on distance, so the
    /// directions exist to spread trials over the field (edges, neighbours),
    /// not to add hit-test cases. Unit vectors rather than angles so the
    /// displacement is exact.
    private static let offsetDirections: [CGVector] = [
        CGVector(dx: 1, dy: 0),
        CGVector(dx: -1, dy: 0),
        CGVector(dx: 0, dy: 1),
        CGVector(dx: 0, dy: -1),
    ]

    /// 1 centre tap + 8 magnitudes x 4 directions.
    private static var trialsPerOrb: Int { 1 + offsetDistances.count * offsetDirections.count }

    // MARK: - Measurement 1: the baseline

    // Each trial is isolated: the orb under test is the only orb on the field,
    // so the number measures the v1.2 hit-test contract itself and cannot be
    // inflated by a neighbour that happened to drift under the thumb. The
    // neighbour case is measured separately, below, against this same run.
    func testV12TapSuccessBaseline() {
        var trials = 0
        var pops = 0
        var predicted = 0
        var orbsSampled = 0

        for seed in Self.baselineSeeds {
            let sim = GameSimulation(seed: seed)
            // Halves the burst particle count. This measures tap resolution,
            // not particle budgets, and it keeps the whole run cheap.
            sim.reduceMotion = true
            sim.layout(size: Self.fieldSize)
            let seeded = sim.orbs
            XCTAssertFalse(seeded.isEmpty, "seed \(seed) produced an empty field")
            orbsSampled += seeded.count

            for target in seeded {
                for point in Self.trialPoints(around: target) {
                    // Restores the single-orb field (and clears the previous
                    // burst) before every trial, so trials never interact.
                    sim.replaceOrbs([target])
                    let events = sim.tap(at: point)

                    trials += 1
                    if Self.poppedCount(events) > 0 { pops += 1 }
                    if Self.isWithinHalo(point, of: target) { predicted += 1 }
                }
            }
        }

        XCTAssertGreaterThan(trials, 20_000,
                             "the harness degenerated — too few trials to trust the rate")
        XCTAssertEqual(trials, orbsSampled * Self.trialsPerOrb,
                       "every sampled orb must contribute the full trial grid")

        // Exact, not approximate: every pop must be explained by the halo rule
        // and every halo hit must produce a pop. A tie exactly on the boundary
        // could in principle differ by one ulp between the sim's comparison and
        // this one, but radii are drawn from a continuous distribution, so an
        // exact tie has probability zero.
        XCTAssertEqual(pops, predicted,
                       "pops (\(pops)) and the r + tapTolerance halo (\(predicted)) disagree — "
                       + "tap resolution no longer matches the v1.2 rule")

        let rate = Double(pops) / Double(trials)
        print("[W20a] v1.2 tap-success baseline = \(rate) "
              + "(\(pops)/\(trials) trials, \(orbsSampled) orbs, \(Self.baselineSeeds.count) seeds)")

        XCTAssertEqual(rate, Self.v12TapSuccessBaseline, accuracy: Self.baselineTolerance,
                       "measured tap success \(rate) has moved off the committed v1.2 baseline "
                       + "\(Self.v12TapSuccessBaseline) — W20's \"within 2% of baseline\" gate "
                       + "compares against this number, so investigate before changing it")
    }

    // The committed constant is only trustworthy if it still follows from the
    // tuning constants. If someone widens tapTolerance or reshapes
    // orbRadiusRange, this fails first and names the real cause.
    func testCommittedBaselineMatchesItsDerivation() {
        let derived = Self.analyticSuccessRate()
        XCTAssertEqual(derived, Self.v12TapSuccessBaseline, accuracy: 0.0005,
                       "the baseline derived from GameConfig is \(derived), but the committed "
                       + "constant is \(Self.v12TapSuccessBaseline) — gameplay tuning moved the "
                       + "baseline; re-commit it deliberately, in its own change")
    }

    // MARK: - Measurement 2: overlapping orbs

    // The same trial grid, but with the whole seeded field present. Two things
    // must hold at once: a touch that would have popped the isolated orb still
    // pops something (neighbours can only add pops, never remove one), and a
    // touch landing on overlapping orbs resolves to exactly one pop — never
    // zero, never two — taking the topmost orb, i.e. the last one drawn.
    func testFieldContextResolvesEveryTapToExactlyOnePop() {
        let seeds = Self.baselineSeeds.prefix(24)
        var trials = 0
        var fieldPops = 0
        var isolatedPops = 0
        var overlapTrials = 0

        for seed in seeds {
            let sim = GameSimulation(seed: seed)
            sim.reduceMotion = true
            sim.layout(size: Self.fieldSize)
            let seeded = sim.orbs

            for target in seeded {
                for point in Self.trialPoints(around: target) {
                    // Every orb whose halo covers this point, topmost last.
                    let covering = seeded.indices.filter { Self.isWithinHalo(point, of: seeded[$0]) }
                    if covering.count > 1 { overlapTrials += 1 }

                    sim.replaceOrbs(seeded)
                    let events = sim.tap(at: point)
                    let popped = Self.poppedCount(events)
                    trials += 1
                    if popped > 0 { fieldPops += 1 }
                    if Self.isWithinHalo(point, of: target) { isolatedPops += 1 }

                    if let top = covering.last {
                        XCTAssertEqual(popped, 1,
                                       "a touch covering \(covering.count) orb(s) must resolve to "
                                       + "exactly one pop, got \(popped)")
                        XCTAssertEqual(sim.popCount, 1)
                        XCTAssertEqual(sim.orbs.filter { !$0.alive }.count, 1,
                                       "exactly one orb may be removed by a single touch")
                        guard let orb = Self.firstPoppedOrb(events) else {
                            return XCTFail("expected a popped orb in \(events)")
                        }
                        XCTAssertEqual(orb.pos, seeded[top].pos,
                                       "overlapping orbs must resolve topmost-first")
                    } else {
                        XCTAssertEqual(popped, 0, "a touch outside every halo must pop nothing")
                    }
                }
            }
        }

        // Coverage guard: if seeding ever spreads orbs so far apart that no
        // trial overlaps, the topmost-first assertions above stop proving
        // anything and this test would pass vacuously.
        XCTAssertGreaterThan(overlapTrials, 0,
                             "no overlapping-orb trials were sampled — this measurement is vacuous")

        // Per trial, "hit the target" implies "hit something", so the field
        // rate can only be greater than or equal to the isolated rate.
        XCTAssertGreaterThanOrEqual(fieldPops, isolatedPops,
                                    "neighbouring orbs must never remove a pop")

        let fieldRate = Double(fieldPops) / Double(trials)
        print("[W20a] tap success in field context = \(fieldRate) "
              + "(\(fieldPops)/\(trials) trials, \(overlapTrials) overlapping, \(seeds.count) seeds)")
        XCTAssertGreaterThan(trials, 4_000,
                             "the harness degenerated — too few trials to trust the rate")
    }

    // Stacked orbs, generated deterministically: every orb in the stack covers
    // the tap point, so the only correct answer is one pop from the topmost.
    func testStackedOrbsAlwaysResolveToTheTopmostSinglePop() {
        var rng = SplitMix64(seed: 0xB1A551F1ED0FF5E7)
        let sim = GameSimulation(seed: 3)
        sim.reduceMotion = true
        sim.layout(size: Self.fieldSize)

        for trial in 0..<300 {
            let count = Int.random(in: 2...4, using: &rng)
            let point = CGPoint(x: CGFloat.random(in: 120...270, using: &rng),
                                y: CGFloat.random(in: 300...700, using: &rng))
            var stack: [Orb] = []
            for _ in 0..<count {
                let r = CGFloat.random(in: GameConfig.orbRadiusRange, using: &rng)
                let angle = CGFloat.random(in: 0...(2 * CGFloat.pi), using: &rng)
                // Centres stay within half a radius of the point, so the point
                // is unambiguously inside every orb — well clear of the
                // tolerance boundary, and clear of float-edge cases.
                let d = CGFloat.random(in: 0...(r * 0.5), using: &rng)
                stack.append(Self.orb(at: CGPoint(x: point.x + cos(angle) * d,
                                                  y: point.y + sin(angle) * d), r: r))
            }

            sim.replaceOrbs(stack)
            let events = sim.tap(at: point)

            XCTAssertEqual(Self.poppedCount(events), 1,
                           "trial \(trial): \(count) stacked orbs must pop exactly one")
            XCTAssertEqual(sim.popCount, 1, "trial \(trial)")
            guard let orb = Self.firstPoppedOrb(events) else {
                return XCTFail("trial \(trial): expected a popped orb in \(events)")
            }
            XCTAssertEqual(orb.pos, stack[count - 1].pos,
                           "trial \(trial): the topmost (last-drawn) orb must win")
            let chained = events.contains {
                if case .popped(_, let c) = $0 { return c }
                return false
            }
            XCTAssertFalse(chained, "trial \(trial): a direct touch is not a chained pop")
        }
    }

    // Topmost-first means topmost *among the orbs actually covering the point*,
    // not simply the last orb on the field.
    func testTopmostRuleSkipsAnUncoveredTopOrb() {
        let sim = GameSimulation(seed: 11)
        sim.layout(size: Self.fieldSize)
        sim.replaceOrbs([
            Self.orb(at: CGPoint(x: 150, y: 400), r: 20),   // covers the point
            Self.orb(at: CGPoint(x: 170, y: 400), r: 20),   // covers it, and is on top
            Self.orb(at: CGPoint(x: 300, y: 400), r: 20),   // topmost, but far away
        ])
        let events = sim.tap(at: CGPoint(x: 160, y: 400))

        XCTAssertEqual(sim.popCount, 1)
        guard let orb = Self.firstPoppedOrb(events) else {
            return XCTFail("expected a popped orb in \(events)")
        }
        XCTAssertEqual(orb.pos, CGPoint(x: 170, y: 400))
    }

    // MARK: - Helpers

    /// The v1.2 hit test, written in exactly the form `GameSimulation.tap`
    /// uses so the two cannot disagree by rounding.
    private static func isWithinHalo(_ p: CGPoint, of o: Orb) -> Bool {
        let dx = p.x - o.pos.x
        let dy = p.y - o.pos.y
        let rr = o.r + GameConfig.tapTolerance
        return dx * dx + dy * dy <= rr * rr
    }

    private static func trialPoints(around o: Orb) -> [CGPoint] {
        var points = [o.pos]
        for d in offsetDistances {
            for dir in offsetDirections {
                points.append(CGPoint(x: o.pos.x + dir.dx * d, y: o.pos.y + dir.dy * d))
            }
        }
        return points
    }

    private static func poppedCount(_ events: [GameEvent]) -> Int {
        events.reduce(into: 0) { total, event in
            if case .popped = event { total += 1 }
        }
    }

    private static func firstPoppedOrb(_ events: [GameEvent]) -> Orb? {
        for event in events {
            if case .popped(let orb, _) = event { return orb }
        }
        return nil
    }

    private static func orb(at pos: CGPoint, r: CGFloat) -> Orb {
        var o = Orb(pos: pos, vel: .zero, r: r, baseR: r,
                    popNumber: PopCatalog.classic.number, variantIndex: 0, phase: 0)
        o.spawn = 1
        return o
    }

    /// The population expectation of the trial grid: for each offset, the
    /// probability that a uniformly-drawn orb radius is large enough for the
    /// halo to reach it. Derived from `GameConfig`, never from a measurement.
    private static func analyticSuccessRate() -> Double {
        let rMin = Double(GameConfig.orbRadiusRange.lowerBound)
        let rMax = Double(GameConfig.orbRadiusRange.upperBound)
        let tolerance = Double(GameConfig.tapTolerance)

        // The centre tap is inside the halo for every radius.
        var expectedPops = 1.0
        var trials = 1.0

        for d in offsetDistances {
            // pops iff d <= r + tolerance, i.e. r >= d - tolerance
            let needed = Double(d) - tolerance
            let p: Double
            if needed <= rMin {
                p = 1
            } else if needed >= rMax {
                p = 0
            } else {
                p = (rMax - needed) / (rMax - rMin)
            }
            expectedPops += p * Double(offsetDirections.count)
            trials += Double(offsetDirections.count)
        }
        return expectedPops / trials
    }
}
