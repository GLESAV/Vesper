import Foundation
import SwiftUI

// MARK: - The horizon
//
// THE SEAM BETWEEN THE SKY AND THE FIELD, ANSWERED WITH LIGHT.
//
// The owner: "can we make the border between 'the sky' and gameplay either
// seamless (transitioning) or delineated (bordered aggressively; one or the
// other)". This file is the seamless answer, and the choice was not a taste
// call: the product's whole claim is that this is ONE continuous world on one
// vertical axis (04 §2, the One Beautiful Place pillar), and a drawn border
// would be the app saying the opposite of its own pillar in the loudest place
// it has.
//
// WHAT WAS ACTUALLY WRONG. Nothing was drawn at the join at all. The ground is
// a radial gradient that swaps colour per place and crossfades on ARRIVAL, so
// between the sky and the field there was a colour change once you got there
// and nothing whatsoever on the way. And the join is not off screen, which is
// the part that makes this worth drawing: `travelPerPlace` is 0.75 screen
// heights, so THE TWO PLACES PERMANENTLY OVERLAP BY A QUARTER OF A SCREEN.
//
//     field top edge      = (0 − offset) · h
//     sky bottom edge     = (−0.75 − offset) · h + h
//     the gap between them = (1 − travelPerPlace) · h  = 0.25 h, ALWAYS
//
// That band is on screen in both places she can see it from — the top quarter
// of the screen at rest on the field, the bottom quarter at rest in the sky —
// and it was where the sky's stars simply stopped and the field's motes simply
// started, along a line. THE HORIZON IS DRAWN EXACTLY IN THAT OVERLAP: light
// where the two places really do coexist, and nowhere else. There is no
// invented geometry here — the band is a fact about the axis, so it stays glued
// to the join at every camera position without anything having to track it.
//
// WHERE IT IS DRAWN, AND WHY THAT IS THE ONLY PLACE IT COULD BE. Inside the
// field's `Canvas`, at the very back of `SceneRenderer.draw`, behind every
// mote, orb, ring and particle. Ruling 7 forbids mirroring a camera value into
// anything SwiftUI diffs; a ground interpolated per frame in a view would
// invalidate that view at frame rate and undo the entire reason the camera
// lives outside the view system. A draw closure may read what a view may not,
// which is why `moteParallax` is already threaded from `WorldView.movingBody`
// into `SceneRenderer.draw` — this follows that precedent exactly, and adds
// nothing published, nothing `@State`, and no `withAnimation`.
//
// AND IT NEEDS NO TRANSLATION OF ITS OWN. The band's top is the field canvas's
// own top edge, so it travels with the field body, for free, at the field's
// exact rate. The one per-frame scalar this file wants from the camera is HOW
// MUCH light the join is carrying (`presence`) — the shape and the position
// are geometry. That is also why Reduce Motion needs no special drawing case:
// under RM `camera.offset` is identically zero, the field body does not
// translate, and the places crossfade — so the horizon crossfades with the
// field and moves not one point. The `reduceMotion` argument to `state` is
// belt-and-braces on exactly that, written out so the accessible path is a
// decision rather than a consequence of a value happening to be 0.
//
// A4, AND WHAT THIS IS RELATIVE TO IT. `docs/sky_assets.md` specs a painted
// "horizon glow" plate at the foot of the sky as asset A4, medium value. This
// is the procedural version that ships first and remains the fallback: it costs
// two gradient fills, adapts to any screen and any `travelPerPlace`, and sits
// on the field's side of the same join. If A4 is ever commissioned it lands
// over this, and this is what it degrades to.
enum HorizonRender {

    // MARK: - The state the camera hands the draw

    // Everything the horizon needs for one frame, and nothing else: how much
    // light the join is carrying, and how deep the join is. Both are pure
    // functions of the camera's position and the world's geometry, so a frame
    // drawn from the same camera position is the same picture, always —
    // nothing here accumulates, so nothing here can drift.
    struct Horizon: Equatable {

        /// 0…1. The share of the horizon's full light this frame carries.
        var presence: Double

        /// The depth of the sky/field overlap in POINTS — the band the light
        /// is allowed to occupy, measured down from the field canvas's top
        /// edge.
        var depth: CGFloat

        /// No join in view, no fills issued. This is the default `draw` takes,
        /// so `ContentView` — the v1.2 field, which has no camera at all —
        /// keeps calling the renderer exactly as it always has and draws
        /// exactly what it always did.
        static let none = Horizon(presence: 0, depth: 0)
    }

