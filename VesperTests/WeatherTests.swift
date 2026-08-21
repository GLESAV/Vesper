import XCTest
@testable import Vesper

// Weather changes how a field FEELS and may not change how hard it is.
// Guardrail 1 has no exception for atmosphere, so these tests are mostly
// about what weather is forbidden from doing.
final class WeatherTests: XCTestCase {

    private let size = CGSize(width: 390, height: 800)

    private func sim(_ weather: Weather, seed: UInt64 = 5) -> GameSimulation {
        // Seeds are searched rather than forced: `weather` is private(set) and
        // chosen from the field's own RNG, which is exactly the coupling worth
        // preserving — a seed is a field, weather included.
        for candidate in seed..<(seed + 4000) {
            let s = GameSimulation(seed: candidate)
            s.layout(size: size)
            s.seedField()
            if s.weather == weather { return s }
        }
        XCTFail("no seed produced \(weather)")
        return GameSimulation(seed: 0)
    }

    private func run(_ s: GameSimulation, frames: Int) {
        for _ in 0..<frames { _ = s.step(dt: 1.0 / 60) }
    }

    private func fastest(_ s: GameSimulation) -> CGFloat {
        s.orbs.filter(\.alive).map { ($0.vel.dx * $0.vel.dx + $0.vel.dy * $0.vel.dy).squareRoot() }
            .max() ?? 0
    }

    // MARK: - The guardrail

    // The ceiling that makes "livelier, not harder" true in fact. A field that
    // outruns her is a field she has to keep up with.
    func testNoWeatherEverLetsTheFieldOutrunHer() {
        for weather in Weather.allCases {
            let s = sim(weather)
            run(s, frames: 3_000)
            let cap = GameConfig.orbMaxSpeed * weather.speedScale * 1.6
            XCTAssertLessThanOrEqual(fastest(s), cap + 0.0001,
                                     "\(weather) let an orb exceed its own ceiling")
            XCTAssertLessThanOrEqual(fastest(s), GameConfig.orbMaxSpeed * 2.0,
                                     "\(weather) is too fast for a calm field")
        }
    }

    func testEveryWeatherStaysInsideTheRestfulSpeedBand() {
        for weather in Weather.allCases {
            XCTAssertGreaterThanOrEqual(weather.speedScale, 0.7, "\(weather) is too sluggish to feel alive")
            XCTAssertLessThanOrEqual(weather.speedScale, 1.15, "\(weather) is too quick to be restful")
        }
    }

    // STORM IS THE ONE TO WATCH. Its chaos must live in direction, never in
    // speed — otherwise "elegant chaos" quietly becomes difficulty.
    func testStormsChaosIsInDirectionAndNotInSpeed() {
        XCTAssertGreaterThan(Weather.storm.wander, 0, "storm without wander is not a storm")
        XCTAssertLessThanOrEqual(Weather.storm.speedScale, 1.12,
                                 "storm must not be fast, only unpredictable")

        let storm = sim(.storm)
        let calm = sim(.clear)
        run(storm, frames: 1_200)
        run(calm, frames: 1_200)
        XCTAssertLessThanOrEqual(fastest(storm), GameConfig.orbMaxSpeed * 2.0)
    }

    // NO WEATHER MAY PULL THE WHOLE FIELD INTO A CORNER AND HOLD IT THERE.
    //
    // This test earned its place immediately: rain and snow originally
    // carried a constant downward drift added to velocity each frame, which
    // inside a bounded field is not a drizzle but a waterfall — the bias
    // accumulated until every orb hit its ceiling travelling straight down
    // and the field collapsed into a bouncing band along the floor.
    func testNoWeatherStrandsTheFieldAgainstAnEdge() {
        for weather in Weather.allCases {
            let s = sim(weather)
            run(s, frames: 4_000)
            let alive = s.orbs.filter(\.alive)
            XCTAssertFalse(alive.isEmpty)
            let spread = (alive.map(\.pos.y).max() ?? 0) - (alive.map(\.pos.y).min() ?? 0)
            XCTAssertGreaterThan(spread, 60,
                                 "\(weather) collapsed the field into a band")
        }
    }

    // Every field still finishes, in every weather.
    func testEveryFieldFinishesInEveryWeather() {
        for weather in Weather.allCases {
            let s = sim(weather)
            var guardCount = 0
            while !s.completed && guardCount < 4_000 {
                if let target = s.orbs.first(where: \.alive) { s.tap(at: target.pos) }
                else { _ = s.step(dt: 1.0 / 60) }
                guardCount += 1
            }
            XCTAssertTrue(s.completed, "a \(weather) field could not be finished")
        }
    }

