import XCTest
import CoreGraphics
@testable import Vesper

// SplitMix64 — the one piece of machinery the whole world is built on.
//
// "A seed is a field." Every orb's place and paint, every stone on the Path,
// every gust of weather and every verse comes out of this eight-byte struct.
// It is also the only thing standing between a persisted seed and the field it
// is supposed to reproduce — and the map never deletes a stone (W08), so a
// change to the mixer would not just break the next field, it would quietly
// redraw every Path anyone has ever walked.
//
// These pin three separate things: that the mixer's ARITHMETIC is fixed
// (golden vectors), that its VALUE SEMANTICS hold (the simulation copies the
// generator every frame to draw the sky), and that its OUTPUT is good enough
// to seed a field with — spread, no repeats, no stuck bits.
final class SeededRandomTests: XCTestCase {

    /// The first `count` draws of a freshly built generator.
    private func draws(seed: UInt64, count: Int) -> [UInt64] {
        var g = SplitMix64(seed: seed)
        var out: [UInt64] = []
        out.reserveCapacity(count)
        for _ in 0..<count { out.append(g.next()) }
        return out
    }

    // MARK: - Determinism

    // The property the game rests on. Two generators built separately from the
    // same seed are the same generator: nothing about construction order,
    // process state, or wall-clock time may enter.
    func testTheSameSeedYieldsTheIdenticalSequence() {
        for seed in [UInt64(0), 1, 7, 42, 0xDEAD_BEEF, UInt64.max] {
            XCTAssertEqual(draws(seed: seed, count: 1000),
                           draws(seed: seed, count: 1000),
                           "seed \(seed) did not reproduce itself")
        }
    }

    // THE MIXER ITSELF IS THE COMPATIBILITY CONTRACT. These are the canonical
    // SplitMix64 vectors. If someone "simplifies" a shift or a multiplier,
    // every saved map seed starts pointing at a different world — the stones
    // she has already walked would come back as strangers. So the arithmetic is
    // pinned by literal value, never by an expression that recomputes it.
    func testTheMixersArithmeticIsFixedByValue() {
        XCTAssertEqual(draws(seed: 0, count: 4),
                       [0xE220_A839_7B1D_CDAF,
                        0x6E78_9E6A_A1B9_65F4,
                        0x06C4_5D18_8009_454F,
                        0xF88B_B8A8_724C_81EC])

        XCTAssertEqual(draws(seed: 1, count: 2),
                       [0x910A_2DEC_8902_5CC1, 0xBEEB_8DA1_658E_EC67])

        XCTAssertEqual(draws(seed: 42, count: 2),
                       [0xBDD7_3226_2FEB_6E95, 0x28EF_E333_B266_F103])

        // The top seed makes the very first `state &+=` wrap. Pinned because an
        // addition that trapped instead of wrapping would crash on a perfectly
        // ordinary seed — both `GameSimulation()` and the map draw their
        // default seeds from the full 64-bit range.
        XCTAssertEqual(draws(seed: UInt64.max, count: 2),
                       [0xE4D9_7177_1B65_2C20, 0xE99F_F867_DBF6_82C9])
    }

    // The state advances BEFORE it is mixed, so a fresh generator never simply
    // hands back the number it was seeded with. A field seeded from a counter
    // would otherwise leak that counter straight into its first orb.
    func testTheFirstValueIsNeverTheSeedItself() {
        var leaks: [UInt64] = []
        for step in stride(from: 0, to: 4096, by: 37) {
            let seed = UInt64(step)
            var g = SplitMix64(seed: seed)
            if g.next() == seed { leaks.append(seed) }
        }
        XCTAssertTrue(leaks.isEmpty, "seeds came straight back out: \(leaks)")
    }

    // MARK: - Divergence

