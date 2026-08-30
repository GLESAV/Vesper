# Release cut feedback — 2026-08-29

**Cut:** `main` @ `caf10bd` ("A QA swarm: eleven new test suites, six production
defects, and the docs made true (#12)")
**Built:** Release, `-configuration Release`, `CODE_SIGNING_ALLOWED=NO` — **succeeded**
**Tests:** `xcodebuild test` — **631 executed, 1 skipped, 0 failures**, 35 files, 23.5 s
**Device:** iOS Simulator, iPhone 16 Pro on **iOS 26.5** (see E1 — the named device
was not available on any runtime the app can install to)
**Method:** fresh install (brand-new simulator, nothing to delete), driven with
synthetic touches + screenshots. Everything a finger, a haptic engine, a 120 Hz
panel or a screen reader is needed for is listed under "Not tested".

Two kinds of item, kept apart on purpose. **F** items are things that are wrong
against the spec, the build or the release. **R** items are things the owner
asked for during the pass — requests and tuning, not defects. Each carries the
one thing that makes it actionable: where it lives.

Nothing in this document has been changed in the code. Every item names its
file, line and constant so the change can be made deliberately, and
`CLAUDE.md`'s rule stands: **gameplay constants move one at a time.**

## What's in here

| | Item | Severity | Lives in |
|---|---|---|---|
| **F1** | First-run hint returns on every new field | Major — spec violation | `WorldView.swift:825`, `GameViewModel.swift:228` |
| **F2** | Checklist §XV stale on two counts | Docs | the walkthrough artifact |
| **F3** | Nothing local can test the iOS 18.5 floor | Major — coverage gap | simulator runtimes |
| **F4** | Unused-result warning in `ribbonTraits` | Minor — hygiene | `JournalView.swift:560` |
| **F5** | Version/build numbers still v1.2's | Blocker for submission | `project.pbxproj` |
| **R1** | Rise to the sky after a clear | Verify — likely already built | `GameConfig.onwardToSkyDelay` |
| **R2** | A pointer to the next suggested stone | New work | `SkyView.swift:503` |
| **R3** | Piercing fireworks | New work — largest | `GameSimulation.swift:929`, `:334` |
| **R4** | Chain too intensive | Tuning — one knob | `GameConfig.ringDisarmFraction` |
| **R5** | Visible dark edge at the sky/field join | Polish — one knob | `HorizonRenderer.swift:132` |
| **R6** | More fireworks | Tuning — one knob | `FieldPlan.swift:222` |
| **R7** | **Pops are not unique enough** | **Major** | `PopCatalog.swift` — an authoring gap |
| **R8** | **Weather too soft / not interesting** | **Major** | `Weather.swift:225`, `:147` |

**If only three things are done:** R7 (the 100-pop collection does not currently
read as 100 things), R8's odds line (a headline feature is invisible half the
time), and F5 (the build cannot ship on v1.2's numbers).

---

## F1 — The first-run hint returns on every new field

**Severity:** Major (spec violation) · **Area:** §I, the core loop

The committed spec says the hint is shown once, ever:

> `docs/e2e_walkthrough.md:30` — *"Foot of the screen: 'tap an orb. let it go.'
> — disappears after the first pop, never returns."*

It returns at the start of **every** field: after every clear, after every
"again?", and after every star tap.

**Where:**
- `Vesper/World/WorldView.swift:825` — the hint renders on `if !game.started`
- `Vesper/Game/GameViewModel.swift:228` — `restart()` sets `started = false`

`started` is per-field session state, but the copy it gates is written as a
lifetime, once-only instruction.

**Evidence:** observed mid-session on a freshly seeded field after 7 cleared
fields and 121 lifetime pops, counter back at 0 and the hint present.

**Action — one of two, and it is a product call, not a code call:**
- **(a) Make the hint lifetime-once.** Gate on a persisted flag in
  `ProgressionStore` (`lifetimePops > 0`) rather than on `game.started`. Matches
  the spec as written. Costs one `UserDefaults` read.
- **(b) Amend the spec.** If a per-field re-offer is intended — it is a calm,
  affirming line, and re-showing it breaks no guardrail — change
  `docs/e2e_walkthrough.md:30` and the §I checklist item to say "disappears
  after the first pop of each field."

**Owner decision:** which of (a)/(b). Recommend (a): "never returns" reads as a
deliberate promise, and a returning instruction quietly implies she forgot how
to play.

---

## F2 — The walkthrough checklist's §XV is stale on two counts

**Severity:** Docs · **Area:** §XV, accepted rough edges

The checklist still lists as an accepted rough edge:

> *"The sky's deep backdrop redraws more than it needs to while scrolling —
> caching deferred deliberately."*

`caf10bd` fixed exactly this — it is the fourth bullet of this cut's own "what
is new" list. `SkyView.swift` now wraps the deep field in
`DeepFieldLayer: View, Equatable`, equatable on `size` alone, which is sound:
`SkyRenderer.drawDeepField` reads nothing but `size` and a constant seed, so
eliding an update cannot elide a change.

Same section also points readers at *"docs/e2e_walkthrough.md on PR #11"*; the
current cut is #12.

**Action:** delete the deep-backdrop bullet from §XV and retarget the PR
reference to #12. Both live in the checklist artifact
(`493bd3b9-df20-4e36-9751-e4c8e1972f37`), not in the repo.

---

## F3 — Nothing local can exercise the 18.5 deployment floor

**Severity:** Major (test coverage gap) · **Area:** release readiness

`IPHONEOS_DEPLOYMENT_TARGET` is **18.5**. Installed simulator runtimes are
**iOS 18.3** and **iOS 26.5** — nothing in between.

- 18.3 is *below* the floor: the app will not install there.
- 26.5 is eight minor versions above it.

So every check in this cut ran on an OS far newer than the minimum the App Store
listing promises to support. Any 18.x-only SwiftUI behaviour — hit-testing,
`TimelineView(paused:)`, `Canvas`, safe-area insets — is currently unverified,
and this is a submission-adjacent risk rather than a cosmetic one.

**Action:** install an iOS 18.5 (or 18.6) simulator runtime and re-run at
minimum §I, §III and §XI on it. Xcode → Settings → Components.

**Owner decision:** or consciously raise `IPHONEOS_DEPLOYMENT_TARGET` to a
version you can actually test against, and say so in `RELEASE_v1.3.md`.

---

## F4 — Build warning: unused result in `ribbonTraits`

**Severity:** Minor (hygiene) · **Area:** §XI, the journal

The Release build emits exactly one source warning:

```
Vesper/World/JournalView.swift:560:31: warning: result of call to 'insert' is unused
```

```swift
private func ribbonTraits(isCurrent: Bool) -> AccessibilityTraits {
    var traits: AccessibilityTraits = .isButton
    if isCurrent { traits.insert(.isSelected) }   // ← line 560
    return traits
}
```

Behaviourally harmless — `SetAlgebra.insert` mutates regardless, and VoiceOver
does receive `.isSelected` on the current page. It is noise in a build that is
otherwise clean, and noise is where real warnings go to hide.

**Action:** `_ = traits.insert(.isSelected)`, or
`traits.formUnion(.isSelected)`. One line.

---

## F5 — Version and build numbers are still v1.2's

**Severity:** Blocker for submission · **Area:** `RELEASE_v1.3.md` §2

Unchanged in `Vesper.xcodeproj/project.pbxproj` at this cut:

| Setting | Lines | Current |
|---|---|---|
| `MARKETING_VERSION` (Vesper, Debug + Release) | 342, 371 | `1.2` |
| `CURRENT_PROJECT_VERSION` (Vesper) | 328, 357 | `1` |
| `MARKETING_VERSION` (VesperTests) | 389, 408 | `1.0` |

`RELEASE_v1.3.md` marks this **🖐 owner's change — do not let an agent edit
`project.pbxproj`**, so this is recorded, not actioned.

**Owner decision (already open in `RELEASE_v1.3.md` §7):** 1.3 + build 2, or
2.0. Build must go to at least `2` either way — 1.2 shipped at build 1.

---

## R1 — After a clear, the world should rise to the sky on its own

**Severity:** Request — verify first, it may already be built · **Area:** §V, auto-onward

**Owner's note:** *"after completion, the screen should automatically scroll up to
view the sky."*

**This is already specified and already implemented.** It is §V of the
walkthrough, and the machinery is there:

| Step | Where | Timing |
|---|---|---|
| Done card is hers alone | `GameConfig.onwardToSkyDelay` | **3.4 s** |
| …then the world rises to the sky | `GameViewModel.swift:464-471` (`onwardWork = rise`) | |
| …then, with exactly one road on, it steps onto the next stone and carries her down | `GameConfig.onwardInSkyPause` → `GameViewModel.swift:495-496` | **+2.2 s** |

A fork deliberately **halts** in the sky with the roads lit, rather than
choosing for her.

**So the action here is to confirm, not to build.** I could not confirm it
behaviourally: every attempt was cancelled by my own harness, because §V says
*"any touch during the sequence cancels it for that field"* and a tap-driven
clear keeps tapping after the last orb pops. That cancel is correct behaviour —
but it means the rise itself is **unverified on this cut**.

**Action:** clear a field on device, then take your hands off the glass
completely. The world should lift to the sky at ~3.4 s.
- If it does rise — the request is already satisfied, and the open question is
  whether **3.4 s feels right**, which is a tuning call, not a code one.
- If it does not rise — that is a defect against §V, and the first place to look
  is `cancelOnward()`: `restart()` now calls it (new in `caf10bd`), so anything
  that triggers a restart on the way into the done card would kill the sequence
  before it starts.

---

## R2 — A pointer to the next suggested stone

**Severity:** Request — new work · **Area:** §IV, the sky

**Owner's note:** *"it should have some sort of cursor that points to the next
suggested level (to click)."*

**What exists today** is signage, but nothing on the stone itself:

- The road ahead is drawn in its own brighter tier — `SkyView.swift:67`
  (`case onward`), assigned at `:253`, painted at `:503` as
  `ink = accent; alpha = 0.30`.
- The HUD posts a line after a clear: *"the path continues"* / *"the path forks
  — N roads ahead"*.

So she is told *that* the path continues, and the road ahead is lit — but the
destination **star** carries no mark of its own. That is the gap the note is
pointing at.

**Two constraints any answer has to satisfy**, both from `CLAUDE.md`:

1. **Guardrail 1, affirming-only, no pressure.** A blinking arrow, a pulsing
   "GO HERE", or anything that reads as a prompt to hurry is out. The phrasing
   to test against is *more engaging, never more difficult* — and never more
   demanding.
2. **The One World pillar: no icons, no chrome.** A literal cursor or arrow
   glyph would be the first piece of UI furniture in a world that has
   deliberately none. It should be made of what the sky is already made of.

**Three options that stay inside the existing vocabulary**, cheapest first:

- **(a) Carry the onward tier onto the star.** The road is already brighter;
  give its destination star the same accent at a matching alpha. One value, in
  `SkyRenderer`'s star pass, next to the existing anchor-rim treatment. Least
  new vocabulary, least risk.
- **(b) Let the suggested star breathe.** Stars already breathe (and already
  stop under Reduce Motion). Give the onward star a slightly deeper, slower
  breath than its neighbours. Reads as invitation rather than instruction.
- **(c) A mote that walks the road.** A single drifting light travelling the
  onward road from the anchor to the next stone, once, slowly. The most
  beautiful and the most work; also the most likely to need a Reduce Motion
  answer.

**Recommendation:** (a) first, and look at it before building (b) or (c) — the
road is already lit, and the star inheriting that light may be the whole fix.

**Must not do:** pick a winner at a fork. §V halts in the sky with **both**
roads lit precisely so the choice stays hers; a "next suggested" marker that
resolves a fork would quietly undo that. At a fork, either mark both or mark
neither.

**Owner decision:** (a), (b) or (c) — and whether a fork gets two markers or
none.

---

## R3 — A launched firework should be piercing

**Severity:** Request — new work, and the largest of the three · **Area:** §X, fireworks

**Owner's note:** *"fireworks should pop bubbles as they move (after being shot
off); that is the firework should be 'piercing', counting as a 'user click' on
the items it touches; (including activating other fireworks)."*

**Today the climb touches nothing.** A shell lights, climbs for ~1 s, and only
the *break* affects the field — and it affects it with a **shove**, not a pop
(`GameSimulation.swift:1153`, `GameConfig.fireworkShove`). The climb is pure
spectacle.

### Where it goes

The clean insertion is the rising step, and the clean implementation is to reuse
the tap path rather than write a second one:

| Piece | Where |
|---|---|
| Shell enters the climb | `GameSimulation.swift:880` — `phase = .rising(progress: 0)` |
| Climb advances each frame | `GameSimulation.swift:929` — `phase = .rising(progress: next)` ← **sweep here** |
| What a touch already does to orbs *and* to fireworks | `GameSimulation.swift:334-356` — `tap(at:)` pops orbs, lights a waiting fuse, hurries a burning one |

Because `tap(at:)` already handles **both** orbs and fireworks, routing the
shell's swept path through the same code is what makes the request literally
true: it *is* a user click. Pops, chain rings, points, the counter, the
"chain of N" whisper and **lighting other shells** all follow for free, and the
sim stays the single source of truth — sound and haptics come along because they
already ride `GameEvent`.

### Four things that will bite

1. **Sweep the segment, not the point.** The climb crosses most of the field in
   ~1 s, so per-frame travel is comfortably larger than an orb. A point test at
   each frame will **tunnel straight through orbs**. Test the capsule from last
   position to this one against `orb.pos` + radius.
2. **Reduce Motion changes the outcome.** §X's own fixed item says that under
   Reduce Motion *"the shell climbs straight"*. If the path decides what gets
   pierced, then a **straight path pierces different orbs than a wobbling one** —
   an accessibility setting would silently change how many orbs pop and how many
   points accrue. Nothing is lost or compared, so no guardrail breaks, but the
   "same stone, same field every time" promise picks up an asterisk. **Decide
   deliberately:** either accept it, or make the collision path the straight one
   in both modes and let only the *drawn* path wobble.
3. **The audio limiter stops being optional.** §XV already accepts that *"huge
   chains can in principle sum loud (no limiter)"*. A shell piercing a dense
   field is precisely the huge-chain generator that assumption was written
   before. This likely becomes a **prerequisite**, not a pending tuning pass.
4. **The particle cap will be hit harder.** `burst()` already trims to
   `GameConfig.particleCap` with `removeFirst` (`GameSimulation.swift:1078`). A
   pierce cascade *plus* a break in the same frame will trim more aggressively,
   and `removeFirst` eats the oldest particles — visible as effects vanishing
   mid-life rather than fading.

### Guardrail check

**It passes, and comfortably.** It makes the field shorter and more spectacular,
never harder — *more engaging, never more difficult*. Nothing is lost, spent or
failed, and an unlit shell still gates nothing.

**Cascades terminate.** A field carries 2–6 shells and each lights once, so
shell-lights-shell is bounded by the shell count. No loop guard needed, though
a lit shell must not be re-lightable by a later pierce.

**One arithmetic knock-on:** the break currently raises **3 orbs from the
reserve** so that *"a display never lengthens the field"* (§X). Piercing now
*shortens* it on the way up. That is the right direction, but the reserve rule
was tuned against a climb that touched nothing — revisit whether 3 is still the
number.

**Owner decision:** the Reduce Motion question in (2) — same path for both, or
accept a different outcome per setting.

---

## R4 — The chain is too intensive; she doesn't get to pop enough

**Severity:** Request — tuning · **Area:** §I, the core loop

**Owner's note:** *"the chain of popping is too intensive (i don't get to pop as
much as i like)."*

