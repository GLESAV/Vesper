import XCTest
import Foundation
@testable import Vesper

// POP SOUND ENGINE — what is actually reachable, and what is honestly true.
//
// THE BOUNDARY FIRST, because it decides the whole shape of this file.
// `PopSoundEngine` is a singleton around `AVAudioEngine`, and almost all of
// it is `private`: `makePopBuffer`, `makeChimeBuffer`, `makeWhirrBuffer`,
// `makeThoomfBuffer`, `makeFuseTickBuffer`, `play`, `ensureRunning`,
// `buildEngine`, `configureSession`, `observeInterruptions`, `engine`,
// `format`, `sampleRate`, `bank`, `bankOrder`, `bankLimit`, `pitchBuckets`,
// `variantsPerBucket`, `players`, `nextPlayerIndex`, `whirrBank`, `fuseBank`,
// `thoomfBuffer`, `chimeBuffer`, and the `scale` the snapper reads.
// `@testable import` exposes `internal`, not `private`, so NONE of the
// synthesis output can be inspected from here.
//
// Reachable (re-derived from the source rather than taken on trust):
// `shared`, `warmUp()`, `prepare(_:)`, `playPop(profile:pitch:)`,
// `playWhirr(startFreq:)`, `playThoomf()`, `playFuseTick(startFreq:)`,
// `playCompletionChime()`, `setActive(_:)`, and the one static:
// `snapToPentatonic(_:)`. That is the whole surface.
//
// That means the properties one would most like to pin about a synthesizer —
// the buffer never clips, is never silent, opens with a soft attack rather
// than a click — CANNOT be asserted against this type. They ARE asserted, on
// the extracted engine that documents itself as the lesson learned here, in
// AnimaTests (`testNoVoiceCanClip` and its neighbours). The recommendation in
// the report is to give `makePopBuffer` (or a small `static` renderer beside
// it) `internal` visibility so the same assertions can cover the sound the
// game actually ships. No production change is made here.
//
// What IS reachable and worth pinning:
//
//   1. `snapToPentatonic` — `internal static`, pure, total. The one piece of
//      real logic in the file that can be examined, and the piece that makes
//      a five-orb chain consonant instead of a clatter. Most of this file is
//      about it. (PopCatalogTests already checks it against the catalog's
//      own frequencies; the tests here are about the function itself:
//      totality, monotonicity, range, and the shape of the scale — including
//      recovering the private `scale` array through the only door there is.)
//
//   2. Robustness. The file's own stated philosophy is that "every failure
//      path degrades to silence, never to a crash" — sound is a nice-to-have
//      and a crash in it costs the whole evening. Under that philosophy,
//      "calling the public API with sound off, with absurd pitches, and in
//      long bursts does not crash" is a LOAD-BEARING invariant rather than a
//      vacuous one, and it is stated as such at each test below. These tests
//      also drive `prepare` over every voice and over the whole catalog,
//      which is the only way any of the ~200-line synthesis routine gets
//      exercised at all.
//
// WHAT THIS FILE DELIBERATELY DOES NOT TOUCH. Every frequency handed to
// `playWhirr` and `playFuseTick` below is positive, finite and small. That is
// not fastidiousness, it is the difference between a failing assertion and a
// dead test run: those two paths convert a Double to an Int to key their
// caches, and `Int(_: Double)` traps on NaN and on either infinity while
// `UInt64(_: Int)` traps again on anything negative. A trap is not a test
// failure — it takes the whole process down and every other suite with it.
// The bug is named in the report; the tests refuse to be the thing that
// detonates it. For the same reason nothing here reaches for any symbol that
// only exists in an in-flight fix: this file must compile and pass against
// the engine as it stands today.
//
// Nothing here requires the engine to be running or any audio to be produced:
// in the simulator `AVAudioEngine.start()` may fail, in which case every
// `play…` call returns at its own guard. Both outcomes must be safe, and both
// are exercised by the same call. Nothing sleeps, waits on wall clock, or
// waits on an expectation — every call below is synchronous and bounded.
final class PopSoundEngineTests: XCTestCase {

    private var soundWasEnabled = true
    private var hapticsWereEnabled = true

