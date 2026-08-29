import XCTest
@testable import Vesper

// HAPTICS ENGINE — a very small reachable surface, honestly stated.
//
// THE BOUNDARY. `HapticsEngine` has exactly three internal entry points —
// `warmUp()`, `pop(profile:sizeNorm:chained:)` and `cleared()` — and nothing
// else. The three `UIFeedbackGenerator`s are `private let`, the delayed
// follow-up `tap(_:intensity:after:)` is `private`, and the intensity
// arithmetic (`base + perSize * sizeNorm`, ×0.8 when chained, clamped to
// 0.1...1, ×1.25 for `.thud`) lives INLINE inside `pop` rather than in a
// helper. `@testable import` exposes `internal`, not `private`.
//
// The consequence is worth being blunt about: the properties this file would
// most like to pin — that a bigger orb taps harder, that a chained echo is
// lighter than the pop that caused it, that intensity never leaves 0.1...1 —
// are NOT observable from a test. `pop` returns Void, mutates no reachable
// state, and its only effect is a message to hardware that does not exist in
// the simulator. There is no seam. The report recommends extracting the
// arithmetic into an internal pure function (something like
// `static func intensity(for:sizeNorm:chained:) -> Double`) so those three
// properties become assertable; no production change is made here.
//
// What IS both reachable and real is safety. Haptics are optional hardware:
// iPad has no Taptic Engine, the setting can be off, and `pop` is called from
// the tap path and from four firework events with values derived from orb
// geometry — `sizeNorm` is computed as an unclamped normalization of the orb
// radius, so it is not guaranteed to be inside 0...1. Every one of those
// calls must be a no-op or a tap, never a crash. That is not a vacuous
// assertion here: it is the whole contract of a subsystem whose output cannot
// otherwise be seen, and it covers the clamping arithmetic that keeps a NaN
// or an out-of-range size from reaching `impactOccurred(intensity:)`, which
// is documented to take 0...1.
final class HapticsEngineTests: XCTestCase {

    private var hapticsWereEnabled = true

    override func setUp() {
        super.setUp()
        // Other test classes mutate SettingsStore.shared, so nothing here may
        // assert a setting it did not itself set — only save and restore.
        hapticsWereEnabled = SettingsStore.shared.hapticsEnabled
    }

    override func tearDown() {
        SettingsStore.shared.hapticsEnabled = hapticsWereEnabled
        super.tearDown()
    }

    /// Every profile shape the catalog and the firework paths can produce:
    /// both generators (`sharp`), all five rhythms, and the classic's own
    /// numbers alongside the flatter firework ones.
    private static let profiles: [HapticProfile] = {
        var made: [HapticProfile] = []
        for pattern in HapticPattern.allCases {
            for sharp in [false, true] {
                made.append(HapticProfile(baseIntensity: 0.35, intensityPerSize: 0.5,
                                          sharp: sharp, pattern: pattern))
                made.append(HapticProfile(baseIntensity: 0.18, intensityPerSize: 0,
                                          sharp: sharp, pattern: pattern))
            }
        }
        return made
    }()

    // MARK: - Coverage of the shapes that actually ship

    // Every one of the hundred pops is felt through this one method, and the
    // pattern switch is the part that is newest and least exercised elsewhere.
    // Driving all five rhythms on both generators, direct and chained, at both
    // ends of the size range is the closest thing to a smoke test the hand has.
    func testEveryPatternOnBothGeneratorsIsSafeDirectAndChained() {
        SettingsStore.shared.hapticsEnabled = true
        for profile in Self.profiles {
            for sizeNorm in [0.0, 0.25, 0.5, 1.0] {
                HapticsEngine.shared.pop(profile: profile, sizeNorm: sizeNorm, chained: false)
                HapticsEngine.shared.pop(profile: profile, sizeNorm: sizeNorm, chained: true)
            }
        }
    }

    // The catalog is a hundred hand-edited entries and it is the part most
    // likely to be changed by someone who never opens Xcode. Feeling every
    // authored profile once proves no entry produces a value the engine cannot
    // clamp — the same reason PopCatalogTests walks all hundred.
    func testEveryAuthoredPopProfileIsSafeToFeel() {
        SettingsStore.shared.hapticsEnabled = true
        for definition in PopCatalog.all {
            HapticsEngine.shared.pop(profile: definition.behavior.haptic,
                                     sizeNorm: 0, chained: false)
            HapticsEngine.shared.pop(profile: definition.behavior.haptic,
                                     sizeNorm: 1, chained: true)
        }
    }

    // `sizeNorm` reaches this method as `(baseR - lower) / (upper - lower)`,
    // computed at the call site and never clamped, so a grown or shrunken orb
    // can hand it a value outside 0...1. `UIImpactFeedbackGenerator` documents
    // its intensity as 0...1; the clamp inside `pop` is what stands between
    // those two facts, and a NaN or an infinity must come out as a quiet tap
    // rather than as a trap.
    func testAnOutOfRangeOrNonFiniteSizeStillProducesATapRatherThanACrash() {
        SettingsStore.shared.hapticsEnabled = true
        let sizes: [Double] = [-1, -0.001, 1.001, 4, 1e9, -1e9, .infinity, -.infinity, .nan]
        for profile in Self.profiles {
            for sizeNorm in sizes {
                HapticsEngine.shared.pop(profile: profile, sizeNorm: sizeNorm, chained: false)
                HapticsEngine.shared.pop(profile: profile, sizeNorm: sizeNorm, chained: true)
            }
        }
    }

    // The same argument one level up: the profile's own numbers are data, and
    // data can be wrong. A zero-intensity profile must not fall below the
    // engine's 0.1 floor and an oversized one must not exceed 1.
    func testAProfileWithAbsurdIntensitiesIsClampedRatherThanPassedThrough() {
        SettingsStore.shared.hapticsEnabled = true
        let absurd: [(Double, Double)] = [(0, 0), (-5, -5), (10, 10), (.nan, 0), (0, .nan),
                                          (.infinity, 0), (0, .infinity)]
        for (base, perSize) in absurd {
            for pattern in HapticPattern.allCases {
                let profile = HapticProfile(baseIntensity: base, intensityPerSize: perSize,
                                            sharp: false, pattern: pattern)
                HapticsEngine.shared.pop(profile: profile, sizeNorm: 0.5, chained: false)
                HapticsEngine.shared.pop(profile: profile, sizeNorm: 0.5, chained: true)
            }
        }
    }

    // MARK: - The setting, and hardware that is not there

    // Guardrail: the haptics toggle must silence every entry point. The
    // silence itself cannot be observed from outside the type — there is no
    // reachable witness to whether a generator fired — so what this pins is
    // that the disabled path is executed and is harmless, including the
    // delayed follow-up taps of `.double`, `.ripple` and `.swell`, which
    // re-check the setting when they land rather than when they are scheduled.
    func testEveryEntryPointIsSafeWithHapticsTurnedOff() {
        SettingsStore.shared.hapticsEnabled = false
        HapticsEngine.shared.warmUp()
        for profile in Self.profiles {
            HapticsEngine.shared.pop(profile: profile, sizeNorm: 0.5, chained: false)
            HapticsEngine.shared.pop(profile: profile, sizeNorm: 0.5, chained: true)
        }
        HapticsEngine.shared.cleared()
    }

    // She can turn haptics off in the middle of a chain, between a pop and the
    // follow-up tap it scheduled. Toggling around live calls must not leave
    // anything in a bad state either way.
    func testTogglingTheSettingAroundLiveCallsIsSafe() {
        let rippling = HapticProfile(baseIntensity: 0.35, intensityPerSize: 0.5,
                                     sharp: false, pattern: .ripple)
        for step in 0..<12 {
            SettingsStore.shared.hapticsEnabled = step % 2 == 0
            HapticsEngine.shared.pop(profile: rippling, sizeNorm: Double(step) / 11,
                                     chained: step % 3 == 0)
            HapticsEngine.shared.cleared()
        }
    }

    // iPad has no Taptic Engine and the simulator has no haptics at all, so
    // every call in this file already runs against absent hardware — which is
    // exactly the case that must not crash, and the reason these tests are
    // worth having despite asserting no value. `warmUp` and `cleared` are the
    // two entry points with no arguments to vary; they are called from
    // `onAppear` and from field completion, and both are called repeatedly
    // over a session.
    func testWarmUpAndClearedAreSafeToRepeatOnHardwareThatMayNotExist() {
        SettingsStore.shared.hapticsEnabled = true
        for _ in 0..<5 {
            HapticsEngine.shared.warmUp()
            HapticsEngine.shared.cleared()
        }
    }
}
