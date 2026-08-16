# Vesper — Game Design Document

*What the game is, why it's fun, and how its systems serve the mission.
Inherits the pop standard, points, and map designs (docs/pop_*.md) and reframes
them around the audience and the One World navigation (04). Everything below
sits downstream of the baseline fun gate (00): before any of it builds, the
recruited panel plays v1.2 as shipped for ~1 week — first-hour video plus
diary — to produce the baseline the one metric needs and to answer whether the
core loop is described as* fun, *not only relaxing.*

## 1. The fun, named

A stress-free game still needs *fun*, and Vesper's fun comes from five sources —
every feature must feed at least one:

1. **Sensory payoff** — the pop itself: burst + tone + haptic in one frame.
   The single most important asset in the game. (Pillar P2)
2. **Cascade delight** — chains as quiet fireworks: planned a little, gifted a
   lot. The skill ceiling is *noticing*, never *executing*.
3. **Completion** — clearing a field is a full exhale: chime, card, done.
   Short arcs, always finishable. The working figure is ~90 s per field;
   before anything builds on that number, median field-clear time is measured
   in the tuned build across play styles and recorded against 02's design
   consequence 3.
4. **Collection & discovery** — 100 pops with distinct feels; fortunes; secrets;
   visitors on the Path. "What's next" as wonder, not obligation.
5. **Ritual & ownership** — her path, her journal, her evening. The game
   remembers kindly and never asks.

## 2. The three loops

**Moment (seconds):** see field → choose an orb → pop → feel it → watch the
ripple. Depth: bigger orbs pop deeper; clusters invite chain-hunting; the
fortune orb hides in plain sight.

**Session (2–8 min):** arrive (field breathes in) → play 1–3 fields → each clear
is a clean exit ramp → leave whenever; the game closes the door softly behind you.
New: the **arrival moment** — on open, the field assembles from motes over ~1.5 s.
Never a menu, never a popup, never news.

**Journey (weeks to months):** points accrue → pops unlock into the Journal →
stones open on the Path above → phases of the evening pass. All one-directional,
all grace-period'd, nothing to maintain.

**The pacing target (binding).** The journey is tuned to *her* calendar, not an
enthusiast's: the **median evening player reaches Morningside in 90–120
evenings**, and even a heavy player **never finishes in under 30 days**.
`pop_progression.md` and `pop_points.md` are retuned against these bands; the
inherited curve is not assumed correct. Validation is a Phase 2 workstream
(08): a deterministic sim harness replays persona profiles (Maya / Dani /
Priya, 02) through `ProgressionStore` against the target bands — the pure
simulation makes this nearly free — plus a 3-week diary extension probing
*"did anything new happen tonight?"*, with the exit criterion **no persona goes
more than 5 evenings without a discovery in weeks 1–4.**

## 3. Systems (kept, reframed, added)

### Kept unless the fun gate fails (docs/pop_standard.md, pop_points.md, pop_progression.md, pop_map.md)
- **The pop engine & 100-pop catalog** — content as data; #001 sacred.
- **Pop points** — diary-not-scoreboard scoring; whispers optional.
- **Unlock rules** — kind, multi-path, always reachable.
- **The Path** — stones, roads, visitors. (Road fading is redesigned — see
  *the trace*, below.)

The simulation itself stays untouched **unless the baseline fun gate (00)
fails.** On failure, a named **loop-depth workstream** slot opens before any
surface work compounds the problem — run with the existing discipline: one
`GameConfig` constant at a time, sim pure and deterministic, every change
re-run through the unit tests.

### Reframed for the audience
- **Copy warmth pass:** "DETONATED" → **"set free"**; "TAP AN ORB TO BLOW IT UP"
  → **"tap an orb. let it go."** The violent register was wrong for the mission —
  every string gets the 07 voice pass.
- **The trace (replaces road fading):** roads no longer fade away on a 3-day
  timer — a decay clock on the player's own history fails P3's *nothing
  expires* test no matter how kindly it's worded, and no copy survives the
  returning-from-holiday test. Instead, after three days a road **transmutes**:
  the walked path settles into a permanent, quieter form — a thin
  constellation line in the sky that is hers forever. Recent roads glow;
  older ones become the map's memory. History only accrues; nothing she made
  ever disappears. The map view still leads with what's ahead. Mechanics land
  in `docs/pop_map.md`; the `MapStore` implementation follows in-phase.
- **Begin again (replaces the reset button):** a permanent destructive button
  contradicts P5, and a double timed-hold excludes Switch Control users. The
  redesign: a long press **arms only on empty space** — a press that lands on
  an orb always just pops it — and confirmation is a **plain tap** on the
  dim-and-gather treatment (05), never a second timed hold. The same action
  also lives as a plain **"begin again" row** on the journal's last page, with
  a VoiceOver custom action. Full interaction spec in 04.
