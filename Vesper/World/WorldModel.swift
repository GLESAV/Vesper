import Combine
import CoreGraphics
import Foundation
// For `UIAccessibility` only (R-A11Y B3). This object is the SwiftUI-facing
// model, not one of the pure ones — `WorldCamera`, `InputArbiter` and
// `GameSimulation` import neither UIKit nor SwiftUI and still do not.
import UIKit

// The world's one observable object, and the seam between three things that
// deliberately cannot see each other: the pure camera (no SwiftUI), the pure
// simulation behind `GameViewModel` (no wall-clock), and SwiftUI itself.
//
// ─────────────────────────────────────────────────────────────────────────
// IT PUBLISHES `place`, `worldMoving` AND `worldAwake`, AND NOTHING ELSE.
//
// The rule this obeys is a blocking acceptance condition carried onto W04 by
// R-ARCH, not a style preference, and the two halves fail in opposite
// directions:
//
//   * publishing MORE — above all the camera's per-frame offset — rebuilds
//     the TimelineView/Canvas/input subtree 120 times a second, which is
//     verbatim the condition v1.2 blames for cancelled taps (ruling 7);
//   * publishing LESS — leaving the pause predicate to read the camera —
//     latches the world frozen mid-settle, because the camera is not
//     observable and nothing about it can wake a SwiftUI view (host contract
//     H3 in WorldCamera.swift, which is written for this file).
//
// THE THIRD VALUE IS W05c, AND IT IS A SPLIT RATHER THAN AN ADDITION.
// R-ARCH wrote the condition as "`place` and `worldMoving` and nothing else"
// at a moment when movement was the only per-frame state the camera had, so
// "keep the frame clock running" and "the world is travelling" were the same
// sentence. The end-of-axis acknowledgement is the item that separates them:
// it is a time envelope that must be stepped every frame WHILE THE CAMERA IS
// AT REST. So the one flag became the two questions it always was:
//
//   worldMoving   mirrors `!camera.isAtRest`. "The world is travelling."
//                 It gates HIT-TESTING (`WorldView.placed`) and rides with
//                 the sim gate — a place's controls must not take the touch
//                 that is trying to catch the world mid-flight.
//   worldAwake    mirrors `!camera.isIdle`. "There is per-frame camera state
//                 here." It gates THE PAUSE PREDICATE, and nothing else.
//
// `worldMoving` implies `worldAwake`, so the render half is strictly weaker
// than the moving half and can never pause anything the W04 predicate kept
// alive. Overloading `worldMoving` with the acknowledgement instead would
// make the sky's stars untappable for the third of a second after every flick
// at the ceiling, breaking W09's ≥ 44 pt targets; pausing on `worldMoving`
// would freeze the envelope mid-glow.
//
// AND IT IS NOT A VALUE DERIVED FROM THE OTHER TWO — the thing R-ARCH refused
// when it refused an `offField` or a published `simActive`. A derived flag is
// stale against its sources for about a frame at each end of every settle,
// which is exactly the window that costs a pop. `worldAwake` is mirrored from
// the camera, in the same handler and on the same frame as `worldMoving`, and
// carries information neither of the other two has.
//
// All three change at most a couple of times per gesture: `place` at the
// commit instant, and each flag once when its condition begins and once when
// it ends.
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

    // "THE WORLD IS TRAVELLING." Mirrors `!camera.isAtRest`. Never derived in
    // a view body, never read from the camera by SwiftUI.
    //
    // Since W05c this is NOT the pause predicate's term — see `worldAwake`
    // below. It gates hit-testing, so widening it to cover anything that is
    // not translation takes controls away from her while the world is
    // standing still.
    @Published private(set) var worldMoving = false

    // "THERE IS PER-FRAME CAMERA STATE; KEEP THE CLOCK RUNNING." Mirrors
    // `!camera.isIdle`, and it is the pause predicate's term (H3, as amended
    // at W05c).
    //
    // It is true for the whole of every settle AND for the whole of every
    // end-of-axis acknowledgement, which is the case `worldMoving` cannot
    // express: at the sky, a flick at the ceiling leaves the camera at rest
    // with an envelope to step, and the W04 predicate would have paused the
    // world over it and frozen the glow at whatever fraction it had reached.
    @Published private(set) var worldAwake = false

    // MARK: - Owned, and deliberately not published

    // Ruling 7 in full: not `@Published`, not `ObservableObject`, and never
    // mirrored into `@State`. The view reads its per-frame scalars inside the
    // TimelineView closure, at the moment it needs them.
    let camera = WorldCamera()

    // The sky's own scroll position. A `let` to a SEPARATE `ObservableObject`,
    // which is ruling 7's reasoning applied to a second moving value rather
    // than an exception to it:
    //
    //   * it is not a `@Published` on this model, because publishing it would
    //     invalidate every observer of the model at digitizer rate — and one
    //     of those observers is `WorldView`'s body, which contains
    //     `WorldInputLayer`, whose hosted `UIView` must never be rebuilt
    //     mid-touch (ruling 8). It would cancel the very touch doing the
    //     scrolling;
    //   * it is not held off-observation like the camera either, because
    //     unlike the camera's offset this one HAS to reach SwiftUI: the stars
    //     are `Button`s in the view tree, not marks in a `Canvas`, so their
    //     positions come from a body evaluation and nothing else.
    //
    // Its own object, observed only by `SkyView`, is what satisfies both: the
    // redraw stops at the one subtree that has to redraw. Assigning to a `let`
    // reference does not fire this model's `objectWillChange`.
    let skyScroll = SkyScrollState()

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

    // MARK: - How much of a drag the current place wants

    /// Answers the input layer's one question about the place she is standing
    /// in: how far it can move its own content before the world should move
    /// instead. Bound as a LIVE closure, never a pushed value.
    ///
    /// Only the sky has an answer, and only while she is actually resting in
    /// it. Both halves matter:
    ///
    ///   * `place == .sky` — a drag on the field must never scroll a sky she
    ///     cannot see, exactly as a touch at the sky must never pop an orb on
    ///     a field she cannot see (`simActive`);
    ///   * `isAtRest` — a transit grab is a grab of the WORLD. She reached out
    ///     to steady something in flight, and every point of that gesture
    ///     belongs to the camera. The arbiter agrees independently (it holds
    ///     `.none` for a transit grab), so this is belt and braces on the one
    ///     decision that could quietly eat a settle.
    var placeScrollRoom: ScrollRoom {
        guard camera.isAtRest, camera.place == .sky else { return .none }
        return skyScroll.room
    }

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

        // The place's own scroll, before the camera and after the pop. The
        // arbiter has already divided the gesture — whatever reaches the
        // camera as `.panChanged` is the leftover — so these two loops are
        // spending different points and cannot double-count her finger.
        for outcome in outcomes {
            switch outcome {
            case .scrollBegan:
                skyScroll.began()
            case .scrollChanged(let translation):
                skyScroll.scrolled(by: translation)
            case .scrollEnded(let velocity):
                // The glide is an animation rather than a decay on a frame
                // clock, because the world's `TimelineView` may well be paused
                // while she is up here (H3) and a scroll that only coasts when
                // the field happens to be awake is not a scroll. It is owned
                // by the scroll state, so this line spends no opinion on it.
                skyScroll.ended(velocity: velocity)
            default:
                break
            }
        }

        camera.consume(outcomes)

        // Mirrored, not published per-frame: `camera.place` changes at most
        // once per commit. Guarded because `@Published` fires on every write,
        // equal or not.
        if place != camera.place {
            place = camera.place
            // ARRIVING AT THE SKY OPENS IT ON THE GROWING TIP. The tip is the
            // only interactive part of the sky — the stones she can choose
            // next hang off it — so a sky still scrolled to wherever she was
            // reading last time would be a place she arrived in with no star
            // to press. Leaving it does nothing, so a glance back at her
            // history costs nothing on the way out either.
            if place == .sky { skyScroll.returnToTip() }
        }

        // H3: set in the SAME handler that feeds the camera. Guarded for the
        // same reason — `.panChanged` arrives at digitizer rate, and an
        // unguarded write here would republish 120 times a second and undo
        // the whole point of ruling 7.
        //
        // BOTH FLAGS, BOTH MIRRORED FROM THE CAMERA, NEITHER DERIVED FROM THE
        // OTHER. `worldAwake` is the one that has to be right on this line for
        // the acknowledgement to exist at all: an axis-gated flick leaves the
        // camera AT REST, so `worldMoving` correctly stays false, and if
        // nothing else were published here the world would stay paused and the
        // envelope would never be stepped. This handler is a UIKit touch
        // callback — outside the render pass — which is what makes publishing
        // from it safe, and it is also the only moment at which an
        // acknowledgement can ever be armed.
        if !worldMoving && !camera.isAtRest { worldMoving = true }
        if !worldAwake && !camera.isIdle { worldAwake = true }
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
        if camera.isIdle { worldQuietened() }
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

    // Clears the pause predicate's own term, once the camera has nothing left
    // to step — no settle in flight AND no acknowledgement still fading.
    //
    // Deferred and re-checked for exactly the reasons `worldSettled` is, and
    // the re-check matters slightly more here: the touch that can land in the
    // gap is the second flick of a rocking sequence at the ceiling, which
    // re-arms an envelope without ever making the camera move. Clearing
    // `worldAwake` underneath it would pause the world over a live glow and
    // leave it frozen part-lit — the exact failure this pair of flags exists
    // to prevent, reached through the one door the deferral opens.
    func worldQuietened() {
        guard worldAwake else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.camera.isIdle else { return }
                self.worldAwake = false
                self.announceArrivalIfPlaceChanged()
            }
        }
    }

    // MARK: - R-A11Y B3: arrival is spoken

    // The last place VoiceOver was told about, so a journey is announced once
    // and a stay is announced never.
    private var lastAnnouncedPlace: Place = .field

    // A WORLD WITH NO CHROME HAS TO SAY SO ITSELF. Every other iOS navigation
    // model hands VoiceOver something to narrate for free — a pushed nav bar,
    // a presented sheet, a selected tab. This one has none of that: travelling
    // moves a camera and flips `place`, and to VoiceOver that is
    // indistinguishable from nothing happening. Tapping `your journal` used to
    // travel the whole world in silence, with the cursor left behind on the
    // whisper she had just tapped.
    //
    // ON ARRIVAL, NOT AT THE COMMIT INSTANT. `place` flips when the commit is
    // resolved, but the world is still travelling then; announcing there would
    // talk over the motion and name a place not yet on screen. This is called
    // from `worldQuietened`, which is the frame the camera has nothing left to
    // do — the moment she has actually arrived.
    //
    // GUARDED ON CHANGE, because `worldQuietened` also runs at the end of an
    // end-of-axis acknowledgement, which moves nothing. Announcing "the field"
    // because she flicked at a wall would be chatter, and chatter is the way
    // VoiceOver support gets switched off.
    private func announceArrivalIfPlaceChanged() {
        guard place != lastAnnouncedPlace else { return }
        lastAnnouncedPlace = place
        UIAccessibility.post(notification: .screenChanged, argument: Self.label(for: place))
    }

    private static func label(for place: Place) -> String {
        switch place {
        case .sky: return Strings.skyA11y
        case .field: return Strings.fieldA11y
        case .journal: return Strings.journalA11y
        }
    }
}
