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
    /// 30 per second of clip, floored and capped. Thirty is enough to scrub
    /// smoothly and to see a wind-up; sampling at 120 would quadruple the
    /// file to show an author nothing they could act on.
    static func frameCount(for clip: AnimaClip) -> Int {
        min(180, max(8, Int((clip.duration * 30).rounded())))
    }

    /// The sample rate the previewer plays at.
    ///
    /// HALF THE APP'S, ON PURPOSE. 22.05 kHz halves the export and costs
    /// nothing an author can hear on the laptop speakers they will be
    /// listening on: the voices in this library put almost nothing above
    /// 8 kHz, so the ceiling this imposes is above everything that carries
    /// their character. The app still renders at 44.1.
    static let previewSampleRate: Double = 22_050

    // MARK: - The export

    /// The whole library as JSON.
    static func export(_ objects: [AnimaObject] = AnimaLibrary.objects) -> Data {
        var root: [String: Any] = [:]
        root["format"] = "anima-studio/1"
        // A number the previewer checks, so an old page and a new export fail
        // loudly instead of drawing something subtly wrong.
        root["revision"] = 1
        root["sampleRate"] = previewSampleRate
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

    private static func encode(_ object: AnimaObject) -> [String: Any] {
        [
            "name": object.figure.name,
            "note": object.note,
            "paints": object.figure.paints.map { paint in
                ["fill": rgb(paint.fill), "glow": rgb(paint.glow)]
            },
            "reach": object.figure.restReach,
            "clips": object.clips.map { encode($0, of: object.figure) },
            "voice": encode(object.voice)
        ]
    }

    private static func encode(_ clip: AnimaClip, of figure: AnimaFigure) -> [String: Any] {
        let frames = frameCount(for: clip)
        return [
            "name": clip.name,
            "duration": clip.duration,
            "loops": clip.loops,
            "frames": clip.filmstrip(of: figure, frames: frames).map { pose in
                pose.parts.map { part -> [String: Any] in
                    [
                        "paint": part.paint,
                        "opacity": part.opacity,
                        // Flattened to [x, y, x, y, …]. A list of pairs would
                        // roughly double the file for no gain: the previewer
                        // walks it two at a time either way.
                        "points": part.outline.flatMap { [Double($0.x), Double($0.y)] }
                    ]
                }
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