    override func setUp() {
        super.setUp()
        // Other test classes mutate SettingsStore.shared. Remember whatever it
        // holds now and put it back in tearDown; never assert an absolute
        // value that this test did not itself set. Both flags are saved even
        // though only `soundEnabled` is written here — the store is one shared
        // object and restoring the pair costs nothing.
        soundWasEnabled = SettingsStore.shared.soundEnabled
        hapticsWereEnabled = SettingsStore.shared.hapticsEnabled
    }

    override func tearDown() {
        SettingsStore.shared.soundEnabled = soundWasEnabled
        SettingsStore.shared.hapticsEnabled = hapticsWereEnabled
        // Leave the engine the way the app leaves it when it is foregrounded,
        // so no later test inherits a paused engine from this file.
        PopSoundEngine.shared.setActive(true)
        super.tearDown()
    }

    // MARK: - The scale

    /// The scale, rebuilt independently of the engine: C D E G A over seven
    /// octaves from a 65.41 Hz root. Written out here on purpose — a test that
    /// asked the engine for its own scale could not notice the scale changing.
    private static let expectedScale: [Double] = {
        let steps: [Double] = [1, 9.0 / 8, 5.0 / 4, 3.0 / 2, 5.0 / 3]
        var notes: [Double] = []
        for octave in 0..<7 {
            let root = 65.41 * pow(2, Double(octave))
            for step in steps { notes.append(root * step) }
        }
        return notes.sorted()
    }()

    private func distanceToNearestNote(_ freq: Double) -> Double {
        var best = Double.infinity
        for note in Self.expectedScale { best = min(best, abs(note - freq)) }
        return best
    }

    /// The scale as the ENGINE actually holds it, recovered from outside the
    /// type. `scale` is `private`, but the set of distinct answers the snapper
    /// gives over a fine sweep of the audible range IS that array — nearest
    /// neighbour is onto, so every note owns a band of inputs. The step ratio
    /// is far finer than the narrowest band (the smallest interval in the
    /// scale is 10/9, about 182 cents), so no note can be missed.
    private func probeTheEnginesScale() -> [Double] {
        var seen: [Double] = []
        var freq = 30.0
        while freq < 12_000 {
            let snapped = PopSoundEngine.snapToPentatonic(freq)
            if !seen.contains(snapped) { seen.append(snapped) }
            freq *= 1.008
        }
        return seen.sorted()
    }

    // EVERY pop's pitch has to land on the scale, or the pentatonic guarantee
    // (no pair of notes clashes, so any chain in any order is consonant) is
    // not a guarantee at all. This pins both that the snapper answers with a
    // scale member and that the scale is still the one the game was tuned
    // around — a change to either is a change to how a cascade sounds.
    func testSnappingAlwaysAnswersWithANoteOfTheMajorPentatonic() {
        var freq = 30.0
        while freq < 12_000 {
            let snapped = PopSoundEngine.snapToPentatonic(freq)
            XCTAssertLessThan(distanceToNearestNote(snapped), 1e-6,
                              "\(freq) Hz snapped to \(snapped), which is not a note of the scale")
            freq *= 1.013
        }
    }

    // The private `scale`, read through the only door there is, and held to
    // two things at once.
    //
    // FIRST, that it is note-for-note the array rebuilt above: same root, same
    // five steps, same seven octaves. Membership alone (the test above) cannot
    // see a note going MISSING, and a scale of thirty-four notes still passes
    // every membership check while sounding different.
    //
    // SECOND, and this is the property the whole design rests on: no two
    // adjacent notes are closer than 150 cents. Pentatonic was chosen because
    // it has no semitone clashes at all — that is why pops arriving in any
    // order and any overlap still sound like music. Adding a fourth (4/3) to
    // the steps, the single most likely "improvement" someone will make here,
    // puts a 16/15 semitone next to the major third and quietly destroys the
    // guarantee while leaving every other test in this file green. The real
    // minimum is 10/9, about 182 cents, so the threshold has room in it.
    func testTheScaleTheEngineHoldsIsTheOneTheGameWasTunedAround() {
        let probed = probeTheEnginesScale()

        XCTAssertEqual(probed.count, Self.expectedScale.count,
                       "the engine answers with \(probed.count) distinct notes, not \(Self.expectedScale.count)")
        if probed.count == Self.expectedScale.count {
            for (index, note) in probed.enumerated() {
                XCTAssertEqual(note, Self.expectedScale[index], accuracy: 1e-9,
                               "note \(index) of the scale moved to \(note)")
            }
        }

        for index in probed.indices.dropFirst() {
            let cents = 1200 * log2(probed[index] / probed[index - 1])
            XCTAssertGreaterThan(cents, 150,
                                 "\(probed[index - 1]) Hz and \(probed[index]) Hz are \(cents) cents apart — close enough to clash")
        }
    }