    // MARK: - The character is actually there

    func testStillAirIsExactlyTheFieldAsItAlwaysWas() {
        XCTAssertEqual(Weather.clear.speedScale, 1)
        XCTAssertEqual(Weather.clear.glide, 1)
        XCTAssertEqual(Weather.clear.wander, 0)
        XCTAssertEqual(Weather.clear.swellAmount, 0)
    }

    func testEachWeatherIsDistinguishableFromEveryOther() {
        for a in Weather.allCases {
            for b in Weather.allCases where a != b {
                let identical = a.speedScale == b.speedScale
                    && a.glide == b.glide
                    && a.wander == b.wander
                    && a.wanderIsStepped == b.wanderIsStepped
                    && a.swellAmount == b.swellAmount
                XCTAssertFalse(identical, "\(a) and \(b) feel the same")
            }
        }
    }

    func testRainSlidesAndSnowGrips() {
        XCTAssertEqual(Weather.rain.glide, 1, "rain must lose no momentum — that is the slipperiness")
        XCTAssertLessThan(Weather.snow.glide, 1, "snow must be grippy")
        XCTAssertGreaterThan(Weather.rain.wander, 0, "rain needs some life in it")
        XCTAssertTrue(Weather.snow.wanderIsStepped, "snow moves in crunching steps, not smoothly")
        XCTAssertFalse(Weather.storm.wanderIsStepped, "wind is continuous")
    }

    func testSummerSwellsTogetherRatherThanIndividually() {
        XCTAssertGreaterThan(Weather.summer.swellAmount, 0)
        XCTAssertGreaterThan(Weather.summer.swellRate, 0)
        // Slow enough to read as a tide rather than a shake: a full cycle
        // takes several seconds at 60 fps.
        let framesPerCycle = (2 * CGFloat.pi) / Weather.summer.swellRate
        XCTAssertGreaterThan(framesPerCycle, 180, "the swell is a shake, not a tide")
    }

    // MARK: - Still deterministic, and still mostly quiet

    func testWeatherIsDeterministicFromTheSeed() {
        for seed in UInt64(1)...40 {
            let a = GameSimulation(seed: seed); a.layout(size: size); a.seedField()
            let b = GameSimulation(seed: seed); b.layout(size: size); b.seedField()
            XCTAssertEqual(a.weather, b.weather, "seed \(seed) gave two different skies")
        }
    }

    // Weather should be a thing she NOTICES. A sky that is remarkable every
    // evening is a sky that is remarkable never.
    func testStillAirIsTheMostCommonWeatherByADistance() {
        var counts: [Weather: Int] = [:]
        for seed in UInt64(1)...600 {
            let s = GameSimulation(seed: seed)
            s.layout(size: size)
            s.seedField()
            counts[s.weather, default: 0] += 1
        }
        let clear = counts[.clear] ?? 0
        XCTAssertGreaterThan(clear, 600 * 3 / 10, "weather has become the norm")
        for weather in Weather.allCases where weather != .clear {
            XCTAssertGreaterThan(counts[weather] ?? 0, 0, "\(weather) never occurs")
            XCTAssertLessThan(counts[weather] ?? 0, clear, "\(weather) is more common than still air")
        }
    }

    // MARK: - The air as a FIELD
    //
    // Weather has a body now — crests that sweep across the field and carry
    // the pops, eddies, gusts, flakes, shafts, banks of fog. Everything above
    // was about what a MULTIPLIER may not do; everything below is the same
    // question asked of a FORCE, which is the harder half: a force can push
    // the field into a corner, hold it against a wall, or quietly outrun her.

    private func air(_ weather: Weather, frames: Int = 1, reduceMotion: Bool = false,
                     orbs: [Orb] = [], seed: UInt64 = 11) -> WeatherField {
        var field = WeatherField()
        for _ in 0..<max(1, frames) {
            field.step(1, weather: weather, bounds: size,
                       reduceMotion: reduceMotion, orbs: orbs, seed: seed)
        }
        return field
    }

    private func floater(at pos: CGPoint, vel: CGVector = .zero) -> Orb {
        var o = Orb(pos: pos, vel: vel, r: 26, baseR: 26,
                    popNumber: PopCatalog.classic.number, variantIndex: 0, phase: 0)
        o.spawn = 1
        return o
    }

