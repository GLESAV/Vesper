import XCTest
import CoreGraphics
@testable import Vesper

// Proof for the two travel-only render cues (DELIVERY_ROADMAP W05, the second
// half — mote parallax and transit luminance attenuation). Both live in
// `WorldRender` as pure functions of the camera's current position precisely
// so that they can be proved here, with no screen, no Canvas, and no
// wall-clock: `dt` is synthetic and fixed, exactly as WorldCameraTests and
// GameSimulationTests drive theirs.
//
// What is pinned here, and why each one is a test rather than a comment:
//
//   parallax is a FUNCTION, not an integration
//       → testParallaxIsAPureFunctionOfOffsetAndNotAnIntegration
//   parallax is EXACTLY zero at every rest offset, in every geometry
//       → testParallaxIsExactlyZeroAtEveryRestOffset
//       → testParallaxReturnsToExactlyZeroAcrossAFullSettle
//   barrier condition 11: Reduce Motion translates NOTHING, motes included
//       → testParallaxIsIdenticallyZeroUnderReduceMotion
//   the motes never lead the field, never fight it, and never open a gap
//       → testMotesNeverOutrunTheFieldAndNeverReverseAgainstIt
//       → testParallaxNeverExceedsTheFieldsOwnDisplacement
//   barrier condition 14: the light takes turns while she travels, in BOTH
//   motion modes — the R-ARCH carry-forward that `isTransitioning`, not
//   `flow`, is the single question
//       → testLuminanceDimsAndReturnsAcrossAFullSettleInBothMotionModes
//       → testLuminanceDimsUnderReduceMotionWhereFlowIsIdenticallyZero
//   and it comes back EXACTLY, always, with nothing left over
//       → testLuminanceIsExactlyFullAtRest
//       → testLuminanceIsExactlyFullAtEveryPlaceCentre
//       → testNeitherCueLeavesAResidueAfterAnInterruptedSettle
//
// And W05c's third cue — the end-of-axis acknowledgement, the only one that
// is not a function of camera position:
//
//   the scale is linear, bounded, and exactly zero at zero
//       → testEdgeAcknowledgementScalesTheEnvelopeAndNothingElse
//       → testEdgeAcknowledgementRefusesNonsenseWithNoLight
//   the light rises and returns without a step anyone can see
//       → testTheAcknowledgementRisesAndReturnsWithoutAFlicker
//   and it costs the other two cues NOTHING, because the world is at rest
//       → testAnAcknowledgementNeitherDimsTheWorldNorMovesItsDust
//
// `@MainActor` mirrors the camera's own isolation, for the same reason
// WorldCameraTests states it: the camera is written from UIKit touch callbacks
// and read from the SwiftUI render closure, both main.
@MainActor
final class WorldRenderTests: XCTestCase {

    // The 390 × 844 pt reference screen the roadmap's arithmetic is quoted on.
    private let screenHeight: CGFloat = 844

    private let frame: TimeInterval = 1.0 / 120.0

    private func makeCamera(reduceMotion: Bool = false) -> WorldCamera {
        WorldCamera(viewHeight: screenHeight, reduceMotion: reduceMotion)
    }

    // MARK: - Helpers

    // The parallax as `WorldView.movingBody` computes it: from `camera.offset`
    // — the Reduce Motion-aware accessor — and never from anything else.
    private func parallax(_ camera: WorldCamera) -> CGFloat {
        WorldRender.moteParallax(offset: camera.offset,
                                 travelPerPlace: camera.config.travelPerPlace,
                                 viewHeight: screenHeight)
    }

    // The luminance as `WorldView.movingBody` computes it: `isTransitioning`
    // is the question, the crossfade is the shape.
    private func luminance(_ camera: WorldCamera) -> Double {
        WorldRender.transitLuminance(isTransitioning: camera.isTransitioning,
                                     crossfade: camera.transition.t)
    }

    // The field body's own translation in points, as `movingBody` applies it.
    private func fieldTranslation(_ offset: CGFloat) -> CGFloat {
        -offset * screenHeight
    }

    private struct CueTrace {
        var luminance: [Double] = []
        var parallax: [CGFloat] = []
        var flow: [CGFloat] = []
        var frames = 0

