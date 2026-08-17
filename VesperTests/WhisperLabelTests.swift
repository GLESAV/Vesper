import XCTest
import CoreGraphics
import SwiftUI
@testable import Vesper

// Proof for the wayfinding whispers (DELIVERY_ROADMAP W06). The view itself
// needs a host app to say anything about, so what is pinned here is the part a
// review will actually ask us to defend: the opacity floor, the
// assistive-technology override, and the touch target. `WhisperPresentation`
// exists precisely so those three can be tested without a simulator window.
//
//   "whispers dim to a committed floor of ~40% of idle opacity — never zero"
//       → testWhisperNeverReachesZero, testPlayDimsToTheCommittedFloor
//   "with VoiceOver or any assistive technology active, they do not fade"
//       → testAssistiveTechNeverFades*, testAssistiveTechOverridesEverything
//   "nothing blinks; light breathes (≥ 2 s cycles)"
//       → testBreathIsSlowerThanTheBlinkFloor, testBreathBandMatchesIdleTokens
//   "hit regions ≥ 44 pt"
//       → testHitTargetMeetsTheTouchStandard
//
// No timing, no rendering: every case is a pure function of three booleans.
final class WhisperLabelTests: XCTestCase {

    /// Every reachable state, so the invariants below can be asserted
    /// exhaustively rather than on the cases we happened to think of.
    private var allStates: [WhisperPresentation] {
        var states: [WhisperPresentation] = []
        for playing in [false, true] {
            for assistive in [false, true] {
                for reduceMotion in [false, true] {
                    states.append(WhisperPresentation(isPlaying: playing,
                                                      assistiveTechRunning: assistive,
                                                      reduceMotion: reduceMotion))
                }
            }
        }
        return states
    }

    // MARK: - The floor

    func testWhisperNeverReachesZero() {
        // The whole point of the finding: an invisible exit is an exit she
        // cannot find in the dark.
        for state in allStates {
            for atPeak in [false, true] {
                XCTAssertGreaterThanOrEqual(
                    state.opacity(atBreathPeak: atPeak),
                    WhisperPresentation.playFloor,
                    "\(state) fell below the committed floor"
                )
            }
        }
    }

    func testPlayDimsToTheCommittedFloor() {
        let state = WhisperPresentation(isPlaying: true,
                                        assistiveTechRunning: false,
                                        reduceMotion: false)
        XCTAssertEqual(state.restingOpacity, WhisperPresentation.playFloor, accuracy: 0.0001)
        XCTAssertEqual(state.litOpacity, WhisperPresentation.playFloor, accuracy: 0.0001)
        XCTAssertFalse(state.breathes, "a dimmed whisper holds still; it does not pulse at the floor")
    }

    func testTheCommittedFloorClearsTheContrastBarAndStillRecedes() {
        // Pinned as a value, not just as a relation: if someone tunes this
        // down, the failure should name the doc.
        //
        // R-A11Y C1 moved it from 0.40 to 0.74. The old value was chosen as
        // "the reading that still clears APCA Lc >= 60" and measurement
        // disagreed: composited over this world's ground it reaches Lc 22-25,
        // about 3.4:1, under the 4.5:1 bar for 13 pt text — and it failed
        // there while the field is IN PLAY, on the primary way through the
        // world. The constant's own doc comment said it moves up, never down,
        // if measurement disagreed. It disagreed.
        XCTAssertEqual(WhisperPresentation.playFloor, 0.62, accuracy: 0.0001)

        // THE BAND'S ORDERING IS THE INVARIANT, and it is what caught the
        // reviewer's own figure. Imani's 0.74 came from the contrast target
        // alone and sits ABOVE `idleLow` (0.70 then, 0.72 now), which would
        // make the whisper
        // brighter during play than at the bottom of its idle breath —
        // inverting the one behaviour this constant exists to produce.
        // Pinning the number without pinning the ordering is how that ships.
        XCTAssertLessThan(WhisperPresentation.playFloor, WhisperPresentation.idleLow,
                          "the play floor must stay below the idle breath, or it does not recede")
        XCTAssertLessThan(WhisperPresentation.idleLow, WhisperPresentation.idleHigh,
                          "the breath must have somewhere to breathe")
        XCTAssertGreaterThan(WhisperPresentation.playFloor, 0,
                             "never zero — the signage does not leave")

        // And the direction of the C1 fix, so a later tune cannot quietly
        // undo it: whatever this becomes, it is not the 0.40 that measured
        // Lc 22 on the primary way through the world.
        XCTAssertGreaterThan(WhisperPresentation.playFloor, 0.40,
                             "R-A11Y C1: the floor moves up, never back down")
    }