### What actually happens

**Chains are already only one generation deep.** A direct pop's *first* ring
arms; every other ring is decoration — `GameSimulation.swift:448-449`:

> *"Only the first ring of a direct pop arms further chains; echo rings —
> extras, and any ring from a chained pop — are visual only."*

So the complaint is **not** a runaway cascade. It is **reach**: one ring is
sweeping too much of the field. The knobs are all in `GameConfig.swift`:

| Constant | Value | What it does |
|---|---|---|
| `ringBaseMaxRadius` | `110` | Base reach of the shockwave |
| `ringRadiusPerOrbRadius` | `2.6` | Bigger orb → bigger ring |
| `ringArmRadius` | `18` | Ring must exceed this before it can catch anything |
| `ringShellThickness` | `24` | Only orbs inside this moving band are caught |
| `ringDisarmFraction` | `0.5` | The ring stops catching after **half** its growth |

A large orb therefore reaches roughly `0.5 × (110 + 2.6 × r)` ≈ **100 pt** — a
quarter of the screen's width, on a field that at stage 5–6 is dense.

### The one knob to turn first

`CLAUDE.md` says tuning is sacred and changes go **one at a time**. The best
first move is **`ringDisarmFraction`, 0.5 → ~0.38**, because it is the only knob
that **shrinks what the ring catches without changing what the ring looks
like**. The shockwave still blooms to exactly the same size and the pop still
feels as big; it simply stops recruiting sooner. Everything else on that list
makes the visual smaller too, which costs the feel she is not complaining about.

