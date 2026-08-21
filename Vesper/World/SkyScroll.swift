import Combine
import CoreGraphics
import Foundation
// For `withAnimation` only. This is the SwiftUI-facing half of the feature —
// the pure half is `SkyScrollMetrics` and `InputArbiter.split`, and neither
// imports anything.
import SwiftUI

// THE SKY'S OWN SCROLL (owner: "add a scroll mechanic to the sky, as it
// expands, and it should be natural").
//
// Until now the sky fitted every generation into one screenful by compressing
// the row gap until it hit the touch target and then windowing away whatever
// still did not fit. That is a reasonable thing to do to a map that is two
// stones tall. It is the wrong thing to do to a map that accrues forever
// (W08): the tree either squashes into a ladder or her history is simply not
// reachable. A tree that grows has to be a thing you can look up and down.
//
// WHAT SCROLLING MEANS HERE, EXACTLY. The tree hangs from the top and grows
// downward, so:
//
//     offset == 0            the growing tip is at the foot of the screen —
//                            the place she is standing, and where every
//                            arrival rests.
//     offset  > 0            the content has been pushed DOWN by that many
//                            points, revealing older generations above it.
//                            This is looking back along the path.
//
// There is no offset below zero. There is nothing under the tip but the field.
//
// WHY THE REST POSITION IS THE TIP AND NOT THE ROOT. The tip is the only part
// of the sky that is interactive — the stones she can actually choose next
// hang off it. History is scenery. A place opens on the thing you came for.
//
// GOING HOME IS NEVER BEHIND A SCROLL. Two of the three ways out do not touch
// this file at all: the `the field` whisper is a permanent sibling above the
// input layer, and VoiceOver's escape is wired in `SkyView`. The third — the
// swipe down — passes through the scroll first, exactly the way a scroll view
// inside a pager does: her finger walks back up her own path, and when the
// path runs out the same unbroken gesture carries her to the field. She never
// has to lift her finger and try again. See `InputArbiter.split`.
//
// ISOLATION. `SkyScrollState` is `@MainActor` because it is driven from UIKit
// touch callbacks and read from a SwiftUI body. `SkyScrollMetrics` is plain
// data and travels freely.

// MARK: - The metrics (pure)

/// How much sky there is to look back through, and how far back she is.
///
/// Pure, `Equatable`, and unit-tested: every sign question in this feature is
/// settled here rather than in a view.
struct SkyScrollMetrics: Equatable {

    /// How far the root of the drawn tree sits ABOVE the sky's ceiling, in
    /// points, when the tip is at rest. Zero for any map short enough to fit.
    var history: CGFloat

    init(history: CGFloat = 0) {
        self.history = max(0, history)
    }

    /// The furthest back she may travel.
    ///
    /// CAPPED, ON PURPOSE. A 200-generation path is ~23,000 pt of trace and an
    /// uncapped scroll would turn "look back at where I've been" into a chore
    /// with no bottom. The cap is what makes "the road disappears behind"
    /// (W08) true in the sky without anything being deleted from the map —
    /// the store still holds every stone, this view simply stops drawing the
    /// oldest of them.
    var maxOffset: CGFloat { min(history, SkyLayout.maximumHistory) }

    /// Points of scroll still available in a given FINGER direction, from the
    /// given offset. Never negative.
    ///
    /// Sign convention (the same one as `InputArbiter`, and the only place it
    /// is converted): a finger moving DOWN drags the content down with it and
    /// reveals what is above — the older generations. A finger moving UP
    /// returns toward the tip.
    func room(_ direction: WorldDirection, at offset: CGFloat) -> CGFloat {
        switch direction {
        case .down: return max(0, maxOffset - clamped(offset))
        case .up:   return max(0, clamped(offset))
        }
    }

    func clamped(_ offset: CGFloat) -> CGFloat {
        min(max(0, offset), maxOffset)
    }
}

// MARK: - The state

/// The sky's scroll position, and nothing else.
///
/// ITS OWN `ObservableObject`, DELIBERATELY — NOT a `@Published` on
/// `WorldModel` (ruling 7's reasoning, applied to a second moving value). A
/// published property on the model invalidates every observer of the model,
/// and `WorldView`'s body is one of them; that body contains
/// `WorldInputLayer`, whose hosted `UIView` must never be rebuilt mid-touch
/// (ruling 8). Publishing a scroll offset at digitizer rate from the model
/// would rebuild the input layer on every frame of every scroll and UIKit
/// would cancel the very touch doing the scrolling. Held here, observed only
/// by `SkyView`, the redraw stops at the one subtree that has to redraw.
///
/// `metrics` is deliberately NOT published: it is measurement, read by the
/// input layer's room closure, and it changes only when the map or the screen
/// changes. Publishing it would be a second invalidation for no visual gain.
@MainActor
final class SkyScrollState: ObservableObject {

