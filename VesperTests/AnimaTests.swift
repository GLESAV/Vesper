import XCTest
@testable import Vesper

// ANIMA — the engine's guarantees.
//
// Two kinds of test live here and they are worth telling apart.
//
// The first kind pins ENGINE INVARIANTS: an easing lands exactly on its
// endpoints, a curve is total, a voice cannot clip. These protect the engine
// from changes to itself.
//
// The second kind pins AUTHORING INVARIANTS: every figure has one root named
// `body`, no part has a parent that does not exist, no voice is loud, no
// unpitched fall is a laser. These protect the PRODUCT from the catalog —
// and they matter more, because the catalog is the part that will be edited
// by hand, often, possibly by someone who has never opened Xcode. Every one
// of them is a mistake that is cheap to make and expensive to notice.
final class AnimaTests: XCTestCase {

    // MARK: - Easing

    // Keys are absolute values, so an easing that missed its endpoints would
    // leave a visible step at every key — and a different step at every frame
    // rate, which is the kind of bug that gets described as "it looks janky
    // sometimes".
    func testEveryEasingLandsExactlyOnItsEndpoints() {
        for ease in Self.allEasings {
            XCTAssertEqual(ease.shape(0), 0, accuracy: 1e-9, "\(ease) does not start at 0")
            XCTAssertEqual(ease.shape(1), 1, accuracy: 1e-9, "\(ease) does not end at 1")
        }
    }

    // Total: any input at all, including the ones a caller should not have
    // produced, answers a finite number in range.
    func testEasingsAreTotalAndFinite() {
        for ease in Self.allEasings {
            for t in stride(from: -3.0, through: 3.0, by: 0.05) {
                let v = ease.shape(t)
                XCTAssertTrue(v.isFinite, "\(ease) produced a non-finite value at \(t)")
            }
            XCTAssertTrue(ease.shape(.nan).isFinite, "\(ease) passed a NaN through")
        }
    }

