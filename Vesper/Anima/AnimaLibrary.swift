import CoreGraphics
import Foundation

// ANIMA — the library. Six objects, six performances and eight instruments,
// authored entirely as data.
//
// ─────────────────────────────────────────────────────────────────────────
// WHAT THIS FILE IS FOR, BEYOND THE OBJECTS IN IT.
//
// It is the proof that the schema carries real content, and it is the
// reference an author copies. Every entry below was written without touching
// a line of engine code, a renderer, or a synthesis loop — which is the
// claim the whole engine makes, and a claim that is worth nothing until
// somebody has actually tried it.
//
// It is also deliberately SMALL. A hundred entries here would be a content
// drop; six is a vocabulary. The six were chosen to exercise every primitive
// (`disc`, `capsule`, `petal`, `polygon`, `arc`, `blob`, `ribbon`), both
// hierarchy directions, `lag`, and both looping and one-shot clips, so that
// a gap in the engine would show up as an object that could not be written.
//
// NOTHING HERE IS WIRED INTO GAMEPLAY YET, and that is on purpose. Guardrail
// 5 says the tuning is sacred and changes go in one at a time; this change
// adds an engine and an authoring loop, and adoption is its own change with
// its own before/after. `docs/anima.md` §6 sets out that path.

enum AnimaLibrary {

    // MARK: - Authoring helpers

    /// sRGB 0–255, the same units the pop catalog authors in, so a colour can
    /// be moved between the two files by copying it.
    private static func c(_ r: Double, _ g: Double, _ b: Double) -> PopColor {
        PopColor(r: r / 255, g: g / 255, b: b / 255)
    }

    /// A paint whose glow is its fill, slightly deepened — the same
    /// derivation `PopCatalog.pv` uses, repeated rather than shared because
    /// that one is private to its own catalog and neither file should be able
    /// to change the other's palette by accident.
    private static func pv(_ r: Double, _ g: Double, _ b: Double) -> PopPaint {
        PopPaint(fill: c(r, g, b), glow: c(r * 0.93, g * 0.89, b * 0.95))
    }

    private static func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private static func at(_ x: Double, _ y: Double,
                           rotation: Double = 0,
                           scale: Double = 1) -> AnimaTransform {
        AnimaTransform(offset: p(x, y), rotation: rotation, scale: scale)
    }

    // MARK: - The palette
    //
    // Muted, dusk-side, and drawn from the same band the pop catalog lives
    // in. Nothing saturated, nothing pure white — guardrail 4.

    static let offWhite = pv(233, 230, 242)
    static let lilac    = pv(217, 201, 230)
    static let sage     = pv(198, 220, 216)
    static let rose     = pv(230, 205, 212)
    static let sand     = pv(231, 213, 192)
    static let dusk     = pv(176, 168, 206)
    static let seafoam  = pv(186, 214, 208)

    // MARK: - Figures
    //
    // ONE CONVENTION, HELD BY EVERY FIGURE HERE AND BY A TEST: each figure
    // has exactly one root part, and it is named `body`. Everything else
    // descends from it.
    //
    // It is worth the constraint because it is what makes a clip PORTABLE. A
    // performance that says "scale the body from nothing, overshooting" is
    // then meaningful for every object in the library, so `wake` and
    // `release` are authored once and work on all six — and on the seventh,
    // which nobody has written yet. Without the convention every object needs
    // its own copy of every generic performance, which is precisely the
    // per-object cost this engine exists to remove.
    //
    // It also makes hierarchy scaling correct by construction: a part that
    // did not descend from the root would keep its full size while the root
    // grew, which is the bug this convention caught in the lantern.

