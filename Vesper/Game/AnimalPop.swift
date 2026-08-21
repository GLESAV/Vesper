import CoreGraphics
import Foundation

// ANIMAL POPS — the balloon animals.
//
// Owner: "the pops look too similar across the 100 … make animal pops, like a
// balloon animal, that hides across the screen (is hard to pop) and has pop
// health."
//
// THE LINE THIS WALKS. "Hides" and "hard to pop" are, read literally, a
// request for a thing that can be missed and a thing that can be failed —
// which is the one shape this game may not have. A creature that successfully
// evades is not charming, it is a boss fight in a game about going to sleep.
//
// So it is SHY, not evasive, and the difference is entirely in `shyness`,
// which decays. Early in its life it keeps to the edges and eases away from a
// finger; left alone it settles, comes out, and waits in the open. It is hard
// to catch for as long as chasing it is fun and no longer, and nobody has to
// know that is why. The field cannot be finished without it, so it must be
// catchable by everyone, including someone who is tired and not really trying.
//
// `health` is the other half: it takes a few taps, and each one startles it
// into a short dart. That is what makes it feel like a creature rather than a
// target — it reacts — and it is the same mechanic as a `.taps` generator,
// where the last press is the reward.
struct AnimalPop: Equatable {

    /// The silhouette. Balloon animals: a few joined lobes, never a drawing.
    enum Shape: String, CaseIterable {
        case cat, bird, fish, rabbit, fox, bear, deer, frog

        /// Lobes as (offset from centre, radius), both in units of the orb's
        /// radius. Read by the renderer; kept here so the shape and the
        /// creature that has it live in one file.
        var lobes: [(CGPoint, CGFloat)] {
            switch self {
            case .cat:
                return [(CGPoint(x: 0, y: 0.15), 0.86), (CGPoint(x: 0, y: -0.72), 0.52),
                        (CGPoint(x: -0.34, y: -1.08), 0.20), (CGPoint(x: 0.34, y: -1.08), 0.20),
                        (CGPoint(x: 0.78, y: 0.52), 0.20)]
            case .bird:
                return [(CGPoint(x: 0, y: 0.1), 0.80), (CGPoint(x: 0.1, y: -0.74), 0.44),
                        (CGPoint(x: 0.62, y: -0.78), 0.16), (CGPoint(x: -0.72, y: 0.34), 0.34)]
            case .fish:
                return [(CGPoint(x: 0.1, y: 0), 0.88), (CGPoint(x: -0.86, y: -0.3), 0.30),
                        (CGPoint(x: -0.86, y: 0.3), 0.30), (CGPoint(x: 0.66, y: -0.5), 0.22)]
            case .rabbit:
                return [(CGPoint(x: 0, y: 0.22), 0.82), (CGPoint(x: 0, y: -0.62), 0.48),
                        (CGPoint(x: -0.26, y: -1.28), 0.24), (CGPoint(x: 0.26, y: -1.30), 0.24)]
            case .fox:
                return [(CGPoint(x: 0, y: 0.16), 0.84), (CGPoint(x: 0, y: -0.68), 0.50),
                        (CGPoint(x: -0.40, y: -1.06), 0.22), (CGPoint(x: 0.40, y: -1.06), 0.22),
                        (CGPoint(x: -0.86, y: 0.46), 0.28)]
            case .bear:
                return [(CGPoint(x: 0, y: 0.18), 0.92), (CGPoint(x: 0, y: -0.70), 0.54),
                        (CGPoint(x: -0.44, y: -1.02), 0.24), (CGPoint(x: 0.44, y: -1.02), 0.24)]
            case .deer:
                return [(CGPoint(x: 0, y: 0.20), 0.80), (CGPoint(x: 0, y: -0.66), 0.44),
                        (CGPoint(x: -0.36, y: -1.20), 0.18), (CGPoint(x: 0.36, y: -1.20), 0.18),
                        (CGPoint(x: -0.54, y: -1.52), 0.13), (CGPoint(x: 0.54, y: -1.52), 0.13)]
            case .frog:
                return [(CGPoint(x: 0, y: 0.10), 0.90), (CGPoint(x: -0.52, y: -0.62), 0.28),
                        (CGPoint(x: 0.52, y: -0.62), 0.28), (CGPoint(x: -0.88, y: 0.44), 0.24),
                        (CGPoint(x: 0.88, y: 0.44), 0.24)]
            }
        }

        /// Lowercase-calm, for VoiceOver and the journal.
        var name: String { rawValue }
    }

    var shape: Shape

    /// Taps left before it goes. Small on purpose: this is a creature that
    /// reacts, not a thing with a health bar.
    var health: Int

    /// How much it wants to keep to itself, 1 down to 0.
    ///
    /// **This decaying is the whole safety argument.** While it is high the
    /// animal keeps to the edges and eases away from a finger; as it falls it
    /// comes out and waits in the open. The field cannot be finished without
    /// it, so "hard to pop" has to be a phase and never a property — anyone
    /// who simply keeps playing will meet it in the open before long.
    var shyness: CGFloat = 1

    /// A brief impulse after being tapped: it darts, then settles.
    var startle: CGFloat = 0
}