    // Adjacent seeds are the dangerous case: the map derives child seeds from a
    // parent's, and the simulation is often handed small integers by hand. A
    // weak mixer leaks the seed's structure into the first value and
    // neighbouring stones start to look like each other. Measured as avalanche
    // — about half the bits should flip — over a fixed set of pairs, so there
    // is nothing probabilistic about the run itself.
    func testAdjacentSeedsProduceUnrelatedFirstValues() {
        var total = 0
        var worst = 64
        for seed in 0..<256 {
            var a = SplitMix64(seed: UInt64(seed))
            var b = SplitMix64(seed: UInt64(seed) &+ 1)
            let flipped = (a.next() ^ b.next()).nonzeroBitCount
            total += flipped
            worst = min(worst, flipped)
        }
        // A mixer worth having lands near 32 bits; an identity-ish one lands
        // near 1. The bounds are wide on purpose — this checks for structure
        // leaking through, not for a particular distribution.
        XCTAssertGreaterThan(worst, 8, "some adjacent pair flipped only \(worst) bits")
        let mean = Double(total) / 256.0
        XCTAssertGreaterThan(mean, 24, "poor avalanche: \(mean) bits flipped on average")
        XCTAssertLessThan(mean, 40, "suspicious avalanche: \(mean) bits flipped on average")
    }

    // Two seeds must not merely start apart, they must stay apart. If two
    // streams ever met they would run together forever after — two different
    // fields turning into the same field partway through.
    func testDifferentSeedsDoNotConvergeOverALongRun() {
        let a = Set(draws(seed: 1000, count: 2000))
        let b = Set(draws(seed: 1001, count: 2000))
        XCTAssertTrue(a.isDisjoint(with: b),
                      "two seeds shared \(a.intersection(b).count) values")
    }

    // MARK: - Value semantics (load-bearing)

    // `GameSimulation.step` does `var sky = rng` and draws the weather's seed
    // from the COPY. That only works because SplitMix64 is a value: a copy has
    // to replay the original's future exactly, so the sky is determined by the
    // field's seed and by nothing else.
    func testACopyReplaysTheOriginalsFutureExactly() {
        var original = SplitMix64(seed: 31337)
        for _ in 0..<11 { _ = original.next() }

        var copy = original
        var fromOriginal: [UInt64] = []
        var fromCopy: [UInt64] = []
        for _ in 0..<50 {
            fromOriginal.append(original.next())
            fromCopy.append(copy.next())
        }
        XCTAssertEqual(fromCopy, fromOriginal, "the copy left the original's line")
    }

    // The other half of the same contract, and the half that would actually
    // bite: consuming the copy must take NOTHING out of the original. A weather
    // layer that ate a draw every frame would change the composition of every
    // field that already exists.
    func testConsumingACopyDoesNotDisturbTheOriginal() {
        var field = SplitMix64(seed: 31337)
        for _ in 0..<11 { _ = field.next() }

        var copy = field
        for _ in 0..<500 { _ = copy.next() }

        // What the field's own sequence should still be: a generator advanced
        // the same eleven times and never copied at all.
        var untouched = SplitMix64(seed: 31337)
        for _ in 0..<11 { _ = untouched.next() }

        var fromField: [UInt64] = []
        var fromUntouched: [UInt64] = []
        for _ in 0..<50 {
            fromField.append(field.next())
            fromUntouched.append(untouched.next())
        }
        XCTAssertEqual(fromField, fromUntouched, "the copy consumed the field's own draws")
    }

    // The production shape, written out. Six hundred frames of drawing a sky
    // seed off a copy — exactly what `step` does — must leave the field's own
    // next value bit-identical to a field that never ran a frame.
    func testDrawingASkySeedEveryFrameLeavesTheFieldsSequenceUntouched() {
        var field = SplitMix64(seed: 0xA11CE)
        var skySeeds: [UInt64] = []
        for _ in 0..<600 {
            var sky = field
            skySeeds.append(sky.next())
        }

        var untouched = SplitMix64(seed: 0xA11CE)
        let fieldsOwnNext = field.next()
        let untouchedNext = untouched.next()
        XCTAssertEqual(fieldsOwnNext, untouchedNext,
                       "six hundred sky draws moved the field's own sequence")

        // And because the copies are taken from a generator that never moved,
        // every frame asks for the same sky. If the copy shared state with the
        // field these would all be different — this is the reference-semantics
        // tripwire.
        XCTAssertEqual(Set(skySeeds).count, 1,
                       "the sky seed wandered while the field stood still")
    }

