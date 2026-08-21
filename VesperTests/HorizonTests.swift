import XCTest
import CoreGraphics
@testable import Vesper

// Proof for the HORIZON — the seamless answer to the owner's question about
// the border between the sky and gameplay.
//
// The horizon is drawing, so what is provable here is the pure arithmetic
// behind the drawing, and `HorizonRender` is written so that ALL of it is:
// where the light is on the axis, how deep the band is, what alpha every stop
// of it carries, and what the brightest pixel it can produce measures. No
// screen, no `Canvas`, no wall-clock — `dt` is synthetic and fixed, exactly as
// `WorldRenderTests` and `WorldCameraTests` drive theirs.
//
// What is pinned here, and why each one is a test rather than a comment:
//
//   guardrail 4 in numbers: the horizon is never brighter than 12% luminance,
//   at ANY camera offset, in either motion mode
//       → testLuminanceNeverExceedsTheCapAtAnyOffset
//       → testLuminanceNeverExceedsTheCapAcrossEveryRealSettle
//   it is a GLOW, not a line: zero alpha on the row a `Canvas` clips, and zero
//   again where the sky's own bottom edge falls
//       → testTheBandFadesToNothingAtBothOfItsEdges
//       → testEveryProfileIsOrderedAndBounded
//   it is CONTINUOUS across a place centre — the defect class this project has
//   already paid for once
//       → testPresenceIsContinuousAcrossEveryPlaceCentre
//       → testPresenceHasNoKinkAtTheFieldCentre
//       → testPresenceNeverStepsAcrossTheWholeAxis
//   Reduce Motion: identically still, and identical to the field at rest
//       → testReduceMotionIsIdenticallyStillAtEveryOffset
//   and it returns to a known state at rest, in every place
//       → testEveryPlaceAtRestHasItsKnownHorizon
//       → testTheHorizonReturnsToItsRestStateAcrossAFullSettle
//   the band is the sky/field OVERLAP, not an invented number
//       → testTheBandIsTheOverlapBetweenTheTwoPlaces
//   and a degenerate world draws no horizon rather than a NaN
//       → testNonsenseDrawsNoHorizonAtAll
//
// `@MainActor` mirrors the camera's own isolation, for the reason
// `WorldCameraTests` states: the camera is written from UIKit touch callbacks
// and read from the SwiftUI render closure, both main.
@MainActor
final class HorizonTests: XCTestCase {

    // The 390 × 844 pt reference screen the roadmap's arithmetic is quoted on.
    private let screenHeight: CGFloat = 844

    private let frame: TimeInterval = 1.0 / 120.0

    private func makeCamera(reduceMotion: Bool = false) -> WorldCamera {
        WorldCamera(viewHeight: screenHeight, reduceMotion: reduceMotion)
    }

    // The horizon exactly as `WorldView.movingBody` computes it: from
    // `camera.offset` — the Reduce Motion-aware accessor — and never from
    // anything else.
    private func horizon(_ camera: WorldCamera) -> HorizonRender.Horizon {
        HorizonRender.state(offset: camera.offset,
                            travelPerPlace: camera.config.travelPerPlace,
                            viewHeight: screenHeight,
                            reduceMotion: camera.reduceMotion)
    }

    private func horizon(atOffset offset: CGFloat,
                         travelPerPlace: CGFloat = 0.75,
                         reduceMotion: Bool = false) -> HorizonRender.Horizon {
        HorizonRender.state(offset: offset,
                            travelPerPlace: travelPerPlace,
                            viewHeight: screenHeight,
                            reduceMotion: reduceMotion)
    }

    // MARK: - Guardrail 4, in numbers

    // THE CEILING, SWEPT RATHER THAN SAMPLED. Every offset the camera can
    // occupy — and a margin either side of the axis it clamps to, because a
    // ceiling that only holds inside the reachable range is a ceiling nobody
    // can trust after the next geometry change.
    func testLuminanceNeverExceedsTheCapAtAnyOffset() {
        let travel: CGFloat = 0.75
        let samples = 4001
        for reduceMotion in [false, true] {
            for index in 0..<samples {
                let offset = -2 * travel + 4 * travel * CGFloat(index) / CGFloat(samples - 1)
                let state = horizon(atOffset: offset, travelPerPlace: travel,
                                    reduceMotion: reduceMotion)
                let measured = HorizonRender.peakLuminance(state)
                XCTAssertLessThanOrEqual(measured, HorizonRender.luminanceCap,
                                         "offset \(offset), RM \(reduceMotion): the horizon must "
                                         + "stay under \(HorizonRender.luminanceCap) luminance")
                XCTAssertLessThanOrEqual(state.presence, 1,
                                         "offset \(offset): presence is a share, never a gain")
                XCTAssertGreaterThanOrEqual(state.presence, 0,
                                            "offset \(offset): the horizon may not go negative")
            }
        }
    }