        // The largest one-frame change either cue made. This is the number
        // that decides whether an attenuation is a ramp or a flicker, so it is
        // measured rather than eyeballed.
        var worstLuminanceStep: Double {
            guard luminance.count > 1 else { return 0 }
            var worst: Double = 0
            for index in 1..<luminance.count {
                worst = max(worst, abs(luminance[index] - luminance[index - 1]))
            }
            return worst
        }
        var worstParallaxStep: CGFloat {
            guard parallax.count > 1 else { return 0 }
            var worst: CGFloat = 0
            for index in 1..<parallax.count {
                worst = max(worst, abs(parallax[index] - parallax[index - 1]))
            }
            return worst
        }
    }

    // Samples both cues on every frame of a settle, starting with the frame
    // the settle begins on, and ending with the frame the camera lands.
    private func traceToRest(_ camera: WorldCamera, limit: Int = 10_000) -> CueTrace {
        var trace = CueTrace()
        trace.luminance.append(luminance(camera))
        trace.parallax.append(parallax(camera))
        trace.flow.append(camera.flow)
        while !camera.isAtRest && trace.frames < limit {
            camera.step(dt: frame)
            trace.frames += 1
            trace.luminance.append(luminance(camera))
            trace.parallax.append(parallax(camera))
            trace.flow.append(camera.flow)
        }
        XCTAssertTrue(camera.isAtRest, "settle did not converge within \(limit) frames")
        return trace
    }

    // MARK: - Parallax: the shape

    // The whole of the "not an integration" requirement, as an experiment:
    // two cameras arriving at the same offset by completely different routes
    // — one in a single step, one across hundreds of frames of settling —
    // must produce the SAME parallax, to the bit. A per-frame accumulation
    // could not pass this, and neither could anything that read `dt`.
    func testParallaxIsAPureFunctionOfOffsetAndNotAnIntegration() {
        let travelled = makeCamera()
        travelled.consume(.commit(.up, velocity: -1688))
        for _ in 0..<20 { travelled.step(dt: frame) }
        XCTAssertFalse(travelled.isAtRest, "the camera should still be in flight here")

        let placed = makeCamera()
        placed.consume(.panBegan)
        placed.consume(.panChanged(translation: travelled.offset * screenHeight))
        XCTAssertEqual(placed.offset, travelled.offset, accuracy: 1e-12,
                       "the two routes must arrive at the same offset for this to prove anything")

        XCTAssertEqual(parallax(placed), parallax(travelled), accuracy: 1e-12,
                       "the parallax must depend on WHERE the camera is, never on how it got there")

        // And it does not change when nothing does: sixty frames of a held
        // camera leave it exactly where it was. (A drifting mote layer is
        // what an integration would look like from here.)
        let held = parallax(placed)
        for _ in 0..<60 { placed.step(dt: frame) }
        XCTAssertEqual(parallax(placed), held, "a still world must draw a still mote layer")
    }

    // EXACTLY zero — not "small", not "within a pixel". `step(dt:)` lands the
    // camera exactly on `restOffset`, so `u` is exactly 0 or ±1 there, and the
    // shape `u(1 − u²)` is exactly zero at all three. Swept across geometries
    // because the property must not depend on the tuning.
    func testParallaxIsExactlyZeroAtEveryRestOffset() {
        for travel in [CGFloat(0.75), 0.5, 1.0, 0.6667, 0.123456789] {
            for height in [CGFloat(568), 844, 932, 1366] {
                for place in Place.allCases {
                    let value = WorldRender.moteParallax(offset: CGFloat(place.rawValue) * travel,
                                                         travelPerPlace: travel,
                                                         viewHeight: height)
                    XCTAssertEqual(value, 0,
                                   "travel \(travel), height \(height), \(place): a place at rest "
                                   + "must draw its dust exactly where the field is")
                }
            }
        }
    }

    // As she leaves a place the motes travel at `1 − moteLag` of the field's
    // rate — that is what the constant MEANS, and it is only true because the
    // shape is exactly `u` near a place centre.
    func testMotesLeaveAPlaceAtTheStatedFractionOfTheFieldsRate() {
        let offset: CGFloat = 0.001
        let body = fieldTranslation(offset)
        let net = body + WorldRender.moteParallax(offset: offset,
                                                  travelPerPlace: 0.75,
                                                  viewHeight: screenHeight)
        XCTAssertEqual(Double(net / body), Double(1 - WorldRender.moteLag), accuracy: 1e-4,
                       "the dust should leave the field at 70% of the field's own rate")
    }

