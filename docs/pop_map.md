# The Infinite Pop Map — "The Path"

*Top-level navigation as stepping stones. Implementation:
`Game/Map/PopMap.swift` (model + pure generation), `Game/Map/MapStore.swift`
(state, persistence, the trace), `Views/PathSheet.swift` (the map screen).
Contract enforced by `VesperTests/MapStoreTests.swift`.*

## 1. The idea

The Path is an infinite map of **stepping stones across dark water**. Each stone
is one playable level: a field seeded from that stone's own small set of pops.
You stand on a stone, clear its field, and the path opens ahead — one road, a
fork, or (rarely) a three-way. Behind you, the walked road quietly settles
into the sky as a thin constellation line — yours forever.

This is Vesper's answer to level navigation: **the map only ever moves
forward, and everything it leaves behind becomes memory, not loss** — the
game's whole philosophy, made spatial. There is still no failure, no score
gate, no timer, and nothing ever expires: every stone that exists is playable,
and replaying a cleared stone is always allowed.

## 2. The rules

### Stones
| Rule | Value |
|---|---|
| Pops per stone | **1–2, rarely 3** (50% / 40% / 10%) |
| Uniqueness | a stone's pops avoid its parent's and its siblings' pops whenever the collection allows |
| Visitors | ~35% of stones host **one visitor** — a pop you haven't unlocked, playable on that stone only. A taste of what's ahead; the permanent unlock still comes through the journey's rules |
| First stone | the map begins as **one dot**, lane-centered, drawn from whatever you've unlocked |

### Roads
| Rule | Value |
|---|---|
| Roads opened per first clear | **1 (45%) · 2 (45%) · 3 (10%)** |
| When they open | on a stone's *first* clear only — replays open nothing new |
| Reachability | roads exist only once their parent is cleared, so **every stone on the map is playable** — there is no locked state to display |
| Lanes | children spread left/center/right of the parent, clamped to the banks |

### The trace
| Rule | Value |
|---|---|
| Settle window | a stone untouched for **3 days** settles into the trace |
| What settling is | the road **transmutes, never disappears**: it becomes a thin, permanent constellation line — quieter and dimmer, the map's memory. Its stones stay tappable and replayable |
| Always bright | the **anchor** (the stone you stand on — or your most recently played one) and the roads directly ahead of it |
| Untaken forks | settle into the constellation with the rest of the past — and remain quietly takeable, so there is nothing you could ever "miss" |
| Effect | after quiet days the map leads with your latest stone plus its open roads; everything walked before hangs above as trace. History only accrues |
| When settling runs | app foreground, map open, and view-model init |

Nothing is ever pruned or deleted: `MapStore` replaced its 3-day removal pass
with a settle-state transition (**W08, shipped** — contract in `MapStoreTests`:
*no stone or road is ever removed*). Settled geometry persists compactly
(position, pops, cleared state), so an unbounded history stays cheap to store
and draw.

**How it was built.** Settling turned out to need no schema and no migration —
the deferral had assumed both. It is a pure reading of the stone's own dates
against the clock (`SkyLayout.isSettled`), so shipping it was a deletion: the
removal pass came out, and the trace `SkyView` was already written to draw
(`isSettled`, the `.settled` road tier, the quieted star) began firing for the
first time. What now keeps the sky small is the screenful `SkyLayout` windows
to — the newest generations sit at the baseline and the walked path climbs
quietly out of the top — rather than the destruction of the past.
`SkyLayoutTests` holds that window: no star is ever drawn above the sky's
ceiling, the anchor and the newest generation are always on screen, and rows
never compress below the touch target, at any depth of path.

### Determinism & persistence
- Every stone carries a `seed`; its roads ahead (count, lanes, pop sets) are
  reproduced deterministically from it (SplitMix64) — testable, and stable if
  generation ever needs replaying.
- The map persists as JSON in UserDefaults (`vesper.map.stones` / `.active`).
  Nothing leaves the device. The map never empties: a long absence changes how
  it looks (more constellation, one bright stone), never what you have — coming
  back from a holiday means finding the sky fuller, not the road gone.

## 3. How it plays with the other systems

- **Launch is unchanged (pillar P1):** the app still opens straight into a
  field. If you were on a stone, that field *is* the stone's field. The map is
  navigation you visit, never a menu between you and the first pop.
- **Points and unlocks flow normally** on the path — same scoring
  (`docs/pop_points.md`), same journey rules (`docs/pop_progression.md`).
  Clearing a stone that opens roads shows a soft note: *"the path continues"* /
  *"the path forks — 3 roads ahead."*
- **Free play remains:** choosing a featured pop or Drift in the Journey screen
  steps off the path (the map keeps waiting, and keeps settling, exactly as it
  would). Tapping any stone — bright or trace — steps back on.

## 4. The map screen

`PathSheet` (dotted-path button in the top bar): stones drawn newest-at-top,
connected by faint dashed curves — the roads ahead of your stone tinted with
the accent. Settled roads render as thin constellation lines with small star
points where their stones were: quieter than the active path, but always
there, always tappable. Each active stone shows its pops as small paint dots
and its pop names beneath; cleared stones dim and carry a small check; the
stone you stand on glows. A caption, if one is needed at all, speaks of
keeping, never losing: *"the road behind settles into the sky."* VoiceOver
reads every stone's pops and state, trace included; all stones are 48pt
targets.

## 5. Why these numbers

- **1–3 pops, 1–3 roads** keeps each choice legible at a glance — a fork on a
  calm walk, not a skill tree.
- **3-day settle** is long enough that yesterday's stone is still bright when
  you return to it, short enough that the map always leads with what's ahead —
  without the past ever becoming either a museum of obligation or a loss. A
  decay timer on the player's own history would break "nothing expires"; a
  trace that only accrues keeps the same visual calm and gives you the sky
  you earned.
- **35% visitors** makes the path the place where tomorrow's pops first brush
  past you — wonder without FOMO, since nothing expires that you could "miss":
  new visitors keep arriving forever.
