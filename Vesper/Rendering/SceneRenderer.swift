import SwiftUI

// MARK: - Travel-only render cues (W05b)

// The two things the camera is allowed to do to the picture while the world is
// travelling between places: the ambient motes fall behind the field a little,
// and the light comes down a little. Both are stated here as PURE FUNCTIONS OF
// THE CAMERA'S CURRENT POSITION, so both are provable in `WorldRenderTests`
// without a screen, a clock, or a frame.
//
// THEY ARE RENDERING CONSTANTS, NOT CAMERA CONSTANTS, and they live here
// rather than in `WorldCamera.Config` deliberately. The camera decides how the
// world moves; this file decides what that looks like, and it may never decide
// the first thing. Turning either number to zero must leave the navigation
// itself — distances, durations, ceilings, gates — bit-identical.
//
// NEITHER IS AN INTEGRATION. Each reads where the camera IS this frame and
// answers for this frame; neither accumulates across frames, so neither can
// drift, and rendering stays stateless. That is also why neither is multiplied
// by the clamped frame factor `f` that every piece of MOTION in this app
// scales by — see the paragraph on `moteParallax`, which a later reader will
// otherwise arrive to "fix".
enum WorldRender {

    // MARK: Mote parallax

    // The fraction of the field's own travel the ambient motes give up as she
    // leaves a place: they translate at 1 − this of the field's rate, so the
    // field reads as the nearer plane and the dust as the further one behind
    // it.
    //
    // WHY 0.30 AND NOT MORE. The motes are the only things on the field with
    // no fixed relationship to anything else, which cuts both ways: nobody can
    // see that a faint dot is 70 pt from where a rigid world would have put
    // it, but everybody can see a background that has come apart from its
    // foreground. 0.30 puts the peak displacement at 0.087 screen heights —
    // 73 pt on the 844 pt reference screen — which is depth in peripheral
    // vision across a 300–650 ms settle, and is nothing at all when the world
    // is standing still, because at rest it is exactly zero (below).
    static let moteLag: CGFloat = 0.30

    // THE MOTE LAYER'S TRANSLATION WITHIN THE FIELD CANVAS, in points, for a
    // camera at `offset` (normalized screen heights — the camera's own unit).
    // Positive is down the screen.
    //
    // `WorldView.movingBody` has already translated the whole field body by
    // `(restOffset(.field) − offset) · h`; this is what the dust gets ON TOP
    // of that, so the motes' NET travel is a fraction of the field's. It is
    // applied as a drawing-time translation and nothing else — the mote
    // positions in `sim` are never touched, because rendering reads and never
    // writes.
    //
    // THE SHAPE is `u(1 − u²)`, where `u` is the axis position in place-units.
    // Three properties, all of them load-bearing:
    //
    //   * it is exactly `u` near a place centre, so as she leaves the field
    //     the motes really do travel at `1 − moteLag` of the field's rate. The
    //     parallax is honest where she is actually looking at it;
    //   * it is EXACTLY ZERO at every rest offset — u = 0 and u = ±1, and
    //     `step(dt:)` lands the camera exactly on `restOffset`, in as many
    //     words, rather than near it. So a resting frame in ANY place is drawn
    //     exactly as it would be if this function did not exist. Nothing about
    //     where she has been survives her arriving;
    //   * its magnitude never exceeds |u|, which is what keeps the effect
    //     invisible at the edges. The lag is always SMALLER than the field's
    //     own displacement, so the depopulated edge of the mote layer is
    //     always further off screen than the edge of the field canvas that is
    //     clipping it: there is no offset, anywhere on the axis, at which this
    //     opens a mote-free band into view.
    //
    // REDUCE MOTION FALLS OUT OF THE ARITHMETIC AND NEEDS NO SPECIAL CASE.
    // Under RM the camera's `offset` is identically zero (barrier condition
    // 11), so `u` is zero, so the shape is zero, so the dust sits exactly
    // where the field does and the world produces no translation of any kind.
    // The caller passes `camera.offset` — the RM-aware accessor — for exactly
    // this reason; handing this function `axisPosition` instead would
    // reintroduce translation on the one path that may not have any.
    //
    // NO FRAME FACTOR, DELIBERATELY. This is not motion: it is a pure function
    // of where the camera is on this frame, and the camera's own step is what
    // is already frame-rate independent. Multiplying by `f`, or accumulating a
    // per-frame delta into a stored offset, would make the dust drift by a
    // different amount on a 60 Hz phone than on a 120 Hz one and would make
    // rendering stateful. If you came here to add `f`, this paragraph is why
    // it is not here.
    static func moteParallax(offset: CGFloat,
                             travelPerPlace: CGFloat,
                             viewHeight: CGFloat) -> CGFloat {
        // Guarded exactly as the camera guards its own divisions by
        // `travelPerPlace`: a degenerate world draws without the cue rather
        // than drawing a NaN into every mote on the field.
        guard travelPerPlace > 0, viewHeight > 0, offset.isFinite else { return 0 }
        let u = min(1, max(-1, offset / travelPerPlace))
        return moteLag * travelPerPlace * viewHeight * u * (1 - u * u)
    }

    // MARK: Transit luminance