    // Snapping is a quantizer, and a quantizer that is not monotonic reorders
    // pitches: two orbs authored a tone apart could come out with the higher
    // one sounding lower. Nearest-neighbour onto a sorted set is monotonic by
    // construction — this pins that it stays that way (a mis-sorted or
    // duplicated scale entry would break it). Idempotence is asserted in the
    // same sweep: a note of the scale must snap to itself, which is also what
    // makes the pitch a pop is rendered at stable from one launch to the next.
    func testSnappingIsMonotonicAndIdempotent() {
        var freq = 40.0
        var previous = -Double.infinity
        while freq < 9_000 {
            let snapped = PopSoundEngine.snapToPentatonic(freq)
            XCTAssertGreaterThanOrEqual(snapped, previous,
                                        "snapping went DOWN as the input went up, at \(freq) Hz")
            XCTAssertEqual(PopSoundEngine.snapToPentatonic(snapped), snapped, accuracy: 1e-9,
                           "snapping a note of the scale moved it, at \(freq) Hz")
            previous = snapped
            freq *= 1.007
        }
    }

    // A pop asked for a pitch far outside the scale still has to come back
    // inside it: the catalog is hand-edited, and `freqSpread` plus the ±12 Hz
    // detune can push a request past either end.
    func testAnyPositiveRequestIsPulledInsideTheScalesRange() {
        let lowest = Self.expectedScale.first!
        let highest = Self.expectedScale.last!
        let extremes: [Double] = [0.001, 0.5, 12, 65.41, 440, 6_977, 20_000, 1e6, 1e300]
        for freq in extremes {
            let snapped = PopSoundEngine.snapToPentatonic(freq)
            XCTAssertGreaterThanOrEqual(snapped, lowest - 1e-6, "\(freq) fell below the scale")
            XCTAssertLessThanOrEqual(snapped, highest + 1e-6, "\(freq) rose above the scale")
        }
    }

    // Total: every Double answers something finite-or-passed-through rather
    // than trapping. Zero and negatives are returned untouched by the guard
    // (`freq > 0`, which NaN also fails) — there is no note there to snap to —
    // and the non-finite cases must not crash, because a NaN arriving from a
    // mis-authored profile in a shipped build is a silent pop at worst and
    // must never be a terminated app.
    func testSnappingIsTotalOverEveryInputIncludingTheNonsensical() {
        XCTAssertEqual(PopSoundEngine.snapToPentatonic(0), 0)
        XCTAssertEqual(PopSoundEngine.snapToPentatonic(-440), -440)
        XCTAssertTrue(PopSoundEngine.snapToPentatonic(.nan).isNaN,
                      "a NaN pitch must pass through, not become a note")
        XCTAssertEqual(PopSoundEngine.snapToPentatonic(-.infinity), -.infinity)
        // +infinity is in-range for the guard and every log-distance from it
        // is infinite, so the strict `<` search keeps its first candidate. The
        // property worth holding is only that it degrades to a real note
        // instead of trapping or answering a non-finite frequency.
        let fromInfinity = PopSoundEngine.snapToPentatonic(.infinity)
        XCTAssertTrue(fromInfinity.isFinite, "an infinite pitch produced a non-finite note")
        XCTAssertGreaterThan(fromInfinity, 0)
    }

    // MARK: - prepare()

    // ROBUSTNESS, AND THE ONLY REACH INTO SYNTHESIS THERE IS. `prepare` is the
    // one internal entry point that renders unconditionally — no sound setting,
    // no running engine — so this is the single test that actually executes
    // `makePopBuffer`, for all ten voices, twelve buffers each. Nothing about
    // the samples can be asserted (the buffers are private), but a trap, an
    // out-of-range index or a non-finite frame count inside any voice branch
    // would surface right here.
    //
    // The profile's numbers are ordinary and positive on purpose: `duration`
    // reaches `AVAudioFrameCount(sampleRate * duration)`, and AVAudioFrameCount
    // is a UInt32 whose Double initialiser traps on a negative or non-finite
    // argument. Voice coverage is the point of this test; feeding it a poison
    // duration would only take the run down.
    func testEveryVoiceRendersWithoutTrapping() {
        for voice in SoundVoice.allCases {
            PopSoundEngine.shared.prepare([
                SoundProfile(voice: voice, startFreq: 460, freqSpread: 420,
                             sweep: 0.98, duration: 0.14, decay: 7.5, brightness: 0.1)
            ])
        }
    }