If that is not enough, `ringBaseMaxRadius` (110 → ~95) is second. Leave
`ringRadiusPerOrbRadius` alone longest: `GameConfig.swift:311` notes that a
bigger ring is an *unlock reward* — *"both only ever help"* — so flattening the
big-orb advantage quietly weakens a progression promise.

### A caution about my own numbers

This session recorded a **best chain of 58**, and it would be easy to read that
as proof. **It is not.** `chainStreak` counts *pops inside a 0.9 s window*
(`GameViewModel.swift:533-540`, `GameConfig.chainWindow`), not cascade depth — so
my tap harness firing many taps per second inflated it. Treat 58 as an artefact
of the robot, not evidence. **Your hands are the evidence here.**

**Owner decision:** confirm the direction on device after the `ringDisarmFraction`
change, and whether the chain-of-N whisper should still fire as readily once
chains are shorter (`chainNoteThreshold = 3`).

---

## R5 — The sky/field join has a visible dark edge

**Severity:** Request — polish · **Area:** §III, one world

**Owner's note:** *"the border between the sky and the game place has noticeable
darkness (can we make it one continuous)."*

**Confirmed — I saw it in every field screenshot this session:** a crisp
horizontal line about **216 pt** down the screen, lighter above, darker below.
That is exactly `0.25 × 874`, i.e. the join where the peeking sky place's
rectangle ends and the field's begins. Neighbours peeking is by design (§III,
0.75 screens apart); the hard *edge* between them is not.

