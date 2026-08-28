import CoreGraphics
import Foundation

// ANIMA — Vesper's 2-D animation engine. This file is time: easings and
// keyframed curves. Nothing here knows what a shape is.
//
// ─────────────────────────────────────────────────────────────────────────
// WHY THIS EXISTS AT ALL, given the game already animates.
//
// It does, but only in two ways: the simulation moves things with physics,
// and views ease a single value with SwiftUI. Neither can express "the ear
// droops, then the body settles, then it looks up" — a performance, timed.
// Every object in the game that needed one got its own bespoke Swift
// (`AnimalMotion`, the fuse verlet, the firework phases), which is exactly
// why a new 2-D object costs an engineer a day rather than an author an
// hour.
//
// A curve is the cheapest possible fix: a list of (time, value) with a shape
// between them. Authoring becomes data.
//
// ─────────────────────────────────────────────────────────────────────────
// PURITY, AND WHAT IT BUYS.
//
// Foundation and CoreGraphics only — no SwiftUI, no UIKit, no wall-clock,
// same discipline as `GameSimulation` and for a bigger reason here: because
// sampling is pure, the SAME sample can be drawn on the glass, asserted in a
// test, and exported to a previewer that runs in a browser. That last one is
// the whole economics of this engine (see `AnimaStudio`): an author who can
// see a change in a browser does not need Xcode, a simulator, or an
// engineer.
//
// EVERYTHING IS IN SECONDS, never frames. A curve sampled at 0.31 s is the
// same pose on a 60 Hz phone, a 120 Hz phone, and in a test that never drew
// anything.

// MARK: - Easing

/// How a value travels from one key to the next.
///
/// THESE ARE THE ANIMATION PRINCIPLES, NOT A UI EASING SET. `anticipate`,
/// `overshoot` and `settle` are the three that make procedural motion read as
/// performed rather than computed, and they are the three that a designer
/// reaches for constantly and cannot express with `easeInOut`. Naming them
/// here is what lets an author say "it winds up before it goes" in data.
///
/// EVERY CASE SATISFIES f(0) == 0 AND f(1) == 1 EXACTLY. That is not a
/// nicety: keys are absolute values, so an easing that missed its endpoint
/// would leave a visible step at every key, and the error would accumulate
/// differently at every frame rate. `anticipate`, `overshoot` and `settle`
/// deliberately leave the 0...1 range in the MIDDLE — that is what they are
/// for — but they always arrive. `AnimaTests` holds all of them to it.
enum AnimaEase: Equatable {

    /// No shaping. Mechanical on purpose: useful for a value that is not
    /// motion — an opacity ramp, a colour blend.
    case linear

    /// Slow out of the key. Weight starting to move.
    case easeIn

    /// Slow into the key. The default for anything arriving.
    case easeOut

    /// Slow at both ends. The default for anything that both starts and stops
    /// within one key span.
    case easeInOut

    /// Winds up in the wrong direction before going. `k` is how far it pulls
    /// back, as a fraction of the span; 1.7 is the classic value and anything
    /// over ~3 reads as a mistake rather than a wind-up.
    case anticipate(Double)

    /// Passes the target and comes back to it. The single cheapest thing that
    /// makes a rigid transform look like a soft object. Same `k` scale.
    case overshoot(Double)

    /// Passes the target and rings down to it over several diminishing
    /// swings. `damping` is how quickly the ringing dies — 4 is loose and
    /// rubbery, 12 is a firm settle, below ~2 keeps wobbling past the key and
    /// reads as broken.
    case settle(Double)

    /// No travel at all: the value stays at the previous key until this one,
    /// then jumps. For anything that switches rather than moves — a blink, a
    /// facing flip.
    case hold