    // The three principle easings must actually leave the 0...1 range in the
    // middle — that excursion IS the wind-up and the overshoot. An
    // implementation that clamped them would compile, pass every other test
    // here, and silently turn the engine's whole character off.
    func testAnticipateOvershootAndSettleActuallyLeaveTheRange() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.01)
        XCTAssertTrue(samples.contains { AnimaEase.anticipate(1.7).shape($0) < -0.02 },
                      "anticipate never pulls back — it is just an easeIn")
        XCTAssertTrue(samples.contains { AnimaEase.overshoot(1.7).shape($0) > 1.02 },
                      "overshoot never passes its target")
        XCTAssertTrue(samples.contains { AnimaEase.settle(5).shape($0) > 1.02 },
                      "settle never rings")
    }

    // MARK: - Curves

    func testACurveHoldsItsEndsAndNeverExtrapolates() {
        let curve = AnimaCurve([AnimaKey(0, 10, .linear), AnimaKey(1, 20, .linear)])
        XCTAssertEqual(curve.value(at: -50), 10, accuracy: 1e-9)
        XCTAssertEqual(curve.value(at: 0.5), 15, accuracy: 1e-9)
        XCTAssertEqual(curve.value(at: 900), 20, accuracy: 1e-9)
    }

    func testKeysAreSortedSoAMistypedCatalogStillPlays() {
        let curve = AnimaCurve([AnimaKey(1, 20, .linear), AnimaKey(0, 10, .linear)])
        XCTAssertEqual(curve.value(at: 0.5), 15, accuracy: 1e-9,
                       "out-of-order keys were not sorted")
    }

    func testAnEmptyOrSingleKeyCurveIsConstantRatherThanACrash() {
        XCTAssertEqual(AnimaCurve([]).value(at: 7), 0)
        XCTAssertEqual(AnimaCurve([AnimaKey(3, 5)]).value(at: -1), 5)
        XCTAssertEqual(AnimaCurve([AnimaKey(3, 5)]).value(at: 99), 5)
    }

    // A looping curve is sampled at NEGATIVE times constantly — that is what
    // `AnimaPart.lag` produces for the first `lag` seconds of every clip that
    // uses follow-through. `truncatingRemainder` is signed, so the naive wrap
    // lands before the first key and holds there: every lagged part would
    // freeze at the start of every loop.
    func testALoopingCurveWrapsBackwardsAsWellAsForwards() {
        let curve = AnimaCurve([AnimaKey(0, 0, .linear), AnimaKey(1, 10, .linear)],
                               loops: true)
        XCTAssertEqual(curve.value(at: 0.25), 2.5, accuracy: 1e-9)
        XCTAssertEqual(curve.value(at: 1.25), 2.5, accuracy: 1e-9)
        XCTAssertEqual(curve.value(at: -0.75), 2.5, accuracy: 1e-9,
                       "a negative time did not wrap — every lagged part freezes here")
    }

    // MARK: - Shapes

    func testEveryPrimitiveProducesAUsableClosedOutline() {
        for primitive in Self.allPrimitives {
            let outline = primitive.outline()
            XCTAssertGreaterThan(outline.count, 2, "\(primitive) produced a degenerate outline")
            for point in outline {
                XCTAssertTrue(point.x.isFinite && point.y.isFinite,
                              "\(primitive) produced a non-finite point")
                XCTAssertLessThan(hypot(Double(point.x), Double(point.y)), 8,
                                  "\(primitive) reaches far outside unit space")
            }
        }
    }

    // A hand-typed catalog will contain zeroes and empty arrays. Every one of
    // them must draw something harmless rather than an empty path — which
    // renders as a hole — or a crash inside a fill routine.
    func testDegenerateParametersDrawSomethingHarmless() {
        let degenerate: [AnimaPrimitive] = [
            .capsule(length: 0),
            .petal(sharpness: 0),
            .polygon(sides: 0, roundness: 0),
            .polygon(sides: 2, roundness: -5),
            .arc(sweep: 0, thickness: 0),
            .blob(lobes: []),
            .blob(lobes: [AnimaLobe(0, 0, 0)]),
            .ribbon(spine: [], width: 0),
            .ribbon(spine: [.zero], width: -1)
        ]
        for primitive in degenerate {
            XCTAssertGreaterThan(primitive.outline().count, 2,
                                 "\(primitive) produced nothing to draw")
        }
    }

    // The sampling error a polyline pays instead of a real curve. Pinned so
    // that lowering `samples` to save export size has to be a decision rather
    // than a regression.
    func testTheDiscsSamplingErrorIsInvisibleAtTheLargestOrbSize() {
        let outline = AnimaPrimitive.disc.outline()
        var worst = 0.0
        for i in 0..<outline.count {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            let chord = hypot(Double(b.x - a.x), Double(b.y - a.y))
            // Sagitta of a unit-circle chord.
            worst = max(worst, 1 - (1 - chord * chord / 4).squareRoot())
        }
        let largestOrb = GameConfig.orbRadiusRange.upperBound
        XCTAssertLessThan(worst * Double(largestOrb), 0.05,
                          "the outline is visibly faceted at the largest orb size")
    }

    // MARK: - Figures and poses

    // THE CONVENTION THAT MAKES CLIPS PORTABLE. `wake` and `release` are
    // authored once and work on every figure only because every figure has
    // exactly one root, named `body`.
    func testEveryFigureHasExactlyOneRootAndItIsCalledBody() {
        for figure in AnimaLibrary.figures {
            let roots = figure.parts.filter { $0.parent == nil }
            XCTAssertEqual(roots.count, 1, "\(figure.name) has \(roots.count) roots")
            XCTAssertEqual(roots.first?.name, "body", "\(figure.name)'s root is not `body`")
        }
    }

    func testNoPartNamesAParentThatDoesNotExistAndNoNameIsUsedTwice() {
        for figure in AnimaLibrary.figures {
            var seen = Set<String>()
            for part in figure.parts {
                XCTAssertTrue(seen.insert(part.name).inserted,
                              "\(figure.name) has two parts called \(part.name) — only the first is reachable from a track")
                if let parent = part.parent {
                    XCTAssertNotNil(figure.part(named: parent),
                                    "\(figure.name).\(part.name) hangs off `\(parent)`, which does not exist")
                }
            }
        }
    }

    // A parent cycle is depth-limited at render time so it cannot hang the
    // frame loop, but an author should hear about it here rather than by
    // noticing something drawn wrong.
    func testNoFigureContainsAParentCycle() {
        for figure in AnimaLibrary.figures {
            for part in figure.parts {
                var seen: Set<String> = [part.name]
                var cursor = part.parent
                while let name = cursor {
                    guard seen.insert(name).inserted else {
                        XCTFail("\(figure.name) has a parent cycle through \(name)")
                        break
                    }
                    cursor = figure.part(named: name)?.parent
                }
                let reachedRoot = cursor == nil
                XCTAssertTrue(reachedRoot, "\(figure.name).\(part.name) never reaches a root")
            }
        }
    }

    // Every part of every figure is posed, at every time, for every clip it
    // is paired with — and nothing ever comes back as NaN. Transform maths
    // that produces a NaN does not crash; it silently stops drawing the part,
    // which is the hardest kind of bug to trace back here.
    func testEveryObjectPosesFinitelyThroughoutEveryClip() {
        for object in AnimaLibrary.objects {
            for clip in object.clips {
                for step in 0...40 {
                    let t = clip.duration * Double(step) / 40
                    let pose = clip.pose(of: object.figure, at: t)
                    XCTAssertEqual(pose.parts.count, object.figure.parts.count,
                                   "\(object.figure.name)/\(clip.name) dropped a part at \(t)")
                    for part in pose.parts {
                        XCTAssertTrue(part.opacity.isFinite && part.opacity >= 0 && part.opacity <= 1)
                        for point in part.outline {
                            XCTAssertTrue(point.x.isFinite && point.y.isFinite,
                                          "\(object.figure.name)/\(clip.name).\(part.name) went non-finite at \(t)")
                        }
                    }
                }
            }
        }
    }

    // Sampling is a pure function of time. This is what lets the browser
    // previewer be trusted: the pose it was handed is the pose the phone
    // computes.
    func testPosingIsDeterministic() {
        for object in AnimaLibrary.objects {
            for clip in object.clips {
                let a = clip.pose(of: object.figure, at: clip.duration * 0.37)
                let b = clip.pose(of: object.figure, at: clip.duration * 0.37)
                XCTAssertEqual(a, b, "\(object.figure.name)/\(clip.name) is not deterministic")
            }
        }
    }

    // Parts are drawn back to front, and ties keep the order they were
    // authored in — so inserting a part into a catalog entry cannot silently
    // reorder the ones around it.
    func testPosesComeOutSortedBackToFront() {
        for object in AnimaLibrary.objects {
            let pose = object.clips[0].pose(of: object.figure, at: 0)
            let depths = pose.parts.map(\.depth)
            XCTAssertEqual(depths, depths.sorted(), "\(object.figure.name) is not depth-sorted")
        }
    }

    // SQUASH AND STRETCH PRESERVES AREA. The reason `squash` is one field and
    // not two scale channels: with two, a channel that swings symmetrically
    // about zero does NOT return to its rest shape, and an object bouncing in
    // a loop slowly shrinks with nobody able to see why.
    func testSquashPreservesAreaAndIsExactlyInvertible() {
        for s in stride(from: -1.0, through: 1.0, by: 0.1) {
            let axes = AnimaTransform(squash: s).axes
            XCTAssertEqual(axes.x * axes.y, 1, accuracy: 1e-9,
                           "squash \(s) does not preserve area")
        }
        let squashed = AnimaTransform(squash: 0.5).axes
        let stretched = AnimaTransform(squash: -0.5).axes
        XCTAssertEqual(squashed.x * stretched.x, 1, accuracy: 1e-9,
                       "squash and stretch by the same amount are not inverses")
    }

    // Follow-through is the whole reason `lag` exists: a lagged part must
    // actually be somewhere different from an unlagged one during a move.
    func testLagActuallyDelaysAPart() {
        let figure = AnimaLibrary.jellyfish
        let clip = AnimaLibrary.driftPulse
        let pose = clip.pose(of: figure, at: 0.5)
        guard let lagged = pose.parts.first(where: { $0.name == "trail-c" }),
              let prompt = pose.parts.first(where: { $0.name == "trail-a" }) else {
            return XCTFail("the jellyfish lost its trails")
        }
        // Both hang off the same parent with different lags, so during the
        // push they cannot be at the same offset from it.
        let a = lagged.outline.first ?? .zero
        let b = prompt.outline.first ?? .zero
        XCTAssertNotEqual(Double(a.y), Double(b.y), accuracy: 1e-6,
                          "the trails move as one plate — lag is not being applied")
    }

    // MARK: - Reduce Motion (04 §11)

    /// The furthest any point of `part` travels from where it rests, over the
    /// whole clip. The honest measure of "how much did this move", and the one
    /// a vestibular system actually reacts to.
    private func peakTravel(_ clip: AnimaClip, _ figure: AnimaFigure, part name: String) -> Double {
        guard let rest = figure.part(named: name) else { return 0 }
        let restOutline = rest.primitive.outline().map { figure.worldRest(of: rest).apply(to: $0) }
        var worst = 0.0
        for step in 0...48 {
            let t = clip.duration * Double(step) / 48
            let pose = clip.pose(of: figure, at: t)
            guard let posed = pose.parts.first(where: { $0.name == name }) else { continue }
            for (i, point) in posed.outline.enumerated() where i < restOutline.count {
                worst = max(worst, hypot(Double(point.x - restOutline[i].x),
                                         Double(point.y - restOutline[i].y)))
            }
        }
        return worst
    }

    // §11's first clause: EVERY MOTION HAS A REDUCED VARIANT, and it really is
    // reduced. Measured as peak travel from rest, per part, over the whole
    // clip — not by inspecting the curve values, which would only prove the
    // arithmetic and not the result.
    func testEveryClipsReducedVariantMovesNoFurtherThanTheOriginal() {
        for object in AnimaLibrary.objects {
            for clip in object.clips {
                let reduced = clip.reduced
                for part in object.figure.parts {
                    let full = peakTravel(clip, object.figure, part: part.name)
                    let less = peakTravel(reduced, object.figure, part: part.name)
                    XCTAssertLessThanOrEqual(less, full + 1e-9, """
                        \(object.figure.name)/\(clip.name).\(part.name) moves FURTHER under \
                        Reduce Motion (\(less) vs \(full)) — the variant is not a reduction.
                        """)
                }
            }
        }
    }

    // A looping idle is an affordance that repeats forever, which is exactly
    // what Reduce Motion exists to stop. It reduces to stillness — structurally,
    // by carrying no tracks at all, so this holds exactly rather than to within
    // a tolerance.
    func testALoopingIdleReducesToCompleteStillness() {
        for object in AnimaLibrary.objects {
            for clip in object.clips where clip.loops {
                let reduced = clip.reduced
                XCTAssertTrue(reduced.tracks.isEmpty,
                              "\(clip.name) still carries tracks when reduced")
                let first = reduced.pose(of: object.figure, at: 0)
                for step in 1...12 {
                    let later = reduced.pose(of: object.figure,
                                             at: reduced.duration * Double(step) / 12)
                    XCTAssertEqual(first, later,
                                   "\(object.figure.name)/\(clip.name) still moves when reduced")
                }
            }
        }
    }

    // §11's second clause: NO REDUCED VARIANT MAY CARRY INFORMATION THE
    // ORIGINAL DID NOT — and, read the other way, none may LOSE information the
    // original carried. A part fading to nothing in `release` is the whole
    // message of that clip; damping the fade with the motion would leave
    // someone who asked for less motion unable to tell what happened.
    func testAOneShotsOpacityIsIdenticalWhenReduced() {
        for object in AnimaLibrary.objects {
            for clip in object.clips where !clip.loops {
                let reduced = clip.reduced
                for step in 0...24 {
                    let t = clip.duration * Double(step) / 24
                    let full = clip.pose(of: object.figure, at: t)
                    let less = reduced.pose(of: object.figure, at: t)
                    for (a, b) in zip(full.parts, less.parts) {
                        XCTAssertEqual(a.opacity, b.opacity, accuracy: 1e-9,
                                       "\(object.figure.name)/\(clip.name).\(a.name) lost opacity information when reduced")
                    }
                }
            }
        }
    }

    // The three direction-reversing easings are the vestibular ones, and a
    // reduced clip must not contain any of them. Distance is uncomfortable; a
    // reversal is much more so.
    func testNoReducedClipContainsADirectionReversingEasing() {
        for object in AnimaLibrary.objects {
            for clip in object.clips {
                for track in clip.reduced.tracks {
                    for key in track.curve.keys {
                        switch key.ease {
                        case .anticipate, .overshoot, .settle:
                            XCTFail("\(clip.name).\(track.part) keeps \(key.ease) when reduced")
                        default:
                            break
                        }
                    }
                }
            }
        }
    }

    // A one-shot must still SAY something, or the reduced variant has traded
    // an accessibility problem for a usability one: the state change happens
    // with no feedback at all.
    func testAReducedOneShotStillDoesSomething() {
        for object in AnimaLibrary.objects {
            for clip in object.clips where !clip.loops {
                let reduced = clip.reduced
                let start = reduced.pose(of: object.figure, at: 0)
                let end = reduced.pose(of: object.figure, at: reduced.duration)
                XCTAssertNotEqual(start, end,
                                  "\(object.figure.name)/\(clip.name) does nothing at all when reduced")
            }
        }
    }

    // MARK: - Voices

    // RULE 3: NOTHING IN THIS GAME IS EVER LOUD, and no sum of partials an
    // author happens to type can clip.
    func testNoVoiceEverClipsOrRunsAway() {
        for voice in AnimaLibrary.voices {
            for pitch in [180.0, 440.0, 1_200.0] {
                let samples = voice.render(pitch: pitch)
                XCTAssertFalse(samples.isEmpty, "\(voice.name) rendered nothing")
                var peak: Float = 0
                for sample in samples {
                    XCTAssertTrue(sample.isFinite, "\(voice.name) produced a non-finite sample")
                    peak = max(peak, abs(sample))
                }
                XCTAssertLessThanOrEqual(peak, 1.0, "\(voice.name) clipped at \(pitch) Hz")
                XCTAssertGreaterThan(peak, 0.001, "\(voice.name) is silent at \(pitch) Hz")

                // THE CLAMP IS A GUARDRAIL, NOT A MIXER. `peak <= 1` above is
                // guaranteed by the clamp in `render` and therefore proves
                // nothing on its own; a voice whose partials sum to five
                // would pass it while sounding like a square wave. What
                // actually has to be true is that the voice does not SIT on
                // the clamp — so at most a hair of it may be at full scale.
                let pinned = samples.filter { abs($0) >= 0.999 }.count
                XCTAssertLessThan(Double(pinned) / Double(samples.count), 0.01,
                                  "\(voice.name) spends its life on the clamp at \(pitch) Hz — its gains are too hot")
            }
        }
    }

    // AN INSTRUMENT'S LOUDNESS MUST NOT BE A FUNCTION OF THE NOTE IT PLAYS.
    //
    // This is the invariant `breath` broke, and the assertion that would have
    // caught it a week earlier than the clamp did. Its band resonator's peak
    // gain rises steeply as the centre nears DC — 590x at a 396 Hz centre
    // against 91x at 2640 Hz — so with a fixed output scale the voice was ten
    // times louder at the bottom of its range than the top, sitting on the
    // clamp at 180 Hz. The clipping was the symptom; the real defect is a
    // synthesiser where pitch and volume are the same knob, which no amount
    // of catalogue tuning can compensate for.
    func testNoVoicesLoudnessDependsOnItsPitch() {
        for voice in AnimaLibrary.voices {
            var peaks: [Float] = []
            for pitch in [140.0, 180.0, 260.0, 440.0, 700.0, 1_200.0] {
                let samples = voice.render(pitch: pitch)
                peaks.append(samples.map { abs($0) }.max() ?? 0)
            }
            guard let quietest = peaks.min(), let loudest = peaks.max(),
                  quietest > 0 else {
                // `continue`, not `return`: a silent voice must not exempt
                // every voice after it from the loudness check.
                XCTFail("\(voice.name) was silent at some pitch")
                continue
            }
            // A factor of three across the whole musical range. Some variation
            // is honest — a fixed decay really does mean less energy at high
            // pitch — but an order of magnitude is a bug.
            XCTAssertLessThan(Double(loudest / quietest), 3.0, """
                \(voice.name) is \(String(format: "%.1f", loudest / quietest))x louder at one \
                pitch than another (peaks \(peaks.map { String(format: "%.3f", $0) })). \
                Loudness must not track pitch.
                """)
        }
    }

    // RULE 2: A RAISED-COSINE ATTACK. Any envelope that starts at full
    // amplitude clicks, and a click in a calm game is the loudest thing in
    // it. The first millisecond must be very much quieter than the body.
    func testNoVoiceClicksOnAndNoneClicksOff() {
        for voice in AnimaLibrary.voices {
            let samples = voice.render(pitch: 440)
            guard samples.count > 200 else { continue }
            let peak = samples.map { abs($0) }.max() ?? 1

            XCTAssertLessThan(abs(samples[0]), peak * 0.05,
                              "\(voice.name) starts at full amplitude — that is a click")
            XCTAssertLessThan(abs(samples[samples.count - 1]), peak * 0.05,
                              "\(voice.name) ends on a step — that is a click")
        }
    }

    // RULE 1: NO STEEP DOWNWARD PITCH SWEEP. This is the Space Invaders
    // finding, made unrepresentable: a voice that has not explicitly opted in
    // has its glide floored however the catalog was written.
    func testOnlyAVoiceThatOptsInMayFall() {
        // A deliberately mistyped catalog entry — a laser, written by hand.
        let mistyped = AnimaVoice("mistyped", duration: 0.14,
                                  partials: [AnimaPartial(1, gain: 0.5, decay: 8)],
                                  glide: 0.55)
        XCTAssertFalse(mistyped.allowsFall)
        // It renders, and it renders as a pop rather than as a phaser: with
        // the floor applied the fall is at most 6%.
        XCTAssertFalse(mistyped.render(pitch: 440).isEmpty)

        for voice in AnimaLibrary.voices where !voice.allowsFall {
            XCTAssertGreaterThanOrEqual(voice.glide, AnimaVoice.glideFloor - 1e-9,
                                        "\(voice.name) is authored as a laser and has not opted in")
        }
        XCTAssertTrue(AnimaLibrary.drop.allowsFall,
                      "the one voice whose identity is a falling pitch must opt in")
    }

    // Nothing rings for longer than a breath. Past about a second a pop stops
    // being punctuation and becomes a drone she has to wait out.
    func testNoVoiceRingsForLongerThanABreath() {
        for voice in AnimaLibrary.voices {
            XCTAssertLessThanOrEqual(voice.duration, AnimaVoice.maximumDuration,
                                     "\(voice.name) rings too long for a calm game")
            let samples = voice.render(pitch: 440)
            XCTAssertLessThanOrEqual(Double(samples.count) / 44_100,
                                     AnimaVoice.maximumDuration + 0.001)
        }
    }

    // Same voice, same pitch, same samples — every launch, forever. A
    // hash-seeded texture would make a pop a subtly different sound each run,
    // and buffers are cached, so it would be different-but-consistent within
    // a session and different again the next: the least reproducible bug
    // report imaginable.
    func testVoiceRenderingIsDeterministic() {
        for voice in AnimaLibrary.voices {
            XCTAssertEqual(voice.render(pitch: 523.25), voice.render(pitch: 523.25),
                           "\(voice.name) is not deterministic")
        }
    }

    // A NaN in authored data renders as silence, never as a trap. Swift's
    // `min`/`max` pass NaN through (every comparison against it is false), so
    // an unguarded NaN duration reached `Int(sampleRate * seconds)` and
    // crashed, and a NaN glide poisoned every sample and crashed the
    // exporter's `Int16` conversion instead. The geometry side has been total
    // under NaN since iteration 5; the audio side is now held to the same
    // rule.
    func testAVoiceAuthoredWithNaNRendersAsSilenceNotACrash() {
        let bad = [
            AnimaVoice("nan-duration", duration: .nan,
                       partials: [AnimaPartial(1, gain: 0.5, decay: 6)]),
            AnimaVoice("nan-glide", duration: 0.3,
                       partials: [AnimaPartial(1, gain: 0.5, decay: 6)],
                       glide: .nan),
            AnimaVoice("nan-attack", duration: 0.3,
                       partials: [AnimaPartial(1, gain: 0.5, decay: 6)],
                       attack: .nan),
            AnimaVoice("nan-partial", duration: 0.3,
                       partials: [AnimaPartial(.nan, gain: .nan, decay: .nan)]),
        ]
        for voice in bad {
            let samples = voice.render(pitch: 523.25)
            XCTAssertTrue(samples.allSatisfy(\.isFinite),
                          "\(voice.name) rendered a non-finite sample")
        }
        _ = AnimaStudio.base64Int16([.nan, 1, -1, .infinity])
    }

    // THE VOICE TABLE IS KEYED BY NAME (revision 3), first-wins: two distinct
    // voices sharing a name would make every later object silently play the
    // first one's audio in the previewer — and the structural-distinctness
    // test below skips same-named pairs, so nothing else can see it.
    func testNoTwoVoicesShareAName() {
        let names = AnimaLibrary.voices.map(\.name)
        XCTAssertEqual(Set(names).count, names.count,
                       "duplicate voice names: \(names.sorted())")
    }

    // The library has to be a VOCABULARY, not a hundred notes on one string —
    // which was the exact finding that drove the pop catalog's rework. Two
    // voices differing only in pitch is the failure being tested for.
    func testEveryVoiceIsStructurallyDistinctFromEveryOther() {
        for a in AnimaLibrary.voices {
            for b in AnimaLibrary.voices where a.name != b.name {
                let same = a.partials == b.partials
                    && a.noise == b.noise
                    && abs(a.duration - b.duration) < 1e-9
                XCTAssertFalse(same, "\(a.name) and \(b.name) are the same instrument")
            }
        }
    }

    // MARK: - The library holds together

    func testEveryObjectIsPlayableAndPaintedWithinItsOwnPalette() {
        XCTAssertFalse(AnimaLibrary.objects.isEmpty)
        for object in AnimaLibrary.objects {
            XCTAssertFalse(object.figure.parts.isEmpty, "\(object.figure.name) has no parts")
            XCTAssertFalse(object.figure.paints.isEmpty, "\(object.figure.name) has no paints")
            XCTAssertFalse(object.clips.isEmpty, "\(object.figure.name) has no performances")
            for part in object.figure.parts {
                XCTAssertTrue(object.figure.paints.indices.contains(part.paint),
                              "\(object.figure.name).\(part.name) paints with index \(part.paint), which does not exist")
            }
        }
    }

    // Every track must bind to a part that exists. A track naming a part that
    // was renamed does nothing at all — the object simply stops performing,
    // silently, and there is no other signal.
    func testEveryTrackBindsToAPartThatExists() {
        for object in AnimaLibrary.objects {
            for clip in object.clips {
                for track in clip.tracks {
                    XCTAssertNotNil(object.figure.part(named: track.part),
                                    "\(object.figure.name)/\(clip.name) animates `\(track.part)`, which is not a part of it")
                }
            }
        }
    }

    // The palette stays inside the product's own band. Guardrail 4: nothing
    // saturated, nothing pure white.
    func testTheLibraryPaletteStaysMuted() {
        for figure in AnimaLibrary.figures {
            for paint in figure.paints {
                for colour in [paint.fill, paint.glow] {
                    let channels = [colour.r, colour.g, colour.b]
                    XCTAssertTrue(channels.allSatisfy { $0 >= 0 && $0 <= 1 })
                    let saturation = (channels.max() ?? 0) - (channels.min() ?? 0)
                    XCTAssertLessThan(saturation, 0.30,
                                      "\(figure.name) has a saturated colour")
                    XCTAssertLessThan(channels.min() ?? 0, 0.99,
                                      "\(figure.name) has a pure white")
                }
            }
        }
    }

    // MARK: - Fixtures

    private static let allEasings: [AnimaEase] = [
        .linear, .easeIn, .easeOut, .easeInOut,
        .anticipate(1.7), .anticipate(0), .anticipate(3),
        .overshoot(1.7), .overshoot(0), .overshoot(3),
        .settle(2), .settle(5.5), .settle(12),
        .hold
    ]

    private static let allPrimitives: [AnimaPrimitive] = [
        .disc,
        .capsule(length: 0.55),
        .capsule(length: 3.0),
        .petal(sharpness: 0.42),
        .petal(sharpness: 1.0),
        .polygon(sides: 3, roundness: 0),
        .polygon(sides: 6, roundness: 0.55),
        .polygon(sides: 12, roundness: 1),
        .arc(sweep: 2.6, thickness: 0.16),
        .arc(sweep: .pi * 2, thickness: 1),
        .blob(lobes: [AnimaLobe(0, 0, 1), AnimaLobe(0.5, -0.5, 0.4)]),
        .ribbon(spine: [.zero, CGPoint(x: 0, y: 1)], width: 0.1)
    ]
}