### Why it shows

`HorizonRenderer.swift` exists precisely to hide this join — its own header
calls it *"the seamless answer"*. The glow's strength varies along the axis, and
here is the problem (`HorizonRenderer.swift:132-137`):

```
static let fieldPresence: Double = 0.5
static let skyPresence:   Double = 1.0
```

The light **rises to full toward the sky and sits at half at the field**. So the
join is least concealed exactly where she stands for the whole game, and fully
concealed only while travelling to a place she visits between fields. The
covering cue is weakest where it is needed most.

### Knobs, cheapest first

| Constant | Value | Effect |
|---|---|---|
| `fieldPresence` | `0.5` | **Raise toward `skyPresence`.** The single most direct fix — no new drawing, just more of the glow that already exists, at rest. |
| `lightPeak` | `0.055` | Overall glow strength; lifts the whole cue, sky included. |
| `luminanceCap` | `0.12` | Hard clamp — raising `fieldPresence` may run into this. |
| `depthFloor` / `depthCeiling` | `0.12` / `0.40` | How deep the blend band is. A deeper band spreads the join over more pixels. |

**Try `fieldPresence` first**, alone, and check `luminanceCap` is not clipping
the result before reaching for anything else.

**Watch out for:** the ground colours themselves differ per place (charcoal /
blue-black / warm brown-black, §III). If the two grounds are far enough apart in
value, no amount of glow will fully hide the join and the real fix is bringing
the sky's and field's ground stops closer at the seam. Check that before
spending effort on the glow.