    // MARK: - Quality

    // SplitMix64 mixes a counter bijectively, so within any run far shorter
    // than its period no value may appear twice. This is the strongest cheap
    // check there is: it fails loudly for a short cycle or a collapsed output,
    // and it subsumes "no immediate repeats".
    func testALongRunNeverRepeatsAValue() {
        let values = draws(seed: 12345, count: 20_000)
        XCTAssertEqual(Set(values).count, values.count, "a value came round twice")
    }

    // Stuck or biased bits are how a generator quietly stops being one. The
    // high bits are what `randomElement` and `Int.random` lean on, and a
    // generator with a dead top byte still looks fine in a small sample. Fixed
    // seed, big sample, very loose bound — this must never become the flaky
    // test that gets deleted.
    func testEveryBitPositionIsExercisedAboutHalfTheTime() {
        let values = draws(seed: 12345, count: 20_000)
        var setCount = [Int](repeating: 0, count: 64)
        for v in values {
            for bit in 0..<64 where (v >> bit) & 1 == 1 { setCount[bit] += 1 }
        }
        for bit in 0..<64 {
            let fraction = Double(setCount[bit]) / Double(values.count)
            XCTAssertGreaterThan(fraction, 0.45, "bit \(bit) is set only \(fraction) of the time")
            XCTAssertLessThan(fraction, 0.55, "bit \(bit) is set \(fraction) of the time")
        }
    }

    // Spread, checked at both ends of the word. The low nibble matters because
    // `Int.random(in:)` reduces into small ranges; the high nibble matters
    // because an unmixed counter would still look uniform down at the bottom.
    func testBothEndsOfTheWordSpreadAcrossAllSixteenBuckets() {
        let values = draws(seed: 98765, count: 20_000)
        var high = [Int](repeating: 0, count: 16)
        var low = [Int](repeating: 0, count: 16)
        for v in values {
            high[Int(v >> 60)] += 1
            low[Int(v & 15)] += 1
        }
        let expected = Double(values.count) / 16.0
        for bucket in 0..<16 {
            XCTAssertGreaterThan(Double(high[bucket]), expected * 0.75,
                                 "high bucket \(bucket) is starved: \(high[bucket])")
            XCTAssertLessThan(Double(high[bucket]), expected * 1.25,
                              "high bucket \(bucket) is crowded: \(high[bucket])")
            XCTAssertGreaterThan(Double(low[bucket]), expected * 0.75,
                                 "low bucket \(bucket) is starved: \(low[bucket])")
            XCTAssertLessThan(Double(low[bucket]), expected * 1.25,
                              "low bucket \(bucket) is crowded: \(low[bucket])")
        }
    }

    // The whole 64-bit range is in play — not a generator that only ever
    // returns small numbers, which is the failure mode that survives every
    // "does it look random" eyeball check.
    func testTheFullSixtyFourBitRangeIsReached() {
        let values = draws(seed: 5, count: 5_000)
        XCTAssertGreaterThan(values.max() ?? 0, 0xF000_0000_0000_0000,
                             "the top of the range is never reached")
        XCTAssertLessThan(values.min() ?? UInt64.max, 0x0FFF_FFFF_FFFF_FFFF,
                          "the bottom of the range is never reached")
    }

    // MARK: - Through the standard library