// MARK: - The pop paradigm (E3)

/// The bridge between the catalogue and the engine.
///
/// These are authoring invariants in the strongest sense: the hundred assets
/// are generated from `PopCatalog`, so a defect here is a defect in all
/// hundred at once, and none of it is visible by looking at any one of them.
final class AnimaPopTests: XCTestCase {

    // Every pop in the catalogue produces a drawable object, whether or not
    // anyone has authored a variation for it. That is what lets the hub page
    // show all hundred from the first day and each batch replace derivation
    // with intent.
    func testEveryCatalogPopProducesADrawableObject() {
        let objects = AnimaPop.all
        XCTAssertEqual(objects.count, PopCatalog.all.count)
        XCTAssertEqual(objects.count, 100, "the catalogue is not a hundred pops")

        for (object, definition) in zip(objects, PopCatalog.all.sorted { $0.number < $1.number }) {
            XCTAssertFalse(object.figure.parts.isEmpty,
                           "#\(definition.number) \(definition.name) has no parts")
            for part in object.figure.parts {
                XCTAssertTrue(object.figure.paints.indices.contains(part.paint),
                              "#\(definition.number).\(part.name) paints outside its own palette")
                XCTAssertGreaterThan(part.primitive.outline().count, 2,
                                     "#\(definition.number).\(part.name) draws nothing")
            }
        }
    }

