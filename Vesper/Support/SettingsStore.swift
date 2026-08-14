import Foundation
import Combine

// Everything Vesper remembers, which is deliberately little: two toggles and
// two affirming lifetime counters. UserDefaults only — nothing leaves the
// device (see PRIVACY.md).
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.sound) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    @Published private(set) var lifetimePops: Int
    @Published private(set) var fieldsCleared: Int

    private let defaults: UserDefaults

    private enum Keys {
        static let sound = "vesper.settings.sound"
        static let haptics = "vesper.settings.haptics"
        static let lifetimePops = "vesper.stats.lifetimePops"
        static let fieldsCleared = "vesper.stats.fieldsCleared"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        lifetimePops = defaults.integer(forKey: Keys.lifetimePops)
        fieldsCleared = defaults.integer(forKey: Keys.fieldsCleared)
    }

    func recordPop() {
        lifetimePops += 1
        defaults.set(lifetimePops, forKey: Keys.lifetimePops)
    }

    func recordClear() {
        fieldsCleared += 1
        defaults.set(fieldsCleared, forKey: Keys.fieldsCleared)
    }
}
