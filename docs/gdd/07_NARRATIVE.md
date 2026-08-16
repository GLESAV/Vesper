# Vesper — Narrative & Writing Bible

*Vesper has no plot, but it has a world and a voice — and for this audience the
voice is a core feature, not garnish.*

## 1. The world (canon)

The game takes place in **the held evening** — the moment after sunset,
lasting as long as you need it to. Canon objects: the field (the air where
**small lights** drift as orbs), the sky (where your path is written in first
stars), the journal (a kept book on a windowsill), the lamp (lit when you
visit), fortunes (small truths orbs were carrying), Vesper itself — the
evening star — and its other name, **Morning Star** (pop #100): the promise
that the evening always ends kindly.

**The canonical metaphor is small lights, not worries.** The player may bring
whatever she brings; the game never names it for her. Copy never diagnoses or
describes her inner state — no "your worries", "your anxieties", "your
stress" — the lights are just lights, and setting one free means whatever she
decides it means. (What copy *may* do with heavy frames is defined by the
frame rule in §2.)

Nothing in canon is mystical or religious; it is domestic and cosmic at once —
a kitchen-window view of the universe. Two names carry that claim on their
backs and get verified rather than assumed: see the connotation check in §4.

## 2. The voice

**A wise, warm friend at dusk.** Lowercase-calm, brief, kind, a little wry,
never saccharine, never exclamatory.

### Two registers

All product writing lives in exactly one of two registers. Every string in the
§5 inventory is tagged with its register.

- **Whisper** — world and fortune copy: wayfinding whispers, fortune cards,
  arrival notes, anything spoken *by the world*. This register observes, never
  instructs ("the sky noticed.", never "Check out the Sky Map!"). The
  "never instructive" rule applies **here** — to the world's own voice.
- **Clear** — functional copy: confirmations, toggles, counters, onboarding's
  one teaching line, system-adjacent strings. This register is allowed to say
  plainly what will happen — clarity *is* kindness when she's about to act —
  while staying lowercase, brief, and calm. A functional string that hides its
  meaning behind poetry has failed, not succeeded.

Worked examples — the five highest-traffic functional strings, quoted
verbatim, with the register reasoning:

| String | Register | Why it's written this way |
|---|---|---|
| `tap an orb. let it go.` | clear | onboarding's only instruction; the one earned imperative pair. plain verb, no coaxing, done in six words. |
| `set free` | clear | the counter's label. names what the number counts without scoring it — "cleared: 12" is forbidden framing, "set free" is plain and kind at once. |
| `hush` | clear | one word that does what it says (silences sound + haptics together). a poetic alternative ("let the evening be quiet?") would slow the one control that must be instant. |
| `again?` | clear | the invitation after a clear. one word, zero pressure — states the available act as a question she may ignore. |
| `begin this field again?` | clear | a destructive-adjacent confirm, so it must be unambiguous about scope ("this field") while carrying no loss language. plain question, plain tap to confirm. |

### Voice rules (both registers)

| Rule | Yes | No |
|---|---|---|
| Address gently, rarely | "you're allowed to enjoy something this small." | "You did it!!! 🎉" |
| Observe, don't command (whisper register) | "the sky noticed." | "Check out the Sky Map!" |
| Kind, not clinical | "set free" | "DETONATED", "destroyed", "cleared: 12" |
| Wry is welcome | "the sky has seen worse. it's not worried." | sarcasm at the player's expense |
| Never urgency | "again?" | "Don't stop now!" |
| Never loss-framing | "the road behind folded itself away." | "Your path expired." |
| Never diagnose the player | "some lights take longer. that's allowed." | "let go of your anxiety" |

### Casing (canon)

- **All UI and whisper copy is lowercase.** No exceptions in navigation,
  settings, cards' chrome, or the App Store listing body.
- **Fortunes are sentence-case — a stated, canonical exception.** A fortune is
  a friend's handwriting, not interface; the register contrast is the visible
  signature that a fortune is *from* someone. The 18 shipped fortunes stand as
  written.
- Every string is recorded **verbatim, including casing,** in the §5 catalog;
  casing drift is a bug.

### Forbidden vocabulary

Forbidden anywhere in the product: streak, fail, miss, expire, lose/lost,
blast, destroy, kill, score (as a noun), limited, hurry, last chance.

**The twee/wellness extension** — equally forbidden: self-care, wellness,
mindful/mindfulness, gratitude (as an instruction), manifest, journey (as
marketing), treat yourself, you deserve this, zen, vibes, cozy (as a label for
itself), and any decorative emoji in product copy. Vesper is not a wellness
product and must never sound like one; the moment it tells her it's relaxing,
it isn't.

**The rule bans frames, not tokens.** A listed word may appear when the frame
is not applied *to the player*. The worked allowed case is the shipped
fortune "Nobody's keeping score. Not even the sky." — "score" appears
precisely to release her from it. The test is: does the sentence attach the
forbidden frame to her state or her performance? If yes, it's out; if the
sentence exists to dissolve that frame, it may stand. The CI grep (§5) flags
every token hit; a flagged string ships only with the copy owner's explicit
frame-rule sign-off recorded in the catalog.

## 3. Fortunes (the flagship writing)

For the reader in this audience, fortunes are the game (03 §The fortune
system holds the delivery mechanics: seeded per-player order, no repeats
until the pool is exhausted, one guaranteed-new fortune per evening, the
"things the sky told me" journal archive, and the spoiler policy keeping
secret-pop fortunes unseen until their pop is met). This section owns the
writing.

**Craft rules:** one sentence · ≤ 12 words ideally · sentence-case (§2) ·
concrete over abstract · lands like a friend's aside, not a fortune cookie ·
no imperatives ("breathe" earns its one exception) · reward re-reading ·
never diagnose the player (§1's small-lights rule applies to fortunes above
all).

**The sensitivity gate:** every fortune — the 18 shipped ones included — is
read against a player holding a real and serious worry tonight. A line that
reads as dismissive, glib, or minimizing from inside that evening is
rewritten or cut. The shipped 18 go through this gate during the Phase 0
warmth pass; every new batch goes through it before review.

**Authoring pipeline** (every batch):

1. Write against the rubric: the craft rules above, plus **three passing and
   three near-miss exemplars** kept with this document — the near-misses
   (too cute, too instructive, too fortune-cookie) teach the line better than
   the passes do. Exemplars are themed by phase of the evening (dusk →
   deep night → toward morning) so batches keep the corpus's arc.
2. **Dedup rule:** no two fortunes share an image or a closing move.
3. **Read-aloud batch check:** the whole batch spoken at 1 a.m. in an empty
   kitchen; a fortune that sounds wrong spoken is wrong.
4. **Two-person review**, one reviewer a target-audience reader — the writer
   never solo-approves her own batch.
5. Sensitivity gate (above), then verbatim entry into the §5 catalog.

**Corpus:** launch (v2.0) at **60+ fortunes**, up from the shipped 18 — a
daily player exhausts 18 in about two weeks, and a repeat is the moment the
collection magic dies. The 42+ new fortunes are real editorial work, not a
side effect: the writing sessions are budgeted as named Phase 2 content work
in 08. After launch, each arrival adds a themed set (03 §Content); secret
pops carry one unique fortune each.

## 4. Naming

- Pops: short, concrete, dusk-adjacent nouns (existing catalog is canon).
- Places: always lowercase in-world: `the sky`, `the field`, `your journal`.
- Features never get marketing names in-product (no "Pop Pass", ever).
- **Connotation check (Phase 2, before content lock):** two names carry
  risk the canon's "nothing mystical or religious" claim doesn't settle by
  assertion — **"Morning Star"** (pop #100) has strong religious readings in
  parts of this demographic, and **"fortune"** can read as divination. Both
  run through a connotation check with **10–15 target-audience
  participants** (shown in context, asked what the word suggests). Pass:
  no participant reads either as religious/occult in a way that would put
  them off. If either flags, the in-world alternatives are already canon-
  compatible and adopted without debate: **"first light"** for Morning Star,
  **"small truths"** for fortunes.

## 5. String inventory & process

**One copy owner.** Every user-facing string in the product has a single
owner (Kate) who signs off on additions and changes. No string ships
un-reviewed — including strings written by an AI pair; those enter the
catalog only through the same sign-off.

**One catalog.** All strings live in a single centralized string catalog in
the codebase — quoted **verbatim**, casing included — tagged with surface and
register. The catalog is the single source of truth: 04 §13's canonical
navigation strings (`the sky` · `your journal` · `the field` · `set free` ·
`tap an orb. let it go.` · `again?` · `begin this field again?` · `hush` ·
`press and hold, to keep a thing` · `the road behind folded itself away.` ·
`the sky noticed.`) are owned here, and changes land here first, then flow to
the documents and the build.

**Self-enforcing guardrail.** CI runs a forbidden-vocabulary grep (the
string-registry test in 08's QA plan) over the catalog on every push — the
full §2 list, twee/wellness extension included. A hit fails the build unless
the catalog records a frame-rule sign-off for that string (§2). For a solo
dev working with an AI pair, the grep is what makes the voice rules survive
a tired Tuesday.

**The inventory.** Every surface, its register, its budget, and its sign-off:

| Surface | Register | Budget | Sign-off |
|---|---|---|---|
| Wayfinding whispers (field / sky / journal) | whisper | ≤ 3 words each | copy owner |
| Counter label + chain summaries (`set free`, `three more set free`) | clear | ≤ 4 words | copy owner |
| Onboarding lines (W1) | clear | 2 lines total, ≤ 8 words each | copy owner + fresh-tester read in Phase 0 exit test |
| Fortunes | whisper (sentence-case exception) | 1 sentence, ≤ 12 words | pipeline (§3): two-person review + sensitivity gate |
| Done card / fortune card chrome | whisper | ≤ 6 words | copy owner |
| Confirmations (`begin this field again?`, `again?`) | clear | one plain question | copy owner |
| Journal rows & quiet things (settings) | clear | ≤ 4 words per row | copy owner |
| Discovery whispers (one-time teaches) | clear | ≤ 7 words, shown once ever | copy owner |
| Arrival notes (in-journal) | whisper | ≤ 2 sentences | copy owner |
| Share card text | whisper | fortune verbatim; opt-in count label only (03 §3) | copy owner + pillar check (no comparable numbers) |
| Accessibility labels (VoiceOver) | clear | plain, lowercase, unambiguous | copy owner + VoiceOver pass (04 §10) |
| App Store listing (title, subtitle, description, keywords) | whisper (body) / clear (metadata) | per App Store limits | copy owner; no health-adjacent claims, "anxiety" appears on no owned surface (09) |

**The voice test, kept:** every string still lives through it — read aloud at
1 a.m. in an empty kitchen; if it sounds like software, rewrite it. The v2
warmth pass (04 §4 canonical strings, plus the sensitivity gate over the 18
shipped fortunes) is Phase 0 work and includes the App Store listing, which
already carries the voice well.

## 6. Localization (canon)

**v2.0 ships English-only.** This is decided, not deferred: the voice is the
product, and a voice this specific does not survive vendor translation. Not
choosing would mean a vendor chooses later, and the voice dies quietly.

For any future locale, the policy is **per-locale transcreation**, never
translation:

- A **native writer** transcreates the corpus — fortunes are rewritten as
  fortunes, not converted.
- Each locale gets its **own voice guide and its own forbidden-vocabulary
  list** (the frames that are forbidden, rediscovered in that language — the
  English token list does not map).
- Acceptance is that locale's **1 a.m.-kitchen voice test**, run by a native
  speaker: if it sounds like software — or like translated English — it does
  not ship.
- Each locale ships as **its own gated post-2.0 arrival**, one at a time,
  gated by native-speaker voice review. Phase 3 delivers only the plumbing:
  string-catalog extraction and per-language voice briefs.
