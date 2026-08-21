import CoreGraphics
import Foundation

// WHAT A FIELD IS MADE OF, AND HOW THAT GROWS.
//
// Until now every field was the same shape: 7–20 plain orbs, all present at
// once, and the field was over when the last one went. That is a minute of
// play with nothing to discover in it, which is the "too short" and the "too
// easy" in the owner's note after his first session.
//
// THE RULE THIS FILE IS BUILT AROUND: more engaging, not more difficult
// (owner's words). Nothing here can be failed, timed out of, or lost. Fields
// get *longer* and *more varied* — they do not get *harder*. Concretely:
//
//   * A splitter turns one pop into several. That is more popping per touch,
//     not a smaller target — the children are big enough to hit easily.
//   * A drifter eases away from a finger at mid-range and STOPS RUNNING when
//     you get close (see `GameConfig.evadeSurrenderRadius`). It can always be
//     caught by anyone who wants it; it is a tease, not a chase.
//   * A generator makes orbs while it is open, so the field sustains instead
//     of draining. It closes by its own rule and closing costs her nothing.
//
// Everything is deterministic from the seeded RNG, and everything here is a
// value type with no UI in it.

// MARK: - What one orb is

enum OrbKind: Equatable {
    /// The v1.0 orb. Still the whole of a first field.
    case plain

    /// Pops into `remaining + 1` generations of smaller orbs. Nested dolls.
    case splitter(remaining: Int)

    /// Eases away from a nearby finger, and gives up when it is cornered or
    /// closely approached.
    case drifter

    /// Makes orbs while it is open.
    case generator(Generator)
}

// MARK: - Generators

/// A pop generator: it emits orbs on an interval until it closes.
///
/// **How it closes is the design decision the owner delegated** ("the pop
/// generators expend mechanism is by your design"). All three of the modes he
/// listed are here, because they feel different and a field is more
/// interesting when it holds more than one:
///
///   * `.taps` — press it and it gives you an orb; press it enough times and
///     it opens out into a pop of its own. The most interactive: she is
///     *working* it, and the last press is a reward.
///   * `.quota` — it has so many orbs in it and then it is spent. Predictable;
///     the field visibly drains toward quiet.
///   * `.settles` — it closes on its own after a while. The calmest, and the
///     only one that needs a word of care: see the note on `settles` below.
struct Generator: Equatable {

    enum Closing: Equatable {
        /// Closes on the `remaining`-th tap. Every tap before that yields an
        /// orb and leaves the generator open.
        case taps(remaining: Int)

        /// Closes once it has emitted `remaining` more orbs.
        case quota(remaining: Int)

        /// Closes by itself after `remaining` frames.
        ///
        /// THIS IS THE ONE THAT COULD HAVE BROKEN GUARDRAIL 1, and the shape
        /// it takes is deliberate. A thing on a countdown invites urgency —
        /// "get it before it goes" — and urgency is the one feeling this game
        /// exists to not produce. So: there is no countdown drawn anywhere, no
        /// warning state, no sound when it closes, and *nothing is lost when
        /// it does*. It has already given what it gave; the pops she made from
        /// it are counted and kept. It simply stops, the way a thing settles.
        /// The field does not end until the field is clear either way, so
        /// there is never a race against it.
        case settles(remaining: CGFloat)
    }

    var closing: Closing

    /// Frames between emissions.
    var interval: CGFloat

    /// Frames accumulated toward the next emission.
    var sinceLast: CGFloat = 0
}

// MARK: - The plan for one field

/// The composition of a single field, derived from her stage.
struct FieldPlan: Equatable {
    var orbCount: Int
    var splitters: Int
    var drifters: Int
    var generators: Int

    /// How many further generations a splitter produces. 1 = children only,
    /// 2 = children and grandchildren.
    var splitDepth: Int

    /// The highest stage that changes anything. Past this, fields hold steady
    /// rather than growing without end — a field that never stops arriving is
    /// a field she cannot finish, and finishing is the point.
    static let finalStage = 6

