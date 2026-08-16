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

    // The keys this store owns. See ProgressionStore.ownedDefaultsKeys.
    static let ownedDefaultsKeys: [String] = [
        Keys.sound,
        Keys.haptics,
        Keys.whispers,
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        pointWhispersEnabled = defaults.object(forKey: Keys.whispers) as? Bool ?? true
    }

    // MARK: - W24: fresh install (DEBUG only)

    #if DEBUG
    // Back to the three defaults a first launch finds: everything on. In
    // memory first (each `didSet` writes through), then the keys, so nothing
    // is re-created behind the sweep.
    //
    // Settings are included in the fresh-install reset deliberately: W24 asks
    // for the state a first launch sees, and on a first launch sound, haptics
    // and whispers are all on. A playtest that starts with sound off because
    // the previous session turned it off is not a first run.
    func resetToFreshInstall() {
        soundEnabled = true
        hapticsEnabled = true
        pointWhispersEnabled = true
        for key in Self.ownedDefaultsKeys { defaults.removeObject(forKey: key) }
    }
    #endif

}