    // MARK: - Tuning

    // These are RENDERING constants and they live here rather than in
    // `GameConfig` or `WorldCamera.Config`, for the reason `WorldRender`'s
    // header states for its own: the camera decides how the world moves, this
    // file decides what the join looks like, and it may never decide the first
    // thing. Turning `lightPeak` and `groundPeak` to zero must leave the
    // navigation — distances, durations, gates, `isAtRest` — bit-identical. It
    // does, because nothing outside this file reads them.

    /// THE PEAK ALPHA OF THE LIGHT, at full presence, on the brightest row of
    /// the band.
    ///
    /// WHY 0.055, ANCHORED RATHER THAN GUESSED. The dimmest light this world
    /// already draws on purpose is a quiet star's halo at 0.10, and the
    /// end-of-axis acknowledgement peaks at exactly that. The horizon is
    /// ALWAYS THERE, where both of those are things you look at or things that
    /// happen, so it is deliberately set at a little over half of the dimmest
    /// deliberate light in the world. Composited over the brightest ground the
    /// app paints it measures under 2% relative luminance (`peakLuminance`),
    /// against a 12% ceiling.
    static let lightPeak: Double = 0.055

    /// THE PEAK ALPHA OF THE DEEPENING under the light. This is not a shadow
    /// and it is not a border: it is the field's own deepest ground tone,
    /// gathered just below the glow so the light reads as sitting ON something
    /// rather than floating. It is what lets `lightPeak` stay this low and
    /// still be seen — contrast rather than brightness, which is the calm way
    /// to spend it.
    ///
    /// It also earns its keep for the orbs: it is DARKEST where the light has
    /// already fallen away, so the band never reduces an orb's contrast
    /// against its ground — it raises it. And its strength follows `presence`,
    /// which is at its lowest exactly where the gameplay is.
    static let groundPeak: Double = 0.22

    /// The horizon's light at rest ON THE FIELD, as a share of full.
    ///
    /// HALF, NOT FULL, and this is the one number here that is about the game
    /// rather than about the join. Standing in the field the band is at the
    /// top of the screen behind the counter, and the field is where her eyes
    /// are doing work; from the sky the same band is at her feet with nothing
    /// else near it and nothing to compete with. So the join is quietest in
    /// the place where quiet costs the most.
    static let fieldPresence: Double = 0.5

    /// The horizon's light at rest IN THE SKY: full. This is where the join
    /// does its whole job — the field's top quarter really is on screen down
    /// there, and before this it ended along a line.
    static let skyPresence: Double = 1.0

    /// THE BAND'S DEPTH, in screen heights, is `1 − travelPerPlace` — the
    /// overlap itself, not a number picked to look right. These two clamps
    /// exist only so a degenerate geometry cannot produce a degenerate
    /// picture: at `travelPerPlace >= 1` the places would butt rather than
    /// overlap and the join would need the glow MORE than it does now, not
    /// less, so the floor keeps a band there; and a tiny `travelPerPlace`
    /// must not hand the field a haze half a screen deep.
    static let depthFloor: CGFloat = 0.12
    static let depthCeiling: CGFloat = 0.40

    /// THE CEILING THE HORIZON MAY NEVER REACH, as sRGB relative luminance:
    /// 12%. Guardrail 4 in numbers — dark, muted, unsaturated — and the thing
    /// `HorizonTests` actually proves, at every camera offset rather than at
    /// the one someone thought to look at.
    static let luminanceCap: Double = 0.12

    // The two tones, held as components rather than as `Color` so the
    // luminance arithmetic below can be done on them and PROVED. Neither is
    // new: the light is the mote tone leaned a half-step warm, and the ground
    // is the field's own deepest gradient stop.
    static let lightTone: (r: Double, g: Double, b: Double) = (210 / 255, 202 / 255, 228 / 255)
    static let groundTone: (r: Double, g: Double, b: Double) = (9 / 255, 8 / 255, 14 / 255)

    /// The brightest ground the world ever paints — the journal's first
    /// radial stop. The horizon is never drawn over the journal, so this is a
    /// deliberately pessimistic floor for "what is underneath the light".
    static let brightestGround: (r: Double, g: Double, b: Double) = (28 / 255, 24 / 255, 29 / 255)