- **One long-press grammar:** across the whole game a long press means
  **"hold to keep"** (the share card) — taught once by a one-time discovery
  whisper, then never mentioned again. The begin-again press is the only
  other long press, and it lives on empty space alone.

### Added (new, from audience needs)

v2.0 ships **arrival, evening light, the lamp, and keepsakes**. The breath and
the widget are a named v2.1 bucket; the share card ships only if it holds its
no-numbers constraint. Each addition is ranked by the fun source it feeds and
its polish cost — this table is the local half of 00's cut order, and **the
pop's feel budget is never traded for any row of it**:

| Rank | Addition | Feeds fun source | Polish cost | Ships |
|---|---|---|---|---|
| 1 | The arrival | 1 · sensory / 3 · completion | Medium (animation + audio) | v2.0 |
| 2 | Evening light | 5 · ritual | Low (palette drift) | v2.0 |
| 3 | The lamp | 5 · ritual | Low (one journal element) | v2.0 |
| 4 | Keepsakes | 4 · collection | Medium (art per family) | v2.0 |
| 5 | Shareable stillness | 5 · ritual (and growth, 09) | Medium (card composer) | v2.0, conditional |
| 6 | The breath | 1 · sensory | High (field-wide motion + mix) | v2.1 |
| 7 | Home-screen widget | 5 · ritual | High (new surface) | v2.1 |

- **The arrival** — the 1.5 s field-assembly moment (P1-compatible: it *is* play
  starting, not a splash).
- **Evening light** — the field's ambient hue drifts subtly with local time of
  day (on-device clock only). Her 8 a.m. field and 1 a.m. field feel different;
  1 a.m. is the dimmest, gentlest version. (Bedside persona.)
- **The lamp** — a ritual, not a record. Her journal holds a single warm
  aggregate: **"47 evenings, so far."** One lamp, always lit a little warmer
  for having been visited — never a row of lamps, never a calendar, never a
  date axis. Absence must be **structurally unrepresentable**, not merely
  unmentioned: a no-streak promise over chronological visit history lets her
  reconstruct the streak herself, so the structure — not the copy — carries
  the guarantee. Veto test for every lamp/journal design: **can any
  arrangement of what it shows reveal an evening she skipped?** The kindness
  guardrails (01) bind here in full: the journal never surfaces time played,
  days missed, or anything readable as a report card.
- **Keepsakes** — finishing a family in the Journal produces a keepsake (a
  pressed-flower-like emblem on the journal page). Pure ownership, zero power.
  Keepsake tiers extend into the full journal (§4.5).
- **Shareable stillness** *(conditional)* — **hold to keep**: a long press on
  the done card *or any fortune card* composes a beautiful card for
  saving/sharing. The card passed the P3/P5 pillar veto only in this form,
  now binding (00): the default is **field + fortune, nothing else**;
  tonight's count appears only as an explicit per-share opt-in; **lifetime
  totals never appear on any shareable surface**; no streaks, no identifying
  stats. The product never pushes a comparable number — she can choose to
  show one. No watermark spam, just quiet credit. Its gate: the card must
  produce organic posts from the TestFlight panel before launch, or the
  screenshot loop is demoted from primary growth channel (02, 09).
- **The breath** *(v2.1)* — the whole field inhales/exhales on a ~5.5 s cycle,
  and the completion chime carries a subtle **ambient, un-earnable
  variation**: sometimes deeper, decoupled from anything she does. No tell,
  no record, no score — a timing-earned reward would be a timer by another
  name. It is never explained or labeled anywhere, in-game or out; the deeper
  chime is weather, not wages. Standing test: **if playtesters begin timing
  their clears, the variation becomes random.** Implementation belongs to the
  v2.1 arrival.

### The variety layer — why field 500 is still worth reading

All longevity must not be delegated to skins on one verb. Two rules keep the
hundredth evening observably different from the first:

- **Field generation is a design space, not a dice roll.** The generator
  composes from a library of **cluster archetypes** (tight bouquets, lone
  drifters, arcs, veils), **density curves** across the field, and occasional
  **special compositions** — a nearly-empty field, one enormous slow orb, a
  spiral — so that reading the field (fun source 2) stays fresh. The design
  question every generator change answers: *why is field 500 still
  interesting to read?* This is the in-game half of 01's promise that every
  ordinary evening contains one small surprise — night four observably
  different from night one.
