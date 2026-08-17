import SwiftUI

@main
struct VesperApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            root
                .statusBarHidden(true)
                .preferredColorScheme(.dark)
                .onAppear {
                    PopSoundEngine.shared.warmUp()
                    HapticsEngine.shared.warmUp()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            PopSoundEngine.shared.setActive(phase == .active)
            // The map used to be pruned here on every foreground — the pass
            // that deleted any stone untouched for three days. W08 removed it:
            // settling is now derived at draw time from the stone's own dates,
            // so coming back to the app changes nothing about the map. There
            // is no longer anything the map needs done to it on waking.
        }
    }

    // THE ONLY READ OF `WorldFlags.oneWorldEnabled` IN THE APP (§6 ruling 10).
    //
    // It is forbidden in view bodies, in `GameViewModel`, and in every store.
    // The stores are shared singletons over one `UserDefaults`; branch deeper
    // than this line and you have two games writing one save file, which is
    // precisely the state the flag can no longer reverse.
    //
    // Both branches compile in both CI configurations (ruling 11) — the flag
    // is a runtime `Bool` over a compile-time condition, not an `#if` wrapped
    // around this call site — so the v1.2 navigation stays releasable on any
    // day of the rebuild. `AnyView` is the erasure the Director specified;
    // it is evaluated once, at launch, and costs nothing.
    private var root: AnyView {
        WorldFlags.oneWorldEnabled ? AnyView(WorldView()) : AnyView(ContentView())
    }
}