    // The cap is not the whole guarantee — the number it is being held against
    // must also be the one guardrail 4 asks for, and the headroom must be real
    // rather than a rounding.
    func testTheCapIsTheGuardrailAndTheHeadroomIsReal() {
        XCTAssertLessThanOrEqual(HorizonRender.luminanceCap, 0.12,
                                 "the ceiling is ~12% luminance, and it may only ever come down")
        let brightest = HorizonRender.peakLuminance(
            HorizonRender.Horizon(presence: 1, depth: screenHeight * 0.25))
        XCTAssertLessThan(brightest, HorizonRender.luminanceCap * 0.5,
                          "at full presence the horizon should not be within touching distance "
                          + "of its own ceiling — it is a glow, not a light")
        // Nothing pure white, nothing saturated: the light is the world's own
        // muted pastel, and its channels are within a few percent of each other.
        let tone = HorizonRender.lightTone
        XCTAssertLessThan(max(tone.r, max(tone.g, tone.b)), 1,
                          "the horizon may never be pure white")
        XCTAssertLessThan(max(tone.r, max(tone.g, tone.b)) - min(tone.r, min(tone.g, tone.b)), 0.15,
                          "the horizon may never be saturated")
    }

    // The same ceiling, on trajectories the camera actually produces rather
    // than on a sweep someone chose.
    func testLuminanceNeverExceedsTheCapAcrossEveryRealSettle() {
        for direction in [WorldDirection.up, .down] {
            for reduceMotion in [false, true] {
                let camera = makeCamera(reduceMotion: reduceMotion)
                camera.consume(.commit(direction, velocity: direction == .up ? -1200 : 1200))
                var frames = 0
                while !camera.isAtRest && frames < 10_000 {
                    camera.step(dt: frame)
                    frames += 1
                    XCTAssertLessThanOrEqual(HorizonRender.peakLuminance(horizon(camera)),
                                             HorizonRender.luminanceCap,
                                             "\(direction), RM \(reduceMotion): frame \(frames)")
                }
                XCTAssertTrue(camera.isAtRest, "settle did not converge")
            }
        }
    }

    // MARK: - A glow, not a line

    // THE SINGLE PROPERTY THAT DECIDES WHETHER THIS IS THE SEAMLESS ANSWER OR
    // THE BORDERED ONE. The band's top row is the field `Canvas`'s own clipped
    // edge; any alpha at all on it is a step from nothing to something along a
    // perfectly straight horizontal line, which is a border drawn by accident.
    // The bottom row is where the sky's own bottom edge falls, and light
    // attributed to the sky may not outlive the sky.
    func testTheBandFadesToNothingAtBothOfItsEdges() {
        for presence in stride(from: 0.0, through: 1.0, by: 0.05) {
            let state = HorizonRender.Horizon(presence: presence, depth: 211)
            for stops in [HorizonRender.lightStops(state), HorizonRender.groundStops(state)] {
                XCTAssertEqual(stops.first?.location, 0, "the band must start at its own top")
                XCTAssertEqual(stops.last?.location, 1, "the band must end at its own foot")
                XCTAssertEqual(stops.first?.alpha, 0,
                               "presence \(presence): EXACTLY zero on the clipped row — not "
                               + "small, not nearly")
                XCTAssertEqual(stops.last?.alpha, 0,
                               "presence \(presence): EXACTLY zero where the sky ends")
            }
        }
    }

    // Ordered, bounded, and never brighter than the constant that is supposed
    // to be the whole of the tuning.
    func testEveryProfileIsOrderedAndBounded() {
        for presence in stride(from: 0.0, through: 1.0, by: 0.05) {
            let state = HorizonRender.Horizon(presence: presence, depth: 211)
            let light = HorizonRender.lightStops(state)
            let ground = HorizonRender.groundStops(state)

            for stops in [light, ground] {
                for index in 1..<stops.count {
                    XCTAssertGreaterThan(stops[index].location, stops[index - 1].location,
                                         "gradient stops must ascend")
                }
                for stop in stops {
                    XCTAssertGreaterThanOrEqual(stop.alpha, 0)
                    XCTAssertLessThanOrEqual(stop.alpha, 1)
                }
            }

            XCTAssertEqual(light.map(\.alpha).max() ?? 0,
                           HorizonRender.lightPeak * presence, accuracy: 1e-12,
                           "the brightest row is `lightPeak` scaled by presence and nothing else")
            XCTAssertLessThanOrEqual(ground.map(\.alpha).max() ?? 0,
                                     HorizonRender.groundPeak,
                                     "the deepening may never exceed its own constant")
        }
    }

