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
        XCTAssertEqual(root["format"] as? String, AnimaStudio.formatName)
        XCTAssertEqual(root["revision"] as? Int, AnimaStudio.revision)
        XCTAssertEqual(root["sampleRate"] as? Double, AnimaStudio.previewSampleRate)

        let objects = try XCTUnwrap(root["objects"] as? [[String: Any]])
        XCTAssertEqual(objects.count, AnimaLibrary.objects.count)

        for object in objects {
            XCTAssertNotNil(object["name"] as? String)

            let parts = try XCTUnwrap(object["parts"] as? [[String: Any]])
            XCTAssertFalse(parts.isEmpty, "an object exported no parts")
            for part in parts {
                let points = try XCTUnwrap(part["points"] as? [Double])
                XCTAssertGreaterThan(points.count, 6)
                XCTAssertEqual(points.count % 2, 0,
                               "a flattened outline has an odd number of coordinates")
            }

            let clips = try XCTUnwrap(object["clips"] as? [[String: Any]])
            XCTAssertFalse(clips.isEmpty)
            for clip in clips {
                let frames = try XCTUnwrap(clip["frames"] as? [[Double]])
                XCTAssertFalse(frames.isEmpty, "a clip exported no frames")
                for frame in frames {
                    // Seven numbers per part — a, b, c, d, tx, ty, opacity —
                    // in the object's own part order. A frame whose length is
                    // not an exact multiple would silently shear every part
                    // after the miscount.
                    XCTAssertEqual(frame.count, parts.count * 7,
                                   "a frame does not carry exactly seven numbers per part")
                    for value in frame {
                        XCTAssertTrue(value.isFinite, "a frame carries a non-finite number")
                    }
                }
            }
            let voice = try XCTUnwrap(object["voice"] as? [String: Any])
            let pcm = try XCTUnwrap(voice["pcm"] as? String)
            XCTAssertFalse(pcm.isEmpty, "a voice exported no audio")
        }
    }

    // THE PREVIEWER AND THE EXPORT MUST AGREE ON THE REVISION.
    //
    // This test exists because the failure it prevents just happened. Format 2
    // bumped the exporter and left the shape test asserting format 1 — caught,
    // because a test named the number. The previewer holds the SAME number in
    // JavaScript, where no Swift test was looking at all, and an old page
    // against a new export does not fail: `frame` stops being a list of parts
    // and becomes a list of numbers, and the page draws nonsense, silently, to
    // an author who has no reason to distrust it.
    //
    // Reading the file via `#filePath` is the whole trick: it is the path of
    // THIS source file at compile time, so the test can find the repository
    // without being told where it is. Skipped rather than failed when the file
    // is missing, since a test bundle can be run from somewhere the source
    // tree is not.
    func testThePreviewerExpectsTheRevisionTheExporterWrites() throws {
        let page = URL(fileURLWithPath: #filePath)     // …/VesperTests/AnimaStudioTests.swift
            .deletingLastPathComponent()               // …/VesperTests
            .deletingLastPathComponent()               // repository root
            .appendingPathComponent("tools/anima-studio/index.html")

        try XCTSkipUnless(FileManager.default.fileExists(atPath: page.path),
                          "previewer not reachable from \(page.path); skipping the pairing check")

        let html = try String(contentsOf: page, encoding: .utf8)
        guard let match = html.range(of: #"EXPECTED_REVISION\s*=\s*(\d+)"#,
                                     options: .regularExpression) else {
            return XCTFail("could not find EXPECTED_REVISION in the previewer")
        }
        let digits = html[match].compactMap { $0.isNumber ? $0 : nil }
        let expected = Int(String(digits))

        XCTAssertEqual(expected, AnimaStudio.revision, """
            The previewer expects revision \(expected.map(String.init) ?? "?") and the exporter \
            writes \(AnimaStudio.revision). Bump EXPECTED_REVISION in \
            tools/anima-studio/index.html in the same commit as AnimaStudio.revision.
            """)
    }

    // Byte-identical for the same library. `.sortedKeys` is what makes the
    // export diffable: without it a re-export shuffles dictionary ordering and
    // every regeneration looks like a content change.
    func testTheExportIsStableAcrossRuns() {
        XCTAssertEqual(AnimaStudio.export(), AnimaStudio.export())
    }

    // THE PREVIEWER IS ONLY WORTH HAVING IF IT CANNOT LIE.
    //
    // Format 2 ships each part's REST outline once and a resolved affine
    // matrix per frame, so the previewer does one multiply the app does not
    // hand it. This test does exactly what the previewer does — matrix times
    // rest outline — and holds the result against the app's own posed
    // outline. If the exporter ever ships a matrix that does not reproduce
    // the pose, this fails, which is the only thing standing between an
    // author and a preview that quietly disagrees with the phone.
    //
    // The tolerance is the rounding, not slack: geometry is written to four
    // decimal places, and a coordinate reaching ~2.5 unit radii accumulates
    // at most a few times 1e-4 through the multiply. In app terms that is
    // under a hundredth of a point at the largest orb in the game.
    func testExportedFramesReconstructTheApplicationsOwnPoses() throws {
        for object in AnimaLibrary.objects {
            let data = AnimaStudio.export([object])
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let objects = try XCTUnwrap(root["objects"] as? [[String: Any]])
            let parts = try XCTUnwrap(objects[0]["parts"] as? [[String: Any]])
            let clipsJSON = try XCTUnwrap(objects[0]["clips"] as? [[String: Any]])

            // The rest outlines, in the exporter's draw order.
            let restOutlines: [[CGPoint]] = try parts.map { part in
                let flat = try XCTUnwrap(part["points"] as? [Double])
                return stride(from: 0, to: flat.count, by: 2).map {
                    CGPoint(x: flat[$0], y: flat[$0 + 1])
                }
            }
            let names = try parts.map { try XCTUnwrap($0["name"] as? String) }

            for (clipIndex, clip) in object.clips.enumerated() {
                let frames = try XCTUnwrap(clipsJSON[clipIndex]["frames"] as? [[Double]])
                let expected = clip.filmstrip(of: object.figure,
                                              frames: AnimaStudio.frameCount(for: clip))
                XCTAssertEqual(frames.count, expected.count)

                for (frameIndex, frame) in frames.enumerated() {
                    let pose = expected[frameIndex]
                    for (partIndex, name) in names.enumerated() {
                        guard let posed = pose.parts.first(where: { $0.name == name }) else {
                            return XCTFail("\(object.figure.name): exported part \(name) is not in the pose")
                        }
                        let o = partIndex * 7
                        // Exactly the previewer's arithmetic, in Swift.
                        let a = frame[o], b = frame[o + 1], c = frame[o + 2]
                        let d = frame[o + 3], tx = frame[o + 4], ty = frame[o + 5]

                        for (i, rest) in restOutlines[partIndex].enumerated() {
                            let x = a * Double(rest.x) + c * Double(rest.y) + tx
                            let y = b * Double(rest.x) + d * Double(rest.y) + ty
                            XCTAssertEqual(x, Double(posed.outline[i].x), accuracy: 0.002,
                                           "\(object.figure.name)/\(clip.name) frame \(frameIndex) \(name) drifted in x")
                            XCTAssertEqual(y, Double(posed.outline[i].y), accuracy: 0.002,
                                           "\(object.figure.name)/\(clip.name) frame \(frameIndex) \(name) drifted in y")
                        }
                        XCTAssertEqual(frame[o + 6], posed.opacity, accuracy: 0.002)
                    }
                }
            }
        }
    }

    // The size gate, in the tests as well as in CI. CI measured format 1 at
    // 9,253,479 bytes for SIX objects — 1.54 MB each, 154 MB for a hundred —
    // which is what format 2 exists to fix.
    func testTheExportIsSmallEnoughToReachAHundredAssets() {
        let bytes = AnimaStudio.export().count
        let perObject = Double(bytes) / Double(AnimaLibrary.objects.count)
        XCTAssertLessThan(perObject, 120_000,
                          "at \(Int(perObject)) bytes an object, a hundred assets would be "
                          + "\(Int(perObject * 100) / 1_048_576) MB — see docs/anima_backlog.md E1")
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
    ///     TEST_RUNNER_ANIMA_EXPORT_DIR="$PWD/tools/anima-studio" \
    ///       xcodebuild test -project Vesper.xcodeproj -scheme Vesper \
    ///       -destination 'platform=iOS Simulator,name=iPhone 16' \
    ///       CODE_SIGNING_ALLOWED=NO \
    ///       -only-testing:VesperTests/AnimaStudioTests/testWriteTheStudioExport
    ///
    /// Then open `tools/anima-studio/index.html`.
    ///
    /// NOTE THE `TEST_RUNNER_` PREFIX ON THE COMMAND LINE, AND ITS ABSENCE IN
    /// THE CODE. This test runs inside the iOS Simulator, in a process that
    /// does not inherit the invoking shell's environment; `xcodebuild test`
    /// forwards only variables prefixed `TEST_RUNNER_` and strips the prefix
    /// on the way in. So the shell says `TEST_RUNNER_ANIMA_EXPORT_DIR` and
    /// this code reads `ANIMA_EXPORT_DIR`, and they are the same variable.
    ///
    /// Getting it wrong is quiet, which is why it is written down here: the
    /// test simply skips, the run stays green, and the export never appears.
    func testWriteTheStudioExport() throws {
        let environment = ProcessInfo.processInfo.environment
        // The unprefixed name is what arrives after xcodebuild strips the
        // prefix. The prefixed one is accepted too, for a hypothetical
        // macOS-native runner where the variable would pass straight through.
        let directory = environment["ANIMA_EXPORT_DIR"]
            ?? environment["TEST_RUNNER_ANIMA_EXPORT_DIR"]
        try XCTSkipIf(directory == nil, """
            Set TEST_RUNNER_ANIMA_EXPORT_DIR to write the studio export \
            (the TEST_RUNNER_ prefix is required to reach the simulator). \
            Skipped so an ordinary CI run writes nothing.
            """)

        let folder = URL(fileURLWithPath: directory!, isDirectory: true)
        // Created rather than assumed: an export directory that does not exist
        // yet should produce the export, not an unhelpful write error.
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("library.json")
        try AnimaStudio.export().write(to: url, options: .atomic)

        let written = try Data(contentsOf: url)
        XCTAssertFalse(written.isEmpty)
        print("anima-studio: wrote \(written.count) bytes to \(url.path)")
    }
}