    private func speed(_ v: CGVector) -> CGFloat { (v.dx * v.dx + v.dy * v.dy).squareRoot() }

    // THE AIR MAY NOT MOVE FASTER THAN THE AIR IS ALLOWED TO MOVE.
    //
    // `flowCarry` is the speed of the air itself, and therefore the fastest
    // the air can carry anything. Holding it under the ceiling that already
    // existed is what keeps the whole field system inside guardrail 1.
    func testTheAirsOwnSpeedStaysUnderTheAirsOwnCeiling() {
        for weather in Weather.allCases {
            XCTAssertGreaterThanOrEqual(weather.flowCarry, 0)
            XCTAssertLessThanOrEqual(weather.flowCarry, weather.speedScale * 1.6,
                                     "\(weather) blows faster than its own ceiling allows")
            XCTAssertLessThanOrEqual(weather.flowCarry, 1.4,
                                     "\(weather) is too quick to be restful")
        }
    }

    // THE ONE SUBTRACTION THAT MAKES ALL OF THIS SAFE, PROVEN RATHER THAN
    // ASSERTED. The air carries an orb by moving WHERE IT IS, and it may only
    // use what is left under the ceiling once the orb's own speed is counted
    // — so however many crests, eddies, gusts and thermals overlap, the total
    // distance covered in a frame is what it has always been.
    //
    // WHAT THE INVARIANT ACTUALLY SAYS, AND WHY IT IS NOT `total <= ceiling`.
    // The first draft of this test asserted exactly that, over orb speeds
    // drawn from a fixed ±0.22-per-axis box — up to 0.311 pt/frame. That box
    // is above the ceiling for half the airs in the game (snow's is 0.236,
    // fog's 0.213), so it failed on the orb's own speed before the air had
    // contributed anything at all, in every air whose `flowCarry` is zero and
    // whose `drift` therefore returns exactly `.zero`. It was asking the
    // weather to answer for a speed the weather did not create and cannot
    // remove.
    //
    // The guarantee `WeatherField.drift` really makes — the one the product
    // needs — is that THE AIR NEVER ADDS TO A TOTAL THAT IS ALREADY AT OR
    // OVER THE CEILING, and never pushes one under it past it. Written as one
    // line: the total after carrying is no more than the greater of the
    // ceiling and what the orb was already doing. Both halves are exercised
    // below, because the draw deliberately spans the ceiling.
    func testTheAirCanNeverCarryAnythingPastTheCeiling() {
        var rng = SplitMix64(seed: 99)
        for weather in Weather.allCases {
            let field = air(weather, frames: 700, orbs: [floater(at: CGPoint(x: 190, y: 400))])
            let ceiling = GameConfig.orbMaxSpeed * weather.speedScale * 1.6
            XCTAssertEqual(field.ceiling, ceiling, accuracy: 0.000_001)

            var sawRoom = false        // at least one sample under the ceiling
            var sawFull = false        // and at least one already at or over it

            for _ in 0..<400 {
                let p = CGPoint(x: CGFloat.random(in: 0...size.width, using: &rng),
                                y: CGFloat.random(in: 0...size.height, using: &rng))
                // Drawn as a magnitude and a heading rather than as a box, so
                // the range of own-speeds is the stated one instead of a
                // corner-dependent accident of two axes.
                let own = CGFloat.random(in: 0...(ceiling * 1.3), using: &rng)
                if own < ceiling { sawRoom = true } else { sawFull = true }

                let d = field.drift(at: p, ownSpeed: own)
                XCTAssertLessThanOrEqual(own + speed(d), max(own, ceiling) + 0.000_001,
                                         "\(weather) carried a pop past the ceiling")
                XCTAssertLessThanOrEqual(speed(d), field.carry + 0.000_001,
                                         "\(weather) moved faster than the air itself")
                if own >= ceiling {
                    XCTAssertEqual(speed(d), 0, accuracy: 0.000_001,
                                   "\(weather) added to a pop with nothing left")
                }
            }

            XCTAssertTrue(sawRoom, "\(weather): the draw never left the air any room")
            XCTAssertTrue(sawFull, "\(weather): the draw never tested a full orb")
        }
    }

