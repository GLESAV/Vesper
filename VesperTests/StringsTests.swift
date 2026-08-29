import XCTest
@testable import Vesper

// The self-enforcing voice guardrail (07 §5, DELIVERY_ROADMAP W14). For a solo
// dev working with an AI pair, this test is what makes the voice rules survive a
// tired Tuesday: it reads the whole catalog and fails loudly on the forbidden
// vocabulary of 07 §2 — plus `DETONATED`, the specific word this build exists to
// remove from the counter.
//
// WHY it enumerates `Strings.allStrings` rather than a hand-picked list: a
// guardrail that only checks the strings someone remembered to check is not a
// guardrail. And because `allStrings` is itself hand-maintained, the last test
// here reads Strings.swift and asserts every declared literal made it into the
// array — so a new string cannot slip past the checks by being forgotten.
//
// Note the frame rule (07 §2): these bans are on frames applied to the player,
// and a string may be defensible with the copy owner's recorded sign-off. This
// test has no exemption list on purpose — the moment one is needed, it should
// cost a deliberate code change and a review, not a quiet edit.
final class StringsTests: XCTestCase {

    // MARK: - Forbidden vocabulary

    /// The 07 §2 list, plus DETONATED. Each is matched case-insensitively at a
    /// word boundary and allowed to carry a suffix, so "misses" and "scores" are
    /// caught while "dismissed" (no boundary before "miss") is not.
    private static let forbiddenStems = [
        "streak", "fail", "miss", "expire", "lose", "lost",
        "blast", "destroy", "kill", "score", "limited", "hurry",
        "detonate"
    ]

    /// Multi-word frames need their own patterns; whitespace is loosened so a
    /// line break between the words cannot smuggle one through.
    private static let forbiddenPhrases = [
        "last chance"
    ]

    func testCatalogContainsNoForbiddenVocabulary() throws {
        for string in Strings.allStrings {
            for stem in Self.forbiddenStems {
                XCTAssertFalse(
                    Self.matches(pattern: "\\b\(stem)[a-z]*\\b", in: string),
                    "forbidden word '\(stem)' in catalog string: \"\(string)\" — see 07 §2"
                )
            }
            for phrase in Self.forbiddenPhrases {
                let pattern = phrase
                    .split(separator: " ")
                    .joined(separator: "\\s+")
                XCTAssertFalse(
                    Self.matches(pattern: "\\b\(pattern)\\b", in: string),
                    "forbidden phrase '\(phrase)' in catalog string: \"\(string)\" — see 07 §2"
                )
            }
        }
    }

    /// The word this build exists to remove, asserted on its own so a failure
    /// names itself rather than hiding inside the loop above.
    func testDetonatedIsGoneFromTheCatalog() {
        for string in Strings.allStrings {
            XCTAssertFalse(
                string.lowercased().contains("detonat"),
                "'DETONATED' is not a word this game says: \"\(string)\""
            )
        }
        XCTAssertEqual(Strings.setFreeLabel, "set free")
    }

    /// Guards the matcher itself: a regex that caught nothing would let the test
    /// above pass forever.
    func testMatcherCatchesSuffixesButNotSubstrings() {
        XCTAssertTrue(Self.matches(pattern: "\\bmiss[a-z]*\\b", in: "three misses"))
        XCTAssertTrue(Self.matches(pattern: "\\bscore[a-z]*\\b", in: "SCORE"))
        XCTAssertFalse(Self.matches(pattern: "\\bmiss[a-z]*\\b", in: "the card dismissed itself"))
        XCTAssertFalse(Self.matches(pattern: "\\bkill[a-z]*\\b", in: "the evening is still here"))
    }

    // MARK: - Casing

    /// 07 §2: all UI and whisper copy is lowercase. Fortunes are the stated
    /// sentence-case exception and live in `Fortunes`, not in this catalog.
    func testCatalogCopyIsLowercaseFirst() {
        for string in Strings.allStrings {
            guard let first = string.first else {
                XCTFail("empty string in the catalog")
                continue
            }
            if Strings.properNounInitials.contains(string) { continue }
            XCTAssertFalse(
                first.isUppercase,
                "catalog copy is lowercase unless a proper noun starts it: \"\(string)\" — see 07 §2"
            )
        }
    }

    func testCatalogHasNoDecorativeEmojiOrShouting() {
        for string in Strings.allStrings {
            XCTAssertFalse(string.contains("!"), "never exclamatory: \"\(string)\"")
            XCTAssertFalse(
                string.unicodeScalars.contains { $0.properties.isEmoji && $0.value > 0x238C },
                "no decorative emoji in product copy: \"\(string)\""
            )
        }
    }

