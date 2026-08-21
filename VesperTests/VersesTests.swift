import XCTest
@testable import Vesper

// The line under "the field is quiet now."
//
// These are original, unattributed, and written for the game. The tests below
// are mostly about the VOICE, because that is the thing that decays first when
// a set like this is added to: one line that instructs her, and the whole
// surface changes character.
final class VersesTests: XCTestCase {

    func testThereAreEnoughVersesToNotRepeatForAVeryLongTime() {
        XCTAssertGreaterThanOrEqual(Verses.all.count, 150,
                                    "too few to stay fresh across a season of evenings")
    }

    func testNoVerseIsRepeated() {
        XCTAssertEqual(Set(Verses.all).count, Verses.all.count, "a duplicate verse")
    }

    // THE 1 A.M. KITCHEN TEST, mechanised as far as it can be. She has just
    // finished a quiet thing at the end of a long day; being told what to feel
    // about it is the one way this could go wrong.
    func testNoVerseInstructsHer() {
        // Second-person imperatives and self-help register.
        let forbidden = [
            "you should", "you must", "you need", "remember to", "don't forget",
            "be kind to yourself", "let go", "take a breath", "breathe",
            "you deserve", "treat yourself", "make sure", "try to",
        ]
        for verse in Verses.all {
            let lower = verse.lowercased()
            for phrase in forbidden {
                XCTAssertFalse(lower.contains(phrase),
                               "\"\(verse)\" instructs her — see the voice note in Verses")
            }
        }
    }

    // The catalog's forbidden vocabulary applies here too: nothing about
    // scores, streaks, failing, or hurrying belongs on a card that appears
    // when a field goes quiet.
    func testNoVerseUsesTheForbiddenVocabulary() {
        // Matched on WORD BOUNDARIES, the same discipline `StringsTests`
        // uses. A plain substring test fails "the pond has closed over" for
        // containing "lose", which is how a vocabulary guard stops being
        // trusted and starts being worked around.
        let stems = ["streak", "fail", "score", "hurry", "expire", "lose", "lost",
                     "miss", "blast", "destroy", "kill", "limited"]
        for verse in Verses.all {
            for stem in stems {
                let pattern = "\\b\(stem)[a-z]*\\b"
                let found = verse.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
                XCTAssertFalse(found, "\"\(verse)\" contains '\(stem)'")
            }
            XCTAssertFalse(verse.lowercased().contains("last chance"), verse)
        }
    }

    func testEveryVerseIsShortEnoughToReadAtAGlance() {
        for verse in Verses.all {
            XCTAssertFalse(verse.isEmpty)
            XCTAssertLessThanOrEqual(verse.count, 78,
                                     "\"\(verse)\" is too long for the card")
            XCTAssertTrue(verse.hasSuffix(".") || verse.hasSuffix("?"),
                          "\"\(verse)\" should end as a sentence")
            XCTAssertFalse(verse.contains("!"), "\"\(verse)\" raises its voice")
        }
    }

    // No byline, ever. Inventing lines is fine; inventing an attribution for
    // them is not, and a stray em dash at the end of a verse is how one would
    // sneak in.
    func testNoVerseCarriesAnAttribution() {
        for verse in Verses.all {
            XCTAssertFalse(verse.contains("—"), "\"\(verse)\" looks like it has a byline")
            XCTAssertFalse(verse.contains("--"), "\"\(verse)\" looks like it has a byline")
        }
    }

    // MARK: - The deck

    func testTheDeckDealsEveryVerseBeforeRepeatingAny() {
        var deck = Verses.Deck()
        var seen: [String] = []
        for _ in 0..<Verses.all.count { seen.append(deck.next()) }
        XCTAssertEqual(Set(seen).count, Verses.all.count,
                       "a verse repeated before the set was exhausted")
        XCTAssertEqual(Set(seen), Set(Verses.all))
    }

    func testTheDeckKeepsDealingOnceExhausted() {
        var deck = Verses.Deck()
        for _ in 0..<(Verses.all.count * 2 + 5) {
            XCTAssertFalse(deck.next().isEmpty, "the deck ran dry")
        }
    }
}
