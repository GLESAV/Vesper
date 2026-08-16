import XCTest
@testable import Vesper

// The catalog's contract: 100 well-formed pops, stable numbering, sane value
// envelopes (docs/pop_standard.md), and — most important — pop #001 "Vesper"
// reproducing the original v1.0 pop exactly.
final class PopCatalogTests: XCTestCase {

    // MARK: - Shape of the catalog

    func testCatalogHasExactly100StablyNumberedPops() {
        XCTAssertEqual(PopCatalog.all.count, 100)
        XCTAssertEqual(PopCatalog.all.map(\.number), Array(1...100),
                       "numbers must be 1...100 in order — append, never renumber")
        XCTAssertEqual(Set(PopCatalog.all.map(\.name)).count, 100,
                       "every pop name must be unique")
    }

    func testOnlyTheClassicPopIsAvailableFromTheStart() {
        let starters = PopCatalog.all.filter {
            if case .start = $0.unlock { return true }
            return false
        }
        XCTAssertEqual(starters.map(\.number), [1])
    }

    func testRarityDistribution() {
        let secrets = PopCatalog.all.filter { $0.rarity == .secret }
        XCTAssertEqual(secrets.count, 3, "exactly three secret pops")
        let rares = PopCatalog.all.filter { $0.rarity == .rare }
        XCTAssertGreaterThanOrEqual(rares.count, 8)
    }

    // MARK: - Classic fidelity (the original v1.0 pop, codified)

    func testClassicPopMatchesOriginalTuning() {
        let classic = PopCatalog.classic
        XCTAssertEqual(classic.number, 1)
        XCTAssertEqual(classic.name, "Vesper")

        // style — the original five palette pairs, soft dots
        XCTAssertEqual(classic.style.paints.count, 5)
        XCTAssertEqual(classic.style.particleShape, .dot)
        XCTAssertEqual(classic.style.particleSizeRange, 1.2...3.4)
        XCTAssertEqual(classic.style.haloOpacity, 0.18)
        XCTAssertEqual(classic.style.highlightOpacity, 0.14)
        XCTAssertFalse(classic.style.shimmer)
        let offWhite = classic.style.paints[0]
        XCTAssertEqual(offWhite.fill.r, 233.0/255, accuracy: 0.001)
        XCTAssertEqual(offWhite.glow.b, 238.0/255, accuracy: 0.001)

        // behavior — original burst, sound, and haptic values
        XCTAssertEqual(classic.behavior.particleCountBase, GameConfig.particleBaseCount)
        XCTAssertEqual(classic.behavior.particleSpeedRange, 1.2...6)
        XCTAssertEqual(classic.behavior.particleGravity,
                       Double(GameConfig.particleGravity), accuracy: 0.0001)
        XCTAssertEqual(classic.behavior.sound,
                       SoundProfile(startFreq: 460, freqSpread: 420, sweep: 0.55,
                                    duration: 0.14, decay: 7.5, brightness: 0))
        XCTAssertEqual(classic.behavior.haptic.baseIntensity, 0.35, accuracy: 0.0001)
        XCTAssertEqual(classic.behavior.haptic.intensityPerSize, 0.5, accuracy: 0.0001)
        XCTAssertFalse(classic.behavior.haptic.sharp)

        // chain — the original shockwave, sourced from GameConfig
        XCTAssertEqual(classic.chain.ringCount, 1)
        XCTAssertEqual(classic.chain.maxRadiusBase, Double(GameConfig.ringBaseMaxRadius))
        XCTAssertEqual(classic.chain.maxRadiusPerOrbRadius, Double(GameConfig.ringRadiusPerOrbRadius))
        XCTAssertEqual(classic.chain.growthFactor, Double(GameConfig.ringGrowthFactor))
        XCTAssertEqual(classic.chain.growthLinear, Double(GameConfig.ringGrowthLinear))
        XCTAssertEqual(classic.chain.shellThickness, Double(GameConfig.ringShellThickness))
        XCTAssertEqual(classic.chain.disarmFraction, Double(GameConfig.ringDisarmFraction))
        XCTAssertEqual(classic.chain.lifeDecay, Double(GameConfig.ringLifeDecay))
    }

    // MARK: - Value envelopes (docs/pop_standard.md)

