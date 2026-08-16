import SwiftUI
import UIKit

// The UIKit host for InputArbiter: one UIView, raw touches, no recognizers.
//
// WHY NO GESTURE RECOGNIZERS (ruling 5). v1.2 already learned that SwiftUI
// gestures over a continuously-redrawing TimelineView/Canvas silently drop
// taps (see TapCatcherView's header). The obvious next step — add a
// UIPanGestureRecognizer beside the tap recognizer and wire
// require(toFail:) — reintroduces the exact disambiguation delay and
// swallowed-touch behavior that made this layer UIKit in the first place,
// and it does it to the pop, the one interaction that must never be delayed.
// So there is no recognizer here at all. The ruling's
// `delaysTouchesBegan = false` / `cancelsTouchesInView = false` are satisfied
// structurally rather than by assignment: those are properties of
// UIGestureRecognizer, and this view owns none. Do not add one.
//
// WHY THIS VIEW MUST NEVER BE REBUILT (ruling 8). v1.2's own comment in
// ContentView blames rebuilds for cancelled taps: when the view hosting a
// touch is torn down and remade, in-flight touches are cancelled. The camera
// moves continuously, so if this layer sits anywhere downstream of the
// camera's offset it is rebuilt every frame of every swipe and the pop dies
// mid-gesture. Rules for whoever composes WorldView:
//
//   * Keep WorldInputLayer a stable sibling in the ZStack, at a fixed
//     position in the view tree. Never inside the moving world body.
//   * Never apply the camera offset, a transform, or .id() to it.
//   * Never let its position in the tree depend on `place` or on any
//     per-frame value. Ruling 7 keeps the camera offset out of @Published
//     precisely so this subtree is not invalidated 120 times a second.
//   * Reassigning the closures in updateUIView is fine — that updates the
//     existing UIView and does not change its identity.
//
// The view is intentionally dumb: it converts UITouch into arbiter calls and
// forwards outcomes. Every decision lives in the pure struct so it can be
// proven in CI (VesperTests/WorldInputTests.swift).
final class WorldInputView: UIView {

    // MARK: Wiring

    // Asked at touch-down only: does this point land on a live orb?
    // Mirrors GameSimulation.tap's hit test (radius + GameConfig.tapTolerance)
    // so the arbiter and the sim can never disagree about what an orb is.
    var isOrb: (CGPoint) -> Bool = { _ in false }

    // Outcomes are delivered synchronously on the main thread, in order.
    var onOutcome: ([InputOutcome]) -> Void = { _ in }

    var fieldAtRest: Bool {
        get { arbiter.fieldAtRest }
        set { arbiter.fieldAtRest = newValue }
    }

    private var arbiter = InputArbiter()

    // The one touch that steers the camera. Extra fingers still reach the
    // arbiter (and still pop) but are not tracked for panning.
    private weak var steeringTouch: UITouch?

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        // Extra fingers must be delivered, not coalesced away, or a second
        // thumb landing on an orb pops nothing (ruling 4: the pop always wins).
        isMultipleTouchEnabled = true
        // Never claim exclusivity — the buttons and whispers that live in
        // sibling layers must stay reachable.
        isExclusiveTouch = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The distance gate and the dead zones are fractions of screen height,
        // so the arbiter needs the live size. Layout changes (rotation, split
        // view) land here; a size change does not disturb an in-flight touch
        // beyond re-evaluating the gates against the new height.
        arbiter.bounds = bounds.size
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // Leaving the window means no touchesCancelled is guaranteed to
        // arrive; drop the steering touch so the next gesture starts clean.
        if newWindow == nil {
            steeringTouch = nil
            arbiter.reset()
        }
    }

    // MARK: - Raw touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Recovery: if the arbiter still believes it is steering but the
        // touch object is gone (a cancel delivered for a set that did not
        // include it, or the weak reference died), clear it. Without this the
        // arbiter would refuse to adopt any future touch and navigation would
        // be dead for the rest of the session — the worst possible failure
        // for a layer whose whole job is to never lose a touch.
        if arbiter.isTracking && steeringTouch == nil { arbiter.reset() }

        for touch in touches {
            let p = touch.location(in: self)
            let hadSteering = arbiter.isTracking
            let outcomes = arbiter.began(at: p, timestamp: touch.timestamp, onOrb: isOrb(p))
            // Whichever touch the arbiter adopted is the one we follow.
            if !hadSteering && arbiter.isTracking { steeringTouch = touch }
            emit(outcomes)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = steeringTouch, touches.contains(touch) else { return }
        // Coalesced touches carry the intermediate samples a 120 Hz digitizer
        // captured between display frames. Feeding all of them keeps the
        // camera genuinely 1:1 with her finger and gives the velocity gate a
        // history that reflects the flick rather than the frame rate.
        let moves = event?.coalescedTouches(for: touch) ?? [touch]
        for move in moves {
            emit(arbiter.moved(to: move.location(in: self), timestamp: move.timestamp))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = steeringTouch, touches.contains(touch) else { return }
        steeringTouch = nil
        emit(arbiter.ended(at: touch.location(in: self), timestamp: touch.timestamp))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = steeringTouch, touches.contains(touch) else { return }
        steeringTouch = nil
        // Whatever was popped stays popped — there is no outcome that can
        // undo it (ruling 4).
        emit(arbiter.cancelled())
    }

    private func emit(_ outcomes: [InputOutcome]) {
        guard !outcomes.isEmpty else { return }
        onOutcome(outcomes)
    }
}

// MARK: - SwiftUI wrapper

// Same shape as TapCatcherView: makeUIView builds once, updateUIView only
// refreshes the closures, so SwiftUI re-renders never change the UIView's
// identity or cancel an in-flight touch.
struct WorldInputLayer: UIViewRepresentable {
    var isOrb: (CGPoint) -> Bool
    var fieldAtRest: Bool
    var onOutcome: ([InputOutcome]) -> Void

    func makeUIView(context: Context) -> WorldInputView {
        let view = WorldInputView(frame: .zero)
        view.isOrb = isOrb
        view.fieldAtRest = fieldAtRest
        view.onOutcome = onOutcome
        return view
    }

    func updateUIView(_ uiView: WorldInputView, context: Context) {
        uiView.isOrb = isOrb
        uiView.fieldAtRest = fieldAtRest
        uiView.onOutcome = onOutcome
    }
}