    // MARK: - Where the light is, on this frame

    // THE HORIZON FOR A CAMERA AT `offset` (normalized screen heights — the
    // camera's own unit), in a world `travelPerPlace` deep per place, on a
    // screen `viewHeight` points tall.
    //
    // Guarded exactly as `WorldRender.moteParallax` guards its own division: a
    // degenerate world draws WITHOUT the horizon rather than drawing a NaN
    // across the top of the field. Failing toward the picture that existed
    // before this file is the rule every render cue in this app follows.
    static func state(offset: CGFloat,
                      travelPerPlace: CGFloat,
                      viewHeight: CGFloat,
                      reduceMotion: Bool) -> Horizon {
        guard travelPerPlace > 0, travelPerPlace.isFinite,
              viewHeight > 0, viewHeight.isFinite else { return .none }

        let overlap = min(depthCeiling, max(depthFloor, 1 - travelPerPlace))
        let depth = overlap * viewHeight

        // BARRIER CONDITION 11. Under Reduce Motion the world produces zero
        // translation, `camera.offset` is identically zero, and the places
        // crossfade through each other — so the horizon holds the field's rest
        // value and fades with the field. It is written out rather than left
        // to fall out of `offset == 0` so that a later reader cannot make the
        // accessible path move by changing what `offset` means.
        if reduceMotion { return Horizon(presence: fieldPresence, depth: depth) }

        guard offset.isFinite else { return .none }
        let u = Double(min(1, max(-1, offset / travelPerPlace)))
        return Horizon(presence: presence(axis: u), depth: depth)
    }

    // THE LIGHT AS A FUNCTION OF AXIS POSITION, in place-units: −1 is the sky,
    // 0 is the field, +1 is the journal.
    //
    // THE SHAPE IS A SMOOTHSTEP ON EACH SIDE OF THE FIELD, and the reason is a
    // defect this project has already paid for once (see
    // `WorldCamera.Config.maxTransitPerCommit`, which was re-derived after a
    // gate that opened and shut as the camera crossed a place centre). A cue
    // with a kink at u = 0 changes direction on the frame she passes through
    // the field — the one frame in a two-place transit where she is looking
    // straight at the join. `s(t) = t²(3 − 2t)` has zero slope at BOTH ends, so
    // the two branches meet at the field with the same value AND the same
    // slope: nothing steps, and nothing bends, at any of the three centres.
    //
    // Toward the sky the light rises to full; toward the journal it goes out
    // altogether, because by then the join is a whole screen above the top of
    // the glass and drawing it would be two gradient fills nobody can see.
    static func presence(axis u: Double) -> Double {
        guard u.isFinite else { return 0 }
        let t = min(1, max(0, abs(u)))
        let s = t * t * (3 - 2 * t)
        if u <= 0 { return fieldPresence + (skyPresence - fieldPresence) * s }
        return fieldPresence * (1 - s)
    }

    // MARK: - The profile

    /// One stop of the band's alpha profile: `location` is the fraction of the
    /// band's depth measured down from the field's top edge.
    struct Stop: Equatable {
        let location: Double
        let alpha: Double
    }

    // THE FIELD'S LIGHT, SEEN FROM ABOVE.
    //
    // ZERO AT BOTH ENDS, AND THAT IS THE WHOLE ARGUMENT OF THIS FILE.
    //
    //   * ZERO AT THE TOP, because the top of the band is the field canvas's
    //     own edge, and a `Canvas` clips. Any alpha at all on that row would
    //     be a step from nothing to something along a perfectly straight
    //     horizontal line, which is not a glow — it is the aggressive border,
    //     drawn by accident. This is the single property that decides whether
    //     the answer to the owner's question is the one it claims to be.
    //   * ZERO AT THE BOTTOM, because that row is where the sky's own bottom
    //     edge falls. Below it there is no sky at all, so light attributed to
    //     the sky may not persist there.
    //
    // FIVE STOPS RATHER THAN THREE. A straight ramp bands visibly on an OLED
    // at these levels and a band in a soft glow reads as a defect; the extra
    // stops put most of the depth in the falloff, which is also what keeps the
    // average alpha across the band near a third of its peak.
    static func lightStops(_ horizon: Horizon) -> [Stop] {
        let p = peakAlpha(horizon)
        return [Stop(location: 0.00, alpha: 0),
                Stop(location: 0.18, alpha: 0.62 * p),
                Stop(location: 0.36, alpha: p),
                Stop(location: 0.66, alpha: 0.34 * p),
                Stop(location: 1.00, alpha: 0)]
    }