- **The catalog rule: never tint alone.** Every pop family must differ from
  its neighbors in at least one of **sound texture, burst shape, or chain
  behavior** — a palette swap is not a new pop. Each pop also carries a
  one-line journal **flavor line**, so the collection reads like a field
  guide, not a swatch book. `pop_standard.md` and `PopCatalog.swift` are
  audited against this rule before Phase 2 content work.

### The fortune system

Fortunes are, for the reader in the audience, the game — they get a system,
not a string array.

**Runtime rules:**
- The pool draws **seeded per player, no repeats until the pool is
  exhausted** — a repeat is the moment the magic dies, so it is deferred as
  long as the corpus allows.
- **One guaranteed-new fortune per evening** while unseen fortunes remain.
- Every fortune she has met is kept in a journal archive — **"things the sky
  told me."**
- **Spoiler policy:** fortunes tied to secret pops never appear — in the
  archive, in previews, or anywhere — before their pop is met.

**Authoring pipeline (07 owns the voice; this owns the process):**
- A written rubric with **3 passing and 3 near-miss exemplars**, including
  exemplars themed to each dusk phase of the progression.
- **Two-person review** on every batch, one reviewer a target-audience
  reader.
- A **dedup rule** (no two fortunes sharing an image or a closing move) and a
  **read-aloud batch check** — a fortune that sounds wrong spoken at 1 a.m.
  is wrong.
- **Launch corpus: 60+ fortunes** (from the current 18). At a daily-player
  read rate, 18 exhausts in about two weeks; 60+ carries the first two
  months. This is real editorial work — the writing sessions are budgeted
  explicitly in 08, not absorbed.

## 4. Difficulty, failure, and skill

There is no difficulty and no failure — but there *is* mastery texture: reading
clusters for maximal cascades, finding the fortune orb by its behavior (it
drifts a touch dreamier — a tell added for noticing-players), clearing with few
taps. All of it self-assigned, none of it measured publicly. The game never
says "try again"; it only says "again?"

## 4.5 The full journal — after pop #100

Fun source 4 exhausts at pop #100 unless the after-state is designed; it is a
Phase 2 design deliverable (08), built on these commitments:

- **The Path never ends.** Past #100, stones keep opening from the same seeded
  generation — the map is infinite by construction — and stones beyond the
  catalog mark *places*, not unlocks: compositions, visitors, and small
  moments of the generator's variety layer. Walking stays worth it when there
  is nothing left to earn.
- **Drift becomes the endgame.** With everything unlocked, **Drift** — fields
  painted from her whole collection — *is* the game she built, and
  **featuring** becomes curation: sitting with one mood on purpose. The
  Journal's featured-pop flow is polished as an end-state verb, not a
  progression leftover.
- **Depth systems carry ownership forward:** per-pop tallies (each pop's count
  quietly deepens its journal page), **keepsake tiers** (a family's keepsake
  matures with continued company — accrual only, never regression), and
  **fortune-set completion** (finishing a fortune set leaves its own mark in
  "things the sky told me").

Everything here obeys the same law as the rest of the journal: numbers only
accrue, nothing compares, absence stays unrepresentable.

## 5. Content plan

- **v2.0:** the 100-pop catalog across six phases (exists), the fortune corpus
  at 60+, and the systems in §3.
- **Steady state rests on what ships.** The lasting ritual is carried by the
  infinite Path, the 100-pop catalog, the variety layer, and the fortune
  pool — not by a content treadmill. Vesper does not promise live-game
  cadence it cannot keep in its own voice.
- **Arrivals are a bonus rhythm, not a commitment.** An *arrival* is a small
  permanent addition — a new fortune set, 2–3 guest pops joining the catalog
  forever (never limited-time), a new keepsake — announced only inside the
  journal, on arrival, kindly. Publicly, only **arrival #1** is committed: it
  is built in Phase 3 as the content-pipeline proof, with its real cost
  recorded (00). The internal 6–8-week cadence stays internal until three
  arrivals have shipped on time.
- **v2.1 (named bucket):** the breath (§3) and the home-screen widget (the
  lamp + a single poppable orb — investigate).
- **Long term:** family expansions (weather, gardens); iPad interaction design
  as its own v2.x arrival — v2.0 is iPhone-first with the existing iPad
  layout grandfathered (00).

## 6. Success definition

There is exactly one measurement protocol, and it lives in 00; this document
defines no variant. In brief: the single release bar is **wind-down return**
(≥ 60% of panelists play on at least 4 of their first 7 evenings), read from
TestFlight aggregate session data — SDK-free, no telemetry — with a separate
diary cohort for qualitative texture only. Over it sits the qualitative fun
gate: **the game is described as fun, not only relaxing.** Ratings targets and
their instrument live in 09; secondary signals (commuter, collector, organic
screenshots in the wild) inform iteration and never gate the ship.
