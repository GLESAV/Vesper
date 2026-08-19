# Pop Puzzles

*The initiative for making a field worth staying in.*

Status: **design, adopted, unbuilt.** Owner-initiated after the stage-mechanics
build. Companion docs: `pop_standard.md` (what a pop is), `pop_progression.md`
(how content arrives), `gdd/00_MASTER_PLAN.md` (the pillars).

---

## 1. The problem, stated honestly

The owner's words after playing the stage build: *"popping is more
interactive, and we have made a major improvement in gameplay. I can stay
entertained for about 30 seconds."*

Thirty seconds is the real number and it is the right one to design against.
The stage mechanics fixed **duration** — splitters, generators and a fuller
field mean a field now lasts minutes instead of forty seconds. They did not
fix **attention**. A longer field of the same activity is a longer version of
the same thirty seconds.

What is missing is a *reason to look*. Right now the field asks one question —
"where is an orb?" — and answers it identically every time. A puzzle asks a
second question underneath the first, and the second question is what makes
the eye stay.

## 2. What a puzzle may not be

This is the part that decides whether this initiative helps or ruins the
product. Vesper's guardrail 1 is that there are no pressure mechanics: no
timers, no fail states, no scores to chase, nothing spent or lost. A puzzle is
the single most likely feature in this game to smuggle all four back in,
because "puzzle" in most games means *a thing you can get wrong*.

So, the laws. Every one of these is a veto, not a preference.

**1. A puzzle can never be failed, and never be stuck.**
No wrong move exists. There is no lose state, no reset, no "try again". The
worst outcome of not understanding a puzzle is that you popped some orbs in an
order that was merely fine.

**2. A puzzle must be solvable by accident.**
Someone who never notices the rule must still finish the field. The puzzle is
a richer path through the same field, never a gate across it. If a player can
be *blocked*, the puzzle has become a fail state wearing a friendly face.

**3. The rule must be legible in light, never in words.**
No tutorial, no instruction text, no modal explaining the mechanic. If the
rule cannot be taught by how the orbs look and move, the puzzle is cut. This
game has exactly one sentence of instruction in it and that is the budget.

**4. Nothing may demand speed.**
No countdown, no combo window, no "quick, before—". The field waits. A person
can put the phone down mid-puzzle, come back in an hour, and lose nothing.

**5. Being wrong must feel like play, not like correction.**
An orb that isn't ready doesn't buzz, flash red, shake, or refuse. It *slips
aside* — the drifter grammar we already have. It reads as coy, not as a
rejection. Nothing about a not-yet tap says "no".

**6. Every puzzle ends in the same quiet.**
No fanfare, no "PUZZLE COMPLETE", no stars or grades. The field goes quiet the
way it always does. The reward is the pattern resolving under your hands, and
that is the only reward on offer.

### The mercy rule

Underneath all of it, one invisible guarantee: **an orb that has been tapped
three times becomes poppable regardless of the puzzle.** It relents.

Nobody is ever told this. There is no counter, no hint, no acknowledgement.
It exists so that law 1 and law 2 are structurally true rather than
aspirationally true — a player who cannot see the rule, or does not want to
play it, taps the thing they want and after a moment it simply gives. The
puzzle becomes a suggestion the field is making, which is exactly the
relationship this game should have with the person holding it.

---

## 3. The flagship: **Sequence**

*The owner's proposal, specified.* Working name in code: `.sequence`.

### The idea

The field holds orbs in **two or three colour families**. One family is
*ready*. Pop its members and they pop normally. Orbs of the other families are
*waiting*: they ease away from an approaching finger, the way a drifter does.
When the ready family is finished, the next family becomes ready — a soft
bloom passes across the field — and the one that was ready is simply gone.

Two or three colours, never more. Three is already at the edge of what reads
without counting.

### What she sees

The rule is taught entirely by brightness and motion, in this order:

| State | How it looks | How it behaves |
|---|---|---|
| **Ready** | Full paint, full halo, the ordinary breathing orb | Pops on touch, chains normally |
| **Waiting** | Paint at ~55%, halo suppressed, a slightly cooler cast — present but *not lit* | Eases away inside the evade radius; surrenders up close (the drifter contract) |
| **Becoming ready** | The halo blooms up over ~0.8 s, staggered across the family by distance from the last pop | Becomes poppable as the bloom passes it |

