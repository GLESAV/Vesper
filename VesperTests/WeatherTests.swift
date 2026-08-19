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

    // No weather may pull the whole field into a corner and hold it there.
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
        XCTAssertEqual(Weather.clear.drift, .zero)
    }

    func testEachWeatherIsDistinguishableFromEveryOther() {
        for a in Weather.allCases {
            for b in Weather.allCases where a != b {
                let identical = a.speedScale == b.speedScale
                    && a.glide == b.glide
                    && a.wander == b.wander
                    && a.swellAmount == b.swellAmount
                    && a.drift == b.drift
                XCTAssertFalse(identical, "\(a) and \(b) feel the same")
            }
        }
    }

    func testRainSlidesAndSnowGrips() {
        XCTAssertEqual(Weather.rain.glide, 1, "rain must lose no momentum — that is the slipperiness")
        XCTAssertLessThan(Weather.snow.glide, 1, "snow must be grippy")
        XCTAssertGreaterThan(Weather.rain.drift.dy, 0, "rain drizzles downward")
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
}