    // The two properties that keep the effect from ever being seen as a
    // failure rather than as depth: the motes never move AGAINST the field,
    // and they never move FASTER than it. Both fall out of
    // net = body · (1 − moteLag(1 − u²)), and the factor is in [0.7, 1].
    func testMotesNeverOutrunTheFieldAndNeverReverseAgainstIt() {
        let travel: CGFloat = 0.75
        let samples = 4001
        for index in 0..<samples {
            let offset = -travel + 2 * travel * CGFloat(index) / CGFloat(samples - 1)
            let body = fieldTranslation(offset)
            let net = body + WorldRender.moteParallax(offset: offset,
                                                      travelPerPlace: travel,
                                                      viewHeight: screenHeight)
            guard abs(body) > 1e-9 else {
                XCTAssertEqual(net, 0, "a field that has not moved must not move its dust")
                continue
            }
            let ratio = net / body
            XCTAssertGreaterThanOrEqual(Double(ratio), Double(1 - WorldRender.moteLag) - 1e-12,
                                        "the dust must never lag by more than the stated fraction")
            XCTAssertLessThanOrEqual(Double(ratio), 1 + 1e-12,
                                     "the dust must never outrun the field it sits behind")
        }
    }

    // THE NO-GAP INVARIANT, and the reason a rigid mote translation is safe to
    // draw inside a clipped canvas at all: the lag is always smaller than the
    // field's own displacement, so the depopulated edge of the dust is always
    // further off screen than the edge of the canvas clipping it. If this ever
    // fails, a mote-free band opens into view at one edge of the field.
    func testParallaxNeverExceedsTheFieldsOwnDisplacement() {
        let travel: CGFloat = 0.75
        let samples = 4001
        for index in 0..<samples {
            let offset = -travel + 2 * travel * CGFloat(index) / CGFloat(samples - 1)
            let lag = abs(WorldRender.moteParallax(offset: offset,
                                                   travelPerPlace: travel,
                                                   viewHeight: screenHeight))
            XCTAssertLessThanOrEqual(Double(lag),
                                     Double(abs(fieldTranslation(offset))) + 1e-12,
                                     "at offset \(offset) the dust lags further than the field moved")
        }
    }

    // The magnitude, stated once so a later tuning change has to come past a
    // number: at 0.30 the peak displacement is 0.087 screen heights, reached
    // at u = 1/√3, and it is continuous everywhere on the axis.
    func testParallaxPeaksWhereItIsStatedTo() {
        let travel: CGFloat = 0.75
        var peak: CGFloat = 0
        var peakOffset: CGFloat = 0
        var worstStep: CGFloat = 0
        var previous = WorldRender.moteParallax(offset: -travel,
                                                travelPerPlace: travel,
                                                viewHeight: screenHeight)
        let samples = 4001
        for index in 1..<samples {
            let offset = -travel + 2 * travel * CGFloat(index) / CGFloat(samples - 1)
            let value = WorldRender.moteParallax(offset: offset,
                                                 travelPerPlace: travel,
                                                 viewHeight: screenHeight)
            if abs(value) > peak { peak = abs(value); peakOffset = offset }
            worstStep = max(worstStep, abs(value - previous))
            previous = value
        }
        XCTAssertEqual(Double(peak / screenHeight), 0.0866, accuracy: 0.001,
                       "peak displacement should be 0.087 screen heights (73 pt at 844)")
        XCTAssertEqual(Double(abs(peakOffset) / travel), 0.5774, accuracy: 0.01,
                       "…reached at u = 1/√3, the maximum of u(1 − u²)")
        XCTAssertLessThan(Double(worstStep), 1,
                          "the shape must be continuous: no step across a 0.0004-screen-height "
                          + "sample can move the dust a whole point")
    }

