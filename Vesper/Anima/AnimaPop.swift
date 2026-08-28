import CoreGraphics
import Foundation

// ANIMA — the bridge to the pop paradigm.
//
// ─────────────────────────────────────────────────────────────────────────
// THE HUNDRED ASSETS ARE NOT FREE-STANDING ART.
//
// They are the visual half of the catalogue that already exists. Every one is
// bound to a `PopDefinition` by its number — 1...100, stable forever — and
// takes that pop's own paints, its family, and its family's instrument. An
// asset that invented its own colours would be a picture of a different game.
//
// ─────────────────────────────────────────────────────────────────────────
// THE FOURTH FAMILY SIGNATURE.
//
// `PopFamily` already carries three, and they are the reason the catalogue is
// coherent rather than a hundred unrelated noises: `voice` (the instrument),
// `hapticPattern` (what it says to the hand), and `burst` (how it comes
// apart). This file adds the fourth and most immediate one — SILHOUETTE.
//
// The standard's own argument applies unchanged, and it is worth repeating
// because it is what makes a hundred assets authorable at all:
//
//     "TEN FAMILIES, TEN INSTRUMENTS. The FAMILY is the instrument, and the
//      ten pops inside it are notes on it. The alternative, a hundred
//      hand-authored one-offs, is worse and not better: it is a hundred
//      unrelated noises with nothing to learn, and a player cannot build a
//      memory of something that has no pattern."
//
// Shape is the sense that reads first — before colour, before sound, at arm's
// length, in the dark. So the silhouettes have to be separable as black
// shapes: a disc with a moon, a flame, a drop over a ripple, a flower, a
// crystal, a hanging bar, a lantern, a streamer, a shard, stacked bands.
// If two families could be confused in silhouette, the second one is wrong.
//
// ─────────────────────────────────────────────────────────────────────────
// HOW THE TEN NOTES INSIDE A FAMILY DIFFER.
//
// Through `AnimaVariation` — four knobs the family's own builder interprets.
// The family decides what its axis of variation MEANS; the variation only
// says how far along it this pop sits. That is what keeps ten members of a
// family visibly related and individually distinct, and it is what makes the
// authoring incremental: a batch is ten rows of four numbers, not ten figures.
//
// Until a pop's variation is authored it gets a deterministic default derived
// from its own number, so the library is complete and previewable from the
// first day and each batch replaces derivation with intent.

// MARK: - Variation

/// Where one pop sits along its family's own axes.
///
/// FOUR KNOBS, DELIBERATELY, AND NONE OF THEM NAMED FOR A SHAPE. `trait` means
/// something different in every family — elongation in `tide`, spoke length in
/// `frost`, how open the bands are in `aurora` — because a knob named
/// `earLength` would be meaningless in nine families out of ten and the set
/// would grow until nobody could hold it.
struct AnimaVariation: Equatable {
    /// 0...1 along the family's primary axis.
    var trait: Double
    /// 0...1 along a second, independent axis.
    var accent: Double
    /// How many repeated parts, for the families that have them (petals,
    /// spokes, bands). Clamped by each builder to what it can draw.
    var count: Int
    /// A whole-figure rotation, in radians. The cheapest per-pop difference
    /// there is, and it reads instantly.
    var tilt: Double

    init(trait: Double = 0.5, accent: Double = 0.5, count: Int = 5, tilt: Double = 0) {
        self.trait = min(max(trait, 0), 1)
        self.accent = min(max(accent, 0), 1)
        self.count = count
        self.tilt = tilt
    }

    /// The variation a pop gets before anyone has authored one for it.
    ///
    /// DERIVED FROM THE POP'S OWN NUMBER, not random: the same pop is the same
    /// shape on every device and in every run, which is the same guarantee
    /// `PopCatalog` and `SeededRandom` already make. Spread with a small
    /// multiplier so consecutive numbers inside a family land far apart rather
    /// than drifting slowly through the range.
    static func derived(from number: Int) -> AnimaVariation {
        let n = Double(max(0, number - 1))
        func wrapped(_ step: Double, _ phase: Double) -> Double {
            let v = (n * step + phase).truncatingRemainder(dividingBy: 1)
            return v < 0 ? v + 1 : v
        }
        return AnimaVariation(trait: wrapped(0.37, 0.11),
                              accent: wrapped(0.61, 0.43),
                              count: 4 + Int(n.truncatingRemainder(dividingBy: 4)),
                              tilt: (wrapped(0.23, 0.07) - 0.5) * 0.7)
    }
}

// MARK: - The silhouette signature

extension PopFamily {

