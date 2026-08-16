import XCTest
@testable import Vesper

// W24 — the DEBUG-only fresh install (DELIVERY_ROADMAP §3: "One action; wipes
// progression + map; unavailable in release builds").
//
// THE WHOLE FILE IS INSIDE `#if DEBUG`, and it has to be: `DevReset` does not
// exist in a release build, so a test that referred to it unconditionally would
// fail to compile the moment anyone ran the suite against a Release
// configuration. That the test file needs the same guard as the feature is the
// clearest statement available in code that the feature cannot ship.
//
// WHY THE KEY-LIST TEST IS THE IMPORTANT ONE. A reset that misses a key is
// worse than no reset at all: the playtester sees a first-run field with a
// stale lifetime counter under it, and reports the counter as a bug in the
// game rather than as a bug in the reset. So the check here is not "did the
// wipe remove the keys it names" — that is trivially true — but "does the list
// it names match the keys the stores ACTUALLY WRITE", which is the only thing
// that survives somebody adding an eighth key to ProgressionStore next month.
#if DEBUG
final class DevResetTests: XCTestCase {

    // A private suite per test, so nothing here can touch the simulator's real
    // defaults — and so the sweep's "everything in the app's namespace" pass
    // has a bounded world to sweep.
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "vesper.tests.devreset.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private struct Stores {
        var progression: ProgressionStore
        var map: MapStore
        var settings: SettingsStore
    }

    private func makeStores() -> Stores {
        Stores(progression: ProgressionStore(defaults: defaults),
               map: MapStore(defaults: defaults),
               settings: SettingsStore(defaults: defaults))
    }

    // Drives every public write path the three stores have, so that whatever
    // they persist is on disk by the time the assertions run. If a store grows
    // a new write path, this is the function to extend — and until somebody
    // does, the test below still catches the new KEY, because it compares
    // against what is actually in defaults rather than against a list.
    @discardableResult
    private func exerciseEveryWritePath(_ s: Stores) -> Stores {
        s.progression.recordPop(popNumber: PopCatalog.classic.number, points: 7, chainLength: 4)
        s.progression.recordClear(bonus: 40)
        s.progression.recordFortune()
        s.progression.featuredPop = PopCatalog.classic.number

        s.map.ensureGenesis(unlocked: s.progression.unlockedNumbers())
        s.map.setActive(s.map.stones.first?.id)
        s.map.recordClear(unlocked: s.progression.unlockedNumbers())

        s.settings.soundEnabled = false
        s.settings.hapticsEnabled = false
        s.settings.pointWhispersEnabled = false
        return s
    }

    // The SUITE'S OWN domain, deliberately — not `dictionaryRepresentation()`.
    // A `UserDefaults(suiteName:)` searches the app's own domain as well as the
    // suite, so `dictionaryRepresentation()` here would also see whatever other
    // test classes have written to `UserDefaults.standard` (GameViewModel's
    // genesis stone, for one) and this suite would fail depending on test
    // ORDER. Reading the named domain keeps the assertions about the state this
    // test created.
    private func namespacedKeys() -> Set<String> {
        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        return Set(domain.keys.filter { $0.hasPrefix(DevReset.namespacePrefix) })
    }

    // MARK: - The list must match reality

    func testTheDeclaredKeyListMatchesTheKeysTheStoresActuallyWrite() {
        let stores = makeStores()
        exerciseEveryWritePath(stores)

        let written = namespacedKeys()
        let declared = Set(DevReset.ownedDefaultsKeys)

        XCTAssertFalse(written.isEmpty,
                       "the stores wrote nothing — this test would pass vacuously")
        XCTAssertEqual(DevReset.ownedDefaultsKeys.count, declared.count,
                       "a key is declared twice: \(DevReset.ownedDefaultsKeys)")

        // The half that matters: a key the game writes and DevReset does not
        // name. It survives the reset, and the tester sees a stale number under
        // a first-run field.
        XCTAssertTrue(written.subtracting(declared).isEmpty,
                      "the stores write keys DevReset does not declare — the fresh-install reset "
                      + "would leave them behind: \(written.subtracting(declared).sorted())")

        // The other half: a key DevReset names that nothing writes any more.
        // Harmless to wipe, but it means the declaration has drifted from the
        // stores, and a drifted list is one nobody trusts enough to maintain.
        XCTAssertTrue(declared.subtracting(written).isEmpty,
                      "DevReset declares keys no store writes any more: "
                      + "\(declared.subtracting(written).sorted())")

        print("[W24] fresh-install key list — \(declared.count) declared, "
              + "\(written.count) written: \(written.sorted().joined(separator: ", "))")
    }

    // The declaration is assembled from three store-local lists; each must
    // actually contribute, or a whole store has silently dropped out of the
    // reset.
    func testEveryStoreContributesToTheDeclaredList() {
        let declared = Set(DevReset.ownedDefaultsKeys)
        XCTAssertFalse(ProgressionStore.ownedDefaultsKeys.isEmpty)
        XCTAssertFalse(MapStore.ownedDefaultsKeys.isEmpty)
        XCTAssertFalse(SettingsStore.ownedDefaultsKeys.isEmpty)
        XCTAssertTrue(Set(ProgressionStore.ownedDefaultsKeys).isSubset(of: declared))
        XCTAssertTrue(Set(MapStore.ownedDefaultsKeys).isSubset(of: declared))
        XCTAssertTrue(Set(SettingsStore.ownedDefaultsKeys).isSubset(of: declared))
        for key in declared {
            XCTAssertTrue(key.hasPrefix(DevReset.namespacePrefix),
                          "\(key) is outside the app's namespace, so the backstop sweep would "
                          + "never reach it if a store forgot to declare it")
        }
    }

    // MARK: - The wipe itself

    func testTheWipeLeavesNothingOnDiskAndNothingStaleInMemory() {
        let stores = makeStores()
        exerciseEveryWritePath(stores)
        XCTAssertGreaterThan(stores.progression.popPoints, 0)
        XCTAssertFalse(stores.map.stones.isEmpty)

        let undeclared = DevReset.wipeOwnedDefaults(progression: stores.progression,
                                                    map: stores.map,
                                                    settings: stores.settings,
                                                    defaults: defaults)

        XCTAssertEqual(undeclared, [], "the sweep found app keys no store declares")
        XCTAssertTrue(namespacedKeys().isEmpty,
                      "keys survived the wipe: \(namespacedKeys().sorted())")

        // In memory, not just on disk. These are shared singletons that cache
        // everything they persist, so a defaults-only wipe leaves a store that
        // writes its old numbers straight back on the next pop.
        XCTAssertEqual(stores.progression.popPoints, 0)
        XCTAssertEqual(stores.progression.lifetimePops, 0)
        XCTAssertEqual(stores.progression.fieldsCleared, 0)
        XCTAssertEqual(stores.progression.fortunesFound, 0)
        XCTAssertEqual(stores.progression.bestChain, 0)
        XCTAssertEqual(stores.progression.popCounts, [:])
        XCTAssertNil(stores.progression.featuredPop, "a fresh install drifts; it features nothing")
        XCTAssertTrue(stores.map.stones.isEmpty)
        XCTAssertNil(stores.map.activeStoneID)
        XCTAssertTrue(stores.settings.soundEnabled)
        XCTAssertTrue(stores.settings.hapticsEnabled)
        XCTAssertTrue(stores.settings.pointWhispersEnabled)
    }

    // The real proof that the reset reverses a session: a store built AFTER the
    // wipe, over the same defaults, must read exactly what a first launch reads.
    func testStoresRebuiltAfterTheWipeReadFirstRunValues() {
        exerciseEveryWritePath(makeStores())
        let dirty = makeStores()
        DevReset.wipeOwnedDefaults(progression: dirty.progression,
                                   map: dirty.map,
                                   settings: dirty.settings,
                                   defaults: defaults)

        let reborn = makeStores()
        XCTAssertEqual(reborn.progression.popPoints, 0)
        XCTAssertEqual(reborn.progression.lifetimePops, 0)
        XCTAssertEqual(reborn.progression.fieldsCleared, 0)
        XCTAssertEqual(reborn.progression.fortunesFound, 0)
        XCTAssertEqual(reborn.progression.bestChain, 0)
        XCTAssertEqual(reborn.progression.popCounts, [:])
        XCTAssertNil(reborn.progression.featuredPop)
        XCTAssertTrue(reborn.map.stones.isEmpty)
        XCTAssertNil(reborn.map.activeStoneID)
        XCTAssertTrue(reborn.settings.soundEnabled)
        XCTAssertTrue(reborn.settings.hapticsEnabled)
        XCTAssertTrue(reborn.settings.pointWhispersEnabled)

        // And the very next thing a first launch does still works: the genesis
        // stone is laid again, so The Path is a first path rather than an empty
        // one.
        reborn.map.ensureGenesis(unlocked: reborn.progression.unlockedNumbers())
        XCTAssertEqual(reborn.map.stones.count, 1)
        XCTAssertNil(reborn.map.stones[0].parentID)
        XCTAssertFalse(reborn.map.stones[0].cleared)
    }

    // `featuredPop` writes through a `didSet`, so clearing it in the wrong
    // order re-creates its key behind the sweep. Pinned separately because it
    // is the one key in the app that can resurrect itself.
    func testClearingTheFeaturedPopDoesNotResurrectItsKey() {
        let stores = makeStores()
        stores.progression.featuredPop = PopCatalog.classic.number
        XCTAssertFalse(namespacedKeys().isEmpty)

        DevReset.wipeOwnedDefaults(progression: stores.progression,
                                   map: stores.map,
                                   settings: stores.settings,
                                   defaults: defaults)

        XCTAssertTrue(namespacedKeys().isEmpty,
                      "the featured-pop key came back after the sweep: \(namespacedKeys().sorted())")
        XCTAssertNil(stores.progression.featuredPop)
    }

    // The backstop. A store that grows a key and forgets to declare it must
    // still be WIPED — a playtest must never be poisoned by a bookkeeping
    // oversight — and must still be REPORTED, so the oversight is fixed rather
    // than absorbed. This test stands in for that future key.
    func testAnUndeclaredAppKeyIsBothSweptAndReported() {
        let stores = makeStores()
        exerciseEveryWritePath(stores)
        defaults.set(42, forKey: "vesper.someFutureStore.value")
        defaults.set("keep me", forKey: "unrelated.thirdParty.value")

        let undeclared = DevReset.wipeOwnedDefaults(progression: stores.progression,
                                                    map: stores.map,
                                                    settings: stores.settings,
                                                    defaults: defaults)

        XCTAssertEqual(undeclared, ["vesper.someFutureStore.value"],
                       "the sweep must name every app-namespaced key no store declares")
        XCTAssertTrue(namespacedKeys().isEmpty, "the undeclared key survived the sweep")
        XCTAssertEqual(defaults.string(forKey: "unrelated.thirdParty.value"), "keep me",
                       "the sweep reached outside the app's own namespace")
    }

    // Running it twice must be as safe as running it once — a playtester will,
    // because there is no confirmation and no visible result beyond a new field.
    func testTheWipeIsIdempotent() {
        let stores = makeStores()
        exerciseEveryWritePath(stores)
        DevReset.wipeOwnedDefaults(progression: stores.progression, map: stores.map,
                                   settings: stores.settings, defaults: defaults)
        let second = DevReset.wipeOwnedDefaults(progression: stores.progression, map: stores.map,
                                                settings: stores.settings, defaults: defaults)
        XCTAssertEqual(second, [])
        XCTAssertTrue(namespacedKeys().isEmpty)
        XCTAssertEqual(stores.progression.popPoints, 0)
        XCTAssertTrue(stores.map.stones.isEmpty)
    }
}
#endif