    // An orb already travelling at its own top speed is not carried at all:
    // the allowance is what is LEFT, and there is nothing left.
    func testTheAirWillNotCarryWhatIsAlreadyAtItsCeiling() {
        for weather in Weather.allCases {
            let field = air(weather, frames: 500)
            let ceiling = GameConfig.orbMaxSpeed * weather.speedScale * 1.6
            for x in stride(from: CGFloat(10), through: size.width - 10, by: 30) {
                let d = field.drift(at: CGPoint(x: x, y: 400), ownSpeed: ceiling)
                XCTAssertEqual(speed(d), 0, accuracy: 0.000_001,
                               "\(weather) carried a pop that had no room left")
            }
        }
    }

    // THE AIR MOVES THE POP, NOT THE POP'S MOTION. Velocity, size and life are
    // untouched — how hard a thing is to hit is not weather's business.
    func testTheAirCarriesOrbsAndChangesNothingElseAboutThem() {
        for weather in Weather.allCases {
            let field = air(weather, frames: 400)
            var o = floater(at: CGPoint(x: 200, y: 300), vel: CGVector(dx: 0.1, dy: 0))
            field.apply(to: &o, 1)
            XCTAssertEqual(o.vel.dx, 0.1, "\(weather) changed an orb's own motion")
            XCTAssertEqual(o.vel.dy, 0)
            XCTAssertEqual(o.r, 26)
            XCTAssertEqual(o.baseR, 26)
            XCTAssertTrue(o.alive)
            XCTAssertEqual(o.spawn, 1)
        }
    }

    // And it carries by the same amount whether that frame was long or short:
    // everything here scales by the clamped frame factor, like all motion in
    // this app. Stepped until the water actually reaches the point, so the
    // test cannot pass by measuring nothing.
    func testTheAirCarriesByTheFrameFactor() {
        let p = CGPoint(x: 190, y: 400)
        var field = WeatherField()
        var carried = CGVector.zero
        for _ in 0..<2_000 {
            field.step(1, weather: .rain, bounds: size, reduceMotion: false,
                       orbs: [floater(at: p)], seed: 4)
            let d = field.drift(at: p, ownSpeed: 0)
            if speed(d) > 0.01 { carried = d; break }
        }
        XCTAssertGreaterThan(speed(carried), 0.01, "the water never reached the pop")

        var single = floater(at: p)
        var triple = floater(at: p)
        field.apply(to: &single, 1)
        field.apply(to: &triple, 3)
        XCTAssertEqual(single.pos.x - p.x, carried.dx, accuracy: 0.000_001)
        XCTAssertEqual(triple.pos.x - p.x, carried.dx * 3, accuracy: 0.000_001)
        XCTAssertEqual(triple.pos.y - p.y, carried.dy * 3, accuracy: 0.000_001)
    }

    // NOTHING MAY PILE THE FIELD AGAINST A SIDE WALL EITHER.
    //
    // The older weather could only strand the field downward, so the original
    // test watched `y`. Crests travel sideways, which is a new way to end up
    // with every orb in one place, so the same standard is applied across.
    func testTheAirNeverStrandsTheFieldAgainstASideWall() {
        for weather in Weather.allCases {
            let s = sim(weather)
            run(s, frames: 4_000)
            let alive = s.orbs.filter(\.alive)
            XCTAssertFalse(alive.isEmpty)
            let xs = alive.map(\.pos.x)
            let spread = (xs.max() ?? 0) - (xs.min() ?? 0)
            XCTAssertGreaterThan(spread, 60, "\(weather) swept the field into a column")
            let centre = xs.reduce(0, +) / CGFloat(xs.count)
            XCTAssertGreaterThan(centre, size.width * 0.15, "\(weather) held the field left")
            XCTAssertLessThan(centre, size.width * 0.85, "\(weather) held the field right")
        }
    }

    // WHY THE WATER GIVES BACK WHAT IT TOOK. Successive crests strictly
    // alternate direction, so a field cannot lose ground to the tide however
    // long she plays.
    func testCrestsStrictlyAlternateDirection() {
        var field = WeatherField()
        var born: [CGFloat] = []
        for _ in 0..<6_000 {
            field.step(1, weather: .rain, bounds: size, reduceMotion: false,
                       orbs: [], seed: 5)
            for c in field.crests where c.age <= 1.0001 { born.append(c.dir) }
        }
        XCTAssertGreaterThan(born.count, 3, "no water arrived at all")
        for (a, b) in zip(born, born.dropFirst()) {
            XCTAssertEqual(a, -b, "two crests ran the same way")
        }
        XCTAssertLessThanOrEqual(abs(born.reduce(0, +)), 1,
                                 "the tide has a net direction")
    }