    // The real production call: `GameViewModel.applyFieldPops` hands `prepare`
    // one profile per pop the field can seed from, which in free play is every
    // unlocked pop. Doing the whole catalog at once covers that worst case and,
    // because the catalog holds more distinct profiles than the bank keeps,
    // also drives the eviction loop that trims `bankOrder` back to its limit.
    // The limit itself is private and cannot be observed; what can be observed
    // is that filling and overflowing the bank is safe and repeatable.
    func testPreparingTheWholeCatalogIsSafeAndRepeatable() {
        let profiles = PopCatalog.all.map { $0.behavior.sound }
        PopSoundEngine.shared.prepare(profiles)
        // Again: the profiles still in the bank take the already-cached path
        // and the evicted ones are re-rendered. Either way it is a no-op from
        // the caller's side. A subset, because re-rendering all hundred a
        // second time buys nothing and costs seconds.
        PopSoundEngine.shared.prepare(Array(profiles.prefix(20)))
        // Duplicates in one call must not double-enter the bank's order list.
        PopSoundEngine.shared.prepare([PopCatalog.classic.behavior.sound,
                                       PopCatalog.classic.behavior.sound])
        PopSoundEngine.shared.prepare([])
    }

    // MARK: - Playback robustness
    //
    // NOT VACUOUS: the header of PopSoundEngine.swift states the contract these
    // tests hold it to — "sound is a nice-to-have throughout: every failure
    // path degrades to silence, never to a crash". Silence cannot be observed
    // from outside the type, so not-crashing IS the assertable half of that
    // contract, and it is a real one: these calls run on the tap path, dozens
    // of times a second during a chain, with values derived from orb geometry.
    //
    // Honest limit: if `AVAudioEngine.start()` fails in the simulator, each of
    // these returns at its `engine.isRunning` guard and the code past it is not
    // reached. The call is still the one the app makes, and on a machine where
    // the engine does start the whole path runs. Neither outcome may crash.

    // `pitch` is documented as 0...1 but the view model already passes 1.18,
    // 1.34 and 1.42 from the splitter, generator and startle paths, and
    // `1 - sizeNorm` is unclamped at its source. So out-of-range pitch is not
    // hypothetical — it is the shipping behaviour, and it must clamp rather
    // than index a bucket that is not there.
    //
    // NaN AND THE INFINITIES ARE SAFE HERE, AND THE ORDER IS WHY. `playPop`
    // clamps with `min(1, max(0, pitch))` BEFORE the `Int(...)` conversion.
    // Swift's `max(x, y)` is `y >= x ? y : x`, so `max(0, .nan)` takes the
    // false branch and yields 0; `min(1, 0)` is `0 < 1 ? 0 : 1`, so 0. NaN
    // therefore reaches the conversion as 0, +infinity as 1, -infinity as 0,
    // and `Int((clamped * 5).rounded())` can only ever see 0...5. If that
    // clamp is ever moved after the conversion this input list becomes a trap
    // and must be cut back to 0...1 at the same time.
    func testPlayingAPopSurvivesEveryPitchIncludingTheImpossibleOnes() {
        SettingsStore.shared.soundEnabled = true
        let profile = PopCatalog.classic.behavior.sound
        let pitches: [Double] = [0, 0.5, 1, 1.18, 1.34, 1.42, 2, -1, -1e9, 1e9,
                                 .infinity, -.infinity, .nan]
        for pitch in pitches {
            PopSoundEngine.shared.playPop(profile: profile, pitch: pitch)
        }
    }

