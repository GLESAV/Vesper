import XCTest
@testable import Vesper

// The three switches Vesper has: sound, haptics, and the point whispers in
// the field. Small surface, but two properties of it matter more than the
// code's size suggests.
//
// THE CALM DEFAULT. A first launch has all three ON, and that is a product
// decision rather than an accident of storage: the pop, the tap in the hand
// and the quiet number are the game. `UserDefaults.bool(forKey:)` returns
// false for a key that has never been written, so the obvious spelling of
// this store would ship a silent, still, numberless first launch to everyone.
// The store reads `object(forKey:) as? Bool ?? true` instead, and the tests
// below are what keeps somebody from "simplifying" that back.
//
// AND THE OTHER HALF: a switch the player turned off must STAY off. A setting
// that quietly turns itself back on is worse than one that cannot be changed.
//
// Everything runs over a private suite — `SettingsStore.shared` writes
// `UserDefaults.standard`, which the app and other test classes share, so a
// test that used it would be order-dependent and would edit the device.
final class SettingsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "vesper.tests.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: defaults)
    }

    // The suite's own domain, deliberately — `dictionaryRepresentation()`
    // would also see everything other test classes wrote to `.standard` and
    // make these assertions depend on test order.
    private func storedKeys() -> Set<String> {
        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        return Set(domain.keys.filter { $0.hasPrefix("vesper.") })
    }

    // The on-disk names, spelled out: they are a data format, and renaming
    // one silently resets a returning player's preferences to on.
    private static let soundKey = "vesper.settings.sound"
    private static let hapticsKey = "vesper.settings.haptics"
    private static let whispersKey = "vesper.settings.pointWhispers"

    private func switches(_ store: SettingsStore) -> [Bool] {
        [store.soundEnabled, store.hapticsEnabled, store.pointWhispersEnabled]
    }

    // MARK: - The calm default

    func testAFirstLaunchHasSoundHapticsAndWhispersAllOn() {
        XCTAssertTrue(storedKeys().isEmpty, "the suite was not clean; this test proves nothing")
        let store = makeStore()
        XCTAssertEqual(switches(store), [true, true, true],
                       "a first launch must arrive with the whole game switched on — an absent "
                       + "key means \"never chosen\", not \"off\"")
    }

    // Reading is not writing. If building the store wrote its three keys,
    // "has this player ever chosen anything" would be unanswerable from disk,
    // and a fresh install would leave settings behind before the first orb.
    func testBuildingAStoreWritesNothing() {
        _ = makeStore()
        XCTAssertTrue(storedKeys().isEmpty,
                      "constructing the store wrote \(storedKeys().sorted())")
    }

    // MARK: - Independence

    // Three switches, three keys, no crosstalk: turning the sound off must
    // not disturb the hand or the whispers, on disk or in memory. Each step
    // checks BOTH — a shared key would show up as an extra flipped switch,
    // and a store that wrote all three on every change would show up as an
    // extra key on disk.
    func testTurningOneSwitchOffLeavesTheOtherTwoExactlyAsTheyWere() {
        let store = makeStore()

        store.soundEnabled = false
        XCTAssertEqual(switches(store), [false, true, true], "turning sound off moved something else")
        XCTAssertEqual(storedKeys(), [Self.soundKey],
                       "one choice wrote more than its own key: \(storedKeys().sorted())")

        store.hapticsEnabled = false
        XCTAssertEqual(switches(store), [false, false, true],
                       "turning haptics off moved something else")
        XCTAssertEqual(storedKeys(), [Self.soundKey, Self.hapticsKey])

        store.pointWhispersEnabled = false
        XCTAssertEqual(switches(store), [false, false, false])
        XCTAssertEqual(storedKeys(), [Self.soundKey, Self.hapticsKey, Self.whispersKey])

        // and back on again, one at a time
        store.hapticsEnabled = true
        XCTAssertEqual(switches(store), [false, true, false],
                       "turning haptics back on moved something else")
    }

    // MARK: - Persistence

    // A switch the player turned off must still be off the next time the app
    // opens. This is the failure that reads as the app ignoring you.
    func testASwitchTurnedOffIsStillOffAfterARelaunch() {
        let store = makeStore()
        store.soundEnabled = false
        store.pointWhispersEnabled = false

        let reborn = makeStore()
        XCTAssertEqual(switches(reborn), [false, true, false],
                       "a rebuilt store did not read back what the player chose")

        // and a choice made in the new store persists in turn, so the store
        // is genuinely reading and writing the same key both ways
        reborn.soundEnabled = true
        XCTAssertEqual(switches(makeStore()), [true, true, false])
    }

    // Defaults are a file that can be damaged. Something that is not a Bool
    // must fall back to the calm default rather than crashing the launch or
    // silently reading as off, and it must not take the healthy keys with it.
    func testAnUnreadableSettingFallsBackToOnWithoutDisturbingTheOthers() {
        defaults.set("yes please", forKey: Self.soundKey)
        defaults.set(false, forKey: Self.hapticsKey)

        let store = makeStore()
        XCTAssertTrue(store.soundEnabled, "an unreadable switch must read as on, not as off")
        XCTAssertFalse(store.hapticsEnabled, "a healthy neighbouring choice was lost")
        XCTAssertTrue(store.pointWhispersEnabled)

        // the first honest write repairs the damaged key
        store.soundEnabled = false
        XCTAssertEqual(switches(makeStore()), [false, false, true])
    }

    // MARK: - The declared key list

    // What the W24 fresh install sweeps. Checked here per store and against
    // literal names because DevResetTests is entirely `#if DEBUG` (in a
    // Release test run nothing checks this at all) and compares the UNION of
    // three stores' lists, which would still pass if this store's key were
    // declared by another store.
    func testTheDeclaredKeyListIsExactlyTheKeysThisStoreWrites() {
        let store = makeStore()
        store.soundEnabled = false
        store.hapticsEnabled = false
        store.pointWhispersEnabled = false

        let written = storedKeys()
        let declared = Set(SettingsStore.ownedDefaultsKeys)
        XCTAssertEqual(SettingsStore.ownedDefaultsKeys.count, declared.count,
                       "a key is declared twice: \(SettingsStore.ownedDefaultsKeys)")
        XCTAssertEqual(written, declared,
                       "declared and written have drifted — written but not declared: "
                       + "\(written.subtracting(declared).sorted()); declared but never written: "
                       + "\(declared.subtracting(written).sorted())")
        XCTAssertEqual(declared, [Self.soundKey, Self.hapticsKey, Self.whispersKey],
                       "a settings key was renamed; every returning player's choices read as "
                       + "never made")
    }

    // MARK: - W24: the fresh install (DEBUG only)

    #if DEBUG
    // DevResetTests reaches this through `DevReset.wipeOwnedDefaults`, which
    // sweeps the whole namespace afterwards and would therefore hide a reset
    // that left its own keys behind. On its own, the reset must clear both
    // halves: the values in memory (each `didSet` writes through, so the order
    // matters) and the keys on disk, so that a store built afterwards reads a
    // genuine first launch rather than three keys that happen to say true.
    func testResetToFreshInstallTurnsEverythingBackOnAndLeavesNoKeys() {
        let store = makeStore()
        store.soundEnabled = false
        store.hapticsEnabled = false
        store.pointWhispersEnabled = false
        XCTAssertEqual(storedKeys().count, 3)

        store.resetToFreshInstall()

        XCTAssertEqual(switches(store), [true, true, true],
                       "the reset left a switch off; a playtest that begins in silence is not a "
                       + "first run")
        XCTAssertTrue(storedKeys().isEmpty,
                      "keys survived the store's own reset — a `didSet` wrote one back behind "
                      + "the sweep: \(storedKeys().sorted())")
        XCTAssertEqual(switches(makeStore()), [true, true, true])
    }
    #endif
}
