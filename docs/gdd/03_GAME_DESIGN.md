# Vesper — Game Design Document

*What the game is, why it's fun, and how its systems serve the mission.
Inherits the pop standard, points, and map designs (docs/pop_*.md) and reframes
them around the audience and the One World navigation (04).*

## 1. The fun, named

A stress-free game still needs *fun*, and Vesper's fun comes from five sources —
every feature must feed at least one:

1. **Sensory payoff** — the pop itself: burst + tone + haptic in one frame.
   The single most important asset in the game. (Pillar P2)
2. **Cascade delight** — chains as quiet fireworks: planned a little, gifted a
   lot. The skill ceiling is *noticing*, never *executing*.
3. **Completion** — clearing a field is a full exhale: chime, card, done.
   90-second arcs, always finishable.
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

**Journey (weeks):** points accrue → pops unlock into the Journal → stones open
on the Path above → phases of the evening pass. All one-directional, all
grace-period'd, nothing to maintain.

## 3. Systems (kept, reframed, added)

### Kept as designed (docs/pop_standard.md, pop_points.md, pop_progression.md, pop_map.md)
- **The pop engine & 100-pop catalog** — content as data; #001 sacred.
- **Pop points** — diary-not-scoreboard scoring; whispers optional.
- **Unlock rules** — kind, multi-path, always reachable.
- **The Path** — stones, roads, visitors, 3-day fading.

### Reframed for the audience
- **Copy warmth pass:** "DETONATED" → **"set free"**; "TAP AN ORB TO BLOW IT UP"
  → **"tap an orb. let it go."** The violent register was wrong for the mission —
  every string gets the 07 voice pass.
- **Path fading is a gift, not loss:** copy and art must frame the fading road as
  the sky letting go *for* you ("the road behind folded itself away"), and the
  map view leads with what's ahead, never what faded.
- **Reset ("start over") demoted:** a permanent destructive button contradicts
  P5. Start-over moves to a long-press on the field with a whispered confirm.

### Added (new, from audience needs)
- **The arrival** — the 1.5 s field-assembly moment (P1-compatible: it *is* play
  starting, not a splash).
- **Evening light** — the field's ambient hue drifts subtly with local time of
  day (on-device clock only). Her 8 a.m. field and 1 a.m. field feel different;
  1 a.m. is the dimmest, gentlest version. (Bedside persona.)
- **The breath** — optional: the whole field inhales/exhales on a ~5.5 s cycle;
  clearing during a shared exhale gives a slightly deeper chime. Never scored.
- **Keepsakes** — finishing a family in the Journal produces a keepsake (a
  pressed-flower-like emblem on the journal page). Pure ownership, zero power.
- **The lamp** — a ritual, not a streak: her journal shows "you visited this
  evening" as a small lit lamp. Unlit lamps *disappear from history* — there is
  no chain to break, only evenings that happened.
- **Shareable stillness** — a long-press on the done card composes a beautiful
  card (field + fortune + count) for saving/sharing. Organic growth engine for
  this audience; no watermark spam, just quiet credit.

## 4. Difficulty, failure, and skill

There is no difficulty and no failure — but there *is* mastery texture: reading
clusters for maximal cascades, finding the fortune orb by its behavior (it
drifts a touch dreamier — a tell added for noticing-players), clearing with few
taps. All of it self-assigned, none of it measured publicly. The game never
says "try again"; it only says "again?"

## 5. Content plan

- **v2.0:** the 100-pop catalog across six phases (exists).
- **v2.x seasonsless seasons:** small *arrivals* every 6–8 weeks — a new fortune
  set, 2–3 guest pops joining the catalog permanently (never limited-time), a
  new keepsake. Announced only inside the journal, on arrival, kindly.
- **Long term:** family expansions (weather, gardens), an iPad "big sky" layout,
  a home-screen widget (the lamp + a single poppable orb?  — investigate).

## 6. Success definition (privacy-first)

No telemetry. Success reads from: App Store ratings/reviews (target ≥ 4.8),
organic screenshots/shares in the wild, TestFlight playtest panel (see 08 §QA)
session reports, and the only number that matters: **do playtesters open it
again the next evening without being reminded?**