The staggered bloom is the whole teaching moment. The first time a family
lights up in a wave, the player learns the rule without a word: *oh — these
are next.* It also makes the transition the nicest-looking half-second in the
game, which is the point.

### What she hears and feels

- Popping a ready orb: unchanged.
- Touching a waiting orb: **nothing**. No sound, no haptic, no error tone. The
  orb slips aside and that is the entire response. Silence here is deliberate —
  any sound at all would read as a buzzer.
- A family completing: a single soft rising interval on the completion of the
  family, quieter than the field-clear chime and distinct from it. One note,
  not a flourish.

### Edge cases, all of which must be answered

- **Chains crossing families.** A shockwave from a ready orb must not pop a
  waiting one. It passes through and does not even ripple it — a chain that
  half-works reads as a bug. Chain arming already distinguishes direct from
  echoed rings; waiting orbs are simply not chain targets.
- **Splitters inside a sequence.** A splitter in a waiting family stays whole
  until its family is ready. Children inherit the family. A splitter in the
  ready family behaves normally.
- **Generators inside a sequence.** A generator emits into **its own family**.
  If its family is waiting, it does not emit at all — it waits with them, rings
  dimmed and still. Otherwise it would fill the field with unpoppable orbs,
  which is the one way this puzzle could feel like being held back.
- **The fortune orb** never belongs to the last family, so a fortune is never
  the thing standing between her and quiet.
- **The mercy rule** applies: three taps on a waiting orb and it pops, out of
  order, with no comment. The family it belonged to carries on as if it had
  always been one short.

### Why it is the flagship

It is the only puzzle in this list where the *whole field* changes state at
once. That wave of light crossing the screen is the most visual thing this
game has ever done, and it costs one new orb property and one bloom animation.

---

## 4. The other five

Specced more lightly. Each is one idea, each obeys all six laws, and each is
buildable on the existing entity model.

### 4.1 **Stillness** — `.stillness`
Some orbs only become poppable when **no finger has touched the glass for a
beat and a half**. They are drawn slightly translucent, and they *solidify* as
the pause lengthens.

The reward for stopping is the mechanic. This is the most on-mission puzzle in
the document — it is a game asking you to take your hands off it — and it is
the one to build second if the flagship lands. It cannot be failed because
waiting is free and unlimited.

### 4.2 **Pairs** — `.pairs`
Orbs exist in twinned pairs sharing a paint. Popping one makes its twin
**glow and drift gently toward where its partner was** for a few seconds;
popping it in that window links them with a brief constellation line and both
count as a pair.

Missing the window costs nothing at all — the twin just settles back to
ordinary and can be popped whenever. The window is not a timer against her; it
is a *bonus* that only ever adds. Ties visually to the Path's constellation
lines.

### 4.3 **The Lantern** — `.lantern`
One large, beautiful, closed orb sits in the field, its rings dark. Every pop
anywhere fills one ring. When the last ring fills it opens — a slow, big,
generous pop worth several ordinary ones.

Pure accumulation, no order, no rule to misread. It gives a long field a
destination. Reuses the generator's ring rendering, inverted.

### 4.4 **Constellation** — `.constellation`
A handful of orbs are faintly linked by a line, drawn in the Path's road ink.
Popping them **along the line** — each one adjacent to the last — lights the
segment behind you and deepens the tone with each step.

Pop them out of order and they simply pop; the line fades without complaint.
The whole puzzle is optional beauty, which makes it the purest expression of
law 2.

### 4.5 **Tides** — `.tides`
The field breathes: over a slow ~12 s cycle, one half of the orbs swell toward
full brightness while the other half recede, then reverse. Both halves are
always poppable — this one has **no gating at all**. It is a rhythm, not a
rule.

It exists because a field of puzzles needs somewhere to rest, and because
popping *with* a rhythm you did not have to obey is a very Vesper pleasure.

---

## 5. How puzzles arrive

Puzzles extend the existing stage curve in `FieldPlan` rather than replacing
it. One puzzle per field, at most — two puzzles in one field is noise, and the
field must never become a rulebook.

