import CoreGraphics
import Foundation

// ANIMA — the shape language. This file is form: what a 2-D object is made
// of, expressed as parameters rather than as drawing code.
//
// ─────────────────────────────────────────────────────────────────────────
// THE PROBLEM THIS SOLVES, MEASURED.
//
// The game already draws five different vocabularies of 2-D object, and no
// two of them share a line of code: orbs are ellipses in `SceneRenderer`,
// balloon animals are unions of circles in `AnimalRendering`, sky stars are
// rounded polygons in `SkyRenderer.gemPath`, firework shells are their own
// thing, weather is another. Each was a day of an engineer's time, and each
// is a place a sixth object cannot reuse.
//
// One parametric vocabulary means a new object is a row of numbers.
//
// ─────────────────────────────────────────────────────────────────────────
// PRIMITIVES EMIT OUTLINES, NOT PATHS. THIS IS THE LOAD-BEARING DECISION.
//
// Every primitive answers a closed polyline of `CGPoint` in unit space. It
// does NOT answer a `SwiftUI.Path`, and the difference is the entire reason
// the authoring loop is cheap:
//
//   * this file stays UI-free, so it can be sampled in a test and serialised
//     by `AnimaStudio` with no rendering stack at all;
//   * the browser previewer fills the SAME polyline the phone fills. It does
//     not reimplement a single curve. A previewer that reimplemented the
//     shape maths would drift from the app within a week and then quietly
//     lie to whoever was authoring against it, which is worse than having no
//     previewer;
//   * a polyline is trivially transformable, so squash, stretch and rotation
//     in `AnimaFigure` are one matrix rather than per-primitive special
//     cases.
//
// The cost is that curves are sampled rather than exact. At `samples = 64`
// on a shape drawn at 34 pt — the largest orb in the game — the chord error
// is under a twentieth of a point, which is a quarter of a pixel on a 3x
// screen. Nobody will ever see it, and `AnimaTests` pins the bound.
//
// UNIT SPACE: every outline is centred near the origin and reaches about 1.0
// at its furthest point. The renderer multiplies by the object's radius. So
// a figure is resolution-independent and scale is never authored into a
// shape, which is what stops a library of objects from being a library of
// objects that only look right at one size.

// MARK: - Lobes

/// One circle in a blob: where it sits, in unit space, and how big it is.
///
/// This is the balloon animal's vocabulary, lifted out of `AnimalPop` and
/// generalised. It stays because it is genuinely the cheapest way to author a
/// creature silhouette — a body, a head, two ears, four legs is six numbers
/// pairs and reads at a glance in a catalog.
struct AnimaLobe: Equatable {
    var offset: CGPoint
    var radius: Double

    init(_ x: Double, _ y: Double, _ radius: Double) {
        self.offset = CGPoint(x: x, y: y)
        self.radius = radius
    }
}

// MARK: - Primitives

/// The whole vocabulary. Adding a primitive here is the only thing in this
/// engine that is a code change rather than a data change, and that is
/// deliberate: the set is meant to stay small enough that an author can hold
/// it in their head.
enum AnimaPrimitive: Equatable {

    /// The circle. Every orb in the game is one, so the engine's simplest
    /// case is also the one that has to be exactly right.
    case disc

    /// A rounded bar of unit radius, `length` long along x, centred. Limbs,
    /// ears, petals-on-stems, the body of a moth.
    case capsule(length: Double)

    /// A teardrop — a limaçon, r(θ) = 1 − s·cos θ, normalised. `sharpness`
    /// runs 0 (a circle) to 1 (a cusp at one end). Seeds, flames, leaves,
    /// anything that wants a direction without wanting a point.
    case petal(sharpness: Double)

    /// A polygon rounded toward a circle. `roundness` 0 is a hard polygon and
    /// 1 is a disc. This reproduces `SkyRenderer.gemPath`'s family signature
    /// exactly, which is what will let the sky's stars move onto this engine
    /// without their silhouettes changing.
    case polygon(sides: Int, roundness: Double)

    /// An annular sector: a band of `thickness` (in unit radii) covering
    /// `sweep` radians, centred on the +x axis. Rings, arcs, crescents,
    /// a mouth.
    case arc(sweep: Double, thickness: Double)

    /// The union of circles, as one silhouette. The balloon-animal shape.
    case blob(lobes: [AnimaLobe])

    /// A stroked polyline of `width` (in unit radii), turned into a closed
    /// outline. Trails, fuses, stems, the tentacle of a jellyfish.
    case ribbon(spine: [CGPoint], width: Double)

    /// How many points a curved primitive is sampled at. One number, so the
    /// fidelity/size trade is made once rather than per shape.
    static let samples = 64