**Do not** simply darken the sky's ground to match — the ground crossfade is a
travel cue in its own right (§III), and flattening it would cost the sense of
moving between places.

---

## R6 — More fireworks

**Severity:** Request — tuning · **Area:** §X, fireworks

**Owner's note:** *"more fireworks please."*

There are **two independent levers**, and they answer different complaints.

### Lever 1 — how often a field has any (frequency)

`FieldPlan.swift:214-215`:

```swift
guard stage >= 2 else { return false }
return (generation + stage) % 2 == 1
```

Displays land on **alternating stones**, and the *other* alternating stones carry
the balloon animal. So today it is display, creature, display, creature.

**This lever is the expensive one to pull.** `FieldPlan.swift:228-236` is
explicit that the alternation is doing three jobs: it keeps neither spectacle
ordinary, it is a function of the stone (so a stone is the same field every time
she returns), and it guarantees a display and an animal never share a field —
because *"a shy animal keeping to the edges while shells go up in the middle is
two things asking for the same attention, and a firework's shove would be pushing
the one orb that is trying to stay put."*

Raising frequency therefore costs animal frequency one-for-one, unless you accept
the two sharing a field — which that comment argues against, and which R3's
piercing shells would make worse (a shell that pops what it touches would hunt
the animal).

### Lever 2 — how many shells per display (density)

`FieldPlan.swift:220-223`:

```swift
return min(GameConfig.maxFireworksPerField, 2 + generation / 3)
```

So **2 shells**, gaining one every 3 generations, capped by
`GameConfig.maxFireworksPerField`. The cap's comment says it exists *"so a field
never becomes a firing range."*

**Pull this one first.** `2 + generation / 3` → `2 + generation / 2` gets more
shells on screen sooner without touching the alternation, the animal's share, or
the same-stone-same-field promise. Then raise `maxFireworksPerField` if the cap
binds before it feels right.

