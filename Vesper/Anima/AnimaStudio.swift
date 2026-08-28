import CoreGraphics
import Foundation

// ANIMA STUDIO — the authoring loop, and the reason this engine is cheap.
//
// ─────────────────────────────────────────────────────────────────────────
// THE ACTUAL COST OF CONTENT, MEASURED IN THE ONLY UNIT THAT MATTERS.
//
// Not lines of code — ITERATIONS PER HOUR. Today, seeing a change to a 2-D
// object in Vesper costs: edit Swift, `xcodebuild` (about four minutes cold),
// launch the simulator, play far enough into the game to reach the content,
// look at it for two seconds. Call it five minutes, and it needs a Mac with
// Xcode and someone who is comfortable in it. An author gets perhaps ten
// looks in an hour and cannot get any without an engineer.
//
// This file exports the whole library — figures, sampled performances,
// rendered sound — as one JSON file that `tools/anima-studio/index.html`
// plays in a browser. Scrubbing a timeline costs nothing, and the author
// needs no Xcode, no simulator, no toolchain, and nobody's help.
//
// ─────────────────────────────────────────────────────────────────────────
// WHY THE PREVIEWER CANNOT DRIFT FROM THE APP.
//
// This is the failure that kills every tool like this: the preview
// reimplements the runtime, the two diverge, and the tool starts quietly
// lying to whoever is authoring against it. The lie is worse than having no
// tool, because it is believed.
//
// Two decisions make drift structurally impossible rather than merely
// unlikely:
//
//   1. THE PREVIEWER DOES NO ANIMATION MATHS. It is handed poses — flat lists
//      of screen-space polygons, already keyed, eased, lagged, composed and
//      depth-sorted by `AnimaClip.pose`. It fills polygons. There is no
//      easing function in the JavaScript to disagree with `AnimaEase`,
//      because there is no easing in the JavaScript at all.
//   2. THE PREVIEWER DOES NO SYNTHESIS. It is handed PCM rendered by
//      `AnimaVoice.render` — the same arithmetic that will reach the phone's
//      speaker. It has no oscillator. What an author hears in a browser is
//      what ships.
//
// The export is therefore large and dumb, which is the correct shape for a
// development artifact. A whole library is a few hundred kilobytes.
//
// ─────────────────────────────────────────────────────────────────────────
// PURE, AND WRITTEN BY A TEST.
//
// Foundation only. It does not touch the filesystem — `AnimaStudioTests`
// does, opting in through an environment variable so CI never writes
// anything. That is the cheapest possible harness: no new target, no new
// scheme, no build configuration, and the one command an engineer already
// runs.

enum AnimaStudio {

    /// How many poses a performance is sampled into.
    ///
    /// 24 per second, hard-capped at 32 frames. Twenty-four is enough to
    /// scrub smoothly and to see a wind-up; the cap is what keeps a long idle
    /// (the four-second `breathe`) from costing four times what a reaction
    /// does to show the same amount of information.
    static func frameCount(for clip: AnimaClip) -> Int {
        // A clip with no tracks cannot change, so one frame says everything
        // thirty-two identical ones would. This is not a micro-optimisation:
        // every reduced looping idle is exactly this shape (that is what
        // "reduces to stillness" means), so it is a third of the gallery.
        guard !clip.tracks.isEmpty else { return 1 }
        return min(32, max(8, Int((clip.duration * 24).rounded())))
    }

    /// The sample rate the previewer plays at.
    ///
    /// HALF THE APP'S, ON PURPOSE. 22.05 kHz halves the export and costs
    /// nothing an author can hear on the laptop speakers they will be
    /// listening on: the voices in this library put almost nothing above
    /// 8 kHz, so the ceiling this imposes is above everything that carries
    /// their character. The app still renders at 44.1.
    static let previewSampleRate: Double = 22_050

    /// THE FORMAT REVISION, IN ONE PLACE.
    ///
    /// It is written into every export and checked by the previewer, which
    /// refuses to draw a revision it was not written for. That check is the
    /// only thing standing between an old page and a new export -- a pairing
    /// that does not fail, it just draws something subtly and unaccountably
    /// wrong.
    ///
    /// Bump it whenever the shape of the export changes, and bump
    /// `EXPECTED_REVISION` in `tools/anima-studio/index.html` in the same
    /// commit. `AnimaStudioTests` reads that file and fails if the two ever
    /// disagree, so this is a rule with a machine behind it rather than a
    /// comment.
    static let revision = 3
    static var formatName: String { "anima-studio/\(revision)" }

