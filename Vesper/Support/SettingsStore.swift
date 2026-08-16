import Foundation
import Combine

// The few things Vesper lets you switch: sound, haptics, and whether point
// whispers appear in the field. Lifetime counters live in ProgressionStore.
// UserDefaults only — nothing leaves the device (see PRIVACY.md).
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.sound) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    @Published var pointWhispersEnabled: Bool {
        didSet { defaults.set(pointWhispersEnabled, forKey: Keys.whispers) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let sound = "vesper.settings.sound"
        static let haptics = "vesper.settings.haptics"
        static let whispers = "vesper.settings.pointWhispers"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        pointWhispersEnabled = defaults.object(forKey: Keys.whispers) as? Bool ?? true
    }
}