    /// Shapes a normalised 0...1 progress.
    ///
    /// TOTAL, INCLUDING FOR NaN — and the guard below is why, because clamping
    /// alone is NOT total. `min(max(.nan, 0), 1)` is `.nan` in Swift: every
    /// comparison against NaN is false, so both clamps pass their input
    /// straight through. This claimed totality before it had it, and
    /// `testEasingsAreTotalAndFinite` failed once for each of the fourteen
    /// easings, which is exactly what a test that names its invariant is for.
    ///
    /// A non-finite progress answers 0 — the rest pose. A NaN time means
    /// "unknown", and holding at the beginning is the one answer that cannot
    /// put geometry somewhere surprising; propagating the NaN would silently
    /// stop the part being drawn at all, which is the hardest failure of this
    /// kind to trace back to its cause.
    func shape(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        let t = min(max(progress, 0), 1)
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            let inv = 1 - t
            return 1 - inv * inv
        case .easeInOut:
            if t < 0.5 { return 2 * t * t }
            let inv = 1 - t
            return 1 - 2 * inv * inv
        case .anticipate(let k):
            // Back-in. f(0) = 0 and f(1) = (k+1) - k = 1, exactly.
            let c = max(0, k)
            return (c + 1) * t * t * t - c * t * t
        case .overshoot(let k):
            // Back-out — the mirror of the above. f(0) = 1 - (k+1) + k = 0.
            let c = max(0, k)
            let u = t - 1
            return 1 + (c + 1) * u * u * u + c * u * u
        case .settle(let damping):
            // A damped cosine, then a LINEAR CORRECTION so it lands exactly.
            //
            // The raw ring is 1 - e^(-d·t)·cos(ω·t): correct at t = 0, and at
            // t = 1 it is off by however much swing is left. Adding
            // (1 - raw(1))·t fixes the endpoint without disturbing the start
            // (the correction is zero there) and without flattening the
            // ringing in between, which a rescale would.
            let d = max(0.5, damping)
            let w = Double.pi * 3
            func raw(_ x: Double) -> Double { 1 - exp(-d * x) * cos(w * x) }
            return raw(t) + (1 - raw(1)) * t
        case .hold:
            return t >= 1 ? 1 : 0
        }
    }
}

// MARK: - Keys

/// One authored moment: "at this time, be this value, having got here like
/// this".
///
/// `ease` describes the approach TO this key, not away from it. That is the
/// convention every animation tool uses and it is worth stating, because the
/// opposite convention makes the first key's easing meaningless and the last
/// key's unreachable.
struct AnimaKey: Equatable {
    var time: Double
    var value: Double
    var ease: AnimaEase

    init(_ time: Double, _ value: Double, _ ease: AnimaEase = .easeInOut) {
        self.time = time
        self.value = value
        self.ease = ease
    }
}

// MARK: - Curves

/// A keyframed scalar over time.
///
/// DEFENSIVE BY CONSTRUCTION. Keys are sorted at init and an empty curve is
/// representable and answers a constant. Authoring is data, and data gets
/// typed by hand — a curve that trapped on unsorted keys would turn a typo in
/// a catalog into a crash on a customer's phone.
struct AnimaCurve: Equatable {

    private(set) var keys: [AnimaKey]

    /// Whether time wraps at `duration`. A loop is how an idle is written —
    /// a breath, a blink, a drift — and it costs nothing but a modulo.
    var loops: Bool

    /// The value before the first key and after the last, when not looping.
    /// Held, never extrapolated: an extrapolating curve run for two minutes
    /// leaves the screen, and something that leaves the screen because nobody
    /// touched it is the least debuggable class of bug there is.
    var duration: Double { keys.last?.time ?? 0 }

    init(_ keys: [AnimaKey], loops: Bool = false) {
        self.keys = keys.sorted { $0.time < $1.time }
        self.loops = loops
    }

    /// A curve that never changes. Useful as a neutral element and as the
    /// answer for a channel nobody authored.
    static func constant(_ value: Double) -> AnimaCurve {
        AnimaCurve([AnimaKey(0, value, .linear)])
    }

    /// The value at an absolute time in seconds.
    ///
    /// A non-finite time answers the first key, for the same reason
    /// `AnimaEase.shape` answers 0: it is the rest position, and it cannot
    /// propagate a NaN into a transform where it would quietly delete a part.
    func value(at time: Double) -> Double {
        guard let first = keys.first else { return 0 }
        guard time.isFinite else { return first.value }
        guard keys.count > 1, let last = keys.last else { return first.value }

        var t = time
        if loops {
            let span = last.time - first.time
            if span > 0 {
                // `truncatingRemainder` is signed, so a negative time — which
                // `AnimaPart.lag` produces at the very start of every clip
                // that uses follow-through — would land before the first key
                // and hold there instead of wrapping. Adding one span back
                // makes the wrap correct in both directions.
                var phase = (t - first.time).truncatingRemainder(dividingBy: span)
                if phase < 0 { phase += span }
                t = first.time + phase
            }
        }

        if t <= first.time { return first.value }
        if t >= last.time { return last.value }

        // Linear scan. Curves in this engine are a handful of keys — the
        // longest in the library is nine — and a binary search over nine
        // elements is slower than the scan and harder to read.
        var previous = first
        for key in keys.dropFirst() {
            if t <= key.time {
                let span = key.time - previous.time
                guard span > 0 else { return key.value }
                let progress = (t - previous.time) / span
                let shaped = key.ease.shape(progress)
                return previous.value + (key.value - previous.value) * shaped
            }
            previous = key
        }
        return last.value
    }
}