    // BARRIER CONDITION 14. The peak luminance the world gives up while it is
    // travelling, as a fraction: 0.05 → the scene is drawn at 95% of its usual
    // light at the midpoint of a leg, and at 100% everywhere else.
    //
    // This is a vestibular-comfort measure, not a flourish — less luminous
    // energy in a large moving field is measurably less provoking — so it is
    // sized against the risk it carries rather than against how much of it can
    // be seen. THE RISK IS FLICKER: this game's whole claim is calm, and a
    // visible pulse on every navigation would be worse than no dimming at all.
    //
    // WHY 0.05. It is the largest step the cue can produce in a single frame
    // (see below), and 5% of the light in a dark scene of muted pastels is at
    // or under the threshold at which a suprathreshold luminance step is
    // noticed — and the only frames that can produce the whole 5% at once are
    // frames on which the world is visibly changing pace anyway, which is the
    // most masked moment on the axis. It is deliberately at the conservative
    // end: if the motion-safety screen (W22) reports discomfort during
    // transits, THIS is the number to turn up, and it is the only one here
    // that may be turned without touching the camera.
    static let transitDim: Double = 0.05

    // THE SCENE'S LUMINANCE MULTIPLIER for this frame, in (1 − transitDim, 1].
    //
    // `isTransitioning` IS THE QUESTION, AND THE WHOLE OF IT — not `flow`, not
    // `exceedsTransitFlow`. That is the R-ARCH carry-forward onto W05, and the
    // reason is on the camera's own accessor: `flow` is derived from
    // translation, and under Reduce Motion there is none, so a cue keyed on it
    // would never fire on the accessible path — where two whole places are
    // still crossfading through each other and the light is exactly as loud.
    // `isTransitioning` answers true for the whole of a Reduce Motion settle,
    // which is why it is the only question asked here.
    //
    // THE CROSSFADE IS THE SHAPE, NOT A SECOND QUESTION. `t` is the camera's
    // own progress between the two places it is bracketed by, and `4t(1 − t)`
    // rises from nothing at the place she is leaving to the full attenuation
    // at the midpoint and back to nothing at the place she is arriving at. It
    // is the only per-frame value that is continuous in BOTH motion modes, and
    // it is what keeps the ordinary navigation — commit from rest, settle,
    // arrive — free of any step at all: the gate opens and closes at moments
    // when the shape is ~0, so nothing jumps at either end.
    //
    // MONOTONE, IN THE SENSE CONDITION 12 MEANS IT: single-signed and
    // non-overshooting. The multiplier is never greater than 1, so the world
    // never brightens past its own light on the way back — there is no
    // luminance rubber-band — and it never leaves the band, so the scene
    // cannot be pumped by a repeated gesture.
    //
    // EXACTLY 1 AT REST, TWICE OVER, because "no residual dimming, ever" is
    // the requirement and one guarantee is not enough: the gate is false the
    // moment the camera reaches rest, AND `t` is 1 at a place centre, so
    // `4t(1 − t)` is exactly zero there even if the gate were somehow open.
    // Both are exact in floating point, not merely small.
    //
    // WHAT CAN STEP, STATED HONESTLY. The gate is a Bool, so a frame on which
    // it flips carries `transitDim × 4t(1 − t)` in one go. Two cases, both
    // measured across a sweep of distances, seeded velocities, frame rates and
    // both motion modes. CLOSING, it flips as a settle runs out of speed near
    // the place it is arriving at, where the shape is at most 0.37 — under 1.9%
    // of the light, and for a full-place transit far less than that. OPENING,
    // a drag whose finger speed crosses the flow threshold at the middle of a
    // leg flips with the shape near its peak: up to the whole 5%, on a frame
    // where the world is visibly accelerating under her own hand. That worst
    // case is the reason this factor is 0.05 and not 0.12.
    static func transitLuminance(isTransitioning: Bool, crossfade t: CGFloat) -> Double {
        guard isTransitioning else { return 1 }
        let progress = Double(min(1, max(0, t.isFinite ? t : 1)))
        let bell = 4 * progress * (1 - progress)
        return 1 - transitDim * bell
    }
}

// MARK: - Scene

// Draws the simulation into a Canvas, styled entirely by each entity's pop
// definition (PopStyle). Read-only: must never mutate sim state.
struct SceneRenderer {

    private let moteColor = Color(red: 214/255, green: 208/255, blue: 235/255)
    private let noteColor = Color(red: 210/255, green: 202/255, blue: 232/255)

    // `moteParallax` is the dust layer's drawing-time translation in points
    // (W05b), and it defaults to none so that the v1.2 field — `ContentView`,
    // which has no camera at all — keeps calling this exactly as it always
    // has and draws exactly what it always did.
    func draw(_ sim: GameSimulation, into context: inout GraphicsContext, size: CGSize,
              moteParallax: CGFloat = 0) {
        var glow = context
        glow.blendMode = .plusLighter

        // ambient motes — faint depth behind everything, and the one layer
        // that does not travel with the field at the field's own rate (W05b).
        //
        // THE PARALLAX IS APPLIED TO A COPY OF THE CONTEXT, never to the
        // positions: `sim.motes` belongs to the simulation and rendering reads
        // and never writes. `WorldRender.moteParallax` is a pure function of
        // the camera's current offset, so this is zero at rest in every place
        // and identically zero under Reduce Motion — a still world draws its
        // dust exactly where the field is.
        var dust = glow
        dust.translateBy(x: 0, y: moteParallax)
        for m in sim.motes {
            let a = Double(m.alpha * (0.6 + 0.4 * sin(m.phase)))
            let rect = CGRect(x: m.pos.x - m.size, y: m.pos.y - m.size,
                              width: m.size * 2, height: m.size * 2)
            dust.fill(Path(ellipseIn: rect), with: .color(moteColor.opacity(a)))
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
