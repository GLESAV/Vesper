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
    func pop(profile: HapticProfile, sizeNorm: Double, chained: Bool) {
        guard SettingsStore.shared.hapticsEnabled else { return }
        var intensity = profile.baseIntensity + profile.intensityPerSize * sizeNorm
        if chained { intensity *= 0.8 }
        let generator = profile.sharp ? light : soft
        generator.impactOccurred(intensity: min(1, max(0.1, intensity)))
        generator.prepare()
    }

    func cleared() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        notify.notificationOccurred(.success)
        notify.prepare()
    }
}