    // Water meets the pops rather than passing behind them.
    func testWaterSplashesWhereItMeetsAPop() {
        var orbs: [Orb] = []
        for k in 0..<6 {
            orbs.append(floater(at: CGPoint(x: 60 + CGFloat(k) * 50, y: 200 + CGFloat(k) * 60)))
        }
        var field = WeatherField()
        var sawSplash = false
        for _ in 0..<900 {
            field.step(1, weather: .rain, bounds: size, reduceMotion: false,
                       orbs: orbs, seed: 3)
            if !field.splashes.isEmpty { sawSplash = true }
            XCTAssertLessThanOrEqual(field.splashes.count, GameConfig.weatherSplashCap)
        }
        XCTAssertTrue(sawSplash, "the water passed straight through the pops")
    }

    // EVERY ARRAY IS BOUNDED, and by the air's own counts rather than by luck.
    // A weather layer that grew would be a dropped frame waiting to happen.
    func testTheAirHoldsOnlyWhatItSaysItHolds() {
        let orbs = (0..<14).map { floater(at: CGPoint(x: 30 + CGFloat($0) * 24,
                                                      y: 120 + CGFloat($0) * 40)) }
        for weather in Weather.allCases {
            var field = WeatherField()
            for _ in 0..<6_000 {
                field.step(1, weather: weather, bounds: size, reduceMotion: false,
                           orbs: orbs, seed: 21)
            }
            XCTAssertLessThanOrEqual(field.crests.count, 3, "\(weather) grew crests")
            XCTAssertLessThanOrEqual(field.crests.count, weather.crestCount,
                                     "\(weather) holds more water than it says it does")
            XCTAssertLessThanOrEqual(field.eddies.count, 4, "\(weather) grew eddies")
            XCTAssertLessThanOrEqual(field.flakes.count, 72, "\(weather) grew flakes")
            XCTAssertLessThanOrEqual(field.shafts.count, 3, "\(weather) grew shafts")
            XCTAssertLessThanOrEqual(field.banks.count, 7, "\(weather) grew fog")
            XCTAssertLessThanOrEqual(field.splashes.count, GameConfig.weatherSplashCap,
                                     "\(weather) grew splashes")
        }
    }

    // Under Reduce Motion the air is something to LOOK at: it still exists,
    // it moves at a fifth of its pace, and it does not move the field at all.
    func testReduceMotionStillsTheAirWithoutEmptyingIt() {
        for weather in Weather.allCases where weather != .clear {
            let field = air(weather, frames: 400, reduceMotion: true)
            XCTAssertEqual(field.carry, 0, "\(weather) still carries under reduce motion")

            var o = floater(at: CGPoint(x: 190, y: 400), vel: CGVector(dx: 0.05, dy: -0.02))
            field.apply(to: &o, 3)
            XCTAssertEqual(o.pos.x, 190, "\(weather) still moved a pop under reduce motion")
            XCTAssertEqual(o.pos.y, 400)
            XCTAssertEqual(o.vel.dx, 0.05, accuracy: 0.000_001)
            XCTAssertEqual(o.vel.dy, -0.02, accuracy: 0.000_001)
            XCTAssertEqual(speed(field.drift(at: o.pos, ownSpeed: 0)), 0)
        }
        XCTAssertLessThan(GameConfig.weatherStillnessScale, 0.5,
                          "reduce motion must be a heavy damping, not a nudge")
    }

    // A rain field held still still has water in it to watch.
    func testTheAirIsVisibleEvenWhenItIsHeldStill() {
        XCTAssertFalse(air(.rain, frames: 200, reduceMotion: true).crests.isEmpty)
        XCTAssertFalse(air(.storm, frames: 200, reduceMotion: true).eddies.isEmpty)
        XCTAssertFalse(air(.snow, frames: 200, reduceMotion: true).flakes.isEmpty)
        XCTAssertFalse(air(.summer, frames: 200, reduceMotion: true).shafts.isEmpty)
        XCTAssertFalse(air(.fog, frames: 200, reduceMotion: true).banks.isEmpty)
    }