    // The glow's peak sits INSIDE the band, away from both edges — the shape
    // is a swell, not a ramp that has been cut off at one end.
    func testTheGlowPeaksInsideTheBandRatherThanAtAnEdge() {
        let state = HorizonRender.Horizon(presence: 1, depth: 211)
        let light = HorizonRender.lightStops(state)
        guard let peak = light.max(by: { $0.alpha < $1.alpha }) else {
            return XCTFail("the light must have a brightest stop")
        }
        XCTAssertGreaterThan(peak.location, 0.1, "the glow may not hug the clipped edge")
        XCTAssertLessThan(peak.location, 0.6, "the glow belongs to the join, not to the field")

        // And the deepening sits BELOW the light: the glow reads as lying on
        // something rather than floating in front of it.
        guard let deepest = HorizonRender.groundStops(state).max(by: { $0.alpha < $1.alpha }) else {
            return XCTFail("the deepening must have a darkest stop")
        }
        XCTAssertGreaterThan(deepest.location, peak.location,
                             "the darkness belongs under the light, never over it")
    }

    // MARK: - Continuity

    // THE DEFECT CLASS THIS PROJECT HAS ALREADY PAID FOR ONCE (see
    // `WorldCamera.Config.maxTransitPerCommit`, re-derived after a gate that
    // opened and shut as the camera crossed a place centre). Crossing a centre
    // must change nothing anybody can see.
    func testPresenceIsContinuousAcrossEveryPlaceCentre() {
        let travel: CGFloat = 0.75
        for place in Place.allCases {
            let centre = CGFloat(place.rawValue) * travel
            for epsilon in [CGFloat(1e-9), 1e-7, 1e-5, 1e-3] {
                let before = horizon(atOffset: centre - epsilon, travelPerPlace: travel).presence
                let at = horizon(atOffset: centre, travelPerPlace: travel).presence
                let after = horizon(atOffset: centre + epsilon, travelPerPlace: travel).presence
                XCTAssertEqual(before, at, accuracy: 1e-3,
                               "\(place) at ε \(epsilon): the light may not step as she arrives")
                XCTAssertEqual(after, at, accuracy: 1e-3,
                               "\(place) at ε \(epsilon): the light may not step as she leaves")
            }
        }
    }

    // Continuous is not enough at the FIELD centre, which is the one centre a
    // two-place transit passes straight THROUGH — and the frame it passes on
    // is the frame she is looking straight at the join. A kink there is a
    // visible change of direction, so both branches meet with the same slope
    // as well as the same value.
    func testPresenceHasNoKinkAtTheFieldCentre() {
        let step = 1e-4
        let below = (HorizonRender.presence(axis: 0) - HorizonRender.presence(axis: -step)) / step
        let above = (HorizonRender.presence(axis: step) - HorizonRender.presence(axis: 0)) / step
        XCTAssertEqual(below, 0, accuracy: 1e-3, "the sky side must arrive flat")
        XCTAssertEqual(above, 0, accuracy: 1e-3, "the journal side must leave flat")
        XCTAssertEqual(below, above, accuracy: 1e-3, "and the two must be the same curve")
    }

    // No step anywhere on the axis at all, at a resolution far finer than a
    // frame of the fastest settle the camera can produce.
    func testPresenceNeverStepsAcrossTheWholeAxis() {
        let travel: CGFloat = 0.75
        let samples = 20_001
        var previous = horizon(atOffset: -travel, travelPerPlace: travel).presence
        var worst = 0.0
        for index in 1..<samples {
            let offset = -travel + 2 * travel * CGFloat(index) / CGFloat(samples - 1)
            let value = horizon(atOffset: offset, travelPerPlace: travel).presence
            worst = max(worst, abs(value - previous))
            previous = value
        }
        XCTAssertLessThan(worst, 1e-3,
                          "the horizon must ramp, never flicker: worst neighbouring step \(worst)")
    }

