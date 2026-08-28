import SwiftUI

// ANIMA — drawing. The only file in the engine that imports SwiftUI, and it
// is deliberately thin: it turns a pose into a `Path`, fills it in three
// passes, and knows nothing about time, keys or shapes.
//
// THE THREE PASSES ARE THE GAME'S, NOT NEW ONES. Every object in Vesper is
// drawn as a soft additive halo, a flat body, and a whisper of a highlight —
// that is `SceneRenderer`'s material, and it is most of why the field looks
// like one place rather than a pile of sprites. An engine that invented its
// own material would produce objects that were obviously bolted on, which is
// the failure mode of every generic 2-D system dropped into a game with a
// look of its own.
//
// So this renderer is a translation layer, not a style. Anything it draws
// should be indistinguishable in material from an orb drawn beside it.
extension SceneRenderer {

    /// Draws one posed figure.
    ///
    /// `centre` and `radius` are where and how big, in points; the pose is in
    /// unit space and is scaled by `radius` here. `presence` is the same
    /// depth/pulse factor an orb carries, so an Anima object rising out of
    /// the reserve dims and grows exactly as an orb does.
    ///
    /// `glow` is the additive layer the caller has already set up — passing
    /// it in rather than making one keeps every additive thing in the scene
    /// in ONE layer, which is the difference between a soft field and a
    /// stack of hotspots.
    func drawAnima(_ pose: AnimaPose,
                   figure: AnimaFigure,
                   at centre: CGPoint,
                   radius: CGFloat,
                   presence: Double,
                   style: PopStyle,
                   facing: CGFloat = 1,
                   into context: inout GraphicsContext,
                   glow: inout GraphicsContext) {

        guard radius > 0.01, presence > 0.001, !pose.parts.isEmpty else { return }
        let alpha = min(max(presence, 0), 1)

        // THE HALO IS SIZED FROM THE POSE, NOT FROM THE RADIUS.
        //
        // `AnimalRendering` learned this: a long-eared shape lit as though it
        // were a ball is the tell that something generic is drawing it. The
        // reach comes from the posed outline rather than the rest one, so a
        // creature mid-stretch is lit at the size it currently is.
        let reach = radius * CGFloat(pose.reach)
        let haloRadius = reach * 1.8
        if let firstPaint = figure.paints.first {
            let glowColor = color(firstPaint.glow)
            let rect = CGRect(x: centre.x - haloRadius, y: centre.y - haloRadius,
                              width: haloRadius * 2, height: haloRadius * 2)
            let gradient = Gradient(stops: [
                .init(color: glowColor.opacity(style.haloOpacity * alpha), location: 0),
                .init(color: glowColor.opacity(0), location: 1)
            ])
            glow.fill(Path(ellipseIn: rect),
                      with: .radialGradient(gradient, center: centre,
                                            startRadius: radius * 0.5, endRadius: haloRadius))
        }

        // THE BODY. Back to front, one fill per part.
        //
        // Note what is NOT here: no stroke, anywhere. `AnimalRendering`'s
        // header explains why at length and it applies to every figure — a
        // stroke outlines the internal seams of a composed shape and turns a
        // creature back into the pile of primitives it is made of. Nothing in
        // this game is outlined.
        for part in pose.parts {
            guard part.opacity > 0.002, part.outline.count > 2 else { continue }
            let paint = figure.paints.indices.contains(part.paint)
                ? figure.paints[part.paint]
                : figure.paints.first
            guard let paint else { continue }

            let path = Self.path(for: part, at: centre, radius: radius, facing: facing)
            context.fill(path,
                         with: .color(color(paint.fill).opacity(alpha * part.opacity)),
                         style: FillStyle(eoFill: false))
        }

        // THE HIGHLIGHT. One, on the nearest part, offset up and toward the
        // light — the same whisper every orb carries. Placed on the part with
        // the greatest depth rather than at the figure's centre so it sits
        // where the light would actually catch.
        if let front = pose.parts.last, front.outline.count > 2 {
            let bounds = Self.bounds(of: front.outline)
            let size = max(bounds.width, bounds.height) * radius
            let highlightRadius = size * 0.13
            if highlightRadius > 0.4 {
                let cx = centre.x + (bounds.midX * radius - size * 0.19) * facing
                let cy = centre.y + bounds.midY * radius - size * 0.21
                let rect = CGRect(x: cx - highlightRadius, y: cy - highlightRadius,
                                  width: highlightRadius * 2, height: highlightRadius * 2)
                glow.fill(Path(ellipseIn: rect),
                          with: .color(Color.white.opacity(style.highlightOpacity * alpha)))
            }
        }
    }

    // MARK: - Geometry

    /// A posed part as a closed path, in screen points.
    ///
    /// `facing` mirrors in x about the figure's centre — the same trick
    /// `AnimalRendering` uses so a creature turns with its drift instead of
    /// reading as a decal. It is applied here rather than baked into the pose
    /// so that one sampled pose can be drawn facing either way, which matters
    /// for the exporter: the previewer ships one filmstrip, not two.
    static func path(for part: AnimaPosedPart,
                     at centre: CGPoint,
                     radius: CGFloat,
                     facing: CGFloat) -> Path {
        var path = Path()
        var first = true
        for point in part.outline {
            let screen = CGPoint(x: centre.x + point.x * radius * facing,
                                 y: centre.y + point.y * radius)
            if first {
                path.move(to: screen)
                first = false
            } else {
                path.addLine(to: screen)
            }
        }
        path.closeSubpath()
        return path
    }

    private static func bounds(of outline: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in outline {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        guard minX <= maxX else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