    // AN ASSET MUST BE THE POP'S OWN, not a picture of a different game. The
    // paints come from the bound PopDefinition and are never invented here.
    func testEveryObjectWearsItsOwnPopsPaints() {
        for definition in PopCatalog.all {
            let object = AnimaPop.object(for: definition)
            XCTAssertEqual(object.figure.paints, definition.style.paints,
                           "#\(definition.number) \(definition.name) is not wearing its own paint")
        }
    }

    // The convention that makes the shared performances portable, held across
    // all hundred rather than across the six hand-written reference figures.
    func testAllHundredKeepTheOneRootNamedBodyConvention() {
        for definition in PopCatalog.all {
            let figure = AnimaPop.object(for: definition).figure
            let roots = figure.parts.filter { $0.parent == nil }
            XCTAssertEqual(roots.count, 1, "#\(definition.number) has \(roots.count) roots")
            XCTAssertEqual(roots.first?.name, "body", "#\(definition.number)'s root is not `body`")
            var names = Set<String>()
            for part in figure.parts {
                XCTAssertTrue(names.insert(part.name).inserted,
                              "#\(definition.number) has two parts called \(part.name)")
                if let parent = part.parent {
                    XCTAssertNotNil(figure.part(named: parent),
                                    "#\(definition.number).\(part.name) hangs off a part that does not exist")
                }
            }
        }
    }