    // A function of WHERE the camera is, never of how it got there — the same
    // experiment `WorldRenderTests` runs on the mote parallax, because a cue
    // that accumulated per frame could not pass it and neither could one that
    // read `dt`.
    func testTheHorizonIsAPureFunctionOfOffsetAndNotAnIntegration() {
        let travelled = makeCamera()
        travelled.consume(.commit(.up, velocity: -1688))
        for _ in 0..<20 { travelled.step(dt: frame) }
        XCTAssertFalse(travelled.isAtRest, "the camera should still be in flight here")

        let placed = makeCamera()
        placed.consume(.panBegan)
        placed.consume(.panChanged(translation: travelled.offset * screenHeight))
        XCTAssertEqual(placed.offset, travelled.offset, accuracy: 1e-12,
                       "the two routes must arrive at the same offset for this to prove anything")
        // To the accuracy the two offsets themselves agree to — a per-frame
        // accumulation could not come within a thousandth of this.
        XCTAssertEqual(horizon(placed).presence, horizon(travelled).presence, accuracy: 1e-9,
                       "the horizon must depend on WHERE the camera is, never on how it got there")
        XCTAssertEqual(horizon(placed).depth, horizon(travelled).depth,
                       "and the band is geometry, so it is the same band either way")

        let held = horizon(placed)
        for _ in 0..<60 { placed.step(dt: frame) }
        XCTAssertEqual(horizon(placed), held, "a still world must draw a still horizon")
    }

    // MARK: - Reduce Motion

    // BARRIER CONDITION 11. Under Reduce Motion the horizon does not move and
    // does not change: it holds the field's rest value at every offset the
    // camera could report, so the only thing that can happen to it is the
    // crossfade the places are doing anyway. Swept over offsets the RM camera
    // cannot even produce, because the guarantee must not rest on
    // `camera.offset` happening to be zero.
    func testReduceMotionIsIdenticallyStillAtEveryOffset() {
        let travel: CGFloat = 0.75
        let rest = horizon(atOffset: 0, travelPerPlace: travel, reduceMotion: true)
        for index in 0..<2001 {
            let offset = -2 * travel + 4 * travel * CGFloat(index) / 2000
            let state = horizon(atOffset: offset, travelPerPlace: travel, reduceMotion: true)
            XCTAssertEqual(state, rest,
                           "offset \(offset): Reduce Motion may not move the horizon at all")
        }
        XCTAssertEqual(rest.presence, HorizonRender.fieldPresence,
                       "and what it holds is the field's own rest value")
    }

    // The accessible path, driven by the real camera rather than by literals:
    // a full commit under Reduce Motion, where the camera's offset is
    // identically zero and the places crossfade through each other.
    func testTheHorizonNeverMovesAcrossAReduceMotionCommit() {
        let camera = makeCamera(reduceMotion: true)
        let before = horizon(camera)
        camera.consume(.commit(.up, velocity: -1688))
        var frames = 0
        while !camera.isAtRest && frames < 10_000 {
            camera.step(dt: frame)
            frames += 1
            XCTAssertEqual(horizon(camera), before,
                           "frame \(frames): nothing about the horizon may translate or brighten "
                           + "on the Reduce Motion path")
        }
        XCTAssertEqual(horizon(camera), before, "and it ends exactly where it started")
    }

    // MARK: - At rest

    // THE KNOWN STATE, IN EVERY PLACE. `step(dt:)` lands the camera exactly on
    // `restOffset`, so these are exact rather than approximate.
    func testEveryPlaceAtRestHasItsKnownHorizon() {
        for travel in [CGFloat(0.75), 0.5, 0.6667, 0.123456789] {
            XCTAssertEqual(horizon(atOffset: -travel, travelPerPlace: travel).presence,
                           HorizonRender.skyPresence, accuracy: 1e-12,
                           "travel \(travel): the sky carries the whole horizon")
            XCTAssertEqual(horizon(atOffset: 0, travelPerPlace: travel).presence,
                           HorizonRender.fieldPresence, accuracy: 1e-12,
                           "travel \(travel): the field carries half of it")
            XCTAssertEqual(horizon(atOffset: travel, travelPerPlace: travel).presence, 0,
                           "travel \(travel): at the journal the join is a screen off the glass, "
                           + "so it costs exactly nothing")
        }
    }

    // The horizon is quietest where the gameplay is: it may never be brighter
    // at the field than it is at the sky, because the field is the one place
    // where light that is not an orb is competition.
    func testTheHorizonIsQuietestWhereTheGameIs() {
        XCTAssertLessThan(HorizonRender.fieldPresence, HorizonRender.skyPresence,
                          "the join must give way to the field, never the other way round")
        XCTAssertGreaterThan(HorizonRender.fieldPresence, 0,
                             "but it may not vanish either — one continuous world")
    }

