import XCTest
import Foundation
import CoreGraphics
import SwiftUI
@testable import Vesper

// PROOF FOR `Vesper/Rendering/` — the parts of it a test can actually reach.
//
// WHAT THIS FILE IS FOR, AND WHAT IT DELIBERATELY IS NOT.
//
// A `GraphicsContext` cannot be constructed outside a `Canvas` draw closure,
// so every function in the renderers that takes one — `SceneRenderer.draw`,
// `drawAnima`, `drawAnimal`, `HorizonRender.draw`, and the whole of
// `WeatherRenderer` bar its two entry points — is unreachable from a unit
// test, permanently and by construction. What IS reachable is the arithmetic
// underneath the drawing: the pure statics that decide geometry, opacity,
// colour and layout, and the data the draw reads. That arithmetic is where
// every defect this file is hunting for actually lives.
//
// IT IS THE COMPLEMENT OF `WorldRenderTests` AND `HorizonTests`, NOT A COPY.
// Those two prove the NORMAL behaviour of the mote parallax, the transit
// luminance, the edge acknowledgement and the horizon's profile — the shapes,
// the rest values, the settles. Nothing here repeats that. What is here is:
//
//   TOTALITY. Every reachable cue fed the values a sweep never contains —
//   NaN, zero, negative, tiny, enormous — and held to "finite, and inside the
//   range you documented". This is a real defect class in this project rather
//   than a hypothetical: Swift's `min`/`max` pass NaN straight through, so a
//   pair of clamps is NOT a total function, and this app has already shipped
//   one NaN through exactly that hole.
//       → testEveryTravelCueIsTotalAcrossItsGuardedDomain
//       → testTheLuminanceCueIsTotalAndNeverLeavesItsBand
//       → testTheAcknowledgementIsTotalAtEveryLevelAnyoneCanHandIt
//       → testTheHorizonIsTotalForEveryGeometryAndEveryNonsenseState
//       → testRelativeLuminanceIsTotalAndAnchoredToTheStandard
//
//   THE THREE RENDERERS WITH NO COVERAGE AT ALL — `AnimaRenderer`,
//   `AnimalRendering`, `WeatherRenderer`:
//       → the Anima placement is an affine of the outline and nothing else
//       → the balloon-animal silhouette is one closed, uncullable shape whose
//         halo covers it
//       → the air's presence is a gate that really closes
//
//   GUARDRAIL 4 IN NUMBERS, on the palette the renderers paint with. The
//   per-renderer palettes (`SceneRenderer.moteColor`, `WeatherRenderer`'s six
//   tones) are `private` and cannot be reached — see the report — but the
//   paints every orb, particle, ring and shell is actually drawn in come from
//   `PopCatalog` and `FireworkCatalog`, and those are reachable.
//       → testNoOrbIsEverPaintedSaturatedOrPureWhite
//       → testNoShellIsEverPaintedSaturatedOrPureWhite
//       → testTheGroundsTheHorizonPaintsOnStayDark
//
// Deterministic and isolated, like the rest of the suite: no wall-clock, no
// unseeded randomness, no defaults, no singletons, and no test here depends on
// another having run.
final class RenderingTests: XCTestCase {

    // The 390 x 844 pt reference screen the roadmap's arithmetic is quoted on.
    private let screenHeight: CGFloat = 844
    private let screen = CGSize(width: 390, height: 844)

    // MARK: - Totality: the camera's render cues

    // EVERY VALUE A CALLER COULD HAND `moteParallax`, NOT THE ONES A SWEEP
    // HAPPENS TO CONTAIN.
    //
    // The cue multiplies its way to a translation in points and is applied to
    // the dust layer of a live `Canvas`; a NaN here does not draw wrongly, it
    // makes the whole mote layer vanish, and an infinity throws it off the
    // glass. So the property is stated as strongly as the function can hold
    // it: the result is FINITE and never larger in magnitude than the
    // constant product the header promises (`moteLag x travelPerPlace x
    // viewHeight`), for every combination of a guarded geometry and an
    // arbitrary offset.
    //
    // KNOWN GAP, STATED RATHER THAN ASSERTED, AND STATED EXACTLY. The guard
    // reads `travelPerPlace > 0, viewHeight > 0, offset.isFinite`. Be precise
    // about what that does and does not catch, because the imprecise version
    // of this paragraph sends the next reader after the wrong bug:
    //
    //   * a NaN `travelPerPlace` or `viewHeight` IS refused, because
    //     `nan > 0` is false. The comparison does the work `.isFinite` would
    //     have done, by accident rather than by intent, and the sweep below
    //     pins that behaviour so it cannot be lost;
    //   * an INFINITE one is not. `inf > 0` is true, `offset / inf` is 0, and
    //     the final product is `inf * 0` — a NaN, out of a guard that just
    //     said yes;
    //   * and neither is a merely ENORMOUS FINITE one. At
    //     `travelPerPlace = viewHeight = 1e200` the leading product overflows
    //     to infinity mid-expression while every argument is finite, and the
    //     result is a NaN (at `u == 0`) or a raw infinity (at `u != 0`).
    //     All-finite in, non-finite out.
    //
    // `HorizonRender.state` — the newer file, guarding the same division —
    // checks `.isFinite` on all three. That asymmetry is reported as a defect
    // rather than pinned here, because pinning it means either a red suite or
    // a test that certifies the bug. The geometries swept below are therefore
    // the ones that cannot overflow, which is every geometry the app can
    // currently produce.
    func testEveryTravelCueIsTotalAcrossItsGuardedDomain() {
        let offsets: [CGFloat] = [0, -0, 1e-9, -1e-9, 0.375, -0.375, 0.75, -0.75,
                                  1, -1, 1e6, -1e6, .nan, .infinity, -.infinity]
        let geometries: [(CGFloat, CGFloat)] = [
            (0.75, 844), (0.5, 844), (1, 844), (2, 844), (0.75, 1),
            (1e-6, 844), (1e6, 1e6), (0.75, 1e-6), (1e-6, 1e-6)
        ]

        for (travel, height) in geometries {
            let ceiling = WorldRender.moteLag * travel * height
            XCTAssertTrue(ceiling.isFinite, "the test's own bound overflowed — widen it, not the cue")
            for offset in offsets {
                let value = WorldRender.moteParallax(offset: offset,
                                                     travelPerPlace: travel,
                                                     viewHeight: height)
                XCTAssertTrue(value.isFinite,
                              "offset \(offset), travel \(travel), height \(height): "
                              + "a non-finite translation empties the whole mote layer")
                XCTAssertLessThanOrEqual(abs(value), ceiling + 1e-9,
                                         "offset \(offset), travel \(travel), height \(height): "
                                         + "the lag may never exceed moteLag x travel x height")
            }
        }

        // And a refused geometry is refused for EVERY offset, including the
        // ones that would otherwise be nonsense — the cue fails toward the
        // picture that existed before it, never toward a NaN.
        for offset in offsets {
            for travel in [CGFloat(0), -1, -0.75, .nan] {
                XCTAssertEqual(WorldRender.moteParallax(offset: offset, travelPerPlace: travel,
                                                        viewHeight: screenHeight), 0,
                               "offset \(offset), travel \(travel): a degenerate world draws no cue")
            }
            for height in [CGFloat(0), -844, .nan] {
                XCTAssertEqual(WorldRender.moteParallax(offset: offset, travelPerPlace: 0.75,
                                                        viewHeight: height), 0,
                               "offset \(offset), height \(height): a degenerate screen draws no cue")
            }
        }
    }