    // Still air is still: nothing to draw, nothing to feel.
    func testStillAirHasNoFieldAtAll() {
        let field = air(.clear, frames: 300)
        XCTAssertFalse(Weather.clear.hasField)
        XCTAssertEqual(field.carry, 0)
        XCTAssertTrue(field.crests.isEmpty)
        XCTAssertTrue(field.eddies.isEmpty)
        XCTAssertTrue(field.flakes.isEmpty)
        XCTAssertTrue(field.shafts.isEmpty)
        XCTAssertTrue(field.banks.isEmpty)
        for weather in Weather.allCases where weather != .clear {
            XCTAssertTrue(weather.hasField, "\(weather) has nothing in it to see")
        }
    }

    // A seed is a field, and the sky over it. Two runs of the same air from
    // the same seed have to be the same weather, frame for frame.
    func testTheAirIsDeterministicFromItsSeed() {
        for weather in Weather.allCases {
            let a = air(weather, frames: 500, seed: 77)
            let b = air(weather, frames: 500, seed: 77)
            XCTAssertEqual(a.crests.count, b.crests.count)
            XCTAssertEqual(a.crests.first?.x, b.crests.first?.x)
            XCTAssertEqual(a.eddies.first?.pos.x, b.eddies.first?.pos.x)
            XCTAssertEqual(a.flakes.first?.pos.y, b.flakes.first?.pos.y)
            XCTAssertEqual(a.gustLevel, b.gustLevel)
        }
    }

    // The simulation and the sky agree about what air it is — the field the
    // renderer draws is the same one the orbs are moving through.
    func testTheSimulationsAirAndItsFieldAreTheSameAir() {
        for weather in Weather.allCases {
            let s = sim(weather)
            run(s, frames: 120)
            XCTAssertEqual(s.weatherField.weather, weather)
            XCTAssertEqual(s.weatherField.bounds, size)
        }
        let wet = sim(.rain)
        run(wet, frames: 60)
        XCTAssertFalse(wet.weatherField.crests.isEmpty, "a rain field with no water in it")
    }

    // Wind gathers and ebbs rather than blowing steadily — a steady wind is a
    // fan, and a fan is one direction the field would slowly lose to.
    func testWindGathersAndEbbs() {
        var field = WeatherField()
        var high = false, low = false
        for _ in 0..<4_000 {
            field.step(1, weather: .storm, bounds: size, reduceMotion: false,
                       orbs: [], seed: 13)
            if field.gustLevel > 0.25 { high = true }
            if high && field.gustLevel < 0.06 { low = true }
            XCTAssertLessThanOrEqual(field.gustLevel, 1)
            XCTAssertGreaterThanOrEqual(field.gustLevel, 0)
        }
        XCTAssertTrue(high, "no gust ever arrived")
        XCTAssertTrue(low, "the gust never ebbed")
        XCTAssertTrue(Weather.storm.hasGusts)
        XCTAssertGreaterThan(Weather.storm.eddyCount, 0, "wind without eddies is a fan")
    }

    // Snow settles, and then it melts and falls again. Nothing in this game
    // is taken away for good, including a flake.
    func testSnowSettlesAndReturns() {
        var field = WeatherField()
        var everSettled = 0
        for _ in 0..<3_000 {
            field.step(1, weather: .snow, bounds: size, reduceMotion: false,
                       orbs: [], seed: 8)
            everSettled = max(everSettled, field.flakes.filter { $0.rest > 0 }.count)
        }
        XCTAssertGreaterThan(everSettled, 0, "nothing ever came to rest")
        XCTAssertEqual(field.flakes.count, Weather.snow.flakeCount,
                       "flakes went missing")
    }

    // Warm is the bright air; the rest keep the light they always had.
    func testWarmIsTheAirThatShines() {
        XCTAssertGreaterThan(Weather.summer.shine, 0)
        XCTAssertGreaterThan(Weather.summer.shaftCount, 0)
        XCTAssertEqual(Weather.clear.shine, 0, "still air must look exactly as it did")
        XCTAssertEqual(Weather.snow.shine, 0)
        XCTAssertEqual(Weather.fog.shine, 0)
        XCTAssertLessThanOrEqual(GameConfig.weatherShineOpacity, 0.3,
                                 "a shine that bright would be a glare")
    }

    // The drawn air stays dark. These are the numbers the renderer draws with,
    // and a bright band would break guardrail 4 in a place no test could see.
    func testTheDrawnAirStaysDark() {
        XCTAssertLessThanOrEqual(GameConfig.weatherBandOpacity, 0.12)
        XCTAssertLessThanOrEqual(GameConfig.weatherFogOpacity, 0.16)
        XCTAssertLessThanOrEqual(GameConfig.weatherFoamOpacity, 0.2)
    }
}