    /// **The curve.** Stage 0 is exactly the game as it shipped, because a
    /// first field should be the thing she already knows how to enjoy. Each
    /// stage after introduces ONE idea and gives the previous one room to
    /// settle — the mechanics arrive one at a time, never in a crowd.
    ///
    /// | stage | what is new |
    /// |---|---|
    /// | 0 | plain orbs, as v1.0 |
    /// | 1 | a fuller field |
    /// | 2 | **splitters** — one pop becomes several |
    /// | 3 | **drifters** — one orb teases the finger |
    /// | 4 | **generators** — the field makes more of itself |
    /// | 5 | splitters go two deep |
    /// | 6 | a second generator, and the field's full shape |
    static func forStage(_ stage: Int) -> FieldPlan {
        let s = max(0, min(stage, finalStage))
        switch s {
        case 0:  return FieldPlan(orbCount: 10, splitters: 0, drifters: 0, generators: 0, splitDepth: 0)
        case 1:  return FieldPlan(orbCount: 13, splitters: 0, drifters: 0, generators: 0, splitDepth: 0)
        case 2:  return FieldPlan(orbCount: 13, splitters: 2, drifters: 0, generators: 0, splitDepth: 1)
        case 3:  return FieldPlan(orbCount: 14, splitters: 2, drifters: 1, generators: 0, splitDepth: 1)
        case 4:  return FieldPlan(orbCount: 14, splitters: 3, drifters: 1, generators: 1, splitDepth: 1)
        case 5:  return FieldPlan(orbCount: 15, splitters: 3, drifters: 2, generators: 1, splitDepth: 2)
        default: return FieldPlan(orbCount: 16, splitters: 4, drifters: 2, generators: 2, splitDepth: 2)
        }
    }

    // MARK: - Growth: depth along the Path, and on return

    /// How many orbs this field actually holds, once its place on the Path
    /// and how often she has been here are taken into account.
    ///
    /// **Growth is in DEPTH, not in crowding.** Only
    /// `GameConfig.surfaceCapacity` orbs are ever on the glass at once; the
    /// rest wait below and rise as room is made. That separation is what
    /// makes compounding growth safe — a field twice the size takes longer
    /// and never looks busier.
    ///
    /// Both curves are capped, and the cap is not a compromise. 1.2× per
    /// generation reaches 38× by generation twenty and 5,000× by generation
    /// fifty; a field that cannot be finished in an evening is not a bigger
    /// field, it is a broken one. `GameConfig.maxFieldOrbs` is where growth
    /// stops meaning anything, and the same reasoning caps `finalStage`.
    static func totalOrbs(base: Int, generation: Int, plays: Int) -> Int {
        let depth = pow(GameConfig.depthGrowthPerGeneration, Double(max(0, generation)))
        let replayIndex = min(max(0, plays), GameConfig.replayMultipliers.count - 1)
        let replay = GameConfig.replayMultipliers[replayIndex]
        // CLAMPED IN DOUBLE SPACE, BEFORE THE CONVERSION, and that is not a
        // style choice. 1.2^400 is about 1e31; `Int(1e32)` is not
        // representable and converting it traps — so a Path deep enough would
        // not have produced a huge field, it would have crashed the app on
        // seeding. The cap has to be applied while the number is still a
        // Double.
        let grown = Double(base) * depth * replay
        let capped = min(Double(GameConfig.maxFieldOrbs), max(Double(base), grown))
        return Int(capped.rounded())
    }

    /// How many of those start on the surface.
    static func surfaceCount(total: Int) -> Int {
        min(total, GameConfig.surfaceCapacity)
    }

    /// Stage from lifetime fields cleared. Slow on purpose: three fields at
    /// each step means a new idea lands roughly once an evening rather than
    /// three in the first sitting.
    static func stage(forFieldsCleared cleared: Int) -> Int {
        min(finalStage, max(0, cleared) / 3)
    }

    /// Orbs that must be popped to clear this field, counting what splitters
    /// will become. Used by the points/telemetry side and by tests that assert
    /// a field actually got longer.
    var reachableOrbs: Int {
        var total = orbCount
        var generation = splitters
        for _ in 0..<max(0, splitDepth) {
            generation *= GameConfig.splitChildCount
            total += generation
        }
        return total
    }
}