    /// This family's form, at one variation, in the pop's own paints.
    ///
    /// Every builder observes the engine's own conventions: exactly one root
    /// part, named `body`, with everything else descending from it — which is
    /// what makes `wake` and `release` work on all hundred without being
    /// written a hundred times.
    ///
    /// `paints` comes from the bound `PopDefinition`. Index 0 is the body,
    /// index 1 the accent where a family has one; a family asked for a paint
    /// the pop does not have falls back to index 0 rather than inventing one.
    func figure(_ name: String,
                variation v: AnimaVariation,
                paints: [PopPaint]) -> AnimaFigure {
        // A pop with no paints at all is not representable in the catalogue,
        // but a figure whose parts index an empty palette draws nothing and
        // says nothing about why. One paint is enough to be safe, and the
        // fallback is the library's own off-white rather than an invention.
        let palette = paints.isEmpty ? [AnimaLibrary.offWhite] : paints
        let accent = palette.count > 1 ? 1 : 0
        let parts = build(v, accent: accent)
        return AnimaFigure(name, parts: parts, paints: palette)
    }

    private func build(_ v: AnimaVariation, accent: Int) -> [AnimaPart] {
        // A whole-figure tilt, applied to the root so everything inherits it.
        func root(_ primitive: AnimaPrimitive,
                  scale: Double,
                  paint: Int = 0,
                  depth: Int = 6) -> AnimaPart {
            AnimaPart("body", primitive,
                      rest: AnimaTransform(offset: .zero, rotation: v.tilt, scale: scale),
                      paint: paint, depth: depth)
        }
        let n = min(max(v.count, 3), 9)

        switch self {

        // VESPER — the original dusk. A disc with a smaller one beside it:
        // the base pop, and the only family that must still read as an orb.
        case .vesper:
            return [
                root(.disc, scale: 0.86),
                AnimaPart("moon", .disc, parent: "body",
                          rest: AnimaTransform(offset: CGPoint(x: 0.72 + 0.4 * v.trait,
                                                               y: -0.52 - 0.3 * v.accent),
                                               scale: 0.24 + 0.16 * v.accent),
                          paint: accent, depth: 8, lag: 0.05)
            ]

        // EMBER — a flame, and sparks leaving it. Points up; nothing else in
        // the set does.
        case .ember:
            // −π/2 SO THE FLAME STANDS UP. A limaçon petal's fat end is at
            // local θ = π (its −x side), so an unrotated one lies on its
            // side; a flame's mass is at its base and it tapers upward.
            var parts = [AnimaPart("body", .petal(sharpness: 0.55 + 0.35 * v.trait),
                                   rest: AnimaTransform(offset: .zero,
                                                        rotation: v.tilt - .pi / 2,
                                                        scale: 0.9),
                                   paint: 0, depth: 6)]
            for i in 0..<min(n, 5) {
                let a = Double.pi * (0.25 + 0.5 * Double(i) / Double(max(1, n - 1)))
                parts.append(
                    AnimaPart("spark-\(i)", .disc, parent: "body",
                              rest: AnimaTransform(
                                  offset: CGPoint(x: cos(-a) * (1.05 + 0.3 * v.accent),
                                                  y: sin(-a) * (1.05 + 0.3 * v.accent)),
                                  scale: 0.10 + 0.07 * v.accent),
                              paint: accent, depth: 9, lag: 0.02 * Double(i + 1))
                )
            }
            return parts

        // TIDE — a drop over a ripple.
        //
        // `accent` MOVES THE RIPPLE'S SIZE, not only its sweep. It changed
        // sweep alone at first, which left all ten members of the family with
        // an identical silhouette extent — and the spread test caught it,
        // correctly. A wider swell genuinely reaches further, so "High Tide:
        // everything the sea meant to say at once" must visibly out-reach
        // "Lagoon: shallow enough to see your own feet". Sweep alone cannot
        // say that.
        case .tide:
            return [
                // +π/2 so the drop's fat end falls TOWARD the ripple below
                // it. Unrotated it lies on its side, which reads as neither a
                // drop nor anything else.
                AnimaPart("body", .petal(sharpness: 0.30 + 0.45 * v.trait),
                          rest: AnimaTransform(offset: .zero,
                                               rotation: v.tilt + .pi / 2,
                                               scale: 0.78),
                          paint: 0, depth: 6),
                AnimaPart("ripple", .arc(sweep: 2.0 + 1.6 * v.accent, thickness: 0.10),
                          parent: "body",
                          rest: AnimaTransform(offset: CGPoint(x: 0, y: 0.85 + 0.25 * v.accent),
                                               rotation: .pi / 2,
                                               scale: 0.50 + 0.30 * v.accent),
                          paint: accent, depth: 3, lag: 0.07)
            ]

        // BLOOM — petals about a heart.
        case .bloom:
            var parts = [root(.disc, scale: 0.28)]
            for i in 0..<n {
                let a = 2 * Double.pi * Double(i) / Double(n) - Double.pi / 2
                let reach = 1.7 + 0.6 * v.trait
                parts.append(
                    // `a + π`, NOT `a`. THE PETALS WERE POINTING INWARD.
                    //
                    // A limaçon petal's fat end sits at local θ = π — its −x
                    // side — so rotating it by the same angle as its offset
                    // turns the fat end back toward the centre. Every bloom
                    // folded its petals over its own heart, and because the
                    // offset and the scale are equal, the tips landed exactly
                    // on the origin: the whole family drew at a fraction of
                    // its intended size and every one of the ten measured an
                    // identical extent.
                    //
                    // That is what the spread test caught. It was written to
                    // stop ten pops being one shape at ten sizes and it found
                    // a family drawn inside out.
                    AnimaPart("petal-\(i)", .petal(sharpness: 0.45 + 0.4 * v.accent),
                              parent: "body",
                              rest: AnimaTransform(offset: CGPoint(x: cos(a) * reach,
                                                                   y: sin(a) * reach),
                                                   rotation: a + .pi, scale: reach),
                              paint: accent, depth: 3, lag: 0.02 * Double(i))
                )
            }
            return parts

        // FROST — a radial crystal. Spokes, not petals: hard and thin.
        case .frost:
            // A SPOKE'S `scale` SHRINKS ITS LENGTH AS WELL AS ITS THICKNESS,
            // and the first numbers here forgot it: a scale of 0.13 on a
            // length-3 capsule is a 0.2-unit stub, so the "radial crystal"
            // never left the 1.0 reach floor and all ten members measured
            // identically — the same failure bloom had, arriving by a
            // different route.
            //
            // Length is in units of the capsule's OWN radius, so a long thin
            // spoke needs a large `length` and a modest `scale`, not a small
            // scale on a short one.
            var parts = [root(.polygon(sides: 6, roundness: 0.15), scale: 0.42)]
            for i in 0..<n {
                let a = 2 * Double.pi * Double(i) / Double(n)
                parts.append(
                    AnimaPart("spoke-\(i)", .capsule(length: 4.0 + 2.4 * v.trait),
                              parent: "body",
                              rest: AnimaTransform(offset: CGPoint(x: cos(a) * 1.5,
                                                                   y: sin(a) * 1.5),
                                                   rotation: a,
                                                   scale: 0.32 + 0.12 * v.accent),
                              paint: accent, depth: 4, lag: 0.012 * Double(i % 3))
                )
            }
            return parts

        // CHIME — a hanging bar. Vertical, plain, and struck.
        case .chime:
            // AUTHOR A THICKNESS AND A HALF-LENGTH, THEN DERIVE `length`.
            //
            // For a capsule, `scale` is the RADIUS and `length` is measured in
            // radius units — so scaling a bar down to make it thin makes it
            // short as well, and the two ideas a chime needs to express ("long
            // and slender", "short and thick") collapse into one. Written the
            // naive way this family had nine of its ten members sitting on the
            // 1.0 reach floor, indistinguishable.
            //
            // Choosing the two quantities the family actually varies and
            // dividing for `length` keeps them independent.
            let thickness = 0.15 + 0.11 * v.accent
            let halfLength = 0.90 + 0.32 * v.trait
            return [
                AnimaPart("body", .capsule(length: 2 * halfLength / thickness),
                          rest: AnimaTransform(offset: .zero, rotation: v.tilt,
                                               scale: thickness),
                          paint: 0, depth: 6),
                // Sat at the bar's own end: the offset is in body-local units,
                // so it is the half-length divided by the thickness, plus a
                // little clearance.
                AnimaPart("hanger", .arc(sweep: 2.4, thickness: 0.18), parent: "body",
                          rest: AnimaTransform(offset: CGPoint(x: 0,
                                                               y: -(halfLength / thickness + 0.3)),
                                               rotation: -.pi / 2, scale: 0.9),
                          paint: accent, depth: 8, lag: 0.05)
            ]

        // LANTERN — a body with a handle. The only boxy one.
        case .lantern:
            // `count` TAKES THE SIDES AND `trait` BECOMES A SIZE.
            //
            // The first version drove sides from `trait` and roundness from
            // `accent`, and neither of those is an extent: every lantern
            // measured exactly 1.160, because the handle sits at a fixed
            // offset and dominates. A family with no size axis has ten members
            // differing only in facet count, which reads at a glance as one
            // object drawn ten times.
            //
            // Sides belong on `count` in any case — it is the knob for "how
            // many of something", and lantern was the only family not using
            // it.
            let scale = 0.72 + 0.26 * v.trait
            return [
                root(.polygon(sides: min(max(v.count, 4), 9),
                              roundness: 0.25 + 0.55 * v.accent),
                     scale: scale),
                AnimaPart("light", .disc, parent: "body",
                          rest: AnimaTransform(offset: CGPoint(x: 0, y: 0.05),
                                               scale: 0.60),
                          paint: accent, depth: 2),
                AnimaPart("handle", .arc(sweep: 2.6, thickness: 0.16), parent: "body",
                          rest: AnimaTransform(offset: CGPoint(x: 0, y: -1.05),
                                               rotation: -.pi / 2, scale: 0.42),
                          paint: accent, depth: 8, lag: 0.04)
            ]

        // CURRENT — a streamer. A small head and a long trailing ribbon, and
        // the family that shows off `lag` most.
        case .current:
            var parts = [root(.disc, scale: 0.34 + 0.12 * v.accent)]
            let trails = min(max(n - 1, 2), 4)
            for i in 0..<trails {
                let sway = (Double(i) - Double(trails - 1) / 2) * 0.30
                let length = 1.5 + 1.2 * v.trait
                parts.append(
                    AnimaPart("trail-\(i)",
                              .ribbon(spine: [CGPoint(x: 0, y: 0),
                                              CGPoint(x: sway * 0.4, y: length * 0.4),
                                              CGPoint(x: -sway * 0.3, y: length * 0.75),
                                              CGPoint(x: sway * 0.5, y: length)],
                                      width: 0.30 + 0.16 * v.accent),
                              parent: "body",
                              rest: AnimaTransform(offset: CGPoint(x: sway, y: 0.5),
                                                   scale: 1.0),
                              paint: accent, depth: 3, lag: 0.05 + 0.04 * Double(i))
                )
            }
            return parts

        // PRISM — a hard shard with a beam. The lowest roundness in the set;
        // it should look cut rather than grown.
        case .prism:
            return [
                root(.polygon(sides: 3 + Int(v.trait * 2), roundness: 0.05), scale: 0.86),
                AnimaPart("beam", .capsule(length: 3.0 + 2.0 * v.accent), parent: "body",
                          rest: AnimaTransform(offset: CGPoint(x: 0.2, y: -0.2),
                                               rotation: -0.7, scale: 0.10),
                          paint: accent, depth: 9, lag: 0.03)
            ]

        // AURORA — stacked bands, nested and open. Nothing else is hollow.
        case .aurora:
            var parts = [root(.arc(sweep: 1.8 + 1.4 * v.trait, thickness: 0.14),
                              scale: 0.9, paint: 0, depth: 6)]
            for i in 1..<min(max(n - 1, 2), 4) {
                parts.append(
                    AnimaPart("band-\(i)",
                              .arc(sweep: 1.6 + 1.4 * v.trait - 0.2 * Double(i),
                                   thickness: 0.12),
                              parent: "body",
                              rest: AnimaTransform(offset: .zero,
                                                   rotation: 0.12 * Double(i) * (v.accent - 0.5) * 2,
                                                   scale: 1 - 0.22 * Double(i)),
                              paint: accent, depth: 6 - i, lag: 0.05 * Double(i))
                )
            }
            return parts
        }
    }
}