    /// Decimal places kept for geometry.
    ///
    /// In unit space 1e-4 is 0.0034 pt at the largest orb in the game — three
    /// orders of magnitude below one device pixel — and it roughly halves the
    /// text of every number.
    static let places = 4

    // MARK: - The export

    /// Everything the hub page shows: the hundred catalogue pops, plus the
    /// hand-authored reference figures that exercise primitives the families
    /// do not.
    static var galleryObjects: [AnimaObject] {
        AnimaPop.all + AnimaLibrary.objects
    }

    /// The whole library as JSON.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// FORMAT 2: MATRICES, NOT OUTLINES. (backlog E1)
    ///
    /// Format 1 wrote a full transformed outline per part PER FRAME. CI
    /// measured the result at 9,253,479 bytes for six objects — 1.54 MB each,
    /// so 154 MB for a hundred. Un-openable, and it blew the size gate on the
    /// sixth asset rather than the hundredth.
    ///
    /// Now each part's REST outline is written once, and each frame carries
    /// only the resolved affine matrix and opacity: seven numbers per part
    /// per frame instead of a hundred and twenty-eight. About 30 KB an
    /// object, so a hundred fits in roughly 3 MB.
    ///
    /// THE DRIFT RULE SURVIVES, BUT IT IS NOW A SMALLER CLAIM AND IS WORTH
    /// STATING HONESTLY. The previewer does one affine multiply per point
    /// that it did not do before. It still contains no easing, no keyframe
    /// interpolation, no hierarchy composition, no lag and no `exp` — every
    /// one of which is a place two implementations could plausibly disagree.
    /// What is left is `x' = a·x + c·y + tx`, which is arithmetic a reviewer
    /// can check by eye, and which
    /// `testExportedFramesReconstructTheApplicationsOwnPoses` pins against
    /// the app's own posed outlines to within the rounding.
    static func export(_ objects: [AnimaObject]? = nil) -> Data {
        let objects = objects ?? galleryObjects
        var root: [String: Any] = [:]
        root["format"] = formatName
        // A number the previewer checks, so an old page and a new export fail
        // loudly instead of drawing something subtly wrong.
        root["revision"] = revision
        root["sampleRate"] = previewSampleRate

        // VOICES ARE A TABLE, NOT A FIELD ON EACH OBJECT (revision 3).
        //
        // A hundred pops share ten instruments, so inlining the PCM per object
        // would ship each instrument an average of ten times — some 2.5 MB of
        // duplicated audio, most of the export, for nothing. Written once and
        // referenced by name, the audio is ~250 KB however many objects there
        // are.
        var voices: [String: Any] = [:]
        for object in objects where voices[object.voice.name] == nil {
            voices[object.voice.name] = encode(object.voice)
        }
        root["voices"] = voices

        // A closure rather than `objects.map(encode)`: `encode` is overloaded
        // three ways and a bare function reference makes overload resolution
        // do work it does not need to do.
        root["objects"] = objects.map { encode($0) }

        // `.sortedKeys` so two exports of the same library are byte-identical
        // and a diff shows content changes rather than dictionary ordering.
        // `.withoutEscapingSlashes` keeps notes readable in the file.
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        return (try? JSONSerialization.data(withJSONObject: root, options: options)) ?? Data()
    }

    /// The order parts are written in, and therefore the order every frame's
    /// matrices are written in.
    ///
    /// Taken from a pose rather than from the figure, because `AnimaClip.pose`
    /// depth-sorts and the previewer draws the list in the order it is given.
    /// The sort is stable and depth is static, so this order is the same at
    /// every time — which is what lets the outlines be written once.
    private static func drawOrder(of object: AnimaObject) -> [AnimaPosedPart] {
        let clip = object.clips.first ?? AnimaClip.still()
        return clip.pose(of: object.figure, at: 0).parts
    }

