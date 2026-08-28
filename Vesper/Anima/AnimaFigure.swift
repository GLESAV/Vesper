import CoreGraphics
import Foundation

// ANIMA — figures. A figure is a named set of parts, each a primitive with a
// rest transform, arranged in a hierarchy.
//
// The unit of authoring is the PART, not the object, because that is what
// makes a performance possible: a clip animates "the left ear", and the ear
// exists as a nameable thing whether or not anything is animating it today.

// MARK: - Transforms

/// Where a part sits, and what has been done to it.
///
/// SQUASH AND STRETCH IS A FIRST-CLASS FIELD, not a pair of scales an author
/// has to remember to keep reciprocal. It is the first principle of character
/// animation and the one that separates a moving picture of an object from an
/// object that is alive, and every implementation that leaves it to two
/// independent scale channels gets volume drift the moment anyone keyframes
/// them separately — the object slowly inflates over a loop and nobody can
/// see why.
///
/// Here `squash` is one number: positive flattens and widens, negative
/// stretches and narrows, and the area is preserved by construction because
/// the two axes are derived from the one value.
struct AnimaTransform: Equatable {
    var offset: CGPoint = .zero
    var rotation: Double = 0          // radians, positive clockwise on screen
    var scale: Double = 1             // uniform, on top of squash
    var squash: Double = 0            // -1 (stretched) ... 1 (squashed)
    var opacity: Double = 1

    static let identity = AnimaTransform()

    /// The two axis scales this transform actually applies.
    ///
    /// `exp` rather than `1 ± s`, so that squashing by 0.5 and stretching by
    /// 0.5 are exact inverses of one another and a channel that swings
    /// symmetrically about zero returns to exactly its rest shape. With the
    /// linear form they are not inverses (1.5 × 0.5 = 0.75) and a bouncing
    /// object shrinks a little on every bounce.
    var axes: (x: Double, y: Double) {
        let s = min(max(squash, -1), 1)
        let k = exp(s)
        return (x: scale * k, y: scale / k)
    }

    /// Applies this transform to a point in the part's own space.
    func apply(to p: CGPoint) -> CGPoint {
        let (sx, sy) = axes
        let x = Double(p.x) * sx
        let y = Double(p.y) * sy
        let c = cos(rotation), s = sin(rotation)
        return CGPoint(x: x * c - y * s + Double(offset.x),
                       y: x * s + y * c + Double(offset.y))
    }

    /// REST MERGED WITH ANIMATION — not composed.
    ///
    /// This is the one that implements the channel semantics `AnimaChannel`
    /// documents: x/y/rotation/squash add onto rest, scale and opacity
    /// multiply into it. It is deliberately NOT `concatenated(under:)`, and
    /// the difference is a real bug rather than a stylistic one: composing
    /// would push the rest offset through the animation's scale and rotation,
    /// so animating a part's `scale` would slide it away from its parent and
    /// animating its `rotation` would swing it around the figure's origin
    /// instead of its own. An ear that grew would also drift off the head.
    func merged(with animation: AnimaTransform) -> AnimaTransform {
        var out = AnimaTransform()
        out.offset = CGPoint(x: offset.x + animation.offset.x,
                             y: offset.y + animation.offset.y)
        out.rotation = rotation + animation.rotation
        out.scale = scale * animation.scale
        out.squash = squash + animation.squash
        out.opacity = opacity * animation.opacity
        return out
    }

    /// Composition: `self` applied inside `parent`.
    ///
    /// Offsets compose through the parent's rotation and scale, which is what
    /// makes a hierarchy worth having — rotating a body carries its ears with
    /// it, and an author never writes that down.
    func concatenated(under parent: AnimaTransform) -> AnimaTransform {
        var out = AnimaTransform()
        out.offset = parent.apply(to: offset)
        out.rotation = parent.rotation + rotation
        out.scale = parent.scale * scale
        out.squash = parent.squash + squash
        out.opacity = parent.opacity * opacity
        return out
    }
}

// MARK: - Parts

/// One drawable piece of a figure.
struct AnimaPart: Equatable {

    /// The name a clip's tracks bind to. Unique within a figure — duplicates
    /// are not an error, but only the first is reachable from a track, so
    /// `AnimaTests` fails a library that contains any.
    var name: String

    /// The part this one hangs off, by name. `nil` is a root.
    var parent: String?

    var primitive: AnimaPrimitive

    /// Where it sits when nothing is animating it.
    var rest: AnimaTransform

    /// Which of the figure's paints fills it.
    var paint: Int