    // A chain of five pops is five overlapping buffers through a pool of ten
    // player nodes, and the pool wraps. A burst well past the pool size walks
    // the round-robin repeatedly, stopping and re-scheduling nodes that are
    // still sounding — the exact traffic a long cascade makes. Bounded at 200
    // scheduling calls, none of which blocks or waits on the audio hardware.
    func testABurstLongerThanThePlayerPoolIsSafe() {
        SettingsStore.shared.soundEnabled = true
        let profiles = PopCatalog.all.prefix(6).map { $0.behavior.sound }
        PopSoundEngine.shared.prepare(profiles)
        for index in 0..<200 {
            PopSoundEngine.shared.playPop(profile: profiles[index % profiles.count],
                                          pitch: Double(index % 7) / 6)
        }
        PopSoundEngine.shared.playCompletionChime()
    }

    // The firework voices, at the frequencies FireworkCatalog actually
    // supplies: `whirr` runs 200...420 Hz across the 36 shells, and the fuse
    // tick is called at 0.8× that, so 160...420 covers the shipping range at
    // both ends.
    //
    // NO NEGATIVE, NaN OR INFINITE FREQUENCY IS PASSED, AND THAT IS
    // DELIBERATE. Both of these paths key their buffer cache by converting the
    // frequency to an Int, and the fuse tick then seeds its noise generator
    // with `UInt64` of that Int. `Int(_: Double)` traps on NaN and on either
    // infinity; `UInt64(_: Int)` traps on anything negative. Each of those is
    // a process kill, not an assertion failure — it would take every other
    // suite in the run down with it. The unguarded conversion is reported as a
    // production bug rather than demonstrated here, because demonstrating it
    // has no failure mode short of a red CI run with no useful output.
    func testTheFireworkSoundsAreSafeToCallRepeatedly() {
        SettingsStore.shared.soundEnabled = true
        let whirrFrequencies: [Double] = [200, 260, 340, 420]
        for freq in whirrFrequencies {
            PopSoundEngine.shared.playFuseTick(startFreq: freq * 0.8)
            PopSoundEngine.shared.playFuseTick(startFreq: freq)
            PopSoundEngine.shared.playThoomf()
            PopSoundEngine.shared.playWhirr(startFreq: freq)
        }
        // Cached by rounded frequency: the second pass must take the cache.
        for freq in whirrFrequencies {
            PopSoundEngine.shared.playWhirr(startFreq: freq)
            PopSoundEngine.shared.playFuseTick(startFreq: freq)
        }
    }

    // With sound off, every entry point must be an immediate, harmless no-op.
    // This is the setting's whole job, and while the silence itself is not
    // observable from here, the guarded path is executed — including the ones
    // that would otherwise synthesize.
    func testEverySoundEntryPointIsSafeWithSoundTurnedOff() {
        SettingsStore.shared.soundEnabled = false
        PopSoundEngine.shared.playPop(profile: PopCatalog.classic.behavior.sound, pitch: 0.5)
        PopSoundEngine.shared.playWhirr(startFreq: 210)
        PopSoundEngine.shared.playThoomf()
        PopSoundEngine.shared.playFuseTick(startFreq: 168)
        PopSoundEngine.shared.playCompletionChime()
        // `prepare` is deliberately NOT gated by the setting — a field seeded
        // while muted must still be ready if she turns sound back on mid-field.
        PopSoundEngine.shared.prepare([PopCatalog.classic.behavior.sound])
    }

    // MARK: - Lifecycle

    // `warmUp` is called from `onAppear` and `setActive` from every scene-phase
    // change — backgrounding and foregrounding repeatedly is ordinary use, and
    // neither may accumulate state or fail on the second call.
    func testWarmUpAndSetActiveAreIdempotent() {
        PopSoundEngine.shared.warmUp()
        PopSoundEngine.shared.warmUp()
        for _ in 0..<3 {
            PopSoundEngine.shared.setActive(false)
            PopSoundEngine.shared.setActive(false)
            PopSoundEngine.shared.setActive(true)
            PopSoundEngine.shared.setActive(true)
        }
        // Playing into a just-paused engine is the route-change case the file
        // guards against twice — it either restarts the engine or returns at
        // one of the two `isRunning` checks. Never an exception.
        SettingsStore.shared.soundEnabled = true
        PopSoundEngine.shared.setActive(false)
        PopSoundEngine.shared.playPop(profile: PopCatalog.classic.behavior.sound, pitch: 0.3)
        PopSoundEngine.shared.playCompletionChime()
        // Restored here as well as in tearDown, so the engine is left running
        // even if a later assertion in this method is ever added and fails.
        PopSoundEngine.shared.setActive(true)
    }
}
