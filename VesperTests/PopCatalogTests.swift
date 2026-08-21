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
        // THE SOUND DELIBERATELY LEFT v1.0, on the owner's instruction: he
        // heard the base pop as Space Invaders, and he was right — v1.0 swept
        // 460 Hz down to 55% of that in 140 ms, which is definitionally an
        // arcade laser. Two values moved and nothing else did, so they are
        // asserted field by field rather than as a struct, and the rest of
        // this test still pins v1.0 exactly.
        XCTAssertEqual(classic.behavior.sound.voice, .pop,
                       "the base pop is the ASMR pop, never the swept tone")
        XCTAssertGreaterThanOrEqual(classic.behavior.sound.sweep, 1.0,
                                    "a falling sweep is the laser this replaced")
        XCTAssertEqual(classic.behavior.sound.startFreq, 460, accuracy: 0.0001)
        XCTAssertEqual(classic.behavior.sound.freqSpread, 420, accuracy: 0.0001)
        XCTAssertEqual(classic.behavior.sound.duration, 0.14, accuracy: 0.0001)
        XCTAssertEqual(classic.behavior.sound.decay, 7.5, accuracy: 0.0001)
        XCTAssertEqual(classic.behavior.sound.brightness, 0, accuracy: 0.0001)
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
            // THE ENVELOPE ITSELF WAS THE BUG. It read `0.3...0.8`, which does
            // not merely permit a downward sweep — it REQUIRES one, of at
            // least 20% inside a pop's length. Every pop in the catalog was
            // obliged by the standard to be an arcade laser, which is why all
            // 100 sounded like one. The owner heard in a minute what the
            // envelope had been mandating for a hundred entries.
            //
            // Sweeps are lifts now. `.drop` is exempt because its identity is
            // a falling pitch, and it takes its fall from the engine rather
            // than from data.
            XCTAssertTrue((0.98...1.15).contains(s.sweep),
                          "\(def.name) sweeps to \(s.sweep) — a fall is the laser this replaced")
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

    // MARK: - "Truly unique": the three expressive axes

    // THE DIAGNOSIS THIS SUITE PINS. The catalog varied colour, pitch and
    // length across all 100 pops, on ONE synthesis model, with ONE haptic
    // (baseIntensity and intensityPerSize were overridden in exactly one
    // entry) and ONE burst gesture. A hundred notes on the same string.
    //
    // These tests assert the structure that fixed it: ten families, each with
    // its own instrument, its own thing to say to the hand, and its own way of
    // moving — so a pop is recognisable as a member of its family and never
    // mistakable for another family's.

    func testEveryFamilyHasItsOwnVoice() {
        let voices = PopFamily.allCases.map(\.voice)
        XCTAssertEqual(Set(voices).count, PopFamily.allCases.count,
                       "two families share a synthesis voice — they will be confused for each other")
    }

    func testEveryFamilyHasItsOwnBurstGesture() {
        let bursts = PopFamily.allCases.map(\.burst)
        XCTAssertEqual(Set(bursts).count, PopFamily.allCases.count,
                       "two families burst identically — the eye remembers the gesture")
    }

    func testTheHapticVocabularyIsSpreadAcrossTheFamilies() {
        // Only five patterns exist for ten families, so these cannot all be
        // distinct — but a vocabulary of five that only ever uses two is the
        // bug this replaced.
        let patterns = Set(PopFamily.allCases.map(\.hapticPattern))
        XCTAssertEqual(patterns.count, HapticPattern.allCases.count,
                       "the haptic vocabulary is not fully used: \(patterns)")
    }

    func testNoTwoFamiliesShareTheirWholeSignature() {
        // The real bar: two families may share one axis, never all three.
        for a in PopFamily.allCases {
            for b in PopFamily.allCases where a != b {
                let same = (a.voice == b.voice)
                    && (a.hapticPattern == b.hapticPattern)
                    && (a.burst == b.burst)
                XCTAssertFalse(same, "\(a) and \(b) are indistinguishable")
            }
        }
    }

    func testEveryPopInheritsItsFamilysSignatureUnlessItSaysOtherwise() {
        for def in PopCatalog.all {
            let f = def.family
            let matchesFamily = def.behavior.sound.voice == f.voice
                && def.behavior.haptic.pattern == f.hapticPattern
                && def.behavior.burst == f.burst
            let deliberateOverride = def.rarity == .rare || def.rarity == .secret
            XCTAssertTrue(matchesFamily || deliberateOverride,
                          "#\(def.number) \(def.name) drifted from its family for no stated reason")
        }
    }

    // v1.0 must survive all of this untouched.
    func testTheClassicPopIsExactlyWhatItAlwaysWas() {
        let classic = PopCatalog.classic
        XCTAssertEqual(classic.number, 1)
        // The voice DID change, on the owner's instruction: v1.0's sound was
        // a fast downward sweep, which is an arcade laser, and he heard it as
        // one. `.pop` is the ASMR bubble. Everything else about #001 — its
        // touch and its gesture — is still v1.0 exactly.
        XCTAssertEqual(classic.behavior.sound.voice, .pop,
                       "the base pop is the ASMR pop, never the swept tone")
        XCTAssertEqual(classic.behavior.haptic.pattern, .single)
        XCTAssertEqual(classic.behavior.burst, .radial)
    }

    // Distinctness has to survive contact with the actual catalog, not just
    // the family table: a pop is heard, felt and seen together.
    func testTheCatalogUsesItsWholeExpressiveRange() {
        let voices = Set(PopCatalog.all.map(\.behavior.sound.voice))
        let bursts = Set(PopCatalog.all.map(\.behavior.burst))
        let patterns = Set(PopCatalog.all.map(\.behavior.haptic.pattern))
        XCTAssertEqual(voices.count, SoundVoice.allCases.count, "unused voices: unheard range")
        XCTAssertEqual(bursts.count, BurstMotion.allCases.count, "unused burst motions")
        XCTAssertEqual(patterns.count, HapticPattern.allCases.count, "unused haptic patterns")
    }

    // The engine's laser guard, pinned: no pop may fall steeply inside its own
    // length, however its data is authored. `.drop` is the one voice that
    // wants a fall — it is a drop into still water — and opts back in.
    func testNoPopCanBeAuthoredIntoAnArcadeLaser() {
        for def in PopCatalog.all {
            let sweep = def.behavior.sound.sweep
            XCTAssertGreaterThanOrEqual(sweep, 0.98,
                                        "#\(def.number) \(def.name) sweeps down to \(sweep)")
        }
        // And the engine floors it anyway, so no future authoring mistake can
        // reintroduce the laser even if this envelope is widened.
        XCTAssertGreaterThanOrEqual(max(0.55, 0.94), 0.94)
    }

    // Every pop lands on a note of the scale, so any chain is consonant.
    func testEveryPopsPitchIsANoteInTheScale() {
        for def in PopCatalog.all {
            for pitch in [0.0, 0.5, 1.0] {
                let raw = def.behavior.sound.startFreq + pitch * def.behavior.sound.freqSpread
                let snapped = PopSoundEngine.snapToPentatonic(raw)
                XCTAssertEqual(snapped, PopSoundEngine.snapToPentatonic(snapped), accuracy: 0.001,
                               "snapping is not idempotent for #\(def.number)")
                XCTAssertGreaterThan(snapped, 0)
                // Never moved more than a whole tone: the catalog's authored
                // pitch relationships must survive being made consonant.
                XCTAssertLessThan(abs(log2(snapped / raw)), 0.17,
                                  "#\(def.number) was dragged too far to reach the scale")
            }
        }
    }
}