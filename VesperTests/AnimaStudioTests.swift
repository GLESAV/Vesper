import XCTest
@testable import Vesper

// ANIMA STUDIO — the export, and the one test in this suite that writes a
// file.
//
// WHY A TEST IS THE EXPORT TOOL. The alternative is a command-line target,
// which means a new target, a new scheme, a new build configuration and a new
// thing for CI to know about — for a tool that runs once when an author wants
// to look at something. A test needs none of that: `xcodebuild test` is a
// command this project's engineer already runs, and the export is one
// `-only-testing:` away.
//
// IT IS OPT-IN, so CI never writes anything. Without `ANIMA_EXPORT_DIR` the
// writing test skips and the rest of the file still checks the export's
// shape — which is the half that has to run on every commit.
final class AnimaStudioTests: XCTestCase {

    // MARK: - The export's shape

    func testTheExportIsValidJSONWithEveryObjectInIt() throws {
        let data = AnimaStudio.export()
        XCTAssertFalse(data.isEmpty, "the export produced nothing")

        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["format"] as? String, "anima-studio/1")
        XCTAssertEqual(root["revision"] as? Int, 1)
        XCTAssertEqual(root["sampleRate"] as? Double, AnimaStudio.previewSampleRate)

        let objects = try XCTUnwrap(root["objects"] as? [[String: Any]])
        XCTAssertEqual(objects.count, AnimaLibrary.objects.count)

        for object in objects {
            XCTAssertNotNil(object["name"] as? String)
            let clips = try XCTUnwrap(object["clips"] as? [[String: Any]])
            XCTAssertFalse(clips.isEmpty)
            for clip in clips {
                let frames = try XCTUnwrap(clip["frames"] as? [[[String: Any]]])
                XCTAssertFalse(frames.isEmpty, "a clip exported no frames")
                for frame in frames {
                    XCTAssertFalse(frame.isEmpty, "a frame exported no parts")
                    for part in frame {
                        let points = try XCTUnwrap(part["points"] as? [Double])
                        XCTAssertGreaterThan(points.count, 6)
                        XCTAssertEqual(points.count % 2, 0,
                                       "a flattened outline has an odd number of coordinates")
                    }
                }
            }
            let voice = try XCTUnwrap(object["voice"] as? [String: Any])
            let pcm = try XCTUnwrap(voice["pcm"] as? String)
            XCTAssertFalse(pcm.isEmpty, "a voice exported no audio")
        }
    }

    // Byte-identical for the same library. `.sortedKeys` is what makes the
    // export diffable: without it a re-export shuffles dictionary ordering and
    // every regeneration looks like a content change.
    func testTheExportIsStableAcrossRuns() {
        XCTAssertEqual(AnimaStudio.export(), AnimaStudio.export())
    }

    // THE PREVIEWER IS ONLY WORTH HAVING IF IT CANNOT LIE. It does no
    // animation maths — it is handed poses — so this is the test that the
    // thing it is handed really is what the app computes, rather than a
    // re-derivation that happens to agree today.
    func testExportedFramesAreExactlyTheApplicationsOwnPoses() throws {
        let object = AnimaLibrary.objects[0]
        let clip = object.clips[0]
        let data = AnimaStudio.export([object])
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let objects = try XCTUnwrap(root["objects"] as? [[String: Any]])
        let clips = try XCTUnwrap(objects[0]["clips"] as? [[String: Any]])
        let frames = try XCTUnwrap(clips[0]["frames"] as? [[[String: Any]]])

        let expected = clip.filmstrip(of: object.figure,
                                      frames: AnimaStudio.frameCount(for: clip))
        XCTAssertEqual(frames.count, expected.count)

        for (index, frame) in frames.enumerated() {
            let pose = expected[index]
            XCTAssertEqual(frame.count, pose.parts.count)
            for (partIndex, part) in frame.enumerated() {
                let points = try XCTUnwrap(part["points"] as? [Double])
                let outline = pose.parts[partIndex].outline
                XCTAssertEqual(points.count, outline.count * 2)
                for (i, point) in outline.enumerated() {
                    XCTAssertEqual(points[i * 2], Double(point.x), accuracy: 1e-9,
                                   "frame \(index) part \(partIndex) drifted in x")
                    XCTAssertEqual(points[i * 2 + 1], Double(point.y), accuracy: 1e-9,
                                   "frame \(index) part \(partIndex) drifted in y")
                }
            }
        }
    }

    // 16-bit PCM has to round-trip within a quantisation step, or what an
    // author hears in the browser is not what the phone will play.
    func testThePCMEncodingIsFaithfulAndCannotWrapAtFullScale() throws {
        // Full scale in both directions is the case that matters: scaling by
        // 32768 rather than 32767 sends +1.0 to −32768, which is a full-scale
        // click at the loudest moment of a sound.
        let extremes: [Float] = [-1, -0.5, 0, 0.5, 1]
        let encoded = AnimaStudio.base64Int16(extremes)
        let bytes = try XCTUnwrap(Data(base64Encoded: encoded))
        XCTAssertEqual(bytes.count, extremes.count * 2)

        for (i, expected) in extremes.enumerated() {
            let low = UInt16(bytes[i * 2])
            let high = UInt16(bytes[i * 2 + 1])
            let value = Int16(bitPattern: low | (high << 8))
            let decoded = Float(value) / 32_767
            XCTAssertEqual(decoded, expected, accuracy: 0.0001,
                           "sample \(expected) did not survive the round trip")
        }
    }

    // A development artifact, but not an unbounded one: an export nobody can
    // open in a browser is an export nobody uses.
    func testTheExportStaysSmallEnoughToOpenInABrowser() {
        let megabytes = Double(AnimaStudio.export().count) / 1_048_576
        XCTAssertLessThan(megabytes, 12,
                          "the export has grown past what a browser will happily hold — "
                          + "lower AnimaStudio.frameCount or previewSampleRate")
    }

    // MARK: - Writing it

    /// Writes the library into `ANIMA_EXPORT_DIR`, beside the previewer.
    ///
    ///     ANIMA_EXPORT_DIR="$PWD/tools/anima-studio" \
    ///       xcodebuild test -project Vesper.xcodeproj -scheme Vesper \
    ///       -destination 'platform=iOS Simulator,name=iPhone 16' \
    ///       CODE_SIGNING_ALLOWED=NO \
    ///       -only-testing:VesperTests/AnimaStudioTests/testWriteTheStudioExport
    ///
    /// Then open `tools/anima-studio/index.html`.
    func testWriteTheStudioExport() throws {
        let directory = ProcessInfo.processInfo.environment["ANIMA_EXPORT_DIR"]
        try XCTSkipIf(directory == nil,
                      "Set ANIMA_EXPORT_DIR to write the studio export. Skipped so CI writes nothing.")

        let url = URL(fileURLWithPath: directory!, isDirectory: true)
            .appendingPathComponent("library.json")
        try AnimaStudio.export().write(to: url, options: .atomic)

        let written = try Data(contentsOf: url)
        XCTAssertFalse(written.isEmpty)
        print("anima-studio: wrote \(written.count) bytes to \(url.path)")
    }
}