    /// Draw order. Higher is nearer the viewer. Explicit rather than implied
    /// by array position, so inserting a part into a catalog entry cannot
    /// silently reorder the ones around it.
    var depth: Int

    /// FOLLOW-THROUGH AND OVERLAPPING ACTION, IN ONE NUMBER.
    ///
    /// Seconds this part lags whatever its parent is doing. An ear with
    /// `lag: 0.06` samples the whole animation 60 ms in the past, so when the
    /// head stops the ear is still arriving — which is the entire effect,
    /// and it is the difference between a rigid puppet and something with
    /// soft parts.
    ///
    /// Cheaper than any physical simulation of it, exactly reproducible, and
    /// it costs one subtraction at sample time. It is not a spring: it cannot
    /// overshoot on its own, so a part that should also overshoot pairs a lag
    /// with an `.overshoot` or `.settle` easing on its own track.
    var lag: Double

    init(_ name: String,
         _ primitive: AnimaPrimitive,
         parent: String? = nil,
         rest: AnimaTransform = .identity,
         paint: Int = 0,
         depth: Int = 0,
         lag: Double = 0) {
        self.name = name
        self.parent = parent
        self.primitive = primitive
        self.rest = rest
        self.paint = paint
        self.depth = depth
        self.lag = lag
    }
}

// MARK: - Figures

/// A complete 2-D object: its parts and the paints they draw in.
///
/// PAINTS COME FROM `PopStandard`, not from a new colour type. The palette is
/// the product's identity and there must be exactly one of it — a second
/// colour model here is how a library of new objects ends up not looking like
/// the game it is for.
struct AnimaFigure: Equatable {
    var name: String
    var parts: [AnimaPart]
    var paints: [PopPaint]

    init(_ name: String, parts: [AnimaPart], paints: [PopPaint]) {
        self.name = name
        self.parts = parts
        self.paints = paints
    }

    func part(named name: String) -> AnimaPart? {
        parts.first { $0.name == name }
    }

    /// How far the furthest point of the figure reaches at rest, in unit
    /// radii.
    ///
    /// The renderer needs this to size a halo: a long-eared creature lit as
    /// though it were a ball is the tell that a generic renderer is drawing
    /// it. Computed rather than authored, so it cannot go stale when a part
    /// moves.
    var restReach: Double {
        var furthest = 1.0
        for part in parts {
            let world = worldRest(of: part)
            for p in part.primitive.outline() {
                let q = world.apply(to: p)
                furthest = max(furthest, (Double(q.x) * Double(q.x)
                                          + Double(q.y) * Double(q.y)).squareRoot())
            }
        }
        return furthest
    }

    /// A part's rest transform with its ancestors' applied.
    ///
    /// Depth-limited rather than cycle-detected: `parts.count` steps is more
    /// ancestors than any figure can have, so a catalog entry that accidentally
    /// makes A the parent of B and B the parent of A draws something wrong
    /// instead of hanging the render loop. `AnimaTests` rejects the cycle
    /// outright, which is where an author should hear about it.
    func worldRest(of part: AnimaPart) -> AnimaTransform {
        var chain: [AnimaTransform] = [part.rest]
        var cursor = part.parent
        var guardCount = 0
        while let name = cursor, guardCount < parts.count {
            guard let next = self.part(named: name) else { break }
            chain.append(next.rest)
            cursor = next.parent
            guardCount += 1
        }
        var out = AnimaTransform.identity
        for transform in chain.reversed() {
            out = transform.concatenated(under: out)
        }
        return out
    }
}

// MARK: - Poses

/// One part, resolved: an outline in unit space, ready to be scaled and
/// drawn, with nothing left to compute.
///
/// This is the type `AnimaStudio` serialises and the browser previewer draws.
/// It is deliberately dumb — points, a paint index, an opacity — because
/// everything that is not dumb is a chance for two renderers to disagree.
struct AnimaPosedPart: Equatable {
    var name: String
    var outline: [CGPoint]
    var paint: Int
    var opacity: Double
    var depth: Int
}

/// A whole figure at one instant, sorted back to front.
struct AnimaPose: Equatable {
    var parts: [AnimaPosedPart]

    /// How far this pose reaches, for halo sizing. Computed from the posed
    /// outline rather than the rest one, so a creature stretching out is lit
    /// as the size it currently is.
    var reach: Double {
        var furthest = 1.0
        for part in parts {
            for p in part.outline {
                furthest = max(furthest, (Double(p.x) * Double(p.x)
                                          + Double(p.y) * Double(p.y)).squareRoot())
            }
        }
        return furthest
    }
}
