import XCTest
@testable import Vesper

// The contract that stopped the signage and the counter crashing into each
// other, and stopped orbs from drifting under a whisper and having their taps
// taken by it.
//
// Every case runs across a spread of real screens AND a spread of safe-area
// insets, because the bug shipped on exactly the combination nobody checked:
// a Dynamic Island phone, where the counter measured 10 pt from an edge the
// island already owned.
final class FieldLayoutTests: XCTestCase {

    /// Width × height for iPhone SE, 13 mini, 16, 16 Pro Max, and a narrow
    /// iPad Split View column.
    private let screens: [CGSize] = [
        CGSize(width: 375, height: 667),
        CGSize(width: 375, height: 812),
        CGSize(width: 393, height: 852),
        CGSize(width: 440, height: 956),
        CGSize(width: 320, height: 1024),
    ]

    /// No inset, notch, Dynamic Island.
    private let safeTops: [CGFloat] = [20, 47, 59]
    private let safeBottoms: [CGFloat] = [0, 34]

    /// 44 pt at standard text, and what the whisper's target grows to at the
    /// largest accessibility sizes.
    private let bands: [CGFloat] = [44, 58, 72]

    private func everyLayout(_ body: (FieldLayout) -> Void) {
        for size in screens {
            for top in safeTops {
                for bottom in safeBottoms {
                    for band in bands {
                        body(FieldLayout(size: size, safeTop: top,
                                         safeBottom: bottom, whisperBand: band))
                    }
                }
            }
        }
    }

    // MARK: - The bug the owner found

    func testTheCounterNeverTouchesTheSkyWhisper() {
        everyLayout { l in
            XCTAssertGreaterThanOrEqual(
                l.hudTop, l.headWhisperBottom,
                "counter starts at \(l.hudTop), sky whisper ends at \(l.headWhisperBottom) "
                + "— safeTop \(l.safeTop), band \(l.whisperBand)")
        }
    }

    func testNothingIsDrawnUnderTheStatusBarOrTheDynamicIsland() {
        everyLayout { l in
            XCTAssertGreaterThanOrEqual(l.headWhisperTop, l.safeTop,
                                        "signage climbed into the safe area")
            XCTAssertGreaterThanOrEqual(l.hudTop, l.safeTop,
                                        "the counter climbed into the safe area")
        }
    }

    // MARK: - The collision that steals taps

    // The whispers are Buttons in a layer ABOVE the input layer, so an orb
    // under one does not merely look wrong — the whisper takes the touch and
    // the world travels when she meant to pop.
    func testNoOrbCanEverReachEitherWhispersTapTarget() {
        everyLayout { l in
            XCTAssertGreaterThanOrEqual(l.orbCeiling, l.headWhisperBottom,
                                        "an orb can reach the sky whisper's target")
            XCTAssertLessThanOrEqual(l.orbFloor, l.footWhisperTop,
                                     "an orb can reach the journal whisper's target")
        }
    }

    // DELIBERATELY REVERSED. Orbs used to be excluded from the counter's band
    // as well, which cost about 70 pt at the top of every screen — a quarter
    // of the glass on a Dynamic Island phone, before a single orb could
    // exist. The counter is not interactive, so an orb behind it costs a
    // moment's overlap on one number; the whisper's target is a Button and an
    // orb under THAT loses her the pop. Only the second is a collision.
    func testTheHeaderCostsTheFieldOnlyWhatTheSignageNeeds() {
        everyLayout { l in
            XCTAssertGreaterThanOrEqual(l.orbCeiling, l.headWhisperBottom,
                                        "an orb can reach the sky whisper's target")
            let headerCost = l.orbCeiling - l.safeTop
            XCTAssertLessThan(headerCost, 90,
                              "the header is eating \(headerCost) pt of field")
        }
    }

    func testTheFirstRunHintSitsAboveTheJournalWhisper() {
        everyLayout { l in
            let hintBottomEdge = l.size.height - l.hintBottomInset
            XCTAssertLessThanOrEqual(hintBottomEdge, l.footWhisperTop,
                                     "the only instruction in the game is under a button")
        }
    }

    // MARK: - The bands are ordered, always

    func testTheBandsNeverInvertOnAnyScreen() {
        everyLayout { l in
            XCTAssertLessThan(l.headWhisperTop, l.headWhisperBottom)
            XCTAssertLessThan(l.headWhisperBottom, l.hudTop)
            XCTAssertLessThan(l.hudTop, l.hudBottom)
            XCTAssertLessThan(l.hudBottom, l.orbCeiling)
            XCTAssertLessThan(l.footWhisperTop, l.footWhisperBottom)
            XCTAssertLessThanOrEqual(l.footWhisperBottom, l.size.height)
        }
    }

