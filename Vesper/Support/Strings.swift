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

    /// The hints on the two whispers that lead away from the field. Clear
    /// register, like every hint here: a hint is read after the label, once
    /// she has already chosen to listen, so it says plainly what a tap does —
    /// and it names the direction, because the world's one axis is the thing
    /// the wayfinding is teaching. `WhisperLabel.hint` is non-optional on
    /// purpose (a whisper that ships without one is a review failure), so
    /// these are required rather than decorative.
    static let skyWhisperHint = "goes up to the sky"
    static let journalWhisperHint = "goes down to your journal"

    // MARK: - The world speaking

    /// The done card's chrome. The field went quiet; nothing is claimed about her.
    static let fieldIsQuiet = "the field is quiet now."
    /// A stone the path let go of, said without loss framing.
    static let roadFaded = "the road behind folded itself away."
    /// The sky's acknowledgement of an arrival. It observes; it does not congratulate.
    static let skyNoticed = "the sky noticed."
    /// The fortune card's dismissal hint — clear register, so it says plainly what a tap does.
    static let fortuneDismissHint = "tap to let it go"

    // MARK: - The sky

    /// A star's state when it is the stone she is standing on.
    static let starHere = "you are here"
    /// A star whose field she has already cleared. Kept, never spent — the
    /// sky's whole claim is that history only accrues (docs/pop_map.md).
    static let starWalked = "walked"
    /// A star that exists and is playable, and that she simply has not
    /// cleared yet. Stated as fact, with nothing owed.
    static let starUnwalked = "not yet walked"
    /// What activating a star does, said plainly rather than invitingly: a
    /// hint is read after the label, when she has already chosen to listen.
    static let starHint = "steps onto this stone"
    /// The hint on the `the field` whisper — the way home from a place that
    /// is not the field. Same act as the swipe.
    static let fieldWhisperHint = "returns to the field"

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

    // MARK: - The journal's pages

    /// Page one. Names the hour, never the date — the journal has no calendar.
    static let theEvening = "the evening"
    /// Page two.
    static let theCollection = "the collection"
    /// VoiceOver custom actions for turning a page, in the book's own voice.
    static let nextPage = "the next page"
    static let previousPage = "the page before"
    /// The hint on a page name in the journal's foot ribbon.
    static let pageHint = "turns to this page"

    // MARK: - The evening page

    static let popPoints = "pop points"
    /// Record labels. `set free` is `setFreeLabel`, reused rather than retyped.
    static let fieldsRecord = "fields"
    static let fortunesRecord = "fortunes"
    static let bestChainRecord = "best chain"

    // MARK: - The collection page

    /// Joins the two halves of "23 of 100". Its own entry so the count line is
    /// assembled from catalog words rather than an inline literal.
    static let collectionOf = "of"
    static let drift = "drift"
    static let driftDetail = "every field mixes all the pops you've found"
    static let driftHint = "paints every field from your whole collection"
    static let featureHint = "paints every field with this pop"
    /// Read as the VoiceOver value of the pop a field is currently painted from.
    static let featuredNow = "featured now"
    /// A pop not met yet, in place of its name. Not a lock, not a wall.
    static let lockedPopName = "· · ·"
    /// A secret keeps its shape until she finds it.
    static let secretPopMark = "?"
    static let lockedPopA11y = "a pop you haven't met yet"
    /// Follows a count: "41 pops so far".
    static let popsSoFar = "pops so far"

    // MARK: - The quiet things, in full

    static let hushDetail = "sound and haptics, together"
    static let hushHint = "turns sound and haptics off"
    /// What `hush` becomes once it has been used — so the row never lies about
    /// what a tap will do.
    static let itIsQuiet = "it is quiet"
    static let unhushHint = "brings sound and haptics back"
    static let soundDetail = "soft pops and a chime"
    static let hapticsDetail = "a gentle tap with every pop"
    static let pointWhispersDetail = "little points that drift up from a pop"
    static let beginAgainDetail = "a new field, whenever you like"
    static let beginAgainHint = "seeds this field again"
    /// The way out of the armed state, as a plain row of its own. A timed
    /// disarm would exclude Switch Control users exactly the way a timed hold
    /// does (04 §6), so leaving is a tap, like arriving was.
    static let notNow = "not now"
    /// The whole of what the journal says about the app. A proper noun starts
    /// it, so it is registered in `properNounInitials` below.
    static let about = "Vesper · made by Kate Wu · collects nothing"

    // MARK: - Accessibility

    static let skyA11y = "the sky, the path of stones"
    static let journalA11y = "your journal, the pages you keep"
    static let fieldA11y = "the field, where the orbs drift"
    // The field is a drawn surface, not a list of controls: with VoiceOver on
    // it is entered directly and the touch itself is the pop (R-A11Y B1). The
    // hint has to say so, because "double-tap to activate" — the thing a
    // VoiceOver user would otherwise reasonably assume — is exactly not how
    // this works.
    static let fieldDirectTouchHint = "touch the orbs directly to let them go"
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
        skyWhisperHint,
        journalWhisperHint,
        fieldIsQuiet,
        roadFaded,
        skyNoticed,
        fortuneDismissHint,
        starHere,
        starWalked,
        starUnwalked,
        starHint,
        fieldWhisperHint,
        quietThings,
        sound,
        haptics,
        pointWhispers,
        hush,
        beginAgain,
        beginAgainConfirm,
        theEvening,
        theCollection,
        nextPage,
        previousPage,
        pageHint,
        popPoints,
        fieldsRecord,
        fortunesRecord,
        bestChainRecord,
        collectionOf,
        drift,
        driftDetail,
        driftHint,
        featureHint,
        featuredNow,
        lockedPopName,
        secretPopMark,
        lockedPopA11y,
        popsSoFar,
        hushDetail,
        hushHint,
        itIsQuiet,
        unhushHint,
        soundDetail,
        hapticsDetail,
        pointWhispersDetail,
        beginAgainDetail,
        beginAgainHint,
        notNow,
        about,
        skyA11y,
        journalA11y,
        fieldA11y,
        fieldDirectTouchHint,
        setFreeA11y
    ]

    /// Catalog entries that legitimately begin with a capital letter because a
    /// proper noun starts them (07 §2: everything else is lowercase, and
    /// fortunes — the sentence-case exception — live in `Fortunes`, not here).
    /// Empty today; kept so the casing test states the exception explicitly
    /// instead of someone weakening the assertion later.
    static let properNounInitials: Set<String> = [about]
}