    func testEveryPopStaysInsideTheStandardEnvelopes() {
        for def in PopCatalog.all {
            XCTAssertFalse(def.name.isEmpty)
            XCTAssertFalse(def.flavor.isEmpty, "\(def.name) needs a flavor line")

            XCTAssertTrue((1...5).contains(def.style.paints.count), def.name)
            XCTAssertTrue(def.style.particleSizeRange.lowerBound >= 0.5, def.name)
            XCTAssertTrue(def.style.particleSizeRange.upperBound <= 6, def.name)
            XCTAssertTrue((0.1...0.4).contains(def.style.haloOpacity), def.name)
            XCTAssertTrue((0.05...0.3).contains(def.style.highlightOpacity), def.name)
            for paint in def.style.paints {
                for channel in [paint.fill.r, paint.fill.g, paint.fill.b,
                                paint.glow.r, paint.glow.g, paint.glow.b] {
                    XCTAssertTrue((0...1).contains(channel), def.name)
                }
            }

            XCTAssertTrue((10...40).contains(def.behavior.particleCountBase), def.name)
            XCTAssertTrue(def.behavior.particleSpeedRange.lowerBound > 0, def.name)
            XCTAssertTrue(def.behavior.particleSpeedRange.upperBound <= 12, def.name)
            XCTAssertTrue((0.0...0.15).contains(def.behavior.particleGravity), def.name)

            let s = def.behavior.sound
            XCTAssertTrue((200...800).contains(s.startFreq), def.name)
            XCTAssertTrue((100...600).contains(s.freqSpread), def.name)
            XCTAssertTrue((0.3...0.8).contains(s.sweep), def.name)
            XCTAssertTrue((0.05...0.5).contains(s.duration), def.name)
            XCTAssertTrue((2...12).contains(s.decay), def.name)
            XCTAssertTrue((0...0.5).contains(s.brightness), def.name)

            XCTAssertTrue((1...3).contains(def.chain.ringCount), def.name)
            XCTAssertTrue((80...150).contains(def.chain.maxRadiusBase), def.name)
            XCTAssertTrue((2.0...3.5).contains(def.chain.maxRadiusPerOrbRadius), def.name)
            XCTAssertTrue((15...35).contains(def.chain.shellThickness), def.name)
            XCTAssertTrue((0.3...0.7).contains(def.chain.disarmFraction), def.name)

            if case .points(let n) = def.unlock {
                XCTAssertTrue(n > 0 && n <= 120_000, "\(def.name): threshold \(n)")
            }
        }
    }

    // MARK: - Progression

    func testFreshJourneyStartsWithOnlyTheClassicPop() {
        let store = freshStore()
        XCTAssertEqual(store.unlockedNumbers(), [1])
        XCTAssertEqual(store.fieldPops(), [1])
    }

    func testPointsUnlockPopsAndRecordsAccumulate() {
        let store = freshStore()
        store.recordPop(popNumber: 1, points: 60, chainLength: 3)
        store.recordPop(popNumber: 1, points: 45, chainLength: 1)
        XCTAssertEqual(store.popPoints, 105)
        XCTAssertEqual(store.lifetimePops, 2)
        XCTAssertEqual(store.bestChain, 3)
        XCTAssertEqual(store.popCounts[1], 2)
        // pop #2 "Gloaming" unlocks at 100 points
        XCTAssertTrue(store.unlockedNumbers().contains(2))
        XCTAssertFalse(store.unlockedNumbers().contains(3))
    }

    func testEveryUnlockRuleIsSatisfiableByPlay() {
        // static reachability: every threshold sits inside what ordinary play
        // can actually produce (see docs/pop_progression.md)
        for def in PopCatalog.all {
            switch def.unlock {
            case .start: break
            case .points(let n): XCTAssertLessThanOrEqual(n, 120_000, def.name)
            case .totalPops(let n): XCTAssertLessThanOrEqual(n, 60_000, def.name)
            case .fieldsCleared(let n): XCTAssertLessThanOrEqual(n, 110, def.name)
            case .fortunesFound(let n): XCTAssertLessThanOrEqual(n, 35, def.name)
            case .bestChain(let n): XCTAssertLessThanOrEqual(n, 10, def.name)
            }
        }

        // functional: a plausible early journey opens a real chunk of the book
        let store = freshStore()
        for _ in 0..<30 { store.recordClear(bonus: 100) }
        for _ in 0..<10 { store.recordFortune() }
        for i in 0..<400 { store.recordPop(popNumber: 1 + i % 10, points: 15, chainLength: 6) }
        let unlocked = store.unlockedNumbers()
        XCTAssertGreaterThanOrEqual(unlocked.count, 15,
                                    "a real journey should keep opening doors")
    }

    private func freshStore() -> ProgressionStore {
        let suite = "vesper.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ProgressionStore(defaults: defaults)
    }
}
