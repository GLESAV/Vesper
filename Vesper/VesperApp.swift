import SwiftUI

@main
struct VesperApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBarHidden(true)
                .preferredColorScheme(.dark)
                .onAppear {
                    PopSoundEngine.shared.warmUp()
                    HapticsEngine.shared.warmUp()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            PopSoundEngine.shared.setActive(phase == .active)
            if phase == .active {
                MapStore.shared.prune()
            }
        }
    }
}
