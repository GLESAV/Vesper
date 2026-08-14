import SwiftUI

// MARK: - Palette

struct Paint {
    let fill: Color
    let glow: Color
}

// The muted pastel palette — values unchanged from v1.0. Order matters:
// the simulation refers to these by index.
let palette: [Paint] = [
    Paint(fill: Color(red: 233/255, green: 230/255, blue: 242/255),
          glow: Color(red: 223/255, green: 220/255, blue: 238/255)), // off-white
    Paint(fill: Color(red: 231/255, green: 213/255, blue: 192/255),
          glow: Color(red: 220/255, green: 190/255, blue: 160/255)), // sand
    Paint(fill: Color(red: 217/255, green: 201/255, blue: 230/255),
          glow: Color(red: 195/255, green: 175/255, blue: 220/255)), // lilac
    Paint(fill: Color(red: 198/255, green: 220/255, blue: 216/255),
          glow: Color(red: 175/255, green: 205/255, blue: 198/255)), // sage
    Paint(fill: Color(red: 230/255, green: 205/255, blue: 212/255),
          glow: Color(red: 220/255, green: 180/255, blue: 190/255)), // dusty rose
]

// MARK: - Renderer

// Draws the simulation into a Canvas. Read-only: must never mutate sim state.
struct SceneRenderer {

    private let moteColor = Color(red: 214/255, green: 208/255, blue: 235/255)

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
            let paint = palette[o.paintIndex]
            let R = o.r
            let haloRect = CGRect(x: o.pos.x - R * 2.2, y: o.pos.y - R * 2.2,
                                  width: R * 4.4, height: R * 4.4)
            let grad = Gradient(stops: [
                .init(color: paint.glow.opacity(0.18), location: 0),
                .init(color: paint.glow.opacity(0), location: 1)
            ])
            glow.fill(Path(ellipseIn: haloRect),
                      with: .radialGradient(grad, center: o.pos,
                                            startRadius: R * 0.6, endRadius: R * 2.2))

            let bodyRect = CGRect(x: o.pos.x - R, y: o.pos.y - R, width: R * 2, height: R * 2)
            context.fill(Path(ellipseIn: bodyRect), with: .color(paint.fill))

            // a whisper of a highlight so the orb reads as a bubble
            let hr = R * 0.26
            let hRect = CGRect(x: o.pos.x - R * 0.38 - hr, y: o.pos.y - R * 0.42 - hr,
                               width: hr * 2, height: hr * 2)
            glow.fill(Path(ellipseIn: hRect), with: .color(Color.white.opacity(0.14)))
        }

        // shockwave rings
        for r in sim.rings {
            let rect = CGRect(x: r.pos.x - r.r, y: r.pos.y - r.r,
                              width: r.r * 2, height: r.r * 2)
            glow.stroke(Path(ellipseIn: rect),
                        with: .color(palette[r.paintIndex].glow.opacity(Double(max(0, r.life) * 0.4))),
                        lineWidth: 1 + r.life * 2)
        }

        // particles
        for p in sim.particles {
            let a = max(0, p.life)
            let s = p.size * (0.5 + a * 0.5)
            let rect = CGRect(x: p.pos.x - s, y: p.pos.y - s, width: s * 2, height: s * 2)
            glow.fill(Path(ellipseIn: rect),
                      with: .color(palette[p.paintIndex].glow.opacity(Double(a))))
        }
    }
}
