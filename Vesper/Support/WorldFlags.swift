// The One World navigation flag.
//
// EXACTLY ONE READ SITE IN THE APP (DELIVERY_ROADMAP §6 ruling 10):
// `VesperApp` choosing between `WorldView()` and `ContentView()`. It is
// forbidden in view bodies, in `GameViewModel`, and in every store — the
// stores are shared singletons over one `UserDefaults`, so branching deeper
// than the root view gives you two games writing one save file, which the
// flag cannot then reverse.
//
// A COMPILE-TIME CONDITION RATHER THAN A STORED BOOL (ruling 11). CI builds
// both configurations on every PR — `world` (default) and `classic`
// (`VESPER_CLASSIC_NAV` defined) — and an unbuilt configuration rots within
// days. The flag's whole value is that the shipped v1.2 navigation stays
// releasable on any day of the rebuild, and that is only true if the compiler
// checks the other branch as often as it checks this one.
//
// Both branches must therefore keep COMPILING in either configuration: this
// is a runtime `Bool` over a compile-time condition, not an `#if` wrapped
// around the call sites.
enum WorldFlags {

    static var oneWorldEnabled: Bool {
        #if VESPER_CLASSIC_NAV
        false
        #else
        true
        #endif
    }
}