    private static func encode(_ object: AnimaObject) -> [String: Any] {
        let order = drawOrder(of: object)
        return [
            "name": object.figure.name,
            "note": object.note,
            // The catalogue identity, so the hub page can group by family,
            // filter by rarity and search by number or name without
            // re-deriving any of it in JavaScript.
            "number": object.popNumber ?? 0,
            "family": object.family ?? "reference",
            "rarity": object.rarity ?? "reference",
            "flavor": object.flavor ?? object.note,
            "paints": object.figure.paints.map { paint in
                ["fill": rgb(paint.fill), "glow": rgb(paint.glow)]
            },
            "reach": round(object.figure.restReach),
            "parts": order.map { posed -> [String: Any] in
                // The REST outline — untransformed, written once. Looked up on
                // the figure by name, because the posed part carries the
                // transformed one.
                let outline = object.figure.part(named: posed.name)?
                    .primitive.outline() ?? []
                return [
                    "name": posed.name,
                    "paint": posed.paint,
                    "depth": posed.depth,
                    // Flattened to [x, y, x, y, …]: a list of pairs roughly
                    // doubles the file for no gain, since the previewer walks
                    // it two at a time either way.
                    "points": outline.flatMap { [round(Double($0.x)), round(Double($0.y))] }
                ]
            },
            // EVERY PERFORMANCE SHIPS WITH ITS REDUCED VARIANT beside it, named
            // so the page can pair them. 04 §11's requirement is not a
            // property of the app alone — an author reviewing a hundred assets
            // has to be able to see what someone who asked for less motion
            // will actually get, and the only honest way to show that is the
            // engine's own `reduced`, exported through the same path.
            "clips": object.clips.flatMap { clip -> [[String: Any]] in
                [encode(clip, of: object.figure, order: order),
                 encode(clip.reduced, of: object.figure, order: order,
                        named: "\(clip.name) (reduced)")]
            },
            // A NAME, into the top-level table. See `export`.
            "voice": object.voice.name
        ]
    }

    private static func encode(_ clip: AnimaClip,
                               of figure: AnimaFigure,
                               order: [AnimaPosedPart],
                               named: String? = nil) -> [String: Any] {
        let frames = frameCount(for: clip)
        let names = order.map(\.name)
        return [
            "name": named ?? clip.name,
            "duration": clip.duration,
            "loops": clip.loops,
            // One flat array per frame: seven numbers per part —
            // a, b, c, d, tx, ty, opacity — in `order`.
            "frames": clip.filmstrip(of: figure, frames: frames).map { pose -> [Double] in
                var row: [Double] = []
                row.reserveCapacity(names.count * 7)
                for name in names {
                    guard let part = pose.parts.first(where: { $0.name == name }) else {
                        row.append(contentsOf: [1, 0, 0, 1, 0, 0, 0])
                        continue
                    }
                    let m = part.transform
                    row.append(contentsOf: [round(m.a), round(m.b), round(m.c),
                                            round(m.d), round(m.tx), round(m.ty),
                                            round(part.opacity)])
                }
                return row
            }
        ]
    }

    private static func encode(_ voice: AnimaVoice) -> [String: Any] {
        let samples = voice.render(pitch: 440, sampleRate: previewSampleRate)
        return [
            "name": voice.name,
            "duration": voice.duration,
            "partials": voice.partials.count,
            "pcm": base64Int16(samples)
        ]
    }

    /// Geometry rounded to `places`.
    ///
    /// `-0` is normalised to `0`: JSONSerialization writes negative zero as
    /// `-0`, which is valid JSON and reads back identically, but it makes two
    /// otherwise-identical exports differ in text and defeats the diffability
    /// `.sortedKeys` exists to give.
    static func round(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let scale = pow(10.0, Double(places))
        let r = (value * scale).rounded() / scale
        return r == 0 ? 0 : r
    }

    private static func rgb(_ c: PopColor) -> [Double] { [c.r, c.g, c.b] }

    // MARK: - PCM

    /// Float samples as base64 little-endian signed 16-bit.
    ///
    /// 16-BIT, NOT 32. Halves the payload again and is transparent for a
    /// preview — the quantisation floor sits around −96 dBFS, some seventy
    /// decibels under anything in this library. Little-endian because that is
    /// what `DataView.getInt16(i, true)` reads in the previewer, and stating
    /// the endianness in both places is cheaper than debugging the one time
    /// it is wrong.
    static func base64Int16(_ samples: [Float]) -> String {
        var bytes = [UInt8]()
        bytes.reserveCapacity(samples.count * 2)
        for sample in samples {
            let clamped = min(max(sample, -1), 1)
            // 32767 rather than 32768: scaling by 32768 makes a sample of
            // exactly −1.0 land on −32768, which is representable, and +1.0
            // land on +32768, which is not, and wraps to −32768 — a full-scale
            // click at the loudest moment of the sound.
            let value = Int16(clamped * 32_767)
            let unsigned = UInt16(bitPattern: value)
            bytes.append(UInt8(unsigned & 0xFF))
            bytes.append(UInt8(unsigned >> 8))
        }
        return Data(bytes).base64EncodedString()
    }
}