    /// A JELLYFISH. Bell over trailing ribbons.
    ///
    /// The reference case for `lag`: each tentacle hangs off the bell and
    /// lags it a little more than the one before, so a single squash channel
    /// on the bell produces a whole cascade of follow-through down the
    /// tentacles that nobody authored. Three tracks would have been needed
    /// to fake it, and they would have gone out of sync the first time
    /// anyone retimed the swim.
    static let jellyfish = AnimaFigure(
        "jellyfish",
        parts: [
            AnimaPart("body", .petal(sharpness: 0.42),
                      rest: AnimaTransform(offset: p(0, -0.15), rotation: .pi / 2, scale: 0.85),
                      paint: 0, depth: 10),
            AnimaPart("trail-a", .ribbon(spine: [p(0, 0), p(0.06, 0.4), p(-0.04, 0.8), p(0.02, 1.1)],
                                         width: 0.13),
                      parent: "body", rest: at(0, 0.1), paint: 1, depth: 5, lag: 0.05),
            AnimaPart("trail-b", .ribbon(spine: [p(0, 0), p(-0.08, 0.42), p(0.05, 0.82), p(-0.03, 1.2)],
                                         width: 0.11),
                      parent: "body", rest: at(-0.22, 0.08), paint: 1, depth: 4, lag: 0.09),
            AnimaPart("trail-c", .ribbon(spine: [p(0, 0), p(0.09, 0.38), p(-0.02, 0.76), p(0.06, 1.05)],
                                         width: 0.11),
                      parent: "body", rest: at(0.22, 0.08), paint: 1, depth: 4, lag: 0.13)
        ],
        paints: [lilac, dusk]
    )

    /// A MOTH. Body under two wings, each lagging the body.
    ///
    /// The reference case for hierarchy plus loop: the wings are children, so
    /// turning the body turns them, and the flutter is one looping rotation
    /// curve authored once and mirrored by the wings' rest rotations.
    static let moth = AnimaFigure(
        "moth",
        parts: [
            AnimaPart("wing-far", .petal(sharpness: 0.55),
                      parent: "body",
                      rest: AnimaTransform(offset: p(-0.1, -0.1), rotation: -2.5, scale: 0.95),
                      paint: 1, depth: 3, lag: 0.02),
            AnimaPart("body", .capsule(length: 0.55),
                      rest: AnimaTransform(offset: .zero, rotation: .pi / 2, scale: 0.34),
                      paint: 0, depth: 6),
            AnimaPart("wing-near", .petal(sharpness: 0.55),
                      parent: "body",
                      rest: AnimaTransform(offset: p(0.1, -0.1), rotation: -0.64, scale: 0.95),
                      paint: 2, depth: 9, lag: 0.02)
        ],
        paints: [sand, offWhite, rose]
    )

    /// A SEED HEAD. A core with filaments radiating off it.
    ///
    /// Authored in a loop rather than by hand — a figure is ordinary Swift
    /// data, so anything that would be tedious to type can be generated, and
    /// the result is still just parts.
    static let seedHead: AnimaFigure = {
        var parts: [AnimaPart] = [
            AnimaPart("body", .disc, rest: at(0, 0, scale: 0.2), paint: 0, depth: 10)
        ]
        let count = 11
        for i in 0..<count {
            let angle = 2 * Double.pi * Double(i) / Double(count)
            parts.append(
                AnimaPart("filament-\(i)", .capsule(length: 2.6),
                          parent: "body",
                          rest: AnimaTransform(offset: p(cos(angle) * 1.2, sin(angle) * 1.2),
                                               rotation: angle, scale: 0.16),
                          paint: 1, depth: 4,
                          // A staggered lag around the head, so a gust
                          // travels through it instead of moving all eleven
                          // filaments as one plate.
                          lag: 0.015 * Double(i % 5))
            )
        }
        return AnimaFigure("seed-head", parts: parts, paints: [sand, offWhite])
    }()

    /// A LANTERN. A rounded polygon body, an arc handle, an inner light.
    ///
    /// The reference case for `polygon` and `arc`, and for depth ordering:
    /// the light is drawn under the body so it reads as coming through it.
    static let lantern = AnimaFigure(
        "lantern",
        parts: [
            AnimaPart("light", .disc, parent: "body",
                      rest: at(0, 0.05, scale: 0.7), paint: 2, depth: 2),
            AnimaPart("body", .polygon(sides: 6, roundness: 0.55),
                      rest: at(0, 0, scale: 0.82), paint: 0, depth: 6),
            AnimaPart("handle", .arc(sweep: 2.6, thickness: 0.16),
                      parent: "body",
                      rest: AnimaTransform(offset: p(0, -0.95), rotation: -.pi / 2, scale: 0.5),
                      paint: 1, depth: 8, lag: 0.04)
        ],
        paints: [seafoam, sage, offWhite]
    )