    // THE FAMILY IS THE INSTRUMENT AND THE SILHOUETTE. A pop's voice must be
    // the one its own definition asks for, and the mapping must be total —
    // `AnimaLibrary.voice(for:)` has no `default:` so a new SoundVoice case
    // stops the build rather than silently inheriting a fallback.
    func testEveryPopIsPlayedOnTheInstrumentItsDefinitionAsksFor() {
        for definition in PopCatalog.all {
            let object = AnimaPop.object(for: definition)
            XCTAssertEqual(object.voice.name,
                           AnimaLibrary.voice(for: definition.behavior.sound.voice).name,
                           "#\(definition.number) is played on the wrong instrument")
        }
        for sound in SoundVoice.allCases {
            XCTAssertFalse(AnimaLibrary.voice(for: sound).render(pitch: 440).isEmpty,
                           "\(sound) maps to an instrument that renders nothing")
        }
    }

    // TEN FAMILIES MUST BE SEPARABLE AS BLACK SHAPES. Shape reads before
    // colour, at arm's length, in the dark — so if two families cannot be
    // told apart by their silhouette alone, the second one is wrong.
    //
    // Measured rather than asserted: a family's structural fingerprint is its
    // part count and the kinds of primitive it is built from. Two families
    // sharing one exactly are drawing the same object in different paint.
    func testTheTenFamiliesAreSeparableBySilhouetteAlone() {
        func fingerprint(_ family: PopFamily) -> String {
            let figure = family.figure("probe",
                                       variation: AnimaVariation(),
                                       paints: [AnimaLibrary.offWhite, AnimaLibrary.lilac])
            let kinds = figure.parts.map { part -> String in
                switch part.primitive {
                case .disc:      return "disc"
                case .capsule:   return "capsule"
                case .petal:     return "petal"
                case .polygon:   return "polygon"
                case .arc:       return "arc"
                case .blob:      return "blob"
                case .ribbon:    return "ribbon"
                }
            }
            return "\(figure.parts.count):\(kinds.joined(separator: ","))"
        }
        var seen: [String: PopFamily] = [:]
        for family in PopFamily.allCases {
            let print = fingerprint(family)
            if let clash = seen[print] {
                XCTFail("\(family) and \(clash) have the same silhouette structure (\(print))")
            }
            seen[print] = family
        }
    }