    func testIdleWhisperIsNeverFullyOpaque() {
        // 05 §5: type is lit, not printed — whispers idle at 70–85%, never 100%.
        for state in allStates {
            for atPeak in [false, true] {
                XCTAssertLessThanOrEqual(state.opacity(atBreathPeak: atPeak),
                                         WhisperPresentation.idleHigh)
            }
        }
    }

    // MARK: - The assistive-technology override

    func testAssistiveTechPredicateTruthTable() {
        XCTAssertFalse(WhisperPresentation.assistiveTechIsRunning(voiceOver: false, switchControl: false))
        XCTAssertTrue(WhisperPresentation.assistiveTechIsRunning(voiceOver: true, switchControl: false))
        XCTAssertTrue(WhisperPresentation.assistiveTechIsRunning(voiceOver: false, switchControl: true))
        XCTAssertTrue(WhisperPresentation.assistiveTechIsRunning(voiceOver: true, switchControl: true))
    }

    func testAssistiveTechNeverFadesEvenDuringPlay() {
        for playing in [false, true] {
            for reduceMotion in [false, true] {
                let state = WhisperPresentation(isPlaying: playing,
                                                assistiveTechRunning: true,
                                                reduceMotion: reduceMotion)
                XCTAssertEqual(state.restingOpacity, WhisperPresentation.idleHigh, accuracy: 0.0001)
                XCTAssertEqual(state.litOpacity, WhisperPresentation.idleHigh, accuracy: 0.0001)
            }
        }
    }

    func testAssistiveTechNeverBreathes() {
        // "Do not fade at all" includes the breath — a fade cycle is still a fade.
        for playing in [false, true] {
            for reduceMotion in [false, true] {
                let state = WhisperPresentation(isPlaying: playing,
                                                assistiveTechRunning: true,
                                                reduceMotion: reduceMotion)
                XCTAssertFalse(state.breathes)
                XCTAssertEqual(state.opacity(atBreathPeak: false),
                               state.opacity(atBreathPeak: true),
                               accuracy: 0.0001,
                               "an assistive-technology whisper must be one steady value")
            }
        }
    }

    func testAssistiveTechOverridesEverything() {
        // The override outranks the play dim, which is the case the finding was
        // actually about: she is popping orbs *and* using VoiceOver.
        let playing = WhisperPresentation(isPlaying: true,
                                          assistiveTechRunning: true,
                                          reduceMotion: false)
        let idle = WhisperPresentation(isPlaying: false,
                                       assistiveTechRunning: true,
                                       reduceMotion: false)
        XCTAssertEqual(playing.restingOpacity, idle.restingOpacity, accuracy: 0.0001)
    }

    // MARK: - Reduce Motion

    func testReduceMotionIsStaticButStillDims() {
        // 05 §7.3: held steady, not held bright — the dim is a state, not a
        // motion, so Reduce Motion removes the breath and keeps the floor.
        let idle = WhisperPresentation(isPlaying: false,
                                       assistiveTechRunning: false,
                                       reduceMotion: true)
        XCTAssertFalse(idle.breathes)
        XCTAssertEqual(idle.restingOpacity, WhisperPresentation.idleHigh, accuracy: 0.0001)
        XCTAssertEqual(idle.opacity(atBreathPeak: false), idle.opacity(atBreathPeak: true), accuracy: 0.0001)

        let playing = WhisperPresentation(isPlaying: true,
                                          assistiveTechRunning: false,
                                          reduceMotion: true)
        XCTAssertFalse(playing.breathes)
        XCTAssertEqual(playing.restingOpacity, WhisperPresentation.playFloor, accuracy: 0.0001)
        XCTAssertEqual(playing.opacity(atBreathPeak: false), playing.opacity(atBreathPeak: true), accuracy: 0.0001)
    }

    func testEveryStaticStateHasOneValue() {
        // The general form of the two tests above: if it does not breathe, the
        // two ends of the breath are the same number. This is what makes
        // "static" impossible to get wrong at the call site.
        for state in allStates where !state.breathes {
            XCTAssertEqual(state.opacity(atBreathPeak: false),
                           state.opacity(atBreathPeak: true),
                           accuracy: 0.0001,
                           "\(state) claims to be static but has two values")
        }
    }

    // MARK: - The breath

    func testOnlyTheIdleUnassistedFullMotionWhisperBreathes() {
        for state in allStates {
            let expected = !state.isPlaying && !state.assistiveTechRunning && !state.reduceMotion
            XCTAssertEqual(state.breathes, expected, "\(state)")
        }
    }

