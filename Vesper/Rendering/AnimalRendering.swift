import SwiftUI

// DRAWING A BALLOON ANIMAL.
//
// The owner's complaint that started this — "the pops look too similar across
// the 100" — is a complaint about variations on a circle. A hundred paints on
// one sphere is one shape, and the eye reads shape long before it reads hue.
// So the first job here is to be UNMISTAKABLY NOT A SPHERE, at a glance, from
// arm's length, in the dark.
//
// The second job is to still be one of this game's objects. It is drawn in the
// pop's own paint, in the same three passes an orb is drawn in — a soft
// additive halo, a flat body, a whisper of a highlight — so an animal reads as
// the field's own material twisted into a creature rather than as a sticker
// laid on top of it. Nothing here is saturated, nothing is outlined, and there
// is no icon anywhere in it.
extension SceneRenderer {

    /// One animal, in the orb's place.
    ///
    /// `radius` and `pulse` arrive already carrying the orb's depth — an
    /// animal still rising is drawn small and dim exactly as an orb is — and
    /// `fill`/`glowColor` are the pop's own paint, resolved by the caller.
    func drawAnimal(_ animal: AnimalPop,
                    orb o: Orb,
                    radius R: CGFloat,
                    pulse: Double,
                    fill: Color,
                    glowColor: Color,
                    style: PopStyle,
                    into context: inout GraphicsContext,
                    glow: inout GraphicsContext) {

        // SHYNESS, SAID IN LIGHT. While it is keeping to itself it is a little
        // dimmer — the way a thing at the edge of the lamplight is — and it
        // comes to full presence as it settles and comes out. This is the
        // phase drawn rather than announced: no badge, no meter, nothing that
        // could be read as a countdown, just something becoming more present.
        let shy = max(0, min(1, animal.shyness))
        let presence = pulse * Double(0.64 + 0.36 * (1 - shy))

        // Which way it faces. A creature that always looked right would read
        // as a decal; turning with its drift is the cheapest thing that makes
        // it read as alive. Bare `< 0` rather than a threshold, because the
        // sign of a drift this slow changes only at a wall bounce.
        let facing: CGFloat = o.vel.dx < 0 ? -1 : 1
        let reach = animal.shape.reach

        // THE SILHOUETTE AS ONE PATH. Every lobe and every joining lobe is a
        // subpath of a single `Path`, filled once under the nonzero winding
        // rule, so the overlaps union instead of stacking. Filling them one by
        // one at `presence` below 1 would darken every seam and the animal
        // would read as a pile of circles, which is exactly what a balloon
        // animal is not.
        var body = Path()
        for (offset, lobeR) in animal.shape.joinedLobes {
            let rr = lobeR * R
            guard rr > 0.01 else { continue }
            let centre = CGPoint(x: o.pos.x + offset.x * R * facing,
                                 y: o.pos.y + offset.y * R)
            body.addEllipse(in: CGRect(x: centre.x - rr, y: centre.y - rr,
                                       width: rr * 2, height: rr * 2))
        }

        // The halo, sized from how far the silhouette actually reaches so a
        // long-eared shape is not lit as though it were a ball.
        let haloR = R * reach * 1.8
        let haloRect = CGRect(x: o.pos.x - haloR, y: o.pos.y - haloR,
                              width: haloR * 2, height: haloR * 2)
        let grad = Gradient(stops: [
            .init(color: glowColor.opacity(style.haloOpacity * presence), location: 0),
            .init(color: glowColor.opacity(0), location: 1)
        ])
        glow.fill(Path(ellipseIn: haloRect),
                  with: .radialGradient(grad, center: o.pos,
                                        startRadius: R * 0.5, endRadius: haloR))

        // FILLED, NEVER STROKED, and that is not a stylistic preference. A
        // stroke would outline every subpath — including the joining lobes
        // buried inside the body — and the creature would come apart into the
        // pile of circles it is made of. The nonzero fill is the only
        // operation that treats this path as one shape.
        context.fill(body, with: .color(fill.opacity(presence)),
                     style: FillStyle(eoFill: false))

        // The same whisper of a highlight every orb carries, placed on the
        // largest lobe — the body — rather than on the orb's centre, so it
        // sits where the light would actually catch.
        if let biggest = animal.shape.lobes.max(by: { $0.1 < $1.1 }) {
            let offset = biggest.0
            let bodyR = biggest.1 * R
            let centre = CGPoint(x: o.pos.x + offset.x * R * facing,
                                 y: o.pos.y + offset.y * R)
            let hr = bodyR * 0.26
            let hRect = CGRect(x: centre.x - bodyR * 0.38 * facing - hr,
                               y: centre.y - bodyR * 0.42 - hr,
                               width: hr * 2, height: hr * 2)
            glow.fill(Path(ellipseIn: hRect),
                      with: .color(Color.white.opacity(style.highlightOpacity * presence)))
        }
    }
}