// MARK: - The binding

/// One pop, as an Anima object.
///
/// Pure and total: given a `PopDefinition` it always answers something
/// drawable, whether or not anyone has authored a variation for that pop yet.
/// That is what lets the hub page show all hundred from the first day, with
/// each batch replacing derivation with intent.
enum AnimaPop {

    /// Authored variations, by pop number.
    ///
    /// Filled a family at a time by phase A of `docs/anima_backlog.md`;
    /// anything absent falls back to `AnimaVariation.derived(from:)`, so the
    /// library is complete and previewable before a single row is written and
    /// each batch replaces derivation with intent.
    ///
    /// A `let`, not a `var`: this is a catalogue, and a mutable global that
    /// anything could write to at runtime would make an asset's appearance
    /// depend on what had run before it.
    static let variations: [Int: AnimaVariation] = [

        // ── 001–010 · VESPER — the original dusk ────────────────────────
        //
        // The family's silhouette is a body with a companion beside it, so
        // `trait` is HOW FAR the companion sits, `accent` is HOW LARGE AND
        // HIGH, and `tilt` is the angle of the pair. Each of the ten is
        // authored to its own flavour line rather than spread evenly, because
        // an even spread is a gradient and a gradient is not ten things.
        //
        // #001 IS THE REFERENCE IMPLEMENTATION OF THE GAME'S LOOK and it is
        // pinned as the most orb-like of the hundred: companion tucked in and
        // small, reach exactly 1.0. Guardrail 5 — pop #001 does not move. A
        // test holds it there.

        // "The first one. It was always enough."
        1:  AnimaVariation(trait: 0.00, accent: 0.05, count: 2, tilt: 0.00),
        // "The hour that asks nothing of you." — close, unhurried.
        2:  AnimaVariation(trait: 0.15, accent: 0.30, count: 2, tilt: -0.12),
        // "Water-colored, like the end of a good day." — dead level; water
        // finds its level and that is the whole line.
        3:  AnimaVariation(trait: 0.35, accent: 0.35, count: 2, tilt: 0.00),
        // "Neither day nor night. Both forgave you." — the exact midpoint of
        // the family, on both axes. Being exactly between IS the flavour.
        4:  AnimaVariation(trait: 0.50, accent: 0.50, count: 2, tilt: 0.00),
        // "Somewhere a kettle is on." — small, domestic, set down at an angle.
        5:  AnimaVariation(trait: 0.25, accent: 0.18, count: 2, tilt: 0.22),
        // "It falls slowly, then all at once, softly." — leaning away, and
        // the companion low.
        6:  AnimaVariation(trait: 0.45, accent: 0.62, count: 2, tilt: 0.30),
        // "One is enough to wish on." — far and tiny. Distance plus smallness
        // is what makes a point of light read as a star rather than a moon.
        7:  AnimaVariation(trait: 0.95, accent: 0.12, count: 2, tilt: -0.30),
        // "The sky lowering its voice." — large and low, close in.
        8:  AnimaVariation(trait: 0.30, accent: 0.85, count: 2, tilt: 0.18),
        // "Cool on the skin, kind to the mind." — open and spacious.
        9:  AnimaVariation(trait: 0.80, accent: 0.45, count: 2, tilt: -0.20),
        // "It stays a moment longer than it must." — the rare one: the
        // companion nearly rivals the body and will not leave.
        10: AnimaVariation(trait: 0.10, accent: 1.00, count: 2, tilt: -0.08),

        // ── 011–020 · EMBER — warm, not burning ─────────────────────────
        //
        // A flame with sparks leaving it. `trait` is HOW POINTED the flame is,
        // `accent` is HOW FAR AND LARGE the sparks fly, `count` is how many,
        // `tilt` is the lean.
        //
        // The family's own line — "warm, not burning" — is a constraint on the
        // whole batch, not just on #011: nothing here is a blaze. The largest
        // reach in the family is Bonfire at 1.37, against Vesper's 1.33.

        // "Warm, not burning. There is a difference." — blunt, sparks close.
        // The bluntness IS the difference.
        11: AnimaVariation(trait: 0.15, accent: 0.20, count: 3, tilt: 0.00),
        // "Small fires ask for small breaths." — sharp and tight.
        12: AnimaVariation(trait: 0.55, accent: 0.10, count: 3, tilt: -0.10),
        // "The center of a house that loves you." — upright and evenly
        // ringed. A hearth is level; nothing about it leans.
        13: AnimaVariation(trait: 0.25, accent: 0.35, count: 5, tilt: 0.00),
        // "What is finished can still glow." — blunt, fallen over, sparks
        // scattered wide. Spent, and still going.
        14: AnimaVariation(trait: 0.05, accent: 0.55, count: 4, tilt: 0.25),
        // "Carried in pockets, given away free." — many sparks, held close.
        15: AnimaVariation(trait: 0.30, accent: 0.15, count: 5, tilt: -0.18),
        // "Nothing worth keeping happens fast." — long and tight; the flame
        // that is going nowhere.
        16: AnimaVariation(trait: 0.85, accent: 0.05, count: 3, tilt: 0.08),
        // "A flower doing an impression of the sun." — radial and even, so it
        // reads as petals rather than sparks.
        17: AnimaVariation(trait: 0.40, accent: 0.62, count: 5, tilt: 0.00),
        // "Gather round. Let the night be long." — the widest reach here.
        18: AnimaVariation(trait: 0.50, accent: 1.00, count: 5, tilt: -0.05),
        // "Something quick and russet in the hedgerow." — sharpest and
        // leaning hardest; quickness drawn as a lean.
        19: AnimaVariation(trait: 0.95, accent: 0.30, count: 3, tilt: 0.42),
        // "The longest light. It turns here." — the longest flame, and the
        // most turned of the ten. The line names its own tilt.
        20: AnimaVariation(trait: 1.00, accent: 0.78, count: 5, tilt: -0.35),

        // ── 021–030 · TIDE — it goes out, it comes back ─────────────────
        //
        // A drop over a ripple. `trait` is HOW SHARP the drop is, `accent` is
        // HOW FAR THE SWELL REACHES (both its sweep and its size), `tilt` is
        // the angle. `count` is unused here — a drop is a drop.

        // "It goes out. It comes back. Trust it." — the middle of the family
        // on both axes, and level. Trust is not dramatic.
        21: AnimaVariation(trait: 0.35, accent: 0.45, count: 2, tilt: 0.00),
        // "The pull beneath. Let it carry, not drag." — blunt drop over a
        // large low swell: the ripple is the subject, not the drop.
        22: AnimaVariation(trait: 0.10, accent: 0.72, count: 2, tilt: 0.20),
        // "The sea keeps what you drop and softens it." — the bluntest drop
        // in the family. Softened is the whole line.
        23: AnimaVariation(trait: 0.00, accent: 0.35, count: 2, tilt: -0.15),
        // "It traveled far to rest here." — come to rest at an angle, which
        // is how driftwood actually lies.
        24: AnimaVariation(trait: 0.55, accent: 0.55, count: 2, tilt: 0.40),
        // "Even oceans answer to something gentle." — a small sharp drop over
        // a very wide swell. The gentle thing is the small one.
        25: AnimaVariation(trait: 0.75, accent: 0.85, count: 2, tilt: 0.00),
        // "Breathe it. It asks for nothing back." — barely a swell at all.
        26: AnimaVariation(trait: 0.45, accent: 0.12, count: 2, tilt: -0.25),
        // "Calm is not empty. It is full and still." — the sharpest drop, and
        // dead level. Still is not the same as slack.
        27: AnimaVariation(trait: 1.00, accent: 0.50, count: 2, tilt: 0.00),
        // "Shallow enough to see your own feet." — the smallest swell here.
        28: AnimaVariation(trait: 0.20, accent: 0.00, count: 2, tilt: 0.10),
        // "Patience, layered until it shines." — round and closed in.
        29: AnimaVariation(trait: 0.05, accent: 0.20, count: 2, tilt: -0.05),
        // "Everything the sea meant to say at once." — the widest swell of
        // the hundred so far, under a sharp drop.
        30: AnimaVariation(trait: 0.85, accent: 1.00, count: 2, tilt: -0.12),

        // ── 031–040 · BLOOM — it opened because it was time ─────────────
        //
        // Petals about a heart. `trait` is HOW LONG the petals are, `accent`
        // is HOW POINTED, `count` is HOW MANY, `tilt` is the lean.
        //
        // `count` is the loudest knob in this family — three petals and nine
        // are different objects at a glance, in a way that a length change is
        // not — so the ten spread across seven distinct counts. Elsewhere it
        // is a supporting knob; here it leads.

        // "It opened because it was time." — the reference bloom: five
        // petals, middling everything, level.
        31: AnimaVariation(trait: 0.45, accent: 0.40, count: 5, tilt: 0.00),
        // "Letting go, one soft piece at a time." — fewer petals than it
        // started with, and tipping over.
        32: AnimaVariation(trait: 0.35, accent: 0.55, count: 4, tilt: 0.28),
        // "Three leaves is already lucky." — THE COUNT IS THE LINE. Exactly
        // three, and round rather than pointed.
        33: AnimaVariation(trait: 0.25, accent: 0.05, count: 3, tilt: -0.10),
        // "Bend. It is not the same as breaking." — long sharp petals under
        // the hardest lean in the family. The lean is the sentence.
        34: AnimaVariation(trait: 0.85, accent: 0.80, count: 4, tilt: 0.45),
        // "Uncut, unhurried, humming quietly." — many small petals; a meadow
        // is a lot of small things, not one big one.
        35: AnimaVariation(trait: 0.15, accent: 0.35, count: 8, tilt: -0.20),
        // "The flower that becomes an evening." — the daisy: many narrow
        // petals, level.
        36: AnimaVariation(trait: 0.55, accent: 0.90, count: 8, tilt: 0.00),
        // "It unrolls its whole life slowly." — the longest, sharpest and
        // fewest. A frond, not a flower.
        37: AnimaVariation(trait: 1.00, accent: 0.95, count: 3, tilt: -0.35),
        // "Patient enough to cover a whole wall." — many, long, and hanging.
        38: AnimaVariation(trait: 0.75, accent: 0.60, count: 7, tilt: 0.35),
        // "Everything arrived. Nothing is missing." — the fullest count in
        // the family. Nothing missing is a number.
        39: AnimaVariation(trait: 0.60, accent: 0.25, count: 9, tilt: 0.00),
        // "Rooted in mud, untroubled by it." — broad, round, perfectly level.
        // Untroubled is drawn as level.
        40: AnimaVariation(trait: 0.70, accent: 0.15, count: 6, tilt: 0.00),

        // ── 041–050 · FROST — the world edited down to its edges ────────
        //
        // A radial crystal. `trait` is SPOKE LENGTH, `accent` is SPOKE
        // THICKNESS, `count` is how many, `tilt` is the turn.
        //
        // Length and thickness are independent here in a way they are not in
        // any other family, which is what lets frost say "needle-thin and
        // long" and "short and thick" as separate ideas.

        // "The world, edited down to its edges." — the reference crystal:
        // six spokes, middling on both axes, level.
        41: AnimaVariation(trait: 0.35, accent: 0.40, count: 6, tilt: 0.00),
        // "It changes everything and harms nothing." — the shortest and
        // finest in the family. Harmlessness drawn as slightness.
        42: AnimaVariation(trait: 0.10, accent: 0.10, count: 6, tilt: -0.10),
        // "Overnight, every branch was decorated." — the most spokes here.
        43: AnimaVariation(trait: 0.45, accent: 0.62, count: 9, tilt: 0.12),
        // "Moving all the time. Never rushing." — longest and thickest, and
        // only four of them. Mass, not speed.
        44: AnimaVariation(trait: 0.95, accent: 0.88, count: 4, tilt: 0.05),
        // "Even the coldest things loosen eventually." — short and thick, and
        // tipping over. Loosening drawn as thickening.
        45: AnimaVariation(trait: 0.15, accent: 0.72, count: 5, tilt: 0.30),
        // "Cold enough to make light look sharpened." — long and needle-thin.
        // The thinnest spokes of the hundred.
        46: AnimaVariation(trait: 0.80, accent: 0.05, count: 8, tilt: -0.22),
        // "Look through it. Everything is still there." — three broad panes,
        // level. Broad enough to be a window rather than a lattice.
        47: AnimaVariation(trait: 0.55, accent: 0.95, count: 3, tilt: 0.00),
        // "A small commotion of soft white." — many fine spokes, knocked
        // off-axis. Commotion is the tilt, small is the thickness.
        48: AnimaVariation(trait: 0.30, accent: 0.18, count: 9, tilt: 0.38),
        // "The snow's real gift is the quiet after." — dead level, perfectly
        // even, six. The rare one, and the stillest thing in the family.
        49: AnimaVariation(trait: 0.62, accent: 0.42, count: 6, tilt: 0.00),
        // "The sun leaves. The sky finds other colors." — the secret one:
        // the longest spokes and the hardest turn.
        50: AnimaVariation(trait: 1.00, accent: 0.68, count: 7, tilt: -0.35),

        // ── 051–060 · CHIME — struck once, heard twice ──────────────────
        //
        // A hanging bar. `trait` is HOW LONG, `accent` is HOW THICK, `tilt` is
        // the swing. `count` is unused — a chime is one bar.
        //
        // Length and thickness are authored directly and the capsule's own
        // `length` is derived from them; see the builder for why that matters.

        // "Struck once, heard twice." — the reference bar, level.
        51: AnimaVariation(trait: 0.35, accent: 0.45, count: 2, tilt: 0.00),
        // "Round sound from a round thing." — the shortest and thickest here,
        // which is as close to round as a bar gets.
        52: AnimaVariation(trait: 0.10, accent: 0.95, count: 2, tilt: -0.08),
        // "The breeze, learning an instrument." — thin, and swinging hardest.
        // The breeze is the tilt.
        53: AnimaVariation(trait: 0.55, accent: 0.15, count: 2, tilt: 0.40),
        // "Many small bells agreeing about the hour." — small, and turned the
        // same way as its neighbours. Agreement drawn as a shared angle.
        54: AnimaVariation(trait: 0.25, accent: 0.30, count: 2, tilt: -0.30),
        // "The day, sung gently to its close." — long, level, unhurried.
        55: AnimaVariation(trait: 0.70, accent: 0.55, count: 2, tilt: 0.00),
        // "Old metal remembers every polish." — broad and heavy.
        56: AnimaVariation(trait: 0.45, accent: 0.80, count: 2, tilt: 0.14),
        // "What you send out comes back rounder." — long and slender.
        57: AnimaVariation(trait: 0.85, accent: 0.35, count: 2, tilt: -0.18),
        // "One note, and the morning starts over." — upright and weighty.
        58: AnimaVariation(trait: 0.60, accent: 0.68, count: 2, tilt: 0.00),
        // "Fragile, and still it sings." — the longest and thinnest of the
        // family. Fragility is the ratio, not the size.
        59: AnimaVariation(trait: 0.95, accent: 0.05, count: 2, tilt: 0.26),
        // "It counts to twelve and lets you rest." — the rare one: the
        // longest bar, and the most turned.
        60: AnimaVariation(trait: 1.00, accent: 0.60, count: 2, tilt: -0.40),

        // ── 061–070 · LANTERN — light you can hold ──────────────────────
        //
        // A body with a handle and a light inside it. `trait` is HOW BIG,
        // `accent` is HOW ROUND (a hard-edged case against a paper balloon),
        // `count` is the number of sides, `tilt` is the hang.

        // "Light you can hold is light you can share." — the reference, level.
        61: AnimaVariation(trait: 0.45, accent: 0.50, count: 6, tilt: 0.00),
        // "Proof that small things can be seen." — the smallest of the
        // hundred so far, and round. Smallness is the entire claim.
        62: AnimaVariation(trait: 0.00, accent: 0.85, count: 5, tilt: 0.18),
        // "It rises because it is mostly hope." — large and almost a balloon:
        // the roundest thing in the family, barely a case at all.
        63: AnimaVariation(trait: 0.85, accent: 1.00, count: 5, tilt: -0.10),
        // "A thread's whole job is to hold a flame." — small, hard-edged and
        // tipping. Four sides is as close to a line as this family gets.
        64: AnimaVariation(trait: 0.12, accent: 0.05, count: 4, tilt: 0.30),
        // "Someone left it on for you." — boxy, four-square, level. A porch
        // fixture is a box, and it is exactly where you left it.
        65: AnimaVariation(trait: 0.62, accent: 0.15, count: 4, tilt: 0.00),
        // "Underground, and still it bothers to shine." — small, round, and
        // the most turned: awkwardly placed, and shining anyway.
        66: AnimaVariation(trait: 0.20, accent: 0.72, count: 7, tilt: 0.42),
        // "A hundred lights, none of them in a hurry." — the most facets in
        // the family. A hundred lights is a count.
        67: AnimaVariation(trait: 0.50, accent: 0.62, count: 9, tilt: -0.25),
        // "The afternoon, preserved in resin." — large and very round, like
        // something set in amber.
        68: AnimaVariation(trait: 0.70, accent: 0.90, count: 8, tilt: 0.10),
        // "Warm noise, good smells, nowhere to be." — large and leaning; the
        // posture of having nowhere to be.
        69: AnimaVariation(trait: 0.92, accent: 0.40, count: 7, tilt: -0.35),
        // "It doesn't chase ships. It just stays lit." — the largest, the
        // hardest-edged, and dead level. Staying put is the whole line.
        70: AnimaVariation(trait: 1.00, accent: 0.10, count: 6, tilt: 0.00),

        // ── 071–080 · CURRENT — it moves because standing still itches ──
        //
        // A head with trailing ribbons. `trait` is HOW LONG the trails are,
        // `accent` is HOW WIDE they are and how large the head is, `count`
        // gives two to four trails, `tilt` is the set of the whole thing.
        //
        // The family that shows off `lag` most: each trail lags a little more
        // than the last, so one movement of the head becomes a cascade nobody
        // authored.
        //
        // Nothing here sits at low trait AND low accent — that corner draws
        // shorter than a plain orb and lands on the reach floor, where ten
        // members stop being distinguishable.

        // "It moves because standing still itches." — the reference, and
        // never quite level. Standing still is what it does not do.
        71: AnimaVariation(trait: 0.50, accent: 0.50, count: 5, tilt: 0.15),
        // "The small jump between almost and done." — the shortest trails
        // here, and only two of them. A jump, not a journey.
        72: AnimaVariation(trait: 0.36, accent: 0.55, count: 3, tilt: 0.35),
        // "A thin thing, asked to hold the light." — long, and the thinnest
        // trails in the family. The thinness is the whole ask.
        73: AnimaVariation(trait: 0.85, accent: 0.10, count: 4, tilt: -0.12),
        // "The city, rinsed and glowing." — four trails, mid-long: rain on a
        // lot of surfaces at once.
        74: AnimaVariation(trait: 0.70, accent: 0.45, count: 5, tilt: 0.22),
        // "Everything connected, nothing strained." — even and dead level.
        // Nothing strained is drawn as nothing tilted.
        75: AnimaVariation(trait: 0.55, accent: 0.35, count: 5, tilt: 0.00),
        // "The storm, far enough away to enjoy." — long and soft, only two
        // trails. Far enough away to be weather rather than an event.
        76: AnimaVariation(trait: 0.75, accent: 0.80, count: 3, tilt: -0.30),
        // "Charged, and choosing to be kind about it." — the widest trails of
        // the family. Kindness drawn as softness, not as smallness.
        77: AnimaVariation(trait: 0.60, accent: 0.92, count: 4, tilt: 0.10),
        // "Your own steady proof of being here." — short, thick and level.
        // Steady is the absence of tilt.
        78: AnimaVariation(trait: 0.30, accent: 0.85, count: 3, tilt: 0.00),
        // "A bridge of light between two quiet points." — the longest trails,
        // and spare: a bridge is a span, not a crowd.
        79: AnimaVariation(trait: 1.00, accent: 0.25, count: 3, tilt: -0.20),
        // "Weather you can hold without getting wet." — the secret one:
        // longest and widest together, the largest reach of the hundred.
        80: AnimaVariation(trait: 0.95, accent: 1.00, count: 5, tilt: -0.38)
    ]