    // Nothing about where she has been survives her arriving: a full settle
    // out and a full settle back leave the horizon bit-identical.
    func testTheHorizonReturnsToItsRestStateAcrossAFullSettle() {
        let camera = makeCamera()
        let atField = horizon(camera)

        camera.consume(.commit(.up, velocity: -1688))
        var frames = 0
        while !camera.isAtRest && frames < 10_000 { camera.step(dt: frame); frames += 1 }
        XCTAssertTrue(camera.isAtRest)
        XCTAssertEqual(horizon(camera).presence, HorizonRender.skyPresence, accuracy: 1e-12,
                       "arriving at the sky must produce the sky's known horizon")

        camera.consume(.commit(.down, velocity: 1688))
        frames = 0
        while !camera.isAtRest && frames < 10_000 { camera.step(dt: frame); frames += 1 }
        XCTAssertTrue(camera.isAtRest)
        XCTAssertEqual(horizon(camera), atField,
                       "and coming home must leave the field exactly as it was found")
    }

    // MARK: - The band

    // THE DEPTH IS A FACT ABOUT THE AXIS, not a number someone liked: the
    // places overlap by `1 − travelPerPlace` screen heights, and the horizon
    // is drawn in exactly that overlap — the region where the sky and the
    // field genuinely coexist.
    func testTheBandIsTheOverlapBetweenTheTwoPlaces() {
        for travel in [CGFloat(0.75), 0.7, 0.65] {
            for height in [CGFloat(568), 844, 932, 1366] {
                let state = HorizonRender.state(offset: 0, travelPerPlace: travel,
                                                viewHeight: height, reduceMotion: false)
                XCTAssertEqual(state.depth, (1 - travel) * height, accuracy: 1e-9,
                               "travel \(travel), height \(height): the band IS the overlap")
                XCTAssertLessThan(state.depth, height,
                                  "and it is never the whole screen")
            }
        }
    }

    // A geometry with no overlap at all — places that butt rather than
    // overlap — still gets a band, because that join needs the glow more than
    // this one does, not less. And a degenerate one cannot flood the field.
    func testDegenerateGeometriesStillProduceASaneBand() {
        for travel in [CGFloat(1.0), 1.5, 0.01, 0.0001] {
            let state = HorizonRender.state(offset: 0, travelPerPlace: travel,
                                            viewHeight: screenHeight, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(state.depth,
                                        HorizonRender.depthFloor * screenHeight - 1e-9,
                                        "travel \(travel): a join always gets some depth")
            XCTAssertLessThanOrEqual(state.depth,
                                     HorizonRender.depthCeiling * screenHeight + 1e-9,
                                     "travel \(travel): and never more than the ceiling")
        }
    }

    // MARK: - Nonsense

    // A degenerate world draws no horizon rather than a NaN across the top of
    // the field — failing toward the picture that existed before this file,
    // exactly as `WorldRender`'s three cues fail toward theirs.
    func testNonsenseDrawsNoHorizonAtAll() {
        let cases: [(String, HorizonRender.Horizon)] = [
            ("travel 0", horizon(atOffset: 0.4, travelPerPlace: 0)),
            ("travel negative", horizon(atOffset: 0.4, travelPerPlace: -1)),
            ("travel NaN", horizon(atOffset: 0.4, travelPerPlace: .nan)),
            ("offset NaN", horizon(atOffset: .nan)),
            ("offset infinite", horizon(atOffset: .infinity)),
            ("height 0", HorizonRender.state(offset: 0, travelPerPlace: 0.75,
                                             viewHeight: 0, reduceMotion: false)),
            ("height NaN", HorizonRender.state(offset: 0, travelPerPlace: 0.75,
                                               viewHeight: .nan, reduceMotion: true))
        ]
        for (name, state) in cases {
            XCTAssertEqual(state, HorizonRender.Horizon.none,
                           "\(name): a degenerate world draws no horizon")
            XCTAssertEqual(HorizonRender.peakAlpha(state), 0, "\(name): and no light either")
        }
        XCTAssertEqual(HorizonRender.presence(axis: .nan), 0, "a NaN axis carries no light")
    }

    // Far off the axis the camera can reach, the light is still bounded — the
    // clamp is what makes the ceiling above hold for a world nobody has built
    // yet.
    func testOffAxisOffsetsAreClampedRatherThanExtrapolated() {
        XCTAssertEqual(horizon(atOffset: -50).presence,
                       horizon(atOffset: -0.75).presence, accuracy: 1e-12,
                       "beyond the sky is the sky")
        XCTAssertEqual(horizon(atOffset: 50).presence,
                       horizon(atOffset: 0.75).presence, accuracy: 1e-12,
                       "beyond the journal is the journal")
    }
}