    // MARK: - The catalog cannot silently miss an entry

    /// Reads Strings.swift and checks every declared string literal is present
    /// in `allStrings`. Swift's `Mirror` cannot see static members, so the
    /// source is the only place this can be verified — and without it, adding a
    /// `static let` without adding it to `allStrings` would silently opt that
    /// string out of every check above.
    func testEveryDeclaredStringIsInAllStrings() throws {
        let source = try Self.catalogSource()
        let declarations = Self.captures(
            pattern: "static\\s+let\\s+\\w+(?:\\s*:\\s*String)?\\s*=\\s*\"([^\"]*)\"",
            in: source
        )

        XCTAssertFalse(declarations.isEmpty, "found no string declarations — did Strings.swift move?")
        for literal in declarations {
            XCTAssertTrue(
                Strings.allStrings.contains(literal),
                "\"\(literal)\" is declared in Strings.swift but missing from Strings.allStrings"
            )
        }
        XCTAssertEqual(
            Set(Strings.allStrings).count, Strings.allStrings.count,
            "duplicate entries in allStrings — two names for one string is a casing bug waiting to happen"
        )
    }

    // MARK: - Helpers

    private static func matches(pattern: String, in string: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }

    private static func captures(pattern: String, in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: string) else { return nil }
            return String(string[captured])
        }
    }

    /// Located relative to this test file so it works from any checkout path.
    private static func catalogSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VesperTests
            .deletingLastPathComponent()   // repo root
        let path = root
            .appendingPathComponent("Vesper")
            .appendingPathComponent("Support")
            .appendingPathComponent("Strings.swift")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: path.path),
            "catalog source not available in this run"
        )
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// Every Swift file under `Vesper/`, located the same way as the catalog
    /// so it works from any checkout path. Skips rather than fails when the
    /// sources are not on disk, exactly as `catalogSource` does.
    private static func appSwiftFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VesperTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Vesper")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.path),
            "app sources not available in this run"
        )
        guard let walker = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    // MARK: - R-CRAFT J1/J2: catalogued, and actually wired

    // The done card said `Nicely done.` and `GO AGAIN` while
    // `Strings.fieldIsQuiet` — documented in this catalog as "the done card's
    // chrome" — and `Strings.again` sat in the binary with zero call sites.
    // The fortune card said "Tap to dismiss" while `fortuneDismissHint` did
    // the same. Three strings were written, reviewed, catalogued and shipped,
    // and the views still said the v1.2 words: a WIRING bug wearing a copy
    // bug's clothes, and invisible to a test that only reads the catalog.
    //
    // So this reads the SOURCE. Entries whose whole purpose is to be the words
    // on a specific surface must appear somewhere other than their own
    // definition. Deliberately narrow — it names the strings whose absence was
    // an actual defect, rather than asserting every catalog entry is used,
    // because a catalogue entry can be correctly unused while its feature is
    // deferred.
    //
    // The three that used to be named here as examples — `keepHint` (W10
    // keepsakes), `skyNoticed` (W15 onboarding) and `roadFaded` — have since
    // been deleted by a dead-code sweep. Two were deferred rather than
    // abandoned, so their one line each is recoverable from git if those
    // features arrive; `roadFaded` is gone for good, because W08 replaced the
    // road's fading with settling and the road no longer fades at all.
    //
    // ONE KNOWN HOLE, worth naming rather than leaving to be rediscovered:
    // this test cannot tell the two navigations apart. `fortuneDismissHint`
    // below is satisfied by a call site in `FortuneCard`, which only the
    // classic `VESPER_CLASSIC_NAV` build constructs — so a string that no
    // player of the shipping build can ever see still counts as wired.
    func testTheStringsWrittenForASurfaceAreActuallyOnIt() throws {
        let mustBeWired = [
            "fieldIsQuiet",
            "again",
            "fortuneDismissHint",
            "fieldDirectTouchHint",
            "popPoints",
        ]
        let sources = try Self.appSwiftFiles()

        for name in mustBeWired {
            var callSites = 0
            for url in sources {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let isCatalog = url.lastPathComponent == "Strings.swift"
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    guard line.contains("Strings.\(name)") else { continue }
                    // The definition itself, and prose about it, are not uses.
                    if isCatalog { continue }
                    if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                    callSites += 1
                }
            }
            XCTAssertGreaterThan(callSites, 0,
                                 "`Strings.\(name)` is catalogued for a surface and used nowhere — "
                                 + "the words exist and the view still says the old ones (R-CRAFT J1)")
        }
    }
}