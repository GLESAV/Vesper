import UIKit

// The haptic vocabulary of the game — one meaning per pattern, always gentle:
// a tap per pop shaped by the pop's HapticProfile (stronger for bigger orbs,
// lighter when the pop was part of a chain's echo, .soft or .light texture
// per pop), and a single success note when the field clears.
final class HapticsEngine {
    static let shared = HapticsEngine()

    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    private init() {}

    func warmUp() {
        soft.prepare()
        light.prepare()
        notify.prepare()
    }

    // sizeNorm: 0 = smallest orb, 1 = largest
    //
    // THE PATTERN IS THE POINT. Before this, `baseIntensity` and
    // `intensityPerSize` were overridden in exactly ONE of the hundred pops
    // and only `sharp` varied at all — so a hundred different-looking,
    // different-sounding pops all said the same single thing to the hand.
    // Touch has the least bandwidth of the three senses this game uses and
    // the longest memory, and a rhythm is far more memorable there than an
    // amplitude.
    //
    // The delays are short and few on purpose: haptics that outlast the
    // sound read as a stutter, and a pop is 140 ms.
    func pop(profile: HapticProfile, sizeNorm: Double, chained: Bool) {
        guard SettingsStore.shared.hapticsEnabled else { return }
        var intensity = profile.baseIntensity + profile.intensityPerSize * sizeNorm
        if chained { intensity *= 0.8 }
        let clamped = min(1, max(0.1, intensity))
        let generator = profile.sharp ? light : soft

        switch profile.pattern {
        case .single:
            generator.impactOccurred(intensity: clamped)

        case .double:
            generator.impactOccurred(intensity: clamped)
            tap(generator, intensity: clamped * 0.55, after: 0.055)

        case .ripple:
            generator.impactOccurred(intensity: clamped)
            tap(generator, intensity: clamped * 0.6, after: 0.045)
            tap(generator, intensity: clamped * 0.32, after: 0.095)

        case .swell:
            // Arrives rather than hits: the light touch first, the body after.
            generator.impactOccurred(intensity: clamped * 0.4)
            tap(generator, intensity: clamped, after: 0.06)

        case .thud:
            // One impact, at weight, always the soft generator — a heavy
            // thing is not a sharp thing.
            soft.impactOccurred(intensity: min(1, clamped * 1.25))
            soft.prepare()
            return
        }
        generator.prepare()
    }

    private func tap(_ generator: UIImpactFeedbackGenerator,
                     intensity: Double, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak generator] in
            guard SettingsStore.shared.hapticsEnabled else { return }
            generator?.impactOccurred(intensity: min(1, max(0.1, intensity)))
            generator?.prepare()
        }
    }

    func cleared() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        notify.notificationOccurred(.success)
        notify.prepare()
    }
}