**Owner decision:** is the wish *"more shells when I get a display"* (Lever 2 —
cheap, no side effects) or *"displays more often"* (Lever 1 — comes straight out
of the balloon animals' budget)? **My read is Lever 2**, and it is worth trying
alone before touching the alternation.

---

## R7 — The pops are not unique enough (MAJOR)

**Severity:** Major — it undercuts the 100-pop collection · **Area:** §XI, progression

**Owner's note:** *"the pops are not unique enough; i literally cannot tell the
difference between the pops (unless its an animal)."*

**This one has a precise, measurable root cause, and it is not a taste
question.**

### The schema is rich. The catalog does not use it.

`PopStandard.swift` gives a pop five perceptual channels. I counted what the
100 entries in `PopCatalog.swift` actually set:

| Channel | Values available | Entries (of 100) that set their own | Result |
|---|---|---|---|
| **Sound voice** | 10 (`pop`, `tone`, `bell`, `pluck`, `breath`, `glass`, `wood`, `crackle`, `shimmer`, `drop`) | **0** | inherited from family |
| **Haptic pattern** | 5 (`single`, `double`, `ripple`, `swell`, `thud`) | **0** | inherited from family |
| **Burst motion** | 10 (`radial`, `bloom`, `implode`, `spiral`, `drip`, `ascend`, `scatter`, `shiver`, `ring`, `veil`) | **0** | inherited from family |
| Particle shape | 5 | 54 | 21 spark · 13 shard · 10 ring · 10 petal · 46 dot |
| Shimmer on/off | 2 | 27 | |

The zeroes are exact, not approximate. `voice:`, `pattern:` and `burst:` each
appear exactly **twice** in `PopCatalog.swift` — once in the `def()` signature
as `= nil`, once in the body as `voice ?? family.voice`. **No individual pop
overrides any of them.**

### What that means in the hand

There are **10 families** (`vesper, ember, tide, bloom, frost, chime, lantern,
current, prism, aurora`). So across 100 pops there are:

- **10 distinct sounds** — one per family, and all ten pops inside a family are
  sonically **identical**;
- **10 distinct burst motions** — same;
- **at most 5 distinct haptics** — same.

Within a family, one pop differs from another only by **paint, particle shape
(5 options), a shimmer flag, and small numeric tweaks**. On a dark screen, at
orb size, in motion, that is not enough signal — which is exactly what the note
reports.

**And the animal is the control case that proves it.** An animal reads as
different because it varies on channels nothing else does: a silhouette, a
multi-tap life, a dart, its own sound. It is the one thing in the game that uses
more than paint.

**Corroborating, already accepted:** §XV of the walkthrough concedes that *"pop
detune variants render nearly identical"* and that *"split/emit/startle sounds
clamp to the top pitch bucket."* So even the small numeric sound differences
that **are** authored are being flattened by the engine before they reach her.

### What to do

The good news: **nothing needs new engine work.** Unlike `FireworkBurst.gravity`
(F-list, authored but never read), all three channels are live —
`SceneRenderer.swift:473` reads `particleShape`, `GameSimulation.swift:590`
switches on `behavior.burst`, `HapticsEngine.swift:41` switches on
`profile.pattern`. **The renderer is ready and the data is empty.** This is an
authoring pass, not a build.

1. **Break the family lock on burst motion first.** It is the most visible
   channel at arm's length, it costs no audio work, and there are 10 motions for
   10 pops per family — a family could use all ten and no two of its pops would
   ever burst alike.
2. **Then voice.** 10 voices × the existing per-pop `freq` / `sweep` / `decay`
   numbers is a very large distinct space. Fix the flattening in §XV first, or
   the new voices land in the same mush.
3. **Haptics last** — 5 patterns is the thinnest channel and it is silent on
   iPad anyway (§XIII).

**Owner decision:** whether a family should stay sonically coherent *by design*
(a family reads as a family — which is a real argument, and may be why it was
authored this way) or whether family identity should live in **paint and name
only**, leaving sound and motion free to individuate. That choice governs the
whole pass and should be made before anyone edits 100 entries.

---

## R8 — The weather is too soft and not interesting enough (MAJOR)

**Severity:** Major — a headline v1.3 feature is under-reading · **Area:** §VII, weather

**Owner's note:** *"the weather is 'too soft' and is not 'interesting' enough."*

Two separable problems, and they have different fixes.

### Problem 1 — she rarely sees any weather at all

`Weather.choose` (`Weather.swift:225-233`):

| Air | Odds |
|---|---|
| **clear** | **44%** |
| rain | 16% |
| summer/warm | 12% |
| snow | 10% |
| fog | 10% |
| storm | **8%** |

**Nearly half of all fields have no weather whatsoever**, and the most dramatic
air is the rarest at 1-in-12. The comment above it defends this — *"a sky that
is remarkable every evening is remarkable never"* — and that argument is sound
for a game played a few fields per evening. But it means the feature reads as
absent, and **storm, the one air that would answer "not interesting enough," is
the one she almost never gets.**

Cheapest possible experiment, and it changes no rendering: **drop `clear` to
~25–30% and put the difference into `storm` and `rain`.** One function, one
edit, immediately testable.

### Problem 2 — when it does arrive, it barely touches the field

`flowCarry` is how much the air actually moves orbs (`Weather.swift:147`):

| Air | `flowCarry` |
|---|---|
| rain | 1.35 |
| storm | 1.20 |
| summer | 0.50 |
| **clear, snow, fog** | **0** |

**Three of the six airs move nothing at all.** Snow and fog are pure overlay —
72 flakes and 7 banks drawn *in front of* a field that behaves exactly as it
does in still air. So half the weather in the game is wallpaper, and "too soft"
is a fair description of wallpaper.

Note also that **storm carries *less* than rain** (1.20 vs 1.35), which is
probably backwards from what the word "storm" promises.

### Where the ceiling is, and the one rule not to break

Other knobs: `speedScale`, `glide`, `swellAmount`, `swellRate`, `wander`,
`shine`, plus the counts (`crestCount` 2, `eddyCount` 4, `flakeCount` 72,
`shaftCount` 3, `bankCount` 7).

**The hard constraint is §VII's own line: weather "never changes
hittability."** Air may move an orb; it must never make one harder to hit. So
the room to grow is in **amplitude and legibility of motion**, not in speed that
outruns a thumb. Snow already has the right idea — *"orbs grip and move in
little jerks"* — it is just set to zero carry.

### Suggested order

1. **Odds** — `clear` 44% → ~28%, into storm and rain. No render changes, biggest
   perceived gain per line changed.
2. **Give snow a real `flowCarry`** (~0.3–0.5). It is the air most obviously
   doing nothing, and the settling/melting behaviour is already built.
3. **Make storm out-carry rain** — swap the ordering so 1.20 > 1.35 becomes
   storm-dominant, and consider raising `eddyCount` or gust depth.
4. **Leave fog at 0 carry** — fog's whole idea is the hole she pushes with a
   finger, which is interaction, not motion. Its problem is that it is *behind*
   nothing; it already reads.

**Must re-check after any of these:** Reduce Motion, where §VII requires *"the
air is nearly still and never carries orbs."* Strengthening carry must not leak
past that guard.

**Owner decision:** step 1 alone may be the whole fix — she may simply need to
*meet* the weather more often before concluding it is dull. I would ship the
odds change first and re-judge before touching carry, per `CLAUDE.md`'s
one-knob-at-a-time rule.

---

## E1 — Test-environment notes (not product defects)

Recorded so the next cut does not rediscover them.

**E1a — `iPhone 16 Pro` does not exist on a usable runtime.** It is present only
on iOS 18.3, below the deployment floor. I created one on 26.5:

```sh
xcrun simctl create "iPhone 16 Pro (26.5)" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
```

Two devices then share the name, so `-destination 'name=iPhone 16 Pro'` is
ambiguous — drive it by UDID. Delete when done:
`xcrun simctl delete E692193E-283F-4645-AF1D-75F30F3C4AC6`.

**E1b — a fresh simulator burns ~800% CPU on its own.** `mediaanalysisd` inside
a newly created device pegged roughly eight cores indefinitely, analysing the
stock photo library. It is unrelated to Vesper but it will wreck any judgement
about pop latency, frame pacing, warmth or battery — precisely what §II and
§XIII ask you to feel. Kill it before testing feel:

```sh
xcrun simctl spawn <udid> launchctl bootout system/com.apple.mediaanalysisd
```

Worth a line in `docs/PLAYTEST.md`.

**E1c — Vesper's own resource behaviour was clean.** Across 268 samples during
active play: peak 104% CPU (one core), peak 447 MB RSS, **zero swap**, host free
memory never below 95%. No leak signature — RSS sat flat at ~300 MB through
hundreds of pops and returned there after each field.

---

## Non-findings — do not re-chase

Recorded because they looked like serious defects mid-run and were not.

- **"The sky is inert to taps."** Stars and the "the field" whisper appeared
  completely dead across ~6 attempts. **Cause: my harness**, not the app. The
  Simulator window moved mid-session and the tap driver held a cached window
  origin, so every touch landed 147 pt off target. With the origin re-read per
  tap, stars, whispers and journal rows all respond normally.
- **"Two orbs will not pop after ~100 taps."** Same root cause, plus centroid
  bias: the blob detector's centre is pulled off the orb body by its asymmetric
  glow. With the origin fixed, a full field cleared in 4 scan-and-tap passes.
- **"A field froze."** The peeking field's orbs are static and CPU drops to ~5%
  while she is at the sky. That is the sim correctly not stepping a place she is
  not standing in, not the §II freeze.

---

## Verified this cut

**The four new behaviours (§4)** — all four present; each diff read against
`1afe11f`:

| Behaviour | Where | Verdict |
|---|---|---|
| A tap stops a coasting sky | `SkyScroll.swift` `catchGlide()`, `WorldInputView.swift` `onTouchDown` | Present, observational only, called ahead of arbitration |
| Choosing during the sky pause sticks | `GameViewModel.swift` `restart()` → `fieldEpoch` + `cancelOnward()`; onward step gained `guard self.sim.completed` | Present, belt and brace |
| A field can no longer freeze | `GameViewModel.swift` `frame()` epoch stamp on the `main.async` hop | Present, discards stale blocks whole |
| Cheaper sky scroll | `SkyView.swift` `DeepFieldLayer: View, Equatable` | Present and sound |

The two sky-side behaviours could not be exercised *behaviourally* — the sky
scroll needs ≳6 generations and the map is still 4 stars.

**Behavioural checks that passed**

- **§I** — opens straight into the field, no menu, status bar hidden; hint
  present and gone after the first pop; done card complete: *"the field is quiet
  now."*, a verse, "75 set free", "+3,230 pop points", "303 set free, all time.",
  "again?", and **no scrim** — the world is live behind it.
- **§III** — **navigation direction is correct**: a finger moving up travels to
  the sky, the journal is below. Whispers name the ways and travel on tap; from
  the sky and journal only "the field" is offered.
- **§IV** — family-shaped gems, closed ring on cleared stars, anchor's brighter
  rim, solid walked road vs dashed unwalked, rendered as a fork.
- **§X** — waiting shells with rope fuses; an unlit shell just sits there and the
  field clears around it.
- **§XI** — all three pages via the ribbon; hush; sound/haptics/point-whisper
  toggles; "begin this field again"; "Vesper · made by Kate Wu · collects
  nothing"; the "✦ new pop · Pearl" capsule. The journal's numbers matched the
  persisted plist exactly (5,219 pts · 121 set free · 7 fields · 7 fortunes ·
  13 best chain).
- **§XIV** — source grep finds **no** `URLSession`, `URLRequest`, `import
  Network`, `CFNetwork`, `StoreKit`, `requestReview`, `UNUserNotification`,
  `CLLocation`, `ATTracking` or any analytics SDK anywhere in `Vesper/`.
- **Progression / stage gates** — accrued correctly across the session (303
  lifetime pops, best chain 29). Fireworks appeared exactly at stage 2, matching
  `FieldPlan.stage = cleared / 3` at 7 fields cleared.

**The two known issues in the directive are accurately described**

- `Vesper/Game/Firework.swift:169` documents in-source that `gravity`, `splits`
  and `twinkles` are authored but not read — so all fourteen shells falling at
  one rate is expected, and a willow does drop like a crackle.
- The animal dart is implemented as a briefly raised **speed ceiling**
  (`AnimalPop.swift:284-289`), not an impulse, which is the mechanism by which
  weather-driven velocity eats it.

---

## Not tested — needs a person and hardware

Nothing below is a pass or a fail; it is untouched.

| Area | Why it needs you |
|---|---|
| §I, §VIII haptics | No haptics in the simulator |
| §II battery / warmth | Needs a real phone over real time |
| §XIII ProMotion parity | Needs a 120 Hz panel and a 60 Hz one, side by side |
| §XIII VoiceOver, Dynamic Type | Needs the real screen reader and text sizes |
| §XIII iPad, Split View | Not run |
| §XII 3-day settling | Needs a clock advance across days |
| §VI sky scroll, glide-catch | Needs ≳6 generations of map |
| §V onward-pause timing | A tap-driven harness cancels the sequence — which is §V's "any touch cancels it" working correctly, but it means the ~2 s window needs a human finger |
| §VII weather (all six airs) | Only clear air came up; the odds are deliberately lopsided |
| §IX splitters, drifters, generators, depth | Needs stages 2–6, i.e. 18 cleared fields |

---

## Housekeeping

- **Your uncommitted dev scaffolding is stashed, not lost.** `DevStage.swift`,
  `DevWeather.swift` and the `JournalView`/`GameViewModel` hooks are in
  `stash@{0}` ("dev affordances: DevStage/DevWeather + journal hooks
  (pre-caf10bd)"). They were written against `e6300d4` and will likely conflict
  with `caf10bd`'s `GameViewModel.swift`, so they were left for you rather than
  forced back. `git stash pop` when you want them.
- Build output: `build/` is already covered by `.gitignore:12`. **`build-test/`
  (mine) and `build-release/` (pre-existing, left alone) are NOT ignored** and
  currently show as untracked — worth adding to `.gitignore` or deleting.
- Those dev affordances are `#if DEBUG` throughout and cannot reach a Release
  binary, so they never needed removing for this cut — only for a clean diff.