    // Variation must actually vary. Ten pops built from one family's builder
    // and ten different variations must not all come out identical — which is
    // exactly what happens if a builder ignores the knobs it was handed.
    func testAVariationChangesTheFigureItBuilds() {
        for family in PopFamily.allCases {
            let paints = [AnimaLibrary.offWhite, AnimaLibrary.lilac]
            let a = family.figure("a", variation: AnimaVariation(trait: 0.05, accent: 0.05,
                                                                 count: 3, tilt: -0.3),
                                  paints: paints)
            let b = family.figure("a", variation: AnimaVariation(trait: 0.95, accent: 0.95,
                                                                 count: 8, tilt: 0.3),
                                  paints: paints)
            XCTAssertNotEqual(a, b, "\(family) ignores its variation — all ten would be identical")
        }
    }

    // The default variation is DERIVED, never random: the same pop is the same
    // shape on every device and in every run, the guarantee PopCatalog and
    // SeededRandom already make.
    func testTheDerivedVariationIsDeterministicAndSpread() {
        for number in 1...100 {
            XCTAssertEqual(AnimaVariation.derived(from: number),
                           AnimaVariation.derived(from: number))
        }
        // And consecutive numbers must not sit on top of each other, or a
        // family's ten members would be ten copies before anyone authors them.
        for number in 1...99 {
            XCTAssertNotEqual(AnimaVariation.derived(from: number),
                              AnimaVariation.derived(from: number + 1),
                              "#\(number) and #\(number + 1) derive the same variation")
        }
    }

