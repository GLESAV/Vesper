// The string catalog for the One World surfaces (07 §5 asks for one catalog;
// DELIVERY_ROADMAP ruling 14 scopes *this* build to a slice of it).
//
// WHY it is only a slice: the field, sky and journal views are being rebuilt
// right now, so a repo-wide literal migration would be a merge war against
// three concurrent view rewrites for zero playtest value. What could not wait
// is the counter label — `DETONATED` never reaches the owner's hands — plus the
// wayfinding whispers and the new world strings the rebuilt surfaces need. The
// remaining literals (Cards, JourneySheet, PathSheet, SettingsSheet, anything
// carrying an interpolated count) migrate here once the views are structurally
// stable. Nothing below is interpolated on purpose: a format string is a copy
// decision that should land with the surface that owns it.
//
// Rules that hold for every entry here:
//   · verbatim, casing included — casing drift is a bug (07 §2)
//   · lowercase-calm, kind, brief; never exclamatory; the whisper register
//     observes and never instructs
//   · the forbidden vocabulary of 07 §2 appears nowhere — StringsTests fails
//     the build if it ever does
//
// Consumers must reference these constants, not re-type the literals; that is
// what keeps the catalog the single source of truth.
//
// ADDING A STRING: add the `static let`, then add it to `allStrings`. The
// source-scan test in StringsTests catches the second step if you forget it.
enum Strings {

    // MARK: - The field

    /// The counter's label. Names what the number counts without scoring it.
    static let setFreeLabel = "set free"
    /// Onboarding's only instruction — the one earned imperative pair.
    static let firstHint = "tap an orb. let it go."
    /// The invitation after a field is clear. A question she may ignore.
    static let again = "again?"
    /// Shown once ever, when keeping a fortune first becomes possible.
    static let keepHint = "press and hold, to keep a thing"

    // MARK: - Wayfinding whispers

    static let skyWhisper = "the sky"
    static let journalWhisper = "your journal"
    static let fieldWhisper = "the field"

    // MARK: - The world speaking

    /// The done card's chrome. The field went quiet; nothing is claimed about her.
    static let fieldIsQuiet = "the field is quiet now."
    /// A stone the path let go of, said without loss framing.
    static let roadFaded = "the road behind folded itself away."
    /// The sky's acknowledgement of an arrival. It observes; it does not congratulate.
    static let skyNoticed = "the sky noticed."
    /// The fortune card's dismissal hint — clear register, so it says plainly what a tap does.
    static let fortuneDismissHint = "tap to let it go"

    // MARK: - The journal's quiet things

    static let quietThings = "the quiet things"
    static let sound = "sound"
    static let haptics = "haptics"
    static let pointWhispers = "point whispers"
    /// Silences sound and haptics together. One word that does what it says.
    static let hush = "hush"
    /// The row. The confirm question below is a separate string on purpose.
    static let beginAgain = "begin this field again"
    /// Destructive-adjacent, so it is unambiguous about scope and carries no loss language.
    static let beginAgainConfirm = "begin this field again?"

    // MARK: - Accessibility

    static let skyA11y = "the sky, the path of stones"
    static let journalA11y = "your journal"
    static let fieldA11y = "the field"
    /// VoiceOver reading of the counter, which is otherwise a bare number.
    static let setFreeA11y = "orbs set free"

    // MARK: - The whole catalog

    /// Every string above, so the guardrail test can enumerate the catalog
    /// rather than the entries someone remembered to list. Order is the order
    /// they are declared in, which keeps diffs readable.
    static let allStrings: [String] = [
        setFreeLabel,
        firstHint,
        again,
        keepHint,
        skyWhisper,
        journalWhisper,
        fieldWhisper,
        fieldIsQuiet,
        roadFaded,
        skyNoticed,
        fortuneDismissHint,
        quietThings,
        sound,
        haptics,
        pointWhispers,
        hush,
        beginAgain,
        beginAgainConfirm,
        skyA11y,
        journalA11y,
        fieldA11y,
        setFreeA11y
    ]

    /// Catalog entries that legitimately begin with a capital letter because a
    /// proper noun starts them (07 §2: everything else is lowercase, and
    /// fortunes — the sentence-case exception — live in `Fortunes`, not here).
    /// Empty today; kept so the casing test states the exception explicitly
    /// instead of someone weakening the assertion later.
    static let properNounInitials: Set<String> = []
}