    func testEveryPhoneStillHasAFieldToPlayIn() {
        for size in screens where size.height >= 667 {
            let l = FieldLayout(size: size, safeTop: 59, safeBottom: 34, whisperBand: 44)
            XCTAssertTrue(l.isPlayable,
                          "\(size) left only \(l.playHeight) pt of field")
            XCTAssertGreaterThan(l.playHeight, 300,
                                 "\(size) is technically playable but cramped")
        }
    }

    // Accessibility text must not be able to squeeze the field out of
    // existence — it may shrink it, and the layout must still report honestly.
    func testTheLayoutStaysCoherentAtTheLargestTextSizes() {
        let l = FieldLayout(size: CGSize(width: 375, height: 667),
                            safeTop: 59, safeBottom: 34, whisperBand: 72)
        XCTAssertGreaterThanOrEqual(l.orbCeiling, l.hudBottom)
        XCTAssertGreaterThanOrEqual(l.playHeight, 0, "play height must never go negative")
    }

    // MARK: - What the simulation is handed

    func testTheSimulationsInsetsMatchTheBandsExactly() {
        everyLayout { l in
            XCTAssertEqual(l.simTopInset, l.orbCeiling)
            XCTAssertEqual(l.simBottomInset, l.size.height - l.orbFloor, accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(l.simBottomInset, 0)
        }
    }

    func testAnOrbHeldByTheSimulationsInsetsCannotReachAWhisper() {
        // The sim keeps an orb's CENTRE at least `r + topInset` from the top,
        // so its top edge sits at `topInset`. Check the whole band contract
        // end to end with a real simulation rather than by arithmetic.
        let l = FieldLayout(size: CGSize(width: 393, height: 852),
                            safeTop: 59, safeBottom: 34, whisperBand: 44)
        let sim = GameSimulation(seed: 7)
        sim.layout(size: l.size)
        sim.topInset = l.simTopInset
        sim.bottomInset = l.simBottomInset
        sim.stage = FieldPlan.finalStage
        sim.seedField()

        for _ in 0..<3_000 { _ = sim.step(dt: 1.0 / 60) }

        for orb in sim.orbs where orb.alive {
            XCTAssertGreaterThanOrEqual(orb.pos.y - orb.r, l.headWhisperBottom - 0.5,
                                        "an orb reached the sky whisper's target")
            XCTAssertLessThanOrEqual(orb.pos.y + orb.r, l.footWhisperTop + 0.5,
                                     "an orb reached the journal whisper's target")
        }
    }

    func testSplitChildrenAndGeneratedOrbsRespectTheBandsToo() {
        // The two places orbs are created outside seeding — a corner splitter
        // and a generator jammed against the ceiling.
        let l = FieldLayout(size: CGSize(width: 393, height: 852),
                            safeTop: 59, safeBottom: 34, whisperBand: 44)
        let sim = GameSimulation(seed: 11)
        sim.layout(size: l.size)
        sim.topInset = l.simTopInset
        sim.bottomInset = l.simBottomInset

        var splitter = Orb(pos: CGPoint(x: 8, y: 4), vel: .zero, r: 30, baseR: 30,
                           popNumber: PopCatalog.classic.number, variantIndex: 0, phase: 0)
        splitter.spawn = 1
        splitter.kind = .splitter(remaining: 2)
        var gen = Orb(pos: CGPoint(x: 380, y: 848), vel: .zero, r: 30, baseR: 30,
                      popNumber: PopCatalog.classic.number, variantIndex: 0, phase: 0)
        gen.spawn = 1
        gen.kind = .generator(Generator(closing: .quota(remaining: 4), interval: 20))
        sim.replaceOrbs([splitter, gen])

        sim.tap(at: splitter.pos)
        for _ in 0..<400 { _ = sim.step(dt: 1.0 / 60) }

        for orb in sim.orbs where orb.alive {
            XCTAssertGreaterThanOrEqual(orb.pos.y, l.simTopInset - 0.5,
                                        "an orb was born above the ceiling")
            XCTAssertLessThanOrEqual(orb.pos.y, l.size.height - l.simBottomInset + 0.5,
                                     "an orb was born below the floor")
        }
    }
}