    // THE SKY'S DARKNESS, SEEN FROM BELOW. Deepest a little under the glow,
    // gone by both edges for the same two reasons the light is.
    static func groundStops(_ horizon: Horizon) -> [Stop] {
        let q = groundPeak * clampedPresence(horizon)
        return [Stop(location: 0.00, alpha: 0),
                Stop(location: 0.40, alpha: 0.30 * q),
                Stop(location: 0.74, alpha: q),
                Stop(location: 1.00, alpha: 0)]
    }

    /// The alpha of the light's brightest row this frame.
    static func peakAlpha(_ horizon: Horizon) -> Double {
        lightPeak * clampedPresence(horizon)
    }

    // MARK: - What it measures

    // THE BRIGHTEST THE HORIZON CAN MAKE ANY PIXEL, as sRGB relative
    // luminance, composited the pessimistic way round:
    //
    //   * the light is additive (`.plusLighter`), so its contribution is added
    //     to the ground in ENCODED space, which yields more luminance than
    //     adding in linear space would — the honest worst case for the blend
    //     mode actually used;
    //   * the ground under it is taken as the BRIGHTEST ground the app paints
    //     anywhere, even though the horizon is never drawn over that one;
    //   * the deepening is ignored, because it only ever subtracts light.
    //
    // This is the number `HorizonTests` holds against `luminanceCap` at every
    // offset on the axis, in both motion modes.
    static func peakLuminance(_ horizon: Horizon) -> Double {
        let a = peakAlpha(horizon)
        return relativeLuminance(r: brightestGround.r + lightTone.r * a,
                                 g: brightestGround.g + lightTone.g * a,
                                 b: brightestGround.b + lightTone.b * a)
    }

    /// sRGB relative luminance (WCAG), on components in 0…1.
    static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private static func linearize(_ c: Double) -> Double {
        let v = min(1, max(0, c.isFinite ? c : 0))
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func clampedPresence(_ horizon: Horizon) -> Double {
        let p = horizon.presence
        return min(1, max(0, p.isFinite ? p : 0))
    }

    // MARK: - The draw

    // TWO GRADIENT FILLS, BEHIND EVERYTHING, AND NOTHING ELSE.
    //
    // Called from the very back of `SceneRenderer.draw` — before the motes,
    // which is to say before every single thing the field draws — so nothing
    // in the game can ever be competing with it. Rendering reads and never
    // writes: this touches no simulation state, holds no state of its own, and
    // is a pure function of the `Horizon` it is handed.
    //
    // It issues NO fills at all when there is no light to draw (at the
    // journal, and for anything that calls `draw` without a camera), so the
    // cost of the horizon in the places it is not in is one comparison.
    static func draw(_ horizon: Horizon, into context: inout GraphicsContext, size: CGSize) {
        let strength = clampedPresence(horizon)
        guard strength > 0, horizon.depth > 0, horizon.depth.isFinite,
              size.width > 0, size.height > 0 else { return }

        // Never deeper than the canvas it is drawn into: a band taller than
        // the field would put its far end off the bottom of the glass, and the
        // far end is one of the two rows that must be dark.
        let depth = min(horizon.depth, size.height)
        let band = CGRect(x: 0, y: 0, width: size.width, height: depth)
        let head = CGPoint(x: size.width / 2, y: 0)
        let foot = CGPoint(x: size.width / 2, y: depth)

        // The deepening first, in the ordinary blend mode, so the light lands
        // on it rather than under it.
        context.fill(Path(band),
                     with: .linearGradient(gradient(groundStops(horizon), tone: groundTone),
                                           startPoint: head, endPoint: foot))

        // The light, additive, exactly as every other glow in this renderer is.
        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(Path(band),
                  with: .linearGradient(gradient(lightStops(horizon), tone: lightTone),
                                        startPoint: head, endPoint: foot))
    }

    private static func gradient(_ stops: [Stop],
                                 tone: (r: Double, g: Double, b: Double)) -> Gradient {
        let color = Color(red: tone.r, green: tone.g, blue: tone.b)
        return Gradient(stops: stops.map {
            Gradient.Stop(color: color.opacity(min(1, max(0, $0.alpha))),
                          location: CGFloat($0.location))
        })
    }
}