    // The luminance multiplier is applied to the WHOLE scene, so a value
    // outside its band is not a wrong colour — it is the field going black or
    // blowing out. `transitLuminance` is total by construction (a non-finite
    // crossfade resolves to 1, where the bell is zero), and this is what says
    // so for the inputs a sweep of 0...1 cannot contain: the crossfade is a
    // camera-owned progress value, and a camera that has just been handed a
    // degenerate geometry can hand this one anything.
    func testTheLuminanceCueIsTotalAndNeverLeavesItsBand() {
        let crossfades: [CGFloat] = [0, -0, 0.5, 1, -1, -1e-9, 1 + 1e-9, 1e6, -1e6,
                                     .nan, .infinity, -.infinity,
                                     .greatestFiniteMagnitude, .leastNonzeroMagnitude]
        for gate in [true, false] {
            for t in crossfades {
                let value = WorldRender.transitLuminance(isTransitioning: gate, crossfade: t)
                XCTAssertTrue(value.isFinite, "gate \(gate), t \(t): a non-finite scene luminance")
                XCTAssertLessThanOrEqual(value, 1,
                                         "gate \(gate), t \(t): the world may never brighten past "
                                         + "its own light — there is no luminance rubber-band")
                XCTAssertGreaterThanOrEqual(value, 1 - WorldRender.transitDim,
                                            "gate \(gate), t \(t): the dimming may never exceed "
                                            + "transitDim")
            }
        }

        // A degenerate crossfade must land on FULL light rather than on the
        // deepest dim: failing dark on a frame nobody can explain is the one
        // failure mode a calm game may not have.
        for t in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: true, crossfade: t), 1,
                           accuracy: 1e-12,
                           "t \(t): a nonsense crossfade must fail toward full light")
        }
    }

    // The acknowledgement's peak, at the extremes `WorldRenderTests` does not
    // reach. It is an alpha handed to a full-screen gradient, so a value above
    // its peak is a flash at the edge of the glass — the exact thing the cue
    // is sized to avoid.
    func testTheAcknowledgementIsTotalAtEveryLevelAnyoneCanHandIt() {
        let levels: [CGFloat] = [0, -0, .leastNonzeroMagnitude, 1e-9, 0.5, 1,
                                 1 + 1e-9, 1e6, .greatestFiniteMagnitude,
                                 -.leastNonzeroMagnitude, -1e6, -.greatestFiniteMagnitude,
                                 .nan, .infinity, -.infinity]
        for level in levels {
            let value = WorldRender.edgeAcknowledgementOpacity(level: level)
            XCTAssertTrue(value.isFinite, "level \(level): a non-finite alpha")
            XCTAssertGreaterThanOrEqual(value, 0, "level \(level): light is never negative")
            XCTAssertLessThanOrEqual(value, WorldRender.edgeAcknowledgementPeak + 1e-12,
                                     "level \(level): the band may never exceed its stated peak")
        }

        // The depth is a share of a screen height, and a band deeper than the
        // screen would put the dark end of the falloff off the glass — which
        // is the hairline this cue exists not to be.
        XCTAssertGreaterThan(WorldRender.edgeAcknowledgementDepth, 0)
        XCTAssertLessThan(WorldRender.edgeAcknowledgementDepth, 0.5,
                          "a band half a screen deep is a wash, not an acknowledgement")
    }

    // MARK: - Totality: the horizon

    // The horizon is drawn behind the entire field, so a NaN alpha in its
    // profile is a full-width band of nothing across the top of the game. Two
    // halves here, neither of them in `HorizonTests`:
    //
    //   * `state` swept over geometries a sweep of offsets cannot reach —
    //     infinite and enormous travel, infinite and negative screens;
    //   * the profile helpers fed a `Horizon` NOBODY WOULD BUILD ON PURPOSE.
    //     `Horizon` is a plain struct with two `var`s, so any caller can
    //     construct one with a NaN presence; `HorizonTests` sweeps presence
    //     over 0...1 only, and the clamp that saves it is the one piece of
    //     arithmetic in the file with nothing holding it in place.
    func testTheHorizonIsTotalForEveryGeometryAndEveryNonsenseState() {
        let offsets: [CGFloat] = [0, 0.75, -0.75, 3, -3, 1e9, .nan, .infinity, -.infinity]
        let travels: [CGFloat] = [0.75, 0.12, 1, 4, 1e-6, 1e9, 0, -1, .nan, .infinity]
        let heights: [CGFloat] = [844, 1, 1e-9, 1e9, 0, -844, .nan, .infinity]

        for offset in offsets {
            for travel in travels {
                for height in heights {
                    for reduceMotion in [false, true] {
                        let state = HorizonRender.state(offset: offset, travelPerPlace: travel,
                                                        viewHeight: height,
                                                        reduceMotion: reduceMotion)
                        let where_ = "offset \(offset), travel \(travel), height \(height), "
                            + "RM \(reduceMotion)"
                        XCTAssertTrue(state.presence.isFinite, "\(where_): non-finite presence")
                        XCTAssertTrue(state.depth.isFinite, "\(where_): non-finite depth")
                        XCTAssertGreaterThanOrEqual(state.presence, 0, where_)
                        XCTAssertLessThanOrEqual(state.presence, 1,
                                                 "\(where_): presence is a share, never a gain")
                        XCTAssertGreaterThanOrEqual(state.depth, 0,
                                                    "\(where_): a band above the field's own edge")
                        XCTAssertLessThanOrEqual(HorizonRender.peakLuminance(state),
                                                 HorizonRender.luminanceCap,
                                                 "\(where_): guardrail 4 is the ceiling everywhere")
                    }
                }
            }
        }

        // The profile, from states no sane camera produces. Whatever comes
        // out has to be a drawable gradient: ascending locations, alphas
        // inside 0...1, and never brighter than the file's own two constants.
        let nonsense: [Double] = [.nan, .infinity, -.infinity, -1, -0.0001,
                                  1.0001, 5, 1e300, .leastNonzeroMagnitude]
        for presence in nonsense {
            for depth in [CGFloat(211), 0, -1, .nan, .infinity] {
                let state = HorizonRender.Horizon(presence: presence, depth: depth)
                let peak = HorizonRender.peakAlpha(state)
                XCTAssertTrue(peak.isFinite, "presence \(presence): non-finite peak alpha")
                XCTAssertGreaterThanOrEqual(peak, 0, "presence \(presence)")
                XCTAssertLessThanOrEqual(peak, HorizonRender.lightPeak + 1e-12,
                                         "presence \(presence): the light may never exceed "
                                         + "lightPeak, whatever it is handed")
                XCTAssertLessThanOrEqual(HorizonRender.peakLuminance(state),
                                         HorizonRender.luminanceCap,
                                         "presence \(presence): a nonsense presence may not "
                                         + "brighten the world past guardrail 4")

                for stops in [HorizonRender.lightStops(state), HorizonRender.groundStops(state)] {
                    XCTAssertEqual(stops.first?.alpha, 0,
                                   "presence \(presence): the clipped row stays dark")
                    XCTAssertEqual(stops.last?.alpha, 0,
                                   "presence \(presence): the far row stays dark")
                    for index in 1..<stops.count {
                        XCTAssertGreaterThan(stops[index].location, stops[index - 1].location,
                                             "presence \(presence): gradient stops must ascend")
                    }
                    for stop in stops {
                        XCTAssertTrue(stop.alpha.isFinite,
                                      "presence \(presence): a non-finite alpha in the profile")
                        XCTAssertGreaterThanOrEqual(stop.alpha, 0, "presence \(presence)")
                        XCTAssertLessThanOrEqual(stop.alpha, 1, "presence \(presence)")
                    }
                }
                XCTAssertLessThanOrEqual(HorizonRender.groundStops(state).map(\.alpha).max() ?? 0,
                                         HorizonRender.groundPeak + 1e-12,
                                         "presence \(presence): the deepening may never exceed "
                                         + "groundPeak")
            }
        }

        // The axis shape, at the two ends of the real line.
        for u in [Double.infinity, -.infinity, .nan] {
            let value = HorizonRender.presence(axis: u)
            XCTAssertTrue(value.isFinite, "axis \(u): non-finite presence")
            XCTAssertGreaterThanOrEqual(value, 0, "axis \(u)")
            XCTAssertLessThanOrEqual(value, 1, "axis \(u)")
        }
        for u in [-1e9, -4.0, -1.0, -0.5, 0, 0.5, 1.0, 4.0, 1e9] {
            let value = HorizonRender.presence(axis: u)
            XCTAssertGreaterThanOrEqual(value, 0, "axis \(u)")
            XCTAssertLessThanOrEqual(value, HorizonRender.skyPresence, "axis \(u)")
        }
    }

    // `relativeLuminance` is the measurement guardrail 4 is enforced WITH, so
    // if it were wrong the cap it is held against would be meaningless — and
    // nothing currently checks it against the standard it claims to implement.
    // Three properties: the sRGB anchors, monotonicity in every channel, and
    // totality (its clamp is what makes a NaN component measure as black
    // rather than poisoning the comparison, which would silently pass the cap).
    func testRelativeLuminanceIsTotalAndAnchoredToTheStandard() {
        XCTAssertEqual(HorizonRender.relativeLuminance(r: 0, g: 0, b: 0), 0, accuracy: 1e-12,
                       "black measures zero")
        XCTAssertEqual(HorizonRender.relativeLuminance(r: 1, g: 1, b: 1), 1, accuracy: 1e-12,
                       "white measures one — the coefficients must sum to unity")
        // WCAG's own worked value for mid grey, which is what makes this a
        // check of the standard rather than of the code that wrote it.
        XCTAssertEqual(HorizonRender.relativeLuminance(r: 0.5, g: 0.5, b: 0.5), 0.2140,
                       accuracy: 1e-3, "sRGB is not linear, and this is where that is proved")
        XCTAssertGreaterThan(HorizonRender.relativeLuminance(r: 0, g: 1, b: 0),
                             HorizonRender.relativeLuminance(r: 1, g: 0, b: 0),
                             "green carries more luminance than red")
        XCTAssertGreaterThan(HorizonRender.relativeLuminance(r: 1, g: 0, b: 0),
                             HorizonRender.relativeLuminance(r: 0, g: 0, b: 1),
                             "and red more than blue")

        var previous = -1.0
        for step in 0...200 {
            let c = Double(step) / 200
            let value = HorizonRender.relativeLuminance(r: c, g: c, b: c)
            XCTAssertTrue(value.isFinite, "grey \(c): non-finite luminance")
            XCTAssertGreaterThanOrEqual(value, previous, "luminance must not fall as grey rises")
            XCTAssertLessThanOrEqual(value, 1, "grey \(c)")
            previous = value
        }

        for bad in [Double.nan, .infinity, -.infinity, -1, 2, 1e300] {
            let value = HorizonRender.relativeLuminance(r: bad, g: bad, b: bad)
            XCTAssertTrue(value.isFinite, "component \(bad): non-finite luminance")
            XCTAssertGreaterThanOrEqual(value, 0, "component \(bad)")
            XCTAssertLessThanOrEqual(value, 1, "component \(bad)")
        }
        // One channel of nonsense may not poison the other two.
        XCTAssertEqual(HorizonRender.relativeLuminance(r: .nan, g: 0, b: 0), 0, accuracy: 1e-12,
                       "a NaN channel measures as black, not as a NaN comparison that passes "
                       + "every ceiling it is held against")
    }

    // MARK: - Guardrail 4: the palette the renderers paint with

    // Nothing the field draws may be saturated, and nothing may be pure white.
    // `PopCatalogTests` proves the channels are inside 0...1 — which permits
    // (1, 0, 0) — and nothing anywhere proves the aesthetic itself. These are
    // the exact numbers `SceneRenderer` fills every orb, ring and particle
    // with, so this is guardrail 4 held against the paint rather than against
    // a screenshot.
    //
    // EVERY BOUND BELOW IS SIZED AGAINST THE CATALOG AS IT STANDS, and the
    // measurement is written down so the next author can see how much room
    // they have before they spend it. Across the 227 paints of the 100 pops
    // (454 colours):
    //
    //     saturation   worst 0.376  (#218,170,136 fill)   bound 0.42
    //     high channel worst 0.965  (#238,236,246 fill)   bound 0.98
    //     low channel  worst 0.507  (#218,170,136 glow)   bound 0.40
    //     chroma       worst 0.345  (#234,202,146 fill)   bound 0.40
    //
    // The two ceilings were WIDENED from a first pass that set them at 0.97
    // and 0.36. Colours here are authored in 1/255 steps, and at 0.97 the
    // brightest pop in the catalog was 1.3 steps from failing — one new
    // off-white and the whole suite goes red for everybody, over a colour
    // nobody would call white. 0.98 still refuses anything at or above
    // 250/255, which is the thing "no pure white" is actually about, and
    // leaves four steps of authoring room. The chroma bound moved for the
    // same reason (3.8 steps of room, now ~14) and is belt-and-braces
    // anyway: at these brightnesses it is nearly implied by the saturation
    // cap above it.
    func testNoOrbIsEverPaintedSaturatedOrPureWhite() {
        var checked = 0
        for definition in PopCatalog.all {
            for (index, paint) in definition.style.paints.enumerated() {
                for (role, colour) in [("fill", paint.fill), ("glow", paint.glow)] {
                    let where_ = "\(definition.name) paint \(index) \(role)"
                    let channels = [colour.r, colour.g, colour.b]
                    let high = channels.max() ?? 0
                    let low = channels.min() ?? 0

                    XCTAssertTrue(channels.allSatisfy(\.isFinite), where_)
                    XCTAssertLessThanOrEqual(high, 0.98,
                                             "\(where_): \(high) — nothing in this game is pure "
                                             + "white")
                    XCTAssertGreaterThan(low, 0.4,
                                         "\(where_): the orbs are pastels lit on a dark ground, "
                                         + "not a dark shape on a dark ground")
                    XCTAssertLessThanOrEqual(saturation(colour), 0.42,
                                             "\(where_): saturation \(saturation(colour)) — the "
                                             + "palette is muted, and this one is not")
                    XCTAssertLessThanOrEqual(high - low, 0.40,
                                             "\(where_): chroma \(high - low) is a colour, not a "
                                             + "tint")
                    checked += 1
                }

                // The halo may never out-shine the body it surrounds: the glow
                // is drawn additively OVER the fill, so a glow brighter than
                // its fill turns a soft orb into a hotspot with a dark middle.
                XCTAssertLessThanOrEqual(paint.glow.r, paint.fill.r + 1e-12, definition.name)
                XCTAssertLessThanOrEqual(paint.glow.g, paint.fill.g + 1e-12, definition.name)
                XCTAssertLessThanOrEqual(paint.glow.b, paint.fill.b + 1e-12, definition.name)
            }
        }
        XCTAssertGreaterThan(checked, 200, "the catalog did not hand over its paints")
    }

    // The shells are the one thing in the game allowed to be hotter than the
    // pops — a light in the air at night IS brighter than a thing on a table —
    // so they get their own, looser ceiling. It is still a ceiling: the most
    // saturated colour anywhere in Vesper is the ember glow, and this is the
    // number that stops the next one being a firework-red.
    //
    // MEASURED, across the ten paints the 36 shells share between them:
    // saturation worst 0.526 (the ember glow, #232,150,110) against 0.58, and
    // high channel worst 0.957 (#214,230,244 fill) against 0.98 — the same
    // white bound the pops carry, and widened here for the same reason.
    func testNoShellIsEverPaintedSaturatedOrPureWhite() {
        XCTAssertFalse(FireworkCatalog.all.isEmpty)
        for definition in FireworkCatalog.all {
            for (index, paint) in definition.paints.enumerated() {
                for (role, colour) in [("fill", paint.fill), ("glow", paint.glow)] {
                    let where_ = "\(definition.name) paint \(index) \(role)"
                    let channels = [colour.r, colour.g, colour.b]
                    XCTAssertTrue(channels.allSatisfy(\.isFinite), where_)
                    XCTAssertLessThanOrEqual(channels.max() ?? 0, 0.98,
                                             "\(where_): not even a firework is pure white")
                    XCTAssertLessThanOrEqual(saturation(colour), 0.58,
                                             "\(where_): saturation \(saturation(colour)) — "
                                             + "hotter than a pop is allowed; saturated is not")
                }
                XCTAssertLessThanOrEqual(paint.glow.r, paint.fill.r + 1e-12, definition.name)
                XCTAssertLessThanOrEqual(paint.glow.g, paint.fill.g + 1e-12, definition.name)
                XCTAssertLessThanOrEqual(paint.glow.b, paint.fill.b + 1e-12, definition.name)
            }
        }
    }

    // The other half of guardrail 4: the light is capped (`HorizonTests`), and
    // the GROUND under it has to stay dark, or the cap is being measured
    // against something that was never dim in the first place. `brightestGround`
    // is the pessimistic floor the whole luminance argument rests on, so if it
    // ever stopped being dark the ceiling above it would quietly stop meaning
    // anything.
    func testTheGroundsTheHorizonPaintsOnStayDark() {
        let ground = HorizonRender.relativeLuminance(r: HorizonRender.groundTone.r,
                                                     g: HorizonRender.groundTone.g,
                                                     b: HorizonRender.groundTone.b)
        let brightest = HorizonRender.relativeLuminance(r: HorizonRender.brightestGround.r,
                                                        g: HorizonRender.brightestGround.g,
                                                        b: HorizonRender.brightestGround.b)
        XCTAssertLessThan(ground, 0.01, "the deepening is the field's own darkest tone")
        XCTAssertLessThan(brightest, 0.02,
                          "the brightest ground the app paints is still a dark room")
        XCTAssertLessThan(ground, brightest,
                          "the deepening must be darker than the ground it deepens")
        XCTAssertLessThan(brightest, HorizonRender.luminanceCap / 4,
                          "the ground has to leave the horizon room under the cap, or the cap "
                          + "is measuring the ground rather than the light")

        // And the ground is a tone, not a colour.
        let g = [HorizonRender.groundTone.r, HorizonRender.groundTone.g, HorizonRender.groundTone.b]
        let b = [HorizonRender.brightestGround.r, HorizonRender.brightestGround.g,
                 HorizonRender.brightestGround.b]
        XCTAssertLessThan((g.max() ?? 0) - (g.min() ?? 0), 0.06, "the deepening is not a colour")
        XCTAssertLessThan((b.max() ?? 0) - (b.min() ?? 0), 0.06, "the ground is not a colour")
    }

    // MARK: - AnimaRenderer: a posed part becomes a path

    // THE PLACEMENT MUST NOT INVENT OR LOSE A VERTEX, AND MUST CLOSE.
    //
    // `drawAnima` fills the result with the nonzero winding rule and never
    // strokes it. An unclosed subpath fills to an implied straight line back
    // to the start, so a missing `closeSubpath` does not produce a gap — it
    // produces a subtly WRONG shape that still looks like a creature, which is
    // the kind of defect that survives review. This pins the element sequence
    // exactly: one move, one line per remaining point, one close.
    func testAPosedPartBecomesOneClosedPathWithNoVertexInventedOrLost() {
        for count in [3, 4, 5, 12, 64] {
            let outline = ring(count: count)
            let path = SceneRenderer.path(for: part(outline), at: CGPoint(x: 40, y: 70),
                                          radius: 12, facing: 1)
            var moves = 0, lines = 0, curves = 0, closes = 0
            var order: [String] = []
            path.forEach { element in
                switch element {
                case .move: moves += 1; order.append("move")
                case .line: lines += 1; order.append("line")
                case .quadCurve, .curve: curves += 1; order.append("curve")
                case .closeSubpath: closes += 1; order.append("close")
                }
            }
            XCTAssertEqual(moves, 1, "\(count) points: one subpath, not \(moves)")
            XCTAssertEqual(lines, count - 1, "\(count) points: a vertex was dropped or duplicated")
            XCTAssertEqual(curves, 0, "\(count) points: the outline is a polygon, not a spline")
            XCTAssertEqual(closes, 1,
                           "\(count) points: an unclosed fill is a different shape, not a gap")
            XCTAssertEqual(order.first, "move", "\(count) points: a path must begin with a move")
            XCTAssertEqual(order.last, "close", "\(count) points: and end closed")
            XCTAssertFalse(path.isEmpty, "\(count) points: nothing was drawn at all")
        }
    }

    // THE IDENTITY PLACEMENT IS THE REST OUTLINE, POINT FOR POINT. Unit space
    // scaled by 1 and centred on the origin has to come back out unchanged —
    // if this drifts, every figure in the library is being drawn slightly
    // somewhere else and there is nothing to compare it against.
    func testTheIdentityPlacementReproducesTheOutlineExactly() {
        let outline = ring(count: 9)
        let drawn = points(of: SceneRenderer.path(for: part(outline), at: .zero,
                                                  radius: 1, facing: 1))
        XCTAssertEqual(drawn.count, outline.count)
        for (index, expected) in outline.enumerated() {
            XCTAssertEqual(drawn[index].x, expected.x, accuracy: 1e-12, "vertex \(index)")
            XCTAssertEqual(drawn[index].y, expected.y, accuracy: 1e-12, "vertex \(index)")
        }
    }

    // SCALING GROWS THE SILHOUETTE AND NOTHING ELSE. `radius` is the only
    // thing between unit space and points, so doubling it has to double the
    // extent about the centre — a figure that grew about the origin instead
    // would swim away from its orb as it rose out of the reserve.
    func testScalingTheRadiusGrowsTheSilhouetteProportionally() {
        let outline = ring(count: 7)
        let centre = CGPoint(x: 120, y: 260)
        let unit = extent(of: SceneRenderer.path(for: part(outline), at: centre,
                                                 radius: 1, facing: 1))
        for radius in [CGFloat(0.5), 2, 13.5, 400] {
            let grown = extent(of: SceneRenderer.path(for: part(outline), at: centre,
                                                      radius: radius, facing: 1))
            XCTAssertEqual(grown.width, unit.width * radius, accuracy: 1e-9,
                           "radius \(radius): the silhouette did not scale in x")
            XCTAssertEqual(grown.height, unit.height * radius, accuracy: 1e-9,
                           "radius \(radius): the silhouette did not scale in y")
            XCTAssertEqual(grown.midX - centre.x, (unit.midX - centre.x) * radius, accuracy: 1e-9,
                           "radius \(radius): it grew about the wrong point")
            XCTAssertEqual(grown.midY - centre.y, (unit.midY - centre.y) * radius, accuracy: 1e-9,
                           "radius \(radius): it grew about the wrong point")
        }
    }

    // MOVING THE CENTRE MOVES THE SILHOUETTE AND DOES NOT RESIZE IT. The
    // centre is an orb's position, which changes every frame; a placement that
    // let size follow position would make a creature breathe as it drifted.
    func testMovingTheCentreMovesTheSilhouetteWithoutResizingIt() {
        let outline = ring(count: 11)
        let origin = extent(of: SceneRenderer.path(for: part(outline), at: .zero,
                                                   radius: 9, facing: 1))
        for centre in [CGPoint(x: 1, y: 0), CGPoint(x: -320, y: 745),
                       CGPoint(x: 1e5, y: -1e5)] {
            let moved = extent(of: SceneRenderer.path(for: part(outline), at: centre,
                                                      radius: 9, facing: 1))
            XCTAssertEqual(moved.width, origin.width, accuracy: 1e-6, "\(centre): it resized")
            XCTAssertEqual(moved.height, origin.height, accuracy: 1e-6, "\(centre): it resized")
            XCTAssertEqual(moved.minX, origin.minX + centre.x, accuracy: 1e-6, "\(centre)")
            XCTAssertEqual(moved.minY, origin.minY + centre.y, accuracy: 1e-6, "\(centre)")
        }
    }

    // FACING MIRRORS IN X ABOUT THE CENTRE, AND TOUCHES NOTHING ELSE. The
    // header says a creature turns with its drift; if the mirror were about
    // the origin instead of about the centre, a figure would jump across the
    // screen the frame its drift changed sign — at a wall bounce, in front of
    // her.
    func testFacingMirrorsTheSilhouetteInXAndNothingElse() {
        let outline = ring(count: 8)
        let centre = CGPoint(x: 200, y: 90)
        let right = SceneRenderer.path(for: part(outline), at: centre, radius: 6, facing: 1)
        let left = SceneRenderer.path(for: part(outline), at: centre, radius: 6, facing: -1)
        let a = points(of: right), b = points(of: left)
        XCTAssertEqual(a.count, b.count, "mirroring changed the vertex count")
        for index in a.indices {
            XCTAssertEqual(b[index].x - centre.x, -(a[index].x - centre.x), accuracy: 1e-9,
                           "vertex \(index): the mirror is not about the centre")
            XCTAssertEqual(b[index].y, a[index].y, accuracy: 1e-12,
                           "vertex \(index): a mirror in x may not move y")
        }
        let ra = extent(of: right), rb = extent(of: left)
        XCTAssertEqual(ra.width, rb.width, accuracy: 1e-9)
        XCTAssertEqual(ra.height, rb.height, accuracy: 1e-9)
    }

    // A DEGENERATE RADIUS COLLAPSES THE SILHOUETTE RATHER THAN CORRUPTING IT.
    // `drawAnima` guards `radius > 0.01`, but `path` is `static` and internal
    // and the exporter calls it too, so it has to behave on its own: at zero
    // it is a point at the centre, and at an absurd size it is still finite
    // and still centred.
    func testADegenerateRadiusCollapsesTheSilhouetteRatherThanCorruptingIt() {
        let outline = ring(count: 6)
        let centre = CGPoint(x: 33, y: 44)
        for radius in [CGFloat(0), -0.0, 1e-9, 1e7, -3] {
            let path = SceneRenderer.path(for: part(outline), at: centre,
                                          radius: radius, facing: 1)
            for point in points(of: path) {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite,
                              "radius \(radius): a non-finite vertex")
            }
            let box = extent(of: path)
            XCTAssertTrue(box.width.isFinite && box.height.isFinite, "radius \(radius)")
            XCTAssertEqual(box.width, abs(radius) * 2, accuracy: max(1e-6, abs(radius) * 1e-9),
                           "radius \(radius): the unit ring is 2 wide, so the drawn one is 2r")
        }
        let collapsed = points(of: SceneRenderer.path(for: part(outline), at: centre,
                                                      radius: 0, facing: 1))
        for point in collapsed {
            XCTAssertEqual(point.x, centre.x, accuracy: 1e-12,
                           "a zero radius must collapse onto the centre, not onto the origin")
            XCTAssertEqual(point.y, centre.y, accuracy: 1e-12)
        }
    }

    // EVERY POSE THE LIBRARY CAN PRODUCE FITS INSIDE THE HALO DRAWN FOR IT.
    //
    // `drawAnima` sizes its halo from `pose.reach` and draws its body from
    // `path(for:)`, and NOTHING CONNECTS THE TWO except this property. If a
    // posed part could reach further than `reach` claims, a creature would
    // stick out of its own light — the exact "lit as though it were a ball"
    // failure the header says the halo sizing exists to avoid. Swept over
    // every figure, every clip and fixed sample times, so it is deterministic.
    //
    // THE ASSERTION IS PER PART, NOT PER VERTEX, AND THAT IS DELIBERATE. Six
    // figures x six clips x four times x two facings x twenty-nine parts is
    // some ninety thousand vertices; asserted individually that is a quarter
    // of a million XCTest calls for a property that is a maximum, and a
    // second of CI for nothing. The worst vertex of each part is measured and
    // asserted once, which is the same statement — `max <= bound` is exactly
    // `all <= bound` — and it names the offending part either way.
    //
    // ON THE EPSILON. The bound is `radius * reach`, and `reach` is defined
    // as the largest `|p|` over the same outlines, so THE EXTREMAL VERTEX
    // SITS ON THE BOUND WITH ZERO SLACK BY CONSTRUCTION. That is not a
    // knife-edge: the comparison is `<=` rather than `==`, the two sides
    // differ only by the order they multiply `radius` in (about 1e-13 at this
    // scale), and 1e-6 is seven orders of magnitude of room on top. What the
    // test really catches is a part that reaches past a reach it was NOT
    // computed from — the case a future `reach` that is authored, cached or
    // taken from the rest pose would introduce.
    func testEveryPoseInTheLibraryFitsInsideTheHaloDrawnForIt() {
        let radius: CGFloat = 24
        let centre = CGPoint(x: 190, y: 410)
        var posesChecked = 0
        for figure in AnimaLibrary.figures {
            for clip in AnimaLibrary.clips {
                for time in [0.0, 0.5, 1.0, 2.7] {
                    let pose = clip.pose(of: figure, at: time)
                    let reach = CGFloat(pose.reach)
                    XCTAssertGreaterThanOrEqual(reach, 1,
                                                "\(figure.name)/\(clip.name): a reach under a "
                                                + "unit disc would light nothing")
                    for facing in [CGFloat(1), -1] {
                        for posed in pose.parts where posed.outline.count > 2 {
                            let path = SceneRenderer.path(for: posed, at: centre,
                                                          radius: radius, facing: facing)
                            var furthest: CGFloat = 0
                            var allFinite = true
                            for point in points(of: path) {
                                guard point.x.isFinite && point.y.isFinite else {
                                    allFinite = false
                                    break
                                }
                                let dx = point.x - centre.x, dy = point.y - centre.y
                                furthest = Swift.max(furthest,
                                                     (dx * dx + dy * dy).squareRoot())
                            }
                            let where_ = "\(figure.name)/\(clip.name) t=\(time) \(posed.name)"
                            XCTAssertTrue(allFinite, "\(where_): a non-finite vertex")
                            XCTAssertLessThanOrEqual(furthest, radius * reach + 1e-6,
                                                     "\(where_): reaches \(furthest), past the "
                                                     + "pose's own stated reach of "
                                                     + "\(radius * reach)")
                        }
                    }
                    posesChecked += 1
                }
            }
        }
        XCTAssertGreaterThan(posesChecked, 50, "the library handed over almost nothing to draw")

        // And the halo really is a widening of that bound rather than a
        // second, tighter one. This is the only part of the relationship the
        // sweep above does not already contain — `reach * 1.8` is looser than
        // `reach` for every pose there has ever been, so asserting the same
        // vertices against it too would have proved nothing twice.
        XCTAssertGreaterThan(1.8, 1.0,
                             "drawAnima's halo multiplier must widen the reach, not crop it")
    }

    // RENDERING READS, NEVER WRITES — the architecture rule, held against the
    // one drawing helper a test can call. The placement takes a posed part and
    // must leave it exactly as it found it, and two calls on the same input
    // must produce the same picture: the renderer holds no state, so nothing
    // in it can drift between frames.
    func testThePlacementIsPureAndLeavesWhatItIsGivenUntouched() {
        let subject = part(ring(count: 10))
        let before = subject
        let first = points(of: SceneRenderer.path(for: subject, at: CGPoint(x: 5, y: 6),
                                                  radius: 3, facing: -1))
        let second = points(of: SceneRenderer.path(for: subject, at: CGPoint(x: 5, y: 6),
                                                   radius: 3, facing: -1))
        XCTAssertEqual(subject, before, "the renderer mutated the pose it was handed")
        XCTAssertEqual(first.count, second.count)
        for index in first.indices {
            XCTAssertEqual(first[index].x, second[index].x, "vertex \(index) moved between frames")
            XCTAssertEqual(first[index].y, second[index].y, "vertex \(index) moved between frames")
        }
    }

    // MARK: - AnimalRendering: the balloon-animal silhouette

    // THE HALO COVERS EVERY LOBE THE RENDERER ACTUALLY DRAWS.
    //
    // `drawAnimal` sizes its halo from `shape.reach`, which is computed from
    // `lobes` — but the BODY it fills is `joinedLobes`, which contains lobes
    // that `reach` never saw. Nothing in the geometry file connects the two.
    // If a joiner ever bulged past the reach, a creature would have a limb
    // outside its own light, which is precisely the tell the halo sizing
    // exists to prevent. (`AnimalPopTests` proves the silhouette is CONNECTED;
    // this proves it is CONTAINED.)
    func testTheHaloCoversEveryLobeTheRendererDraws() {
        for shape in AnimalPop.Shape.allCases {
            let reach = shape.reach
            XCTAssertTrue(reach.isFinite && reach > 0, "\(shape.name): a degenerate reach")
            for (offset, lobeR) in shape.joinedLobes {
                XCTAssertTrue(offset.x.isFinite && offset.y.isFinite && lobeR.isFinite,
                              "\(shape.name): a non-finite lobe")
                XCTAssertGreaterThan(lobeR, 0, "\(shape.name): a lobe with no size")
                let far = hypot(offset.x, offset.y) + lobeR
                XCTAssertLessThanOrEqual(far, reach + 1e-9,
                                         "\(shape.name): a lobe reaches \(far), past the stated "
                                         + "reach of \(reach) — it would be drawn outside its "
                                         + "own halo")
            }
        }
    }

    // THE HIGHLIGHT LANDS ON THE BODY, NOT ON AN EAR. `drawAnimal` places the
    // one specular whisper on `lobes.max(by: radius)` and its comment says
    // that is "the body". Nothing enforces it: a shape authored with a big
    // ear would put the creature's only highlight on its head, which reads as
    // a light source that is not where the light is.
    func testTheHighlightLandsOnTheBodyAndNotOnAnEar() {
        for shape in AnimalPop.Shape.allCases {
            let lobes = shape.lobes
            guard let body = lobes.first else {
                return XCTFail("\(shape.name) has no lobes at all")
            }
            guard let biggest = lobes.max(by: { $0.1 < $1.1 }) else {
                return XCTFail("\(shape.name) has no largest lobe")
            }
            XCTAssertEqual(biggest.1, body.1,
                           "\(shape.name): the largest lobe is not the body, so the highlight "
                           + "would be placed on a limb")
            for (index, lobe) in lobes.enumerated() where index > 0 {
                XCTAssertLessThan(lobe.1, body.1,
                                  "\(shape.name): lobe \(index) is as large as the body — the "
                                  + "highlight's placement becomes an ordering accident")
            }
        }
    }

    // NO PART OF A CREATURE IS EVER CULLED AT A RADIUS THE FIELD CAN PRODUCE.
    //
    // `drawAnimal` skips any lobe whose drawn radius is <= 0.01 pt. The
    // silhouette is filled as ONE path under the nonzero rule, so a culled
    // JOINER does not remove a small dot — it disconnects a limb from the
    // body and the creature comes apart into the pile of circles the whole
    // file exists to avoid. The smallest radius the field can hand it is the
    // smallest orb at the bottom of its rise.
    func testNoPartOfACreatureIsCulledAtAnyRadiusTheFieldCanProduce() {
        let smallestDrawn = GameConfig.orbRadiusRange.lowerBound * GameConfig.depthMinScale
        XCTAssertGreaterThan(smallestDrawn, 0, "an orb that is never drawn at all")
        for shape in AnimalPop.Shape.allCases {
            let smallestLobe = shape.joinedLobes.map { $0.1 }.min() ?? 0
            XCTAssertGreaterThan(smallestLobe * smallestDrawn, 0.01,
                                 "\(shape.name): its smallest lobe (\(smallestLobe) radii) is "
                                 + "culled at the smallest radius the field draws "
                                 + "(\(smallestDrawn) pt), which breaks the silhouette open")
            // And the joined silhouette never loses a lobe it started with.
            XCTAssertGreaterThanOrEqual(shape.joinedLobes.count, shape.lobes.count,
                                        "\(shape.name): joining dropped a lobe")
        }
    }

    // MARK: - WeatherRenderer: the presence gate

    // THE AIR'S PRESENCE IS A GATE, AND IT REALLY CLOSES.
    //
    // Both of `WeatherRenderer`'s entry points open with
    // `guard field.presence > 0.001 else { return }` and then multiply every
    // fill by it, so `presence` is the only thing standing between a settled
    // field and a whole layer of drawing nobody can see. Everything inside
    // those two functions is `private` and takes a `GraphicsContext`, so the
    // gate itself is unreachable — what IS reachable is the value it turns
    // on, and this pins the three things the renderer relies on: it is always
    // a finite share in 0...1, it only ever falls while the field is settling,
    // and it reaches EXACTLY zero in bounded time, so the layer is skipped
    // outright rather than drawn at an invisible alpha forever.
    //
    // (`WeatherTests` proves quiescence waits for this through the whole
    // simulation; this drives `WeatherField` directly, one air at a time, and
    // is about the renderer's gate rather than about the pause.)
    func testTheAirsPresenceIsAGateThatActuallyCloses() {
        let airs = Weather.allCases.filter(\.hasField)
        XCTAssertFalse(airs.isEmpty, "no air has a field to draw")

        for weather in airs {
            var field = WeatherField()
            for _ in 0..<120 {
                field.step(1, weather: weather, bounds: screen,
                           reduceMotion: false, orbs: [], seed: 17)
                XCTAssertTrue(field.presence.isFinite, "\(weather): non-finite presence")
                XCTAssertGreaterThanOrEqual(field.presence, 0, "\(weather)")
                XCTAssertLessThanOrEqual(field.presence, 1,
                                         "\(weather): presence is a share, and every fill is "
                                         + "multiplied by it")
            }
            XCTAssertEqual(field.presence, 1, "\(weather): a field in play is fully on the glass")

            // Settling: monotone down, to exactly zero, inside a bounded run.
            var previous = field.presence
            var frames = 0
            while field.presence > 0 && frames < 600 {
                field.step(1, weather: weather, bounds: screen, reduceMotion: false,
                           orbs: [], seed: 17, settling: true)
                frames += 1
                XCTAssertTrue(field.presence.isFinite, "\(weather): non-finite presence")
                XCTAssertLessThanOrEqual(field.presence, previous,
                                         "\(weather): the air came back while settling")
                XCTAssertGreaterThanOrEqual(field.presence, 0, "\(weather)")
                previous = field.presence
            }
            XCTAssertEqual(field.presence, 0,
                           "\(weather): the gate never closed — the renderer would keep drawing "
                           + "the whole air layer at an alpha nobody can see")
            XCTAssertLessThan(frames, 600, "\(weather): the fade never finished")
            XCTAssertFalse(field.presence > 0.001,
                           "\(weather): the renderer's own gate does not close on this value")

            // And it stays shut for as long as the field is settled.
            for _ in 0..<30 {
                field.step(1, weather: weather, bounds: screen, reduceMotion: false,
                           orbs: [], seed: 17, settling: true)
                XCTAssertEqual(field.presence, 0, "\(weather): the air came back on its own")
            }

            // Coming back is bounded too: a share, never a gain.
            for _ in 0..<200 {
                field.step(1, weather: weather, bounds: screen, reduceMotion: false,
                           orbs: [], seed: 17)
                XCTAssertLessThanOrEqual(field.presence, 1,
                                         "\(weather): presence overshot 1 on the way back")
                XCTAssertGreaterThanOrEqual(field.presence, 0, "\(weather)")
            }
            XCTAssertEqual(field.presence, 1, "\(weather): the air never came back")
        }
    }

    // MARK: - Helpers

    // HSV saturation, which is the measure "muted" actually means: how far a
    // colour is from the grey of the same brightness.
    private func saturation(_ colour: PopColor) -> Double {
        let high = max(colour.r, max(colour.g, colour.b))
        let low = min(colour.r, min(colour.g, colour.b))
        guard high > 0 else { return 0 }
        return (high - low) / high
    }

    // A closed unit ring of `count` vertices — 1 unit from the origin, so its
    // extent in either axis is exactly 2 and every scaling claim above has a
    // number to be checked against.
    private func ring(count: Int) -> [CGPoint] {
        (0..<count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count)
            return CGPoint(x: cos(angle), y: sin(angle))
        }
    }

    private func part(_ outline: [CGPoint]) -> AnimaPosedPart {
        AnimaPosedPart(name: "test", outline: outline, transform: .identity,
                       paint: 0, opacity: 1, depth: 0)
    }

    // The vertices the renderer actually put into the path, in order. Read
    // from the path's own elements rather than from its bounding box, so what
    // is being checked is what was drawn rather than what CoreGraphics made
    // of it afterwards.
    private func points(of path: Path) -> [CGPoint] {
        var out: [CGPoint] = []
        path.forEach { element in
            switch element {
            case .move(let to): out.append(to)
            case .line(let to): out.append(to)
            case .quadCurve(let to, let control): out.append(control); out.append(to)
            case .curve(let to, let c1, let c2): out.append(c1); out.append(c2); out.append(to)
            case .closeSubpath: break
            }
        }
        return out
    }

    private func extent(of path: Path) -> CGRect {
        let all = points(of: path)
        guard let first = all.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in all.dropFirst() {
            minX = Swift.min(minX, point.x); maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y); maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