    /// How far back along the path she is looking, in points. Always in
    /// `[0, metrics.maxOffset]`.
    @Published private(set) var offset: CGFloat = 0

    private(set) var metrics = SkyScrollMetrics()

    /// Where the offset was when the current gesture armed. Cumulative
    /// translation is added to this, never to the live offset — the same
    /// idempotence argument as `InputArbiter`'s anchor: a dropped or repeated
    /// event costs a frame of smoothness, not a permanent drift.
    private var gestureOrigin: CGFloat = 0

    /// How much of the release velocity carries into the glide, in seconds.
    /// A flick of 1200 pt/s therefore coasts ~170 pt — about a generation and
    /// a half. Deliberately short: this is a quiet place to look back through,
    /// not a feed to fling.
    static let glideSeconds: CGFloat = 0.14

    /// The longest a glide may run.
    static let glideDuration: Double = 0.45

    // MARK: Measurement

    /// Told what the sky is currently drawing. Idempotent; safe to call from
    /// a layout pass every time the map or the screen changes.
    ///
    /// STICKS TO THE TIP. If she was resting at the tip when a new stone
    /// arrived, she stays at the tip — the growing edge is what an arrival
    /// must show. If she had scrolled back to look at something, the offset is
    /// merely re-clamped, so the thing she was looking at does not jump out
    /// from under her.
    func measure(_ metrics: SkyScrollMetrics) {
        guard metrics != self.metrics else { return }
        self.metrics = metrics
        let clamped = metrics.clamped(offset)
        if clamped != offset { offset = clamped }
    }

    // MARK: The gesture

    func began() {
        gestureOrigin = offset
    }

    /// Back to the growing tip, at once.
    ///
    /// Called when she ARRIVES at the sky, because a place opens on the thing
    /// she came for and the tip is the only interactive part of this one — the
    /// stones she can choose next hang off it. Coming back to a sky still
    /// scrolled to where she was reading last time would mean arriving with no
    /// star to press.
    func returnToTip() {
        if offset != 0 { offset = 0 }
        gestureOrigin = 0
    }

    /// `translation` is the FINGER translation this place absorbed, signed by
    /// the arbiter's convention (down is positive). Converting it to an offset
    /// is a straight addition, which is the whole reason the offset was
    /// defined to grow downward.
    func scrolled(by translation: CGFloat) {
        let next = metrics.clamped(gestureOrigin + translation)
        if next != offset { offset = next }
    }

    /// Released. Projects where an exponential deceleration would come to
    /// rest and lets SwiftUI ease there, rather than running a decay on a
    /// frame clock the sky does not own — the world's `TimelineView` may be
    /// paused while she is up here, and a scroll that only moves while the
    /// field happens to be awake is not a scroll.
    ///
    /// Returns where it went and how long the ease took, so a caller — and
    /// above all a test — can read the outcome without waiting on an
    /// animation. The offset is written synchronously either way; the
    /// animation only decides how the glass gets there.
    @discardableResult
    func ended(velocity: CGFloat) -> Glide {
        let glide = projectedGlide(velocity: velocity)
        if glide.duration > 0 {
            withAnimation(.easeOut(duration: glide.duration)) { settle(to: glide) }
        } else {
            settle(to: glide)
        }
        return glide
    }

    /// Where an exponential deceleration would come to rest, and how long to
    /// ease there. Pure — it writes nothing — so the projection can be
    /// asserted on its own.
    func projectedGlide(velocity: CGFloat) -> Glide {
        let projected = metrics.clamped(offset + velocity * Self.glideSeconds)
        let travel = abs(projected - offset)
        // Proportional, and zero for a release that was already still: a fixed
        // duration makes a 4 pt correction feel like syrup, and animating a
        // zero-length change is a frame of work for nothing.
        let duration = min(Self.glideDuration, Double(travel) / 900)
        return Glide(offset: projected, duration: duration)
    }

    private func settle(to glide: Glide) {
        if offset != glide.offset { offset = glide.offset }
        gestureOrigin = glide.offset
    }

    struct Glide: Equatable {
        var offset: CGFloat
        var duration: Double
    }

    // MARK: Room

    /// What the input layer asks for: how far the sky can still move its own
    /// content, in each finger direction.
    var room: ScrollRoom {
        ScrollRoom(up: metrics.room(.up, at: offset),
                   down: metrics.room(.down, at: offset))
    }
}