    /// A BLOOM. Five petals about a centre.
    static let bloom: AnimaFigure = {
        var parts: [AnimaPart] = [
            AnimaPart("body", .disc, rest: at(0, 0, scale: 0.3), paint: 0, depth: 10)
        ]
        for i in 0..<5 {
            let angle = 2 * Double.pi * Double(i) / 5 - Double.pi / 2
            parts.append(
                AnimaPart("petal-\(i)", .petal(sharpness: 0.6),
                          parent: "body",
                          rest: AnimaTransform(offset: p(cos(angle) * 1.9, sin(angle) * 1.9),
                                               rotation: angle, scale: 1.9),
                          paint: 1, depth: 3, lag: 0.02 * Double(i))
            )
        }
        return AnimaFigure("bloom", parts: parts, paints: [sand, rose])
    }()

    /// A HARE, as a blob.
    ///
    /// Deliberately the same vocabulary `AnimalPop` already uses, to prove
    /// the engine can express what the game currently draws by hand. If this
    /// silhouette is right, the balloon animals can move onto this engine
    /// without their shapes changing — which is the precondition for adopting
    /// it anywhere near gameplay.
    static let hare = AnimaFigure(
        "hare",
        parts: [
            AnimaPart("body", .blob(lobes: [
                AnimaLobe(0, 0.1, 0.66),        // body
                AnimaLobe(0.42, -0.34, 0.40),   // head
                AnimaLobe(0.52, -0.86, 0.20),   // near ear
                AnimaLobe(0.30, -0.90, 0.17),   // far ear
                AnimaLobe(-0.44, 0.34, 0.28),   // haunch
                AnimaLobe(0.20, -0.10, 0.34)    // the joining lobe
            ]), paint: 0, depth: 6)
        ],
        paints: [offWhite]
    )

    static let figures: [AnimaFigure] = [jellyfish, moth, seedHead, lantern, bloom, hare]

    // MARK: - Clips

    /// The universal idle. Everything alive in this game breathes.
    ///
    /// One squash channel, looping, four seconds. Slow enough to read as
    /// breath rather than a pulse — under about two seconds a loop reads as
    /// anxious, which is the opposite of the product.
    static let breathe = AnimaClip("breathe", duration: 4.0, loops: true, tracks: [
        AnimaTrack("body", .squash, [
            AnimaKey(0.0, 0.0, .easeInOut),
            AnimaKey(2.0, 0.055, .easeInOut),
            AnimaKey(4.0, 0.0, .easeInOut)
        ], loops: true)
    ])

    /// A JELLYFISH SWIM. The bell squashes and the whole figure rises, and
    /// the tentacles trail because they lag.
    static let driftPulse = AnimaClip("drift-pulse", duration: 3.2, loops: true, tracks: [
        AnimaTrack("body", .squash, [
            AnimaKey(0.0, 0.0, .easeInOut),
            AnimaKey(0.45, 0.22, .easeIn),      // the push
            AnimaKey(1.5, -0.10, .easeOut),     // the long stretch after it
            AnimaKey(3.2, 0.0, .easeInOut)
        ], loops: true),
        AnimaTrack("body", .y, [
            AnimaKey(0.0, 0.0, .easeInOut),
            AnimaKey(0.6, -0.16, .easeOut),
            AnimaKey(3.2, 0.0, .easeInOut)
        ], loops: true)
    ])

    /// A MOTH FLUTTER. Fast, shallow, and the two wings share one curve
    /// because their rest rotations already mirror them.
    static let flutter: AnimaClip = {
        let beat = AnimaCurve([
            AnimaKey(0.0, 0.0, .easeInOut),
            AnimaKey(0.09, 0.85, .easeOut),
            AnimaKey(0.22, 0.0, .easeIn)
        ], loops: true)
        return AnimaClip("flutter", duration: 0.22, loops: true, tracks: [
            AnimaTrack("wing-near", .rotation, beat),
            AnimaTrack("wing-far", .rotation, AnimaCurve([
                AnimaKey(0.0, 0.0, .easeInOut),
                AnimaKey(0.09, -0.85, .easeOut),
                AnimaKey(0.22, 0.0, .easeIn)
            ], loops: true))
        ])
    }()

