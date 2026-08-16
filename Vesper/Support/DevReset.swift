#if DEBUG
import Foundation

// W24 — the DEBUG-only fresh install (DELIVERY_ROADMAP §3: "One action; wipes
// progression + map; unavailable in release builds").
//
// WHY IT EXISTS. A playtest is only worth watching once. The first field
// somebody sees is the only one they meet without knowing what an orb does,
// The Path's genesis stone is the only stone that is ever the first, and every
// unlock hint is only kind the first time it is read. After one session that
// state is gone from the device and the next tester gets a different game.
// This puts it back, so a session is repeatable and two testers can be shown
// the same first thirty seconds.
//
// ─────────────────────────────────────────────────────────────────────────
// THE WHOLE FILE IS INSIDE `#if DEBUG`, AND THAT IS THE SAFETY PROPERTY.
//
// Not a runtime flag, not a hidden gesture, not a build setting somebody can
// flip: the type does not exist in a release binary, so a call site that
// reaches it fails to COMPILE for release rather than shipping a button that
// erases a stranger's journey. If you add a call site, it must be inside
// `#if DEBUG` too — that is not a style rule, it is the only thing keeping
// this out of the App Store build.
// ─────────────────────────────────────────────────────────────────────────
//
// THERE IS NO CONFIRMATION AND NO UNDO. Both belong to a product that ships
// this, and neither is worth building for a type that cannot exist in one.
enum DevReset {

    // THE JOURNAL CALL SITE, for whoever owns JournalView. One row among the
    // journal's quiet things, and it must carry the guard with it:
    //
    //     #if DEBUG
    //     Button(DevReset.label) { DevReset.freshInstall(game: model.game) }
    //         .buttonStyle(.plain)
    //     #endif
    //
    // The `#if` is not decoration. Without it the release build stops
    // compiling, which is the point — but only if nobody "fixes" that by
    // deleting the guard on this file instead.

    // The label a DEBUG affordance should carry, in the app's voice. Kept here
    // rather than in `Strings.swift` because it must vanish with the rest of
    // the file — a localizable string for a feature that does not exist in
    // release is a string somebody eventually shows.
    static let label = "begin again, from nothing"

    // MARK: - What "the game owns" means

    // Every UserDefaults key Vesper writes starts with this. The sweep below
    // uses it as a backstop so that a store which grows a key and forgets to
    // declare it is still wiped — and still REPORTED, so the omission gets
    // fixed rather than silently absorbed.
    static let namespacePrefix = "vesper."

    // The keys the stores declare they own, gathered in one place. This is
    // what `DevResetTests` compares against the keys the stores actually
    // write; the sweep does not depend on it being complete.
    static var ownedDefaultsKeys: [String] {
        ProgressionStore.ownedDefaultsKeys
            + MapStore.ownedDefaultsKeys
            + SettingsStore.ownedDefaultsKeys
    }

    // MARK: - The wipe

    // Returns the app-namespaced keys that were found in `defaults` but NOT
    // declared by any store — always empty in a healthy build, and the one
    // signal that a store has grown a key nobody told this file about.
    //
    // The stores are asked to reset themselves FIRST. They hold cached copies
    // of everything they persist, so a defaults-only wipe would leave
    // `ProgressionStore.shared.popPoints` at 400 and let the next pop write it
    // straight back — a reset that undoes itself, which is worse than none
    // because the tester believes it worked.
    //
    // `defaults` must be the same store the three stores were built over. In
    // the app that is `.standard` for all four; in tests it is one private
    // suite for all four, which is what keeps a test run out of the
    // simulator's real defaults.
    @discardableResult
    static func wipeOwnedDefaults(progression: ProgressionStore = .shared,
                                  map: MapStore = .shared,
                                  settings: SettingsStore = .shared,
                                  defaults: UserDefaults = .standard) -> [String] {
        progression.resetToFreshInstall()
        map.resetToFreshInstall()
        settings.resetToFreshInstall()

        let declared = Set(ownedDefaultsKeys)
        var undeclared: [String] = []
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(namespacePrefix) {
            if !declared.contains(key) { undeclared.append(key) }
            defaults.removeObject(forKey: key)
        }
        return undeclared.sorted()
    }

    // MARK: - The one action

    // What a DEBUG affordance calls. Wipe, then do the two things a genuine
    // first launch does in `GameViewModel.init` — lay the genesis stone, and
    // seed a field from the pops a fresh journey starts with.
    //
    // `@MainActor` because `GameViewModel.restart()` runs `withAnimation` and
    // publishes; the affordance that calls this is a view, so it is already
    // there.
    //
    // Passing the LIVE `GameViewModel` matters. Wiping the stores under a
    // running game leaves it holding a field seeded from a stone that no
    // longer exists, and the next clear would try to open roads from it.
    @MainActor
    static func freshInstall(game: GameViewModel?,
                             progression: ProgressionStore = .shared,
                             map: MapStore = .shared,
                             settings: SettingsStore = .shared,
                             defaults: UserDefaults = .standard) {
        let undeclared = wipeOwnedDefaults(progression: progression,
                                           map: map,
                                           settings: settings,
                                           defaults: defaults)
        if !undeclared.isEmpty {
            // Loud on purpose. DevResetTests is supposed to catch this in CI;
            // reaching it at runtime means the test has gone stale too.
            assertionFailure("""
                DevReset swept app-owned defaults keys that no store declares: \
                \(undeclared). Add them to that store's `ownedDefaultsKeys`.
                """)
        }

        map.ensureGenesis(unlocked: progression.unlockedNumbers())
        game?.restart()
    }
}
#endif