    static func variation(for number: Int) -> AnimaVariation {
        variations[number] ?? .derived(from: number)
    }

    /// The object for one catalogue pop.
    static func object(for definition: PopDefinition) -> AnimaObject {
        let v = variation(for: definition.number)
        let figure = definition.family.figure(definition.name,
                                              variation: v,
                                              paints: definition.style.paints)
        return AnimaObject(figure,
                           // The shared performances work on every figure
                           // because of the one-root-named-`body` convention.
                           clips: [AnimaLibrary.breathe, AnimaLibrary.wake, AnimaLibrary.release],
                           voice: AnimaLibrary.voice(for: definition.behavior.sound.voice),
                           note: definition.flavor,
                           popNumber: definition.number,
                           family: definition.family.rawValue,
                           rarity: definition.rarity.rawValue,
                           flavor: definition.flavor)
    }

    /// Every pop in the catalogue, in number order.
    ///
    /// Driven from `PopCatalog.all` rather than from `1...100`, so it stays
    /// correct if the catalogue is ever a different size — and so this cannot
    /// silently synthesise a hundred copies of pop #001 through
    /// `definition(for:)`'s fallback.
    static var all: [AnimaObject] {
        PopCatalog.all.sorted { $0.number < $1.number }.map { object(for: $0) }
    }
}