    // Reduce Motion still applies to a generated asset, all hundred of them.
    func testEveryGeneratedAssetPosesFinitelyAndReduces() {
        for definition in PopCatalog.all {
            let object = AnimaPop.object(for: definition)
            for clip in object.clips {
                for step in 0...8 {
                    let t = clip.duration * Double(step) / 8
                    for pose in [clip.pose(of: object.figure, at: t),
                                 clip.reduced.pose(of: object.figure, at: t)] {
                        for part in pose.parts {
                            for point in part.outline {
                                XCTAssertTrue(point.x.isFinite && point.y.isFinite,
                                              "#\(definition.number)/\(clip.name).\(part.name) went non-finite")
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Authored variations (phase A)

/// The ten notes inside each instrument.
///
/// Phase A replaces derived variations with authored ones, a family at a
/// time. These tests hold what authoring is FOR: that the ten are actually
/// ten, and that authoring never disturbs the one pop that must not move.
final class AnimaVariationTests: XCTestCase {

    private func authored(in family: PopFamily) -> [(Int, AnimaVariation)] {
        PopCatalog.all
            .filter { $0.family == family && AnimaPop.variations[$0.number] != nil }
            .sorted { $0.number < $1.number }
            .map { ($0.number, AnimaPop.variations[$0.number]!) }
    }

    // GUARDRAIL 5, AS A TEST. Pop #001 is the reference implementation of the
    // game's look — the v1.0 pop, codified. Every other asset may be as
    // adventurous as its flavour asks, but this one stays an orb: a companion
    // tucked in so close that the silhouette does not reach past a plain disc.
    func testPopOneStillReadsAsAPlainOrb() {
        let figure = AnimaPop.object(for: PopCatalog.definition(for: 1)).figure
        XCTAssertLessThanOrEqual(figure.restReach, 1.10,
                                 "pop #001 has grown past a plain orb — guardrail 5")
    }

    // Ten pops in a family must be ten SHAPES, not one shape at ten sizes. A
    // pair sitting on top of each other in the variation plane is one pop
    // drawn twice, and nobody reviewing a hundred tiles would spot it.
    func testAuthoredVariationsAreSeparatedWithinTheirFamily() {
        for family in PopFamily.allCases {
            let entries = authored(in: family)
            guard entries.count > 1 else { continue }
            for i in entries.indices {
                for j in entries.indices where j > i {
                    let a = entries[i].1, b = entries[j].1
                    let distance = ((a.trait - b.trait) * (a.trait - b.trait)
                                    + (a.accent - b.accent) * (a.accent - b.accent)).squareRoot()
                    XCTAssertGreaterThan(distance, 0.08, """
                        #\(entries[i].0) and #\(entries[j].0) sit on top of each other in \
                        \(family)'s variation plane — that is one pop drawn twice.
                        """)
                }
            }
        }
    }

    // An authored family must actually look authored: its ten silhouettes
    // must span a real range, or the batch changed nothing an eye could see.
    func testAnAuthoredFamilySpansARangeOfSilhouettes() {
        for family in PopFamily.allCases {
            let entries = authored(in: family)
            guard entries.count >= 5 else { continue }
            let reaches = entries.map { number, _ -> Double in
                AnimaPop.object(for: PopCatalog.definition(for: number)).figure.restReach
            }
            let spread = (reaches.max() ?? 0) - (reaches.min() ?? 0)
            XCTAssertGreaterThan(spread, 0.15, """
                \(family)'s authored silhouettes span only \(spread) — the ten are \
                one shape at ten sizes.
                """)
        }
    }

    // Authoring may never break the conventions the engine depends on.
    func testAuthoredVariationsKeepEveryEngineConvention() {
        for (number, _) in AnimaPop.variations {
            let object = AnimaPop.object(for: PopCatalog.definition(for: number))
            let roots = object.figure.parts.filter { $0.parent == nil }
            XCTAssertEqual(roots.count, 1, "#\(number) has \(roots.count) roots")
            XCTAssertEqual(roots.first?.name, "body", "#\(number)'s root is not `body`")
            for part in object.figure.parts {
                XCTAssertTrue(object.figure.paints.indices.contains(part.paint),
                              "#\(number).\(part.name) paints outside its own palette")
            }
            XCTAssertTrue(object.figure.restReach.isFinite && object.figure.restReach > 0,
                          "#\(number) has a degenerate reach")
        }
    }

    // Every authored number is a real catalogue pop. A typo'd key is silent:
    // it authors a pop that does not exist while the one that does keeps its
    // derived shape.
    func testEveryAuthoredNumberIsARealPop() {
        let known = Set(PopCatalog.all.map(\.number))
        for number in AnimaPop.variations.keys {
            XCTAssertTrue(known.contains(number),
                          "#\(number) is authored but is not in the catalogue")
        }
    }
}