    /// ARRIVING. The anticipate/overshoot pair, which is what makes a thing
    /// appear rather than merely become visible.
    ///
    /// Scale winds down below its rest before growing, and passes its target
    /// before settling on it. 320 ms — long enough to read, short enough that
    /// it never delays her.
    static let wake = AnimaClip("wake", duration: 0.32, tracks: [
        AnimaTrack("body", .scale, [
            AnimaKey(0.0, 0.0, .linear),
            AnimaKey(0.32, 1.0, .overshoot(1.9))
        ]),
        AnimaTrack("body", .opacity, [
            AnimaKey(0.0, 0.0, .linear),
            AnimaKey(0.16, 1.0, .easeOut)
        ])
    ])

    /// RELEASING — the pop, as a performance rather than a particle spray.
    ///
    /// Squash in (the wind-up), stretch out (the release), fade. The
    /// anticipation is 90 ms of the 260, which is the proportion that reads
    /// as "it gathered itself" rather than "it hesitated".
    static let release = AnimaClip("release", duration: 0.26, tracks: [
        AnimaTrack("body", .squash, [
            AnimaKey(0.0, 0.0, .linear),
            AnimaKey(0.09, 0.30, .easeIn),
            AnimaKey(0.26, -0.55, .easeOut)
        ]),
        AnimaTrack("body", .scale, [
            AnimaKey(0.0, 1.0, .linear),
            AnimaKey(0.09, 0.88, .easeIn),
            AnimaKey(0.26, 1.5, .easeOut)
        ]),
        AnimaTrack("body", .opacity, [
            AnimaKey(0.0, 1.0, .linear),
            AnimaKey(0.11, 1.0, .hold),
            AnimaKey(0.26, 0.0, .easeIn)
        ])
    ])

    /// TURNING, with a ring-down. The reference case for `.settle`.
    static let turn = AnimaClip("turn", duration: 0.8, tracks: [
        AnimaTrack("body", .rotation, [
            AnimaKey(0.0, 0.0, .linear),
            AnimaKey(0.8, 0.5, .settle(5.5))
        ])
    ])

    static let clips: [AnimaClip] = [breathe, driftPulse, flutter, wake, release, turn]

    // MARK: - Voices
    //
    // Eight instruments. The first four are the existing game's families
    // re-expressed as data — if these cannot be written here the schema is
    // not general enough to adopt — and the last four are new.

    /// THE ASMR POP. A soft broadband transient and a resonant body that
    /// lifts very slightly as it decays. The base sound of the game.
    static let popVoice = AnimaVoice(
        "pop", duration: 0.13,
        partials: [
            AnimaPartial(1.0, gain: 0.55, decay: 22),
            AnimaPartial(2.02, gain: 0.12, decay: 40)
        ],
        noise: AnimaNoise(gain: 0.5, decay: 150, lowpass: 0.45),
        attack: 0.002, glide: 1.03
    )

    /// STRUCK AND INHARMONIC. Bells, not tones — the partials are the whole
    /// identity, and none of them is a whole multiple of the fundamental.
    static let bell = AnimaVoice(
        "bell", duration: 0.9,
        partials: [
            AnimaPartial(1.0, gain: 0.42, decay: 3.2),
            AnimaPartial(2.76, gain: 0.20, decay: 5.0),
            AnimaPartial(5.40, gain: 0.10, decay: 8.5),
            AnimaPartial(8.93, gain: 0.05, decay: 13.0)
        ],
        attack: 0.003, glide: 1.0
    )

    /// A KNUCKLE ON A TABLE. Low, damped, almost pitchless.
    static let wood = AnimaVoice(
        "wood", duration: 0.11,
        partials: [
            AnimaPartial(0.5, gain: 0.5, decay: 46),
            AnimaPartial(1.0, gain: 0.18, decay: 70)
        ],
        noise: AnimaNoise(gain: 0.35, decay: 220, lowpass: 0.22),
        attack: 0.0015, glide: 0.98
    )

