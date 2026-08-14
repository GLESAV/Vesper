import SwiftUI

// Draws the simulation into a Canvas, styled entirely by each entity's pop
// definition (PopStyle). Read-only: must never mutate sim state.
struct SceneRenderer {

    private let moteColor = Color(red: 214/255, green: 208/255, blue: 235/255)
    private let noteColor = Color(red: 210/255, green: 202/255, blue: 232/255)

    func draw(_ sim: GameSimulation, into context: inout GraphicsContext, size: CGSize) {
        var glow = context
        glow.blendMode = .plusLighter

        // ambient motes — faint depth behind everything
        for m in sim.motes {
            let a = Double(m.alpha * (0.6 + 0.4 * sin(m.phase)))
            let rect = CGRect(x: m.pos.x - m.size, y: m.pos.y - m.size,
                              width: m.size * 2, height: m.size * 2)
            glow.fill(Path(ellipseIn: rect), with: .color(moteColor.opacity(a)))
        }

        // orbs: faint halo (additive) + flat solid disc + soft specular
        for o in sim.orbs where o.alive {
            let style = PopCatalog.definition(for: o.popNumber).style
            let paint = style.paints[min(o.variantIndex, style.paints.count - 1)]
            let fill = color(paint.fill)
            let glowColor = color(paint.glow)
            let R = o.r
            let pulse = style.shimmer ? 1 - 0.06 * Double(sin(o.phase * 2)) : 1

            let haloRect = CGRect(x: o.pos.x - R * 2.2, y: o.pos.y - R * 2.2,
                                  width: R * 4.4, height: R * 4.4)
            let grad = Gradient(stops: [
                .init(color: glowColor.opacity(style.haloOpacity * pulse), location: 0),
                .init(color: glowColor.opacity(0), location: 1)
            ])
            glow.fill(Path(ellipseIn: haloRect),
                      with: .radialGradient(grad, center: o.pos,
                                            startRadius: R * 0.6, endRadius: R * 2.2))

            let bodyRect = CGRect(x: o.pos.x - R, y: o.pos.y - R, width: R * 2, height: R * 2)
            context.fill(Path(ellipseIn: bodyRect), with: .color(fill.opacity(pulse)))

            // a whisper of a highlight so the orb reads as a bubble
            let hr = R * 0.26
            let hRect = CGRect(x: o.pos.x - R * 0.38 - hr, y: o.pos.y - R * 0.42 - hr,
                               width: hr * 2, height: hr * 2)
            glow.fill(Path(ellipseIn: hRect),
                      with: .color(Color.white.opacity(style.highlightOpacity)))
        }

        // shockwave rings
        for r in sim.rings {
            let style = PopCatalog.definition(for: r.popNumber).style
            let paint = style.paints[min(r.variantIndex, style.paints.count - 1)]
            let rect = CGRect(x: r.pos.x - r.r, y: r.pos.y - r.r,
                              width: r.r * 2, height: r.r * 2)
            glow.stroke(Path(ellipseIn: rect),
                        with: .color(color(paint.glow).opacity(Double(max(0, r.life) * 0.4))),
                        lineWidth: 1 + r.life * 2)
        }

        // particles, shaped per pop
        for p in sim.particles {
            let style = PopCatalog.definition(for: p.popNumber).style
            let paint = style.paints[min(p.variantIndex, style.paints.count - 1)]
            let a = max(0, p.life)
            let s = p.size * (0.5 + a * 0.5)
            let tint = GraphicsContext.Shading.color(color(paint.glow).opacity(Double(a)))
            drawParticle(p, shape: style.particleShape, size: s, tint: tint, into: &glow)
        }

        // point whispers
        for n in sim.notes {
            let a = Double(max(0, min(1, n.life)))
            let text = Text(n.text)
                .font(.system(size: 11, design: .serif))
                .italic()
                .foregroundColor(noteColor.opacity(a * 0.85))
            glow.draw(text, at: n.pos, anchor: .center)
        }
    }

    private func drawParticle(_ p: Particle, shape: ParticleShape, size s: CGFloat,
                              tint: GraphicsContext.Shading, into glow: inout GraphicsContext) {
        switch shape {
        case .dot:
            let rect = CGRect(x: p.pos.x - s, y: p.pos.y - s, width: s * 2, height: s * 2)
            glow.fill(Path(ellipseIn: rect), with: tint)

        case .spark:
            let angle = atan2(p.vel.dy, p.vel.dx)
            let dx = cos(angle) * s * 1.8
            let dy = sin(angle) * s * 1.8
            var path = Path()
            path.move(to: CGPoint(x: p.pos.x - dx, y: p.pos.y - dy))
            path.addLine(to: CGPoint(x: p.pos.x + dx, y: p.pos.y + dy))
            glow.stroke(path, with: tint, lineWidth: max(0.8, s * 0.6))

        case .petal:
            let angle = atan2(p.vel.dy, p.vel.dx)
            let rect = CGRect(x: p.pos.x - s * 1.5, y: p.pos.y - s * 0.7,
                              width: s * 3, height: s * 1.4)
            let transform = CGAffineTransform(translationX: p.pos.x, y: p.pos.y)
                .rotated(by: angle)
                .translatedBy(x: -p.pos.x, y: -p.pos.y)
            glow.fill(Path(ellipseIn: rect).applying(transform), with: tint)

        case .shard:
            let angle = atan2(p.vel.dy, p.vel.dx)
            var path = Path()
            path.move(to: point(from: p.pos, angle: angle, distance: s * 1.7))
            path.addLine(to: point(from: p.pos, angle: angle + 2.4, distance: s))
            path.addLine(to: point(from: p.pos, angle: angle - 2.4, distance: s))
            path.closeSubpath()
            glow.fill(path, with: tint)

        case .ring:
            let rect = CGRect(x: p.pos.x - s, y: p.pos.y - s, width: s * 2, height: s * 2)
            glow.stroke(Path(ellipseIn: rect), with: tint, lineWidth: max(0.7, s * 0.45))
        }
    }

    private func point(from origin: CGPoint, angle: CGFloat, distance: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + cos(angle) * distance,
                y: origin.y + sin(angle) * distance)
    }

    private func color(_ c: PopColor) -> Color {
        Color(red: c.r, green: c.g, blue: c.b)
    }
}