    func testBreathBandMatchesIdleTokens() {
        let state = WhisperPresentation(isPlaying: false,
                                        assistiveTechRunning: false,
                                        reduceMotion: false)
        XCTAssertTrue(state.breathes)
        XCTAssertEqual(state.opacity(atBreathPeak: false), WhisperPresentation.idleLow, accuracy: 0.0001)
        XCTAssertEqual(state.opacity(atBreathPeak: true), WhisperPresentation.idleHigh, accuracy: 0.0001)
        // 05 §2.1: `text.whisper` idles at 70–85%. The band is pinned as a
        // RANGE rather than as two exact numbers, because that is what the
        // token says and because the R-A11Y C1 residual was closed by moving
        // inside it: `idleLow` went 0.70 → 0.72 (~Lc 58.9 → ~61) so the whole
        // idle breath clears the Lc 60 body-text bar without leaving the
        // documented band. Pinning 0.70 exactly would have made honouring one
        // committed spec fail the test for the other.
        XCTAssertGreaterThanOrEqual(WhisperPresentation.idleLow, 0.70)
        XCTAssertEqual(WhisperPresentation.idleHigh, 0.85, accuracy: 0.0001)
        XCTAssertLessThan(WhisperPresentation.idleLow, WhisperPresentation.idleHigh)

        // The idle band is the READING state and owes the Lc 60 bar, which is
        // why its floor may not slip back below the measured 0.72.
        XCTAssertGreaterThanOrEqual(WhisperPresentation.idleLow, 0.72)
    }

    func testBreathIsSlowerThanTheBlinkFloor() {
        // 05 §3: "Nothing blinks. Light breathes (≥ 2 s cycles)."
        XCTAssertGreaterThanOrEqual(WhisperPresentation.breathPeriod, 2.0)
    }

    func testBreathIsGentleEnoughToReadThrough() {
        // A breath that swings too far reads as a pulse and pulls the eye off
        // the field. The idle band is the whole permitted excursion.
        let depth = WhisperPresentation.idleHigh - WhisperPresentation.idleLow
        XCTAssertGreaterThan(depth, 0, "a breath with no depth is not a breath")
        XCTAssertLessThanOrEqual(depth, 0.20)
    }

    // MARK: - The touch target

    func testHitTargetMeetsTheTouchStandard() {
        // 04 §9 / 05 §6, and the reason the bottom whisper can be the primary
        // route to quiet at all.
        XCTAssertGreaterThanOrEqual(WhisperPresentation.minimumHitEdge, 44)
    }

    func testSettleIsShortEnoughToFeelLikeFeedback() {
        XCTAssertGreaterThan(WhisperPresentation.settleDuration, 0)
        XCTAssertLessThanOrEqual(WhisperPresentation.settleDuration, 0.65)
    }

    // MARK: - Constructibility

    // The whisper's private state once made its synthesized memberwise
    // initializer private, so no other file could build one and the world
    // shipped with no tappable wayfinding at all. `@testable` raises internal
    // to public but leaves private private, so these cases fail to COMPILE if
    // that regresses — which is the only way to catch it without a device.

    func testAWhisperCanBeBuiltFromAnotherFile() {
        var tapped = 0
        let whisper = WhisperLabel(text: Strings.journalWhisper,
                                   accessibilityLabel: Strings.journalA11y,
                                   hint: "hint",
                                   isPlaying: true,
                                   onTap: { tapped += 1 })
        XCTAssertEqual(whisper.text, Strings.journalWhisper)
        XCTAssertEqual(whisper.accessibilityLabel, Strings.journalA11y)
        XCTAssertEqual(whisper.hint, "hint")
        XCTAssertTrue(whisper.isPlaying)
        whisper.onTap()
        XCTAssertEqual(tapped, 1, "the tap must reach the call site's closure")
    }

    func testIsPlayingDefaultsToIdle() {
        let whisper = WhisperLabel(text: Strings.skyWhisper,
                                   accessibilityLabel: Strings.skyA11y,
                                   hint: "hint",
                                   onTap: {})
        XCTAssertFalse(whisper.isPlaying)
    }

    func testTheTwoDestinationsCarryTheCatalogStrings() {
        let sky = WhisperLabel.sky(hint: "hint", onTap: {})
        XCTAssertEqual(sky.text, Strings.skyWhisper)
        XCTAssertEqual(sky.accessibilityLabel, Strings.skyA11y)
        XCTAssertFalse(sky.isPlaying)

        let journal = WhisperLabel.journal(hint: "hint", isPlaying: true, onTap: {})
        XCTAssertEqual(journal.text, Strings.journalWhisper)
        XCTAssertEqual(journal.accessibilityLabel, Strings.journalA11y)
        XCTAssertTrue(journal.isPlaying)
    }
}