    /// GLASS TAPPED WITH A NAIL. A bright detuned pair, very short — the beat
    /// between them is the sound.
    static let glass = AnimaVoice(
        "glass", duration: 0.22,
        partials: [
            AnimaPartial(1.0, gain: 0.30, decay: 14, detune: 2.4),
            AnimaPartial(3.11, gain: 0.16, decay: 20, detune: 3.1)
        ],
        attack: 0.001, glide: 1.01
    )

    /// AIR RATHER THAN PITCH. No partials at all — the schema has to be able
    /// to say that, and this is the entry that proves it.
    static let breath = AnimaVoice(
        "breath", duration: 0.42,
        partials: [],
        noise: AnimaNoise(gain: 0.9, decay: 7.5, lowpass: 0.10, band: 2.2),
        attack: 0.06, glide: 1.0
    )

    /// A DROP INTO STILL WATER. The one voice whose identity is a falling
    /// pitch, and therefore the one that opts out of the anti-laser floor.
    static let drop = AnimaVoice(
        "drop", duration: 0.20,
        partials: [
            AnimaPartial(1.0, gain: 0.5, decay: 16),
            AnimaPartial(2.0, gain: 0.08, decay: 30)
        ],
        noise: AnimaNoise(gain: 0.18, decay: 190, lowpass: 0.5),
        attack: 0.002, glide: 0.72, allowsFall: true
    )

    /// A SMALL STRUCK CHIME. Harmonic where the bell is not, so the two read
    /// as different instruments rather than as one instrument tuned twice.
    static let chime = AnimaVoice(
        "chime", duration: 0.55,
        partials: [
            AnimaPartial(1.0, gain: 0.34, decay: 5.0),
            AnimaPartial(2.0, gain: 0.16, decay: 7.5),
            AnimaPartial(3.0, gain: 0.07, decay: 11.0),
            AnimaPartial(4.0, gain: 0.03, decay: 16.0)
        ],
        attack: 0.004, glide: 1.02
    )

    /// BARELY A PITCH. Layered near-unisons that beat slowly against each
    /// other — for anything that should be felt rather than heard.
    static let hush = AnimaVoice(
        "hush", duration: 0.75,
        partials: [
            AnimaPartial(1.0, gain: 0.20, decay: 3.0, detune: 0.7),
            AnimaPartial(1.5, gain: 0.12, decay: 4.0, detune: 1.1),
            AnimaPartial(2.0, gain: 0.06, decay: 5.5, detune: 0.4)
        ],
        noise: AnimaNoise(gain: 0.10, decay: 5.0, lowpass: 0.06),
        attack: 0.09, glide: 1.0
    )

    /// A PLAIN ROUND TONE. The v1.0 shape — nothing struck, nothing swept.
    static let tone = AnimaVoice(
        "tone", duration: 0.15,
        partials: [
            AnimaPartial(1.0, gain: 0.60, decay: 14),
            AnimaPartial(2.0, gain: 0.06, decay: 26)
        ],
        attack: 0.003, glide: 1.02
    )

    /// A STRING TOUCHED ONCE. The identity is the decay SPREAD, not the
    /// attack: brightness collapsing several times faster than the body is
    /// what "plucked" actually is, and it is why four partials with four
    /// different decays sound like one event rather than a chord.
    static let pluck = AnimaVoice(
        "pluck", duration: 0.30,
        partials: [
            AnimaPartial(1.0, gain: 0.44, decay: 9),
            AnimaPartial(2.0, gain: 0.20, decay: 22),
            AnimaPartial(3.0, gain: 0.10, decay: 38),
            AnimaPartial(4.0, gain: 0.05, decay: 60)
        ],
        attack: 0.0012, glide: 1.0
    )

    /// EMBERS SETTLING. Almost no pitch: a low body under fast-decaying
    /// noise.
    static let crackle = AnimaVoice(
        "crackle", duration: 0.26,
        partials: [AnimaPartial(0.5, gain: 0.16, decay: 20)],
        noise: AnimaNoise(gain: 0.75, decay: 26, lowpass: 0.55),
        attack: 0.002, glide: 0.99
    )