    // A degenerate world draws without the cue rather than drawing a NaN into
    // every mote on the field.
    func testParallaxRefusesADegenerateGeometry() {
        XCTAssertEqual(WorldRender.moteParallax(offset: 0.4, travelPerPlace: 0,
                                                viewHeight: screenHeight), 0)
        XCTAssertEqual(WorldRender.moteParallax(offset: 0.4, travelPerPlace: -1,
                                                viewHeight: screenHeight), 0)
        XCTAssertEqual(WorldRender.moteParallax(offset: 0.4, travelPerPlace: 0.75,
                                                viewHeight: 0), 0)
        XCTAssertEqual(WorldRender.moteParallax(offset: .nan, travelPerPlace: 0.75,
                                                viewHeight: screenHeight), 0)
        // Beyond the ends of the world — which `clampToAxis` makes
        // unreachable, but a cubic that was allowed to run past u = ±1 would
        // invert its sign and throw the dust the wrong way.
        XCTAssertEqual(WorldRender.moteParallax(offset: 5, travelPerPlace: 0.75,
                                                viewHeight: screenHeight), 0)
        XCTAssertEqual(WorldRender.moteParallax(offset: -5, travelPerPlace: 0.75,
                                                viewHeight: screenHeight), 0)
    }

    // MARK: - Parallax: on a real camera

    // BARRIER CONDITION 11. Under Reduce Motion the camera produces zero
    // translation, and the mote layer is part of "zero". This needs no special
    // case in the renderer — `camera.offset` is identically zero there, so the
    // shape is identically zero — and this test is what says so.
    func testParallaxIsIdenticallyZeroUnderReduceMotion() {
        let camera = makeCamera(reduceMotion: true)
        camera.consume(.panBegan)
        for points in stride(from: CGFloat(-20), through: -600, by: -20) {
            camera.consume(.panChanged(translation: points))
            camera.step(dt: frame)
            XCTAssertEqual(parallax(camera), 0, "RM: a drag may not translate the dust")
        }
        camera.consume(.commit(.up, velocity: -1688))
        let trace = traceToRest(camera)
        XCTAssertGreaterThan(trace.frames, 10, "the RM crossfade should have taken real time")
        for value in trace.parallax {
            XCTAssertEqual(value, 0, "RM: nothing translates, motes included")
        }
    }

    // Zero at rest is not enough on its own — it has to be zero at rest AFTER
    // TRAVELLING, in the place she arrived in, on the frame the world stops.
    func testParallaxReturnsToExactlyZeroAcrossAFullSettle() {
        for direction in [WorldDirection.up, .down] {
            let camera = makeCamera()
            camera.consume(.commit(direction, velocity: 0))
            let trace = traceToRest(camera)

            XCTAssertNotEqual(camera.place, .field, "the commit should have moved her")
            XCTAssertEqual(parallax(camera), 0,
                           "\(direction): nothing about where she has been may survive arriving")
            XCTAssertEqual(trace.parallax.last, 0)
            let peak = trace.parallax.map(abs).max() ?? 0
            XCTAssertEqual(Double(peak / screenHeight), 0.0866, accuracy: 0.002,
                           "\(direction): the dust should have lagged by 0.087 screen heights "
                           + "at the middle of the journey")
            XCTAssertLessThan(Double(trace.worstParallaxStep), 12,
                              "\(direction): the dust must not jump between frames")
        }
    }

    // MARK: - Luminance: the shape