| Stage | Field |
|---|---|
| 0–6 | As built today: plain → fuller → splitters → drifters → generators → depth → second generator |
| 7 | **Tides** — a rhythm, no rule. The gentlest possible introduction to "the field can have a shape". |
| 8 | **Lantern** — a destination, still no rule to misread |
| 9 | **Sequence (2 colours)** — the flagship, at its simplest |
| 10 | **Constellation** |
| 11 | **Sequence (3 colours)** |
| 12 | **Stillness** |
| 13 | **Pairs** |
| 14+ | The pool: a puzzle drawn from those unlocked, never the same one twice running |

Same cadence as today — three cleared fields per stage — so this is roughly
five more evenings of new things after the current curve runs out, then a
rotation that stays varied indefinitely.

Puzzles are **remembered in the journal** the way pops are: a puzzle you have
met appears in the collection with its name and a line of description. That
is the only place words explain them, and it is read after the fact, never
before.

---

## 6. Implementation sketch

Deliberately small. Everything below sits on the entity model that already
exists.

**`Orb`** gains one property:
```swift
var family: Int = 0        // which group this orb belongs to; 0 when unpuzzled
```

**`FieldPuzzle`** is a new pure type beside `FieldPlan`:
```swift
enum FieldPuzzle: Equatable {
    case none
    case sequence(families: Int)
    case stillness
    case pairs
    case lantern(rings: Int)
    case constellation
    case tides
}
```
`FieldPlan` gains `var puzzle: FieldPuzzle` and the curve above.

**`GameSimulation`** gains:
- `private(set) var readyFamily: Int` — which family is currently poppable
- a `puzzleStep(_ f:)` called from `step`, alongside `stepGenerators`
- a poppability predicate consulted by `tap` and by chain arming:
  `func isPoppable(_ orb: Orb) -> Bool`
- `mercyTaps: [Int: Int]` — taps per waiting orb, for the mercy rule

**New `GameEvent` cases:** `.familyReady(Int)`, `.puzzleAdvanced`,
`.orbSlippedAside(Orb)` — the last one so the view can draw the slip even
though nothing sounds.

**Rendering** needs one new thing: a `waiting` treatment (paint and halo
multipliers) and the bloom, both of which are multipliers on values
`SceneRenderer` already computes per orb.

**Reduce Motion:** the bloom becomes a crossfade with no stagger and no
travel; the slip-aside becomes an opacity dip with zero translation, exactly
as drifters already do under Amara's conditions 10–15.

**VoiceOver:** a waiting orb's label says *"waiting"* and the field's own
element announces the ready family when it changes — the one place a puzzle
is allowed words, because for a screen-reader user light is not available and
law 3's whole premise fails.

## 7. Test plan

The laws are testable, and they are what the tests should assert — not the
mechanics.

- **Never stuck:** for every puzzle, every seed, a bot that taps only the
  nearest orb repeatedly always reaches `completed`. This is law 1 and law 2
  in one test, and it is the most important test in the initiative.
- **Never punished:** no event, sound profile or haptic is emitted on a
  not-yet tap.
- **Mercy:** three taps on any waiting orb pops it, in every puzzle.
- **Chains respect families:** a shockwave never pops a waiting orb.
- **No timers:** stepping a puzzle field for ten simulated minutes with no
  input changes nothing except `tides`' phase — nothing expires, nothing
  advances, nothing is lost.
- **Determinism:** same seed, same stage, same puzzle, same field.

## 8. Rejected, and why

Recording these so they are not proposed again.

- **Anything with a move limit or a par count.** Both are scores, and both make
  the elegant solution mandatory rather than available.
- **Anything that removes orbs she did not pop.** Nothing on this field
  disappears without her.
- **Matching three-in-a-row.** It is a different game, it rewards speed and
  scanning, and the genre carries a fail state so strongly that players would
  feel it even in its absence.
- **A puzzle that must be understood to finish the field.** Law 2, in the one
  form it is most tempting to break.
- **Difficulty tiers.** Fields get more *varied*, never harder — the owner's
  own framing, and the reason the stage curve caps.
