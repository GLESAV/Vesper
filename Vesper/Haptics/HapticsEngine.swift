import UIKit

// The haptic vocabulary of the game — one meaning per pattern, always gentle:
// a soft tap per pop (stronger for bigger orbs, lighter when the pop was part
// of a chain's echo), and a single success note when the field clears.
final class HapticsEngine {
    static let shared = HapticsEngine()

    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()

    private init() {}

    func warmUp() {
        soft.prepare()
        notify.prepare()
    }

    func pop(intensity: Double, chained: Bool) {
        guard SettingsStore.shared.hapticsEnabled else { return }
        let scaled = chained ? intensity * 0.8 : intensity
        soft.impactOccurred(intensity: min(1, max(0.1, scaled)))
        soft.prepare()
    }

    func cleared() {
        guard SettingsStore.shared.hapticsEnabled else { return }
        notify.notificationOccurred(.success)
        notify.prepare()
    }
}