    func testLuminanceIsExactlyFullAtRest() {
        XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: false, crossfade: 0.5), 1)
        XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: false, crossfade: 0), 1)
        XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: false, crossfade: 1), 1)
        let camera = makeCamera()
        XCTAssertEqual(luminance(camera), 1, "a world that has never moved is fully lit")
        for _ in 0..<600 { camera.step(dt: frame) }
        XCTAssertEqual(luminance(camera), 1, "…and stays that way for as long as she leaves it alone")
    }

    // The second of the two guarantees, and the one that holds even if the
    // gate were somehow open: the shape is exactly zero at either end of a
    // leg, so a place centre is never dimmed by a fraction of anything.
    func testLuminanceIsExactlyFullAtEveryPlaceCentre() {
        XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: true, crossfade: 0), 1)
        XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: true, crossfade: 1), 1)
    }

    // Single-signed and non-overshooting, which is what condition 12's
    // "monotone" asks of a value that has to come back: the multiplier never
    // rises above full light and never falls below the stated floor, so the
    // world cannot be pumped brighter or darker by any gesture.
    func testLuminanceStaysInsideItsBandAndNeverBrightens() {
        for index in 0...1000 {
            let t = CGFloat(index) / 1000
            let value = WorldRender.transitLuminance(isTransitioning: true, crossfade: t)
            XCTAssertLessThanOrEqual(value, 1, "the world may never be brighter than its own light")
            XCTAssertGreaterThanOrEqual(value, 1 - WorldRender.transitDim - 1e-12,
                                        "…nor darker than the stated floor")
        }
        XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: true, crossfade: 0.5),
                       1 - WorldRender.transitDim, accuracy: 1e-12,
                       "the full attenuation belongs at the midpoint of a leg")
        // Out-of-range and nonsense arguments resolve to full light rather
        // than to a NaN multiplying every colour in the world.
        XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: true, crossfade: 2), 1)
        XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: true, crossfade: -1), 1)
        XCTAssertEqual(WorldRender.transitLuminance(isTransitioning: true, crossfade: .nan), 1)
    }

    // MARK: - Luminance: on a real camera

    // BARRIER CONDITION 14, end to end and in both motion modes: the light
    // comes down while she travels, reaches the full attenuation at the middle
    // of the journey, and is back — exactly, not nearly — on the frame she
    // lands. And it gets there without a step: a visible pulse on every
    // navigation would be worse than no dimming at all.
    func testLuminanceDimsAndReturnsAcrossAFullSettleInBothMotionModes() {
        for reduced in [false, true] {
            for direction in [WorldDirection.up, .down] {
                let camera = makeCamera(reduceMotion: reduced)
                camera.consume(.commit(direction, velocity: 0))
                let trace = traceToRest(camera)

                let dimmest = trace.luminance.min() ?? 1
                XCTAssertEqual(dimmest, 1 - WorldRender.transitDim, accuracy: 1e-3,
                               "RM \(reduced) \(direction): the light should take its turn")
                XCTAssertEqual(trace.luminance.last, 1,
                               "RM \(reduced) \(direction): and be back, exactly, on arrival")
                XCTAssertEqual(luminance(camera), 1,
                               "RM \(reduced) \(direction): no residual dimming, ever")
                XCTAssertLessThanOrEqual(trace.luminance.max() ?? 0, 1,
                                         "RM \(reduced) \(direction): never brighter than full")
                XCTAssertLessThan(trace.worstLuminanceStep, 0.01,
                                  "RM \(reduced) \(direction): the attenuation must not flicker — "
                                  + "an ordinary navigation enters and leaves the dim at nothing")
            }
        }
    }

    // THE R-ARCH CARRY-FORWARD, as a test. `flow` is identically zero for the
    // whole of a Reduce Motion transition, because nothing translates — so a
    // cue keyed on `flow` or on `exceedsTransitFlow` would leave the
    // accessible path as the one journey where the light never takes its turn,
    // while two whole places crossfade through each other. `isTransitioning`
    // is the question, and this is why.
    func testLuminanceDimsUnderReduceMotionWhereFlowIsIdenticallyZero() {
        let camera = makeCamera(reduceMotion: true)
        camera.consume(.commit(.down, velocity: 0))
        let trace = traceToRest(camera)

        for value in trace.flow {
            XCTAssertEqual(value, 0, "RM translates nothing, so there is no flow to key off")
        }
        XCTAssertFalse(camera.exceedsTransitFlow,
                       "…and the flow-derived question is false for the whole journey")
        XCTAssertLessThan(trace.luminance.min() ?? 1, 1 - WorldRender.transitDim * 0.9,
                          "…yet the light must still take its turn on the accessible path")
        XCTAssertEqual(trace.luminance.last, 1)
    }

    // Every move is interruptible, so both cues have to survive being caught
    // in the middle and put back. A grab mid-settle, a hold, and a release
    // with no decision behind it must end with the world exactly as lit and
    // exactly as aligned as it would have been if she had never touched it.
    func testNeitherCueLeavesAResidueAfterAnInterruptedSettle() {
        let camera = makeCamera()
        camera.consume(.commit(.up, velocity: -1688))
        for _ in 0..<20 { camera.step(dt: frame) }
        XCTAssertFalse(camera.isAtRest)

        camera.consume(.panBegan)
        for _ in 0..<30 { camera.step(dt: frame) }
        let caught = parallax(camera)
        XCTAssertNotEqual(caught, 0, "the grab should have caught the world mid-journey")

        camera.consume(.cancelToRest)
        let trace = traceToRest(camera)

        XCTAssertEqual(parallax(camera), 0, "the dust is home when the world is")
        XCTAssertEqual(luminance(camera), 1, "and the light is back, exactly")
        XCTAssertEqual(trace.parallax.last, 0)
        XCTAssertEqual(trace.luminance.last, 1)
        XCTAssertLessThanOrEqual(trace.luminance.max() ?? 0, 1)
    }

    // A whisper tap is a commit with no flick behind it (`WorldView.go`), and
    // it is the PRIMARY way through the world — so the cues are proved on that
    // path too, not only on the swipe.
    func testTheCuesBehaveOnTheWhisperPath() {
        let camera = makeCamera()
        camera.consume(.commit(.down, velocity: 0))
        let outbound = traceToRest(camera)
        XCTAssertEqual(camera.place, .journal)
        XCTAssertEqual(outbound.parallax.last, 0)
        XCTAssertEqual(outbound.luminance.last, 1)

        camera.consume(.commit(.up, velocity: 0))
        let home = traceToRest(camera)
        XCTAssertEqual(camera.place, .field)
        XCTAssertEqual(camera.offset, 0, "she is home")
        XCTAssertEqual(home.parallax.last, 0, "…and so is her dust")
        XCTAssertEqual(home.luminance.last, 1, "…and so is her light")
        XCTAssertLessThan(home.worstLuminanceStep, 0.01)
    }

    // MARK: - The end-of-axis acknowledgement (W05c)

    // The cue as `WorldView.edgeAcknowledgement` computes it: the camera's
    // normalized envelope, scaled and nothing else.
    private func edgeLight(_ camera: WorldCamera) -> Double {
        WorldRender.edgeAcknowledgementOpacity(level: camera.acknowledgementLevel)
    }

    // The renderer SCALES the camera's envelope; it does not shape it. A curve
    // here would be the second curve in a fight over one number — the same
    // mistake ruling 7 bars when it bars `withAnimation` on a camera value —
    // so linearity is the property, and it is a test rather than a comment.
    func testEdgeAcknowledgementScalesTheEnvelopeAndNothingElse() {
        XCTAssertEqual(WorldRender.edgeAcknowledgementOpacity(level: 0), 0,
                       "exactly zero at zero: this is what the pause predicate rides on")
        XCTAssertEqual(WorldRender.edgeAcknowledgementOpacity(level: 1),
                       WorldRender.edgeAcknowledgementPeak, accuracy: 1e-12)

        for index in 0...1000 {
            let level = CGFloat(index) / 1000
            let value = WorldRender.edgeAcknowledgementOpacity(level: level)
            XCTAssertEqual(value, WorldRender.edgeAcknowledgementPeak * Double(level),
                           accuracy: 1e-12, "level \(level): the renderer added a shape")
            XCTAssertLessThanOrEqual(value, WorldRender.edgeAcknowledgementPeak + 1e-12,
                                     "the light may never exceed its stated peak")
            XCTAssertGreaterThanOrEqual(value, 0)
        }

        // The peak, stated once so a later tuning change has to come past a
        // number: it is the alpha `SkyView` gives a quiet star's halo, which
        // is the dimmest light this world already draws on purpose.
        XCTAssertEqual(WorldRender.edgeAcknowledgementPeak, 0.10, accuracy: 1e-12)
        XCTAssertLessThan(WorldRender.edgeAcknowledgementPeak, 0.12,
                          "…and under the white hairline the cards use for 'just visible'")
    }

    // Failing toward the picture that existed before W05c, exactly as
    // `transitLuminance` fails toward full light: a degenerate level draws no
    // acknowledgement rather than a NaN alpha over a full-screen gradient.
    func testEdgeAcknowledgementRefusesNonsenseWithNoLight() {
        XCTAssertEqual(WorldRender.edgeAcknowledgementOpacity(level: .nan), 0)
        XCTAssertEqual(WorldRender.edgeAcknowledgementOpacity(level: .infinity), 0)
        XCTAssertEqual(WorldRender.edgeAcknowledgementOpacity(level: -1), 0)
        XCTAssertEqual(WorldRender.edgeAcknowledgementOpacity(level: 5),
                       WorldRender.edgeAcknowledgementPeak, accuracy: 1e-12,
                       "a level past the bound clamps to the peak rather than exceeding it")
    }

    // End to end on a real camera, in both motion modes. The light comes up,
    // reaches its peak, and goes out EXACTLY — and it gets there without a
    // step anyone would see, which is the whole risk this cue carries. A
    // visible pulse at the top of the screen every time she flicks at the
    // ceiling would be worse than the silence it replaced.
    func testTheAcknowledgementRisesAndReturnsWithoutAFlicker() {
        for reduced in [false, true] {
            for (place, direction) in [(Place.sky, WorldDirection.up), (.journal, .down)] {
                let camera = makeCamera(reduceMotion: reduced)
                camera.consume(.commit(direction, velocity: 0))
                _ = traceToRest(camera)
                XCTAssertEqual(camera.place, place)

                camera.consume(.commit(direction, velocity: 2400))
                var light: [Double] = [edgeLight(camera)]
                var frames = 0
                while !camera.isIdle && frames < 10_000 {
                    camera.step(dt: frame)
                    frames += 1
                    light.append(edgeLight(camera))
                }
                XCTAssertTrue(camera.isIdle)

                XCTAssertEqual(light.first, 0, "RM \(reduced) \(place): it starts from nothing")
                XCTAssertEqual(light.last, 0,
                               "RM \(reduced) \(place): and ends at exactly nothing, so a paused "
                               + "frame is never left mid-glow")
                XCTAssertEqual(light.max() ?? 0, WorldRender.edgeAcknowledgementPeak,
                               accuracy: 1e-12,
                               "RM \(reduced) \(place): an undamped answer reaches the full peak")

                var worst: Double = 0
                for index in 1..<light.count {
                    worst = max(worst, abs(light[index] - light[index - 1]))
                }
                XCTAssertLessThan(worst, 0.006,
                                  "RM \(reduced) \(place): the light stepped by \(worst) in one "
                                  + "frame — an acknowledgement that flickers is worse than none")
                print("[W05c] \(place) \(direction) RM \(reduced): \(frames) frames, "
                      + "peak \(String(format: "%.4f", light.max() ?? 0)), "
                      + "worst step \(String(format: "%.5f", worst))")
            }
        }
    }

    // THE COST TO THE OTHER TWO CUES IS ZERO, and it has to be measured rather
    // than asserted, because both of them key off motion the camera is not
    // making here. Through the whole of an acknowledgement the world is at
    // rest: the dust sits exactly where the field is and the light stays
    // exactly full. If either of these ever moves, condition 14 has started
    // dimming a world that is standing still.
    func testAnAcknowledgementNeitherDimsTheWorldNorMovesItsDust() {
        for reduced in [false, true] {
            let camera = makeCamera(reduceMotion: reduced)
            camera.consume(.commit(.up, velocity: 0))
            _ = traceToRest(camera)
            let parked = parallax(camera)
            XCTAssertEqual(parked, 0, "the sky is a rest offset, so the dust is home")

            camera.consume(.commit(.up, velocity: 2400))
            var frames = 0
            while !camera.isIdle && frames < 10_000 {
                camera.step(dt: frame)
                frames += 1
                XCTAssertEqual(luminance(camera), 1,
                               "RM \(reduced) frame \(frames): a still world was dimmed")
                XCTAssertEqual(parallax(camera), parked,
                               "RM \(reduced) frame \(frames): a still world moved its dust")
                XCTAssertFalse(camera.isTransitioning,
                               "RM \(reduced) frame \(frames): a still world claimed a transit")
            }
            XCTAssertGreaterThan(frames, 30, "the envelope was too short to prove anything")
            XCTAssertEqual(edgeLight(camera), 0)
        }
    }
}