    /// The closed outline, counter-clockwise, in unit space.
    ///
    /// Never empty and never degenerate: every case floors its own
    /// parameters, because a catalog entry with a zero radius or one spine
    /// point is a typo and a typo must produce something harmless rather than
    /// an empty path that renders as a hole or a crash in a fill routine.
    func outline() -> [CGPoint] {
        switch self {
        case .disc:
            return Self.ring(radius: { _ in 1 })

        case .capsule(let length):
            return Self.capsuleOutline(halfLength: max(0, length) / 2)

        case .petal(let sharpness):
            let s = min(max(sharpness, 0), 1)
            // Normalised by its own maximum so a petal always reaches 1.0,
            // like every other primitive. Without this a sharp petal would be
            // silently twice the size of a blunt one at the same scale.
            let peak = 1 + s
            return Self.ring(radius: { theta in (1 - s * cos(theta)) / peak })

        case .polygon(let sides, let roundness):
            let n = max(3, sides)
            let r = min(max(roundness, 0), 1)
            let step = 2 * Double.pi / Double(n)
            let inradius = cos(Double.pi / Double(n))
            return Self.ring(radius: { theta in
                // Distance to the polygon edge along this ray, then blended
                // toward the unit circle.
                var phase = theta.truncatingRemainder(dividingBy: step)
                if phase < 0 { phase += step }
                let edge = inradius / cos(phase - step / 2)
                return edge * (1 - r) + r
            })

        case .arc(let sweep, let thickness):
            return Self.arcOutline(sweep: sweep, thickness: thickness)

        case .blob(let lobes):
            return Self.blobOutline(lobes)

        case .ribbon(let spine, let width):
            return Self.ribbonOutline(spine: spine, width: width)
        }
    }

    // MARK: Builders

    /// Samples a polar radius function into a closed ring.
    private static func ring(radius: (Double) -> Double) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(samples)
        for i in 0..<samples {
            let theta = 2 * Double.pi * Double(i) / Double(samples)
            let r = max(0.0001, radius(theta))
            points.append(CGPoint(x: r * cos(theta), y: r * sin(theta)))
        }
        return points
    }

    private static func capsuleOutline(halfLength h: Double) -> [CGPoint] {
        // A true capsule rather than a polar approximation: a polar function
        // cannot describe one (the outline is not star-shaped about the
        // centre once it is long enough), and a squashed disc is a different
        // shape with visibly different ends.
        var points: [CGPoint] = []
        let half = samples / 2
        for i in 0...half {
            let a = -Double.pi / 2 + Double.pi * Double(i) / Double(half)
            points.append(CGPoint(x: h + cos(a), y: sin(a)))
        }
        for i in 0...half {
            let a = Double.pi / 2 + Double.pi * Double(i) / Double(half)
            points.append(CGPoint(x: -h + cos(a), y: sin(a)))
        }
        return points
    }

    private static func arcOutline(sweep: Double, thickness: Double) -> [CGPoint] {
        let s = min(max(sweep, 0.05), 2 * Double.pi)
        let t = min(max(thickness, 0.02), 1)
        let outer = 1.0
        let inner = max(0.01, 1 - t)
        let steps = max(6, samples / 2)
        var points: [CGPoint] = []
        for i in 0...steps {
            let a = -s / 2 + s * Double(i) / Double(steps)
            points.append(CGPoint(x: outer * cos(a), y: outer * sin(a)))
        }
        for i in 0...steps {
            let a = s / 2 - s * Double(i) / Double(steps)
            points.append(CGPoint(x: inner * cos(a), y: inner * sin(a)))
        }
        return points
    }

    /// The silhouette of a union of circles, by ray casting from the origin.
    ///
    /// HONEST ABOUT ITS LIMIT. For each direction this takes the furthest
    /// point at which any lobe's boundary crosses the ray, which is exactly
    /// the union's boundary while the union is star-shaped about the origin —
    /// i.e. while every part of it can "see" the centre. Balloon animals are:
    /// a body at the origin with limbs radiating off it. A shape with a limb
    /// that curls back on itself would lose the curl.
    ///
    /// That is the right trade here. The alternative is a real boolean union,
    /// which is an order of magnitude more code, needs robust predicates to
    /// avoid falling apart on tangent circles, and buys a case the aesthetic
    /// does not want anyway — nothing in this game is knotted.
    private static func blobOutline(_ lobes: [AnimaLobe]) -> [CGPoint] {
        let live = lobes.filter { $0.radius > 0.0001 }
        guard !live.isEmpty else { return AnimaPrimitive.disc.outline() }

        return ring(radius: { theta in
            let dx = cos(theta), dy = sin(theta)
            var furthest = 0.0
            for lobe in live {
                // Distance along the unit ray to the far intersection with
                // this lobe's circle, or nothing if the ray misses it.
                let cx = Double(lobe.offset.x), cy = Double(lobe.offset.y)
                let projection = cx * dx + cy * dy
                let perpendicular = cx * cx + cy * cy - projection * projection
                let discriminant = lobe.radius * lobe.radius - perpendicular
                guard discriminant > 0 else { continue }
                furthest = max(furthest, projection + discriminant.squareRoot())
            }
            return furthest
        })
    }

    private static func ribbonOutline(spine: [CGPoint], width: Double) -> [CGPoint] {
        guard spine.count >= 2 else { return AnimaPrimitive.disc.outline() }
        let half = max(0.005, width / 2)

        // The normal at each spine point, averaged with its neighbour's so
        // the band does not pinch at a corner.
        func normal(at i: Int) -> CGPoint {
            let before = spine[max(0, i - 1)]
            let after = spine[min(spine.count - 1, i + 1)]
            let dx = Double(after.x - before.x)
            let dy = Double(after.y - before.y)
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0.0001 else { return CGPoint(x: 0, y: 1) }
            return CGPoint(x: -dy / length, y: dx / length)
        }

        var points: [CGPoint] = []
        for i in 0..<spine.count {
            let n = normal(at: i)
            points.append(CGPoint(x: spine[i].x + n.x * half,
                                  y: spine[i].y + n.y * half))
        }
        for i in stride(from: spine.count - 1, through: 0, by: -1) {
            let n = normal(at: i)
            points.append(CGPoint(x: spine[i].x - n.x * half,
                                  y: spine[i].y - n.y * half))
        }
        return points
    }
}