    // The game almost never calls `next()` directly: it calls
    // `randomElement(using:)`, `Int.random(in:using:)`,
    // `Double.random(in:using:)` and `shuffled(using:)`. Determinism has to
    // survive that whole path, or "the same seed is the same field" is not true
    // of any field that actually exists.
    func testSwiftsOwnRandomHelpersAreDeterministicThroughIt() {
        var a = SplitMix64(seed: 2024)
        var b = SplitMix64(seed: 2024)
        let pool = Array(1...30)

        var fromA: [String] = []
        var fromB: [String] = []
        for _ in 0..<200 {
            let intA = Int.random(in: 0..<100, using: &a)
            let intB = Int.random(in: 0..<100, using: &b)
            fromA.append("\(intA)")
            fromB.append("\(intB)")

            let doubleA = Double.random(in: 0..<1, using: &a)
            let doubleB = Double.random(in: 0..<1, using: &b)
            fromA.append("\(doubleA)")
            fromB.append("\(doubleB)")

            let pickA = pool.randomElement(using: &a) ?? -1
            let pickB = pool.randomElement(using: &b) ?? -1
            fromA.append("\(pickA)")
            fromB.append("\(pickB)")

            let shuffleA = pool.shuffled(using: &a)
            let shuffleB = pool.shuffled(using: &b)
            fromA.append("\(shuffleA)")
            fromB.append("\(shuffleB)")
        }
        XCTAssertEqual(fromA, fromB, "the standard library's draws diverged for one seed")
    }

    // Ranges are honoured whatever the seed. `Int.random(in: 0..<max(1, paintCount))`
    // indexes a paint array directly, so an out-of-range draw is a crash in a
    // shipped field rather than a wrong colour.
    func testStandardLibraryDrawsStayInsideTheirRanges() {
        var strays: [String] = []
        for seed in 0..<40 {
            var g = SplitMix64(seed: UInt64(seed))
            for _ in 0..<100 {
                let i = Int.random(in: 0..<7, using: &g)
                if !(0..<7).contains(i) { strays.append("Int \(i)") }
                let d = Double.random(in: 0..<1, using: &g)
                if d < 0 || d >= 1 { strays.append("Double \(d)") }
                let c = CGFloat.random(in: -0.5...0.5, using: &g)
                if c < -0.5 || c > 0.5 { strays.append("CGFloat \(c)") }
            }
        }
        XCTAssertTrue(strays.isEmpty, "draws left their range: \(strays.prefix(5))")
    }

    // A shuffle must be a permutation, not a filter — `Verses.all.shuffled(using:)`
    // is the bag the done-card draws from, and a shuffle that dropped a line
    // would quietly retire it forever.
    func testShufflingThroughItKeepsEveryElement() {
        let pool = Array(1...200)
        for seed in 0..<20 {
            var g = SplitMix64(seed: UInt64(seed))
            let shuffled = pool.shuffled(using: &g)
            XCTAssertEqual(shuffled.count, pool.count, "seed \(seed) changed the count")
            XCTAssertEqual(Set(shuffled), Set(pool), "seed \(seed) lost or duplicated an element")
        }
    }

    // MARK: - Edge seeds

    // Zero and UInt64.max are the two seeds most likely to be typed by hand —
    // `WeatherField` starts life at `SplitMix64(seed: 0)` — and the two most
    // likely to be special-cased by a broken generator. They have to behave
    // like any other seed: no repeats, no collapse, full spread.
    func testEdgeSeedsBehaveLikeAnyOtherSeed() {
        for seed in [UInt64(0), UInt64.max, UInt64.max &- 1, 1] {
            let values = draws(seed: seed, count: 4_000)
            XCTAssertEqual(Set(values).count, values.count, "seed \(seed) repeated a value")
            XCTAssertGreaterThan(values.max() ?? 0, 0xF000_0000_0000_0000,
                                 "seed \(seed) never reached the top of the range")
            XCTAssertLessThan(values.min() ?? UInt64.max, 0x0FFF_FFFF_FFFF_FFFF,
                              "seed \(seed) never reached the bottom of the range")
        }
    }

    // Zero and UInt64.max are not each other's stream either — a generator that
    // folded or truncated its seed would put them on the same one.
    func testTheEdgeSeedsAreNotEachOthersStream() {
        let zero = Set(draws(seed: 0, count: 2_000))
        let top = Set(draws(seed: UInt64.max, count: 2_000))
        XCTAssertTrue(zero.isDisjoint(with: top),
                      "the edge seeds shared \(zero.intersection(top).count) values")
    }
}
