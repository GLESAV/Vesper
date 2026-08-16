import Combine
import CoreGraphics
import Foundation

// The world's one observable object, and the seam between three things that
// deliberately cannot see each other: the pure camera (no SwiftUI), the pure
// simulation behind `GameViewModel` (no wall-clock), and SwiftUI itself.
//
// ─────────────────────────────────────────────────────────────────────────
// IT PUBLISHES `place` AND `worldMoving`, AND NOTHING ELSE.
//
// That is a blocking acceptance condition carried onto W04 by R-ARCH, not a
// style preference, and the two halves fail in opposite directions:
//
//   * publishing MORE — above all the camera's per-frame offset — rebuilds
//     the TimelineView/Canvas/input subtree 120 times a second, which is
//     verbatim the condition v1.2 blames for cancelled taps (ruling 7);
//   * publishing LESS — leaving the pause predicate to read the camera —
//     latches the world frozen mid-settle, because the camera is not
//     observable and nothing about it can wake a SwiftUI view (host contract
//     H3 in WorldCamera.swift, which is written for this file).
//
// Both published values change at most a couple of times per gesture:
// `place` at the commit instant, `worldMoving` once when the world starts
// moving and once when it stops.
// ─────────────────────────────────────────────────────────────────────────
//
// `@MainActor` for the same reason the camera is: this object is written from
// UIKit touch callbacks and read from the SwiftUI render closure, both of
// which are main by definition. The annotation states what is already true.
@MainActor
final class WorldModel: ObservableObject {

    // MARK: - The only published state in the world layer

    // Where the camera belongs — where it is, or where it is going. Mirrored
    // from the camera at commit time, inside the touch handler, which is
    // outside the render pass and therefore safe to publish from.
    @Published private(set) var place: Place = .field

    // The MOVING half of the pause predicate (H3). Never derived in a view
    // body, never read from the camera by SwiftUI.
    @Published private(set) var worldMoving = false

    // MARK: - Owned, and deliberately not published

    // Ruling 7 in full: not `@Published`, not `ObservableObject`, and never
    // mirrored into `@State`. The view reads its per-frame scalars inside the
    // TimelineView closure, at the moment it needs them.
    let camera = WorldCamera()

    // The v1.2 game, unchanged. The field place renders it exactly as
    // ContentView does; the only new thing the world tells it is `simActive`.
    let game = GameViewModel()

    // MARK: - W07: does the simulation advance this frame?

    // `camera.isAtRest && camera.place == .field`, and the same predicate
    // serves two consumers so they cannot drift (R-ARCH blocking acceptance):
    //
    //   * the input layer's `isFieldAtRest` — bound as a live closure, never
    //     a pushed snapshot. Testing `isAtRest` alone would let a touch-down
    //     while resting AT THE SKY pop an orb on a field she cannot see;
    //   * `GameViewModel.simActive` — so the field stops the instant she has
    //     decided to leave it and no chain resolves unwatched (04 §5).
    //
    // Computed, never stored: a stored copy is stale for about a frame at
    // each end of every settle, and being wrong there costs a pop.
    var simActive: Bool { camera.isAtRest && camera.place == .field }

    // MARK: - Private

    // The camera's frame clock. A plain var, not `@State` and not published:
    // it is written from inside the render pass, where publishing is
    // SwiftUI's publishing-during-view-update hazard.
    private var lastFrameDate: Date?

    #if DEBUG
    // Host contract H1's trap. See `advance(at:)`.
    private var stepOwner: String?
    #endif

    // MARK: - Input

    // Every outcome the input layer produces arrives here, in order, one
    // batch per touch delivery. This is a UIKit touch callback — outside the
    // render pass — which is what makes publishing from it safe.
    func handle(_ outcomes: [InputOutcome]) {
        // Ruling 4: the pop and the pan have independent lives, and the pop
        // is never retracted. It is applied FIRST because it is the
        // interaction that must never be delayed; the camera ignores `.pop`
        // entirely and says so explicitly in `consume(_:)`.
        for outcome in outcomes {
            if case .pop(let p) = outcome { game.tap(at: p) }
        }

        camera.consume(outcomes)

        // Mirrored, not published per-frame: `camera.place` changes at most
        // once per commit. Guarded because `@Published` fires on every write,
        // equal or not.
        if place != camera.place { place = camera.place }

        // H3: set in the SAME handler that feeds the camera. Guarded for the
        // same reason — `.panChanged` arrives at digitizer rate, and an
        // unguarded write here would republish 120 times a second and undo
        // the whole point of ruling 7.
        if !worldMoving && !camera.isAtRest { worldMoving = true }
    }

    // MARK: - The frame

    // THE ONE PLACE IN THE APP THAT STEPS THE CAMERA (host contract H1).
    //
    // Called once per frame from the world's TimelineView closure, every
    // frame the world is on screen (H2). A second owner does not look like a
    // bug — it silently halves every settle's duration and puts the world
    // above the optical-flow ceiling WorldCamera spends its length proving.
    //
    // `caller` is a debug tripwire, not an argument any caller should pass:
    // it defaults to the calling file, so a preview or a debug overlay in
    // another file — the realistic offenders R-ARCH named — trips the
    // assertion the first time it steps.
    //
    // A repeated call for the SAME date is benign by construction and
    // deliberately not trapped: SwiftUI may evaluate a view body more than
    // once for one timeline tick, and the second pass computes `dt == 0`,
    // which `WorldCamera.step(dt:)` refuses outright. Everything else here is
    // idempotent.
    func advance(at date: Date, caller: StaticString = #fileID) {
        #if DEBUG
        let callerID = caller.description
        if let owner = stepOwner, owner != callerID {
            assertionFailure("""
                Two owners are stepping the WorldCamera ("\(owner)" and \
                "\(callerID)"). Host contract H1 allows exactly one — the \
                world's frame closure. A second stepper double-advances every \
                settle and produces motion above the optical-flow ceiling.
                """)
        }
        stepOwner = callerID
        #endif

        var dt: TimeInterval = 0
        if let last = lastFrameDate { dt = date.timeIntervalSince(last) }
        lastFrameDate = date

        camera.step(dt: dt)

        // W07 / ruling 9. Written after the step, so the sim's gate for this
        // frame reflects the camera position this frame will draw. A plain
        // var on GameViewModel — writing it here does not publish.
        game.simActive = simActive

        if camera.isAtRest { worldSettled() }
    }

    // Clears the moving half of the pause predicate (H3).
    //
    // The arrival of a settle is only observable from inside the frame
    // closure, so this write is DEFERRED to the next main-queue hop, exactly
    // as GameViewModel defers its chain-pop events and for exactly the same
    // reason: the render pass may never publish.
    func worldSettled() {
        guard worldMoving else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // RE-CHECKED ON ARRIVAL. A touch can be delivered between the
                // frame that queued this and the hop that runs it; that touch
                // sets `worldMoving` true and hands the camera to her finger,
                // and clearing the flag underneath it would pause the
                // TimelineView over a camera that is no longer at rest —
                // the frozen world H3 exists to prevent, reached by the one
                // path the deferral opens.
                guard self.camera.isAtRest else { return }
                self.worldMoving = false
            }
        }
    }
}