    /// BARELY A PITCH, and slower than `hush` — near-unisons beating against
    /// one another over most of a second.
    static let shimmer = AnimaVoice(
        "shimmer", duration: 0.70,
        partials: [
            AnimaPartial(1.0, gain: 0.16, decay: 3.4, detune: 0.6),
            AnimaPartial(2.0, gain: 0.10, decay: 4.6, detune: 0.9),
            AnimaPartial(3.0, gain: 0.05, decay: 6.2, detune: 1.4)
        ],
        noise: AnimaNoise(gain: 0.08, decay: 4.0, lowpass: 0.05),
        attack: 0.08, glide: 1.01
    )

    static let voices: [AnimaVoice] = [
        popVoice, tone, bell, pluck, breath, glass, wood, crackle, shimmer, drop,
        chime, hush
    ]

    /// THE INSTRUMENT FOR A CATALOGUE VOICE.
    ///
    /// Total over `SoundVoice`, deliberately with no `default:` — a new case
    /// in the pop standard should stop the build here and be given an
    /// instrument, rather than silently inheriting whatever the fallback
    /// happened to be. That silence is how a family ends up sounding like
    /// another one and nobody can say when it started.
    static func voice(for sound: SoundVoice) -> AnimaVoice {
        switch sound {
        case .pop:      return popVoice
        case .tone:     return tone
        case .bell:     return bell
        case .pluck:    return pluck
        case .breath:   return breath
        case .glass:    return glass
        case .wood:     return wood
        case .crackle:  return crackle
        case .shimmer:  return shimmer
        case .drop:     return drop
        }
    }

    // MARK: - Objects
    //
    // The authoring unit: a figure, the performances it can give, and the
    // sound it makes. This is what `AnimaStudio` exports and what an adopting
    // system would ask for by name.

    static let objects: [AnimaObject] = [
        AnimaObject(jellyfish, clips: [driftPulse, wake, release], voice: hush,
                    note: "trailing lag: one squash channel becomes a whole cascade"),
        AnimaObject(moth, clips: [flutter, wake, turn], voice: breath,
                    note: "hierarchy: the wings are children, so the body carries them"),
        AnimaObject(seedHead, clips: [breathe, wake, release], voice: glass,
                    note: "generated parts: eleven filaments with a staggered lag"),
        AnimaObject(lantern, clips: [breathe, wake, turn], voice: chime,
                    note: "depth order: the light is drawn under the body"),
        AnimaObject(bloom, clips: [breathe, wake, release], voice: bell,
                    note: "radial hierarchy with a per-petal lag"),
        AnimaObject(hare, clips: [breathe, wake, release], voice: popVoice,
                    note: "the balloon-animal vocabulary, expressed on this engine")
    ]
}

// MARK: - The authoring unit

/// One authored thing: how it looks, what it can do, and what it sounds like.
struct AnimaObject: Equatable {
    var figure: AnimaFigure
    var clips: [AnimaClip]
    var voice: AnimaVoice
    /// Why this entry exists, for whoever reads the library next. Not shown
    /// anywhere in the product.
    var note: String

    // MARK: Catalogue identity
    //
    // Set for the hundred generated pops and nil for the hand-authored
    // reference figures, which belong to no family and have no number. Carried
    // so `AnimaStudio` can group, filter and search without re-deriving any of
    // it — and OPTIONAL rather than defaulted, so a reference figure cannot
    // silently claim to be pop #0 of some family.
    var popNumber: Int?
    var family: String?
    var rarity: String?
    var flavor: String?

    init(_ figure: AnimaFigure,
         clips: [AnimaClip],
         voice: AnimaVoice,
         note: String = "",
         popNumber: Int? = nil,
         family: String? = nil,
         rarity: String? = nil,
         flavor: String? = nil) {
        self.figure = figure
        self.clips = clips
        self.voice = voice
        self.note = note
        self.popNumber = popNumber
        self.family = family
        self.rarity = rarity
        self.flavor = flavor
    }
}
