import SwiftUI

// MARK: - Camera render cues (W05b, W05c)

// The three things the camera is allowed to do to the picture. Two of them
// belong to TRAVEL — while the world is moving between places the ambient
// motes fall behind the field a little and the light comes down a little — and
// the third belongs to ARRIVING NOWHERE: a soft brightening at the leading
// edge when she asks to travel past the end of the axis (W05c).
//
// THEY ARE RENDERING CONSTANTS, NOT CAMERA CONSTANTS, and they live here
// rather than in `WorldCamera.Config` deliberately. The camera decides how the
// world moves; this file decides what that looks like, and it may never decide
// the first thing. Turning any of these numbers to zero must leave the
// navigation itself — distances, durations, ceilings, gates, and `isAtRest` —
// bit-identical.
//
// ALL THREE ARE PURE FUNCTIONS OF A SINGLE ARGUMENT THE CAMERA HANDS THEM, so
// all three are provable in `WorldRenderTests` without a screen, a Canvas or a
// wall-clock. NONE OF THEM IS AN INTEGRATION: nothing here accumulates across
// frames, so nothing here can drift, and rendering stays stateless. That is
// also why none of them is multiplied by the clamped frame factor `f` that
// every piece of MOTION in this app scales by — see the paragraph on
// `moteParallax`, which a later reader will otherwise arrive to "fix".
//
// WHERE THE THIRD ONE DIFFERS, STATED SO IT IS NOT MISREAD AS AN EXCEPTION.
// The travel cues take the camera's POSITION; the acknowledgement takes a
// normalized level from a TIME ENVELOPE, because "she asked to go past the end
// of the world" is an event rather than a place, and an event with no duration
// is a single frame nobody sees. The envelope itself — its rise, its fall, its
// damping, and its exact return to zero — is `WorldCamera`'s, stepped in
// `step(dt:)` where every other clock in the world layer is stepped. This file
// still only scales.
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

    // MARK: End-of-axis acknowledgement (W05c)

    // THE THIRD CUE, AND THE ONLY ONE THAT IS NOT A FUNCTION OF POSITION.
    // The other two read where the camera IS on this frame; this one reads a
    // time envelope the camera steps, because "she asked to go past the end of
    // the world" is an EVENT and an event has to have a duration or it is a
    // single frame nobody sees. `WorldCamera.acknowledgementLevel` owns the
    // envelope and everything about its timing, damping and exact return to
    // zero; this file owns only what one unit of it looks like.
    //
    // THE SPLIT IS THE SAME ONE AS ABOVE and matters more here than anywhere:
    // turning `edgeAcknowledgementPeak` to zero must leave the navigation —
    // distances, durations, ceilings, gates, and `isAtRest` — bit-identical.
    // It does, because the camera never reads this file.

    // THE PEAK OPACITY of the acknowledgement's brightest pixel: the row
    // exactly on the edge of the screen she asked to travel past, at the top
    // of a fully undamped envelope. Everything else in the band is dimmer, and
    // every repeat is dimmer still.
    //
    // WHY 0.10, ANCHORED RATHER THAN GUESSED. It is the alpha `SkyView` gives
    // a QUIET STAR'S HALO (`glowColor.opacity(0.10)`) — the dimmest light the
    // world already draws on purpose, and one a person sits and looks at
    // without ever calling it bright. At its very loudest, this cue is exactly
    // as loud as a star at rest. It is also under the 0.12 white hairline the
    // cards use for "just visible", and it is applied to a muted pastel rather
    // than to white.
    //
    // AND IT IS SIZED AGAINST BEING SEEN AS A FLASH, not against being seen.
    // Averaged over the band the added alpha is about 0.03, because the
    // falloff spends most of its depth near zero; averaged over the whole
    // screen it is under 0.006. If W22's motion-safety screen reports that the
    // acknowledgement is missed rather than felt, THIS is the number to turn
    // up, and it is the only one here that may be turned without touching the
    // camera.
    static let edgeAcknowledgementPeak: Double = 0.10

    // How deep into the screen the light reaches, in screen heights: 0.18, or
    // 152 pt on the 844 pt reference screen.
    //
    // DEEP ENOUGH NOT TO BE A LINE. A bright hairline at the edge of a display
    // reads as a rendering artefact — something has gone wrong — where a soft
    // band the depth of the world's own vignette reads as the edge of the
    // world catching a little light, which is the sentence this cue is trying
    // to say.
    //
    // AND IT NEVER CROSSES A WORD. The whispers sit 60 pt from the head and
    // 34 pt from the foot, so a band this deep passes behind one — but it
    // never has to, because the end of the axis and the end with no whisper
    // are the same end (`WorldView.wayfindingWhisper` omits the whisper that
    // would name the place she is already in). The light always answers on the
    // empty edge.
    static let edgeAcknowledgementDepth: CGFloat = 0.18

    // THE BAND'S OPACITY THIS FRAME, in [0, edgeAcknowledgementPeak].
    //
    // LINEAR IN THE LEVEL, DELIBERATELY. The camera's envelope already IS the
    // shape — rise, peak, settle back — and a curve laid over it here would be
    // the second curve in a fight over one number, which is the same mistake
    // ruling 7 bars when it bars `withAnimation` on a camera value. This
    // function scales; it does not shape.
    //
    // EXACTLY ZERO AT ZERO, which is the property the pause predicate rides
    // on: the camera decays its level to the literal 0 and parks there, and
    // `0 × peak` is exactly 0, so the last frame before the world pauses draws
    // precisely the picture it drew before any of this existed.
    //
    // A non-finite or out-of-range level resolves to no light at all rather
    // than to a NaN alpha — failing toward the picture that existed before
    // W05c, exactly as `transitLuminance` fails toward full light.
    static func edgeAcknowledgementOpacity(level: CGFloat) -> Double {
        guard level.isFinite, level > 0 else { return 0 }
        return edgeAcknowledgementPeak * Double(min(1, level))
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
              moteParallax: CGFloat = 0,
              horizon: HorizonRender.Horizon = .none) {
        // THE HORIZON, AT THE VERY BACK OF THE DRAW ORDER — the join between
        // the sky and the field, drawn behind every mote, orb, ring and
        // particle so it can never compete with one. Two gradient fills, and
        // none at all when there is no light to draw. `HorizonRenderer` owns
        // all of it; this is the only line the field's renderer needs to know.
        HorizonRender.draw(horizon, into: &context, size: size)

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
            // DEPTH. `spawn` is how far up an orb has risen: 0 at the bottom
            // of the field, 1 on the surface. An orb still coming up is drawn
            // smaller and fainter — it is under something — and reaches full
            // size and full light exactly as it surfaces.
            //
            // This is what separates "rising" from "appearing". A thing that
            // fades in at full size has teleported; a thing that grows and
            // brightens from small and dim was already there.
            let depth = Double(min(1, max(0, o.spawn)))
            let depthAlpha = GameConfig.depthMinAlpha
                + (1 - GameConfig.depthMinAlpha) * depth
            let R = o.r * (GameConfig.depthMinScale
                           + (1 - GameConfig.depthMinScale) * CGFloat(depth))
            let pulse = (style.shimmer ? 1 - 0.06 * Double(sin(o.phase * 2)) : 1) * depthAlpha

            // A BALLOON ANIMAL IS NOT A SPHERE, so it does not borrow the
            // sphere's body. Everything computed above — the pop's own paint,
            // the depth it has risen to, the pulse, the radius — is handed
            // over unchanged and the animal is drawn in the same halo,
            // body-and-highlight grammar; only the silhouette differs. Drawn
            // here rather than in the kind switch below because that switch
            // runs after the disc is already down, and the whole point of
            // this kind is that there is no disc.
            if case .animal(let animal) = o.kind {
                drawAnimal(animal, orb: o, radius: R, pulse: pulse,
                           fill: fill, glowColor: glowColor, style: style,
                           into: &context, glow: &glow)
                continue
            }

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

            // WHAT KIND OF ORB THIS IS, SAID IN LIGHT.
            //
            // A mechanic she cannot see is a mechanic she cannot learn, and
            // the field is where all of the teaching happens — there is no
            // tutorial and there is not going to be one. So each kind carries
            // one mark, and each mark is a HINT AT ITS BEHAVIOUR rather than a
            // badge: the splitter shows the smaller orb waiting inside it, the
            // generator breathes open like something with more to give, the
            // drifter is drawn a touch softer, the way a thing that is about
            // to move away already looks.
            //
            // No icons, no outlines, nothing saturated — these are the same
            // paints the orb already carries, at different radii.
            switch o.kind {
            case .plain:
                break

            // Drawn above, in its own silhouette, and the loop has already
            // moved on by the time this switch runs. The case is here so the
            // switch stays exhaustive and so a later reader looking for where
            // an animal is drawn finds the answer beside the others.
            case .animal:
                break

            case .splitter:
                // The doll inside the doll.
                let innerR = R * GameConfig.splitChildScale * 0.62
                let inner = CGRect(x: o.pos.x - innerR, y: o.pos.y - innerR,
                                   width: innerR * 2, height: innerR * 2)
                glow.stroke(Path(ellipseIn: inner),
                            with: .color(glowColor.opacity(0.5 * pulse)),
                            lineWidth: 1)

            case .drifter:
                // Softer-edged: a ring just outside the body, like something
                // already half-somewhere-else.
                let haze = R * 1.16
                let ring = CGRect(x: o.pos.x - haze, y: o.pos.y - haze,
                                  width: haze * 2, height: haze * 2)
                glow.stroke(Path(ellipseIn: ring),
                            with: .color(glowColor.opacity(0.26 * pulse)),
                            lineWidth: 1)

            case .generator:
                // Two slow rings, breathing on the orb's own phase — the
                // grammar this project already uses for "there is more here".
                // It breathes rather than blinks (05 §3).
                let breath = 1 + 0.08 * Double(sin(o.phase * 1.2))
                for k in 1...2 {
                    let rr = R * (1.1 + 0.22 * CGFloat(k)) * CGFloat(breath)
                    let rect = CGRect(x: o.pos.x - rr, y: o.pos.y - rr,
                                      width: rr * 2, height: rr * 2)
                    glow.stroke(Path(ellipseIn: rect),
                                with: .color(glowColor.opacity((0.34 - 0.12 * Double(k)) * pulse)),
                                lineWidth: 1)
                }
            }
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

        // THE SMOKE, UNDER EVERYTHING THE SHELLS THREW.
        //
        // Drawn before the stars and after the orbs, so a haze sits behind
        // the field rather than over it — she must never lose an orb in it.
        // Puffs are additive and overlapping, which is what makes them STACK:
        // one is a wisp, six across a display build the thickening bank a
        // real show leaves hanging.
        for puff in sim.smoke {
            let definition = FireworkCatalog.definition(for: puff.fireworkID)
            let paint = definition.paints[min(puff.variantIndex, definition.paints.count - 1)]
            let a = Double(max(0, min(1, puff.life)))
            let r = puff.radius
            let rect = CGRect(x: puff.pos.x - r, y: puff.pos.y - r,
                              width: r * 2, height: r * 2)
            let tint = color(paint.glow)
            glow.fill(Path(ellipseIn: rect),
                      with: .radialGradient(
                        Gradient(stops: [
                            .init(color: tint.opacity(a * 0.055), location: 0),
                            .init(color: tint.opacity(a * 0.028), location: 0.55),
                            .init(color: tint.opacity(0), location: 1),
                        ]),
                        center: puff.pos, startRadius: 0, endRadius: r))
        }

        // shells still on the field or in flight
        for shell in sim.fireworks where shell.phase != .spent {
            drawFirework(shell, into: &glow)
        }

        // particles, shaped per pop — or per shell, when a shell threw them
        for p in sim.particles {
            let style = PopCatalog.definition(for: p.popNumber).style
            var paint = style.paints[min(p.variantIndex, style.paints.count - 1)]
            if let id = p.fireworkID {
                let definition = FireworkCatalog.definition(for: id)
                paint = definition.paints[min(p.variantIndex, definition.paints.count - 1)]
            }
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

    /// A shell: waiting on the field, or climbing.
    ///
    /// It is deliberately NOT a sphere. The owner's complaint that a hundred
    /// pops look alike is a complaint about variations on a circle, and the
    /// first job of a firework is to be unmistakably not one of them — so a
    /// waiting shell is a small tapered body with a lit tip, and a climbing
    /// one is that body stretched along its own heading.
    private func drawFirework(_ shell: Firework, into glow: inout GraphicsContext) {
        let definition = FireworkCatalog.definition(for: shell.definitionID)
        let paint = definition.paints[min(shell.variantIndex, definition.paints.count - 1)]
        let tint = color(paint.glow)
        let body = color(paint.fill)
        let grown = min(1, max(0, shell.spawn))
        guard grown > 0.01 else { return }

        // THE CORD, drawn first so the shell sits on top of it.
        //
        // Two tiers: the part still to burn, and the part already gone. The
        // burnt end is drawn — dimmer and thinner, not deleted — because a
        // fuse that vanishes as it burns loses the thing that makes waiting
        // legible. She can see how much is left.
        if shell.fuseNodes.count > 1, shell.phase != .spent {
            var burned: CGFloat = 0
            if case .fuse(let b) = shell.phase { burned = b }
            let last = shell.fuseNodes.count - 1
            let sparkAt = (1 - burned) * CGFloat(last)

            for k in 0..<last {
                let a = shell.fuseNodes[k], b = shell.fuseNodes[k + 1]
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)
                // Segments beyond the spark have already burned.
                let spent = CGFloat(k + 1) > sparkAt
                glow.stroke(line,
                            with: .color(tint.opacity((spent ? 0.12 : 0.34) * Double(grown))),
                            style: StrokeStyle(lineWidth: spent ? 0.8 : 1.6, lineCap: .round))
            }

            // The spark itself, where it is burning right now.
            if case .fuse = shell.phase {
                let k = min(last - 1, Int(sparkAt))
                let t = sparkAt - CGFloat(k)
                let a = shell.fuseNodes[k], b = shell.fuseNodes[k + 1]
                let sp = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                let sr: CGFloat = 3.2
                glow.fill(Path(ellipseIn: CGRect(x: sp.x - sr * 3, y: sp.y - sr * 3,
                                                 width: sr * 6, height: sr * 6)),
                          with: .radialGradient(
                            Gradient(stops: [
                                .init(color: tint.opacity(0.4), location: 0),
                                .init(color: tint.opacity(0), location: 1),
                            ]),
                            center: sp, startRadius: 0, endRadius: sr * 3))
                glow.fill(Path(ellipseIn: CGRect(x: sp.x - sr, y: sp.y - sr,
                                                 width: sr * 2, height: sr * 2)),
                          with: .color(tint.opacity(0.95)))
            }
        }

        var heading = -CGFloat.pi / 2
        var stretch: CGFloat = 1
        if case .rising = shell.phase {
            let dx = shell.apex.x - shell.origin.x
            let dy = shell.apex.y - shell.origin.y
            if dx != 0 || dy != 0 { heading = atan2(dy, dx) }
            stretch = 2.1
        }

        let h = 13 * grown * stretch
        let w = 4.4 * grown

        var path = Path()
        path.move(to: CGPoint(x: shell.pos.x + cos(heading) * h,
                              y: shell.pos.y + sin(heading) * h))
        let left = heading + .pi * 0.5
        let right = heading - .pi * 0.5
        path.addQuadCurve(
            to: CGPoint(x: shell.pos.x - cos(heading) * h * 0.7,
                        y: shell.pos.y - sin(heading) * h * 0.7),
            control: CGPoint(x: shell.pos.x + cos(left) * w,
                             y: shell.pos.y + sin(left) * w))
        path.addQuadCurve(
            to: CGPoint(x: shell.pos.x + cos(heading) * h,
                        y: shell.pos.y + sin(heading) * h),
            control: CGPoint(x: shell.pos.x + cos(right) * w,
                             y: shell.pos.y + sin(right) * w))
        path.closeSubpath()
        glow.fill(path, with: .color(body.opacity(0.72 * Double(grown))))

        // The lit tip — the fuse, which is the part that says "this goes".
        let tipR = 2.6 * grown
        let tip = CGPoint(x: shell.pos.x + cos(heading) * h,
                          y: shell.pos.y + sin(heading) * h)
        let halo = CGRect(x: tip.x - tipR * 4, y: tip.y - tipR * 4,
                          width: tipR * 8, height: tipR * 8)
        glow.fill(Path(ellipseIn: halo),
                  with: .radialGradient(
                    Gradient(stops: [
                        .init(color: tint.opacity(0.34 * Double(grown)), location: 0),
                        .init(color: tint.opacity(0), location: 1),
                    ]),
                    center: tip, startRadius: 0, endRadius: tipR * 4))
        glow.fill(Path(ellipseIn: CGRect(x: tip.x - tipR, y: tip.y - tipR,
                                         width: tipR * 2, height: tipR * 2)),
                  with: .color(tint.opacity(0.9 * Double(grown))))
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
