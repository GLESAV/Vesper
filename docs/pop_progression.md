# Pop Progression — "The Journey"

*How the 100 pops are earned. Implementation: `Support/ProgressionStore.swift`,
unlock rules on each entry in `PopCatalog.swift`, UI in `Views/JourneySheet.swift`.*

## 1. Design position: are there levels?

**No.** Vesper has no levels, no XP bars to fail, no gates that close. Progression is
a single continuous **journey** that only ever moves forward:

- Nothing is ever lost, spent, or reset. Every counter only goes up.
- Nothing is time-limited. There are no dailies, streaks, or expiring anything.
- Nothing is comparative. There are no leaderboards; the journey is yours alone.
- Every pop is reachable through ordinary play — no purchases, no grinding walls
  (the whole catalog opens in roughly 12–15 relaxed hours; the first new pop arrives
  in the first session).
- Locked pops show a *kind hint* ("gather 700 pop points", "ride a chain of 5"),
  never a wall or a timer.

Instead of levels, the catalog opens in six **phases of the evening** — named bands
that describe where you are, purely cosmetically. A phase never gates anything; it's
how the journey talks about itself.

## 2. The six phases

| Phase | Pops | Roughly | Feel |
|-------|------|---------|------|
| **First Star** | #001–010 (Vesper) | session 1 → hour ~1 | learning that letting go is repeatable |
| **Gloaming** | #011–030 (Ember, Tide) | hours 1–3 | warmth and weight join the dusk |
| **Moonrise** | #031–050 (Bloom, Frost) | hours 3–6 | softness and clarity; the first secret waits here |
| **Deep Night** | #051–070 (Chime, Lantern) | hours 6–9 | longer sounds, carried light |
| **Starfall** | #071–090 (Current, Prism) | hours 9–12 | gentle energy, light taken apart |
| **Morningside** | #091–100 (Aurora) | hours 12–15 | the sky answers; ends at Morning Star |

## 3. Unlock rules

Each pop carries exactly one `UnlockRule`:

| Rule | Counts | Used for |
|------|--------|----------|
| `start` | — | #001 only. The classic is always there. |
| `points(n)` | lifetime pop points (docs/pop_points.md) | ~80% of the catalog; thresholds rise smoothly 100 → 109,000 |
| `totalPops(n)` | lifetime orbs set free | one per family band (150 → 60,000) |
| `fieldsCleared(n)` | fields fully cleared | 5 → 110 |
| `fortunesFound(n)` | fortune orbs found | 3 → 35 |
| `bestChain(n)` | longest single cascade | 4 → 10 (secret #050 at 10) |

Condition rules are sprinkled so that *how* you play occasionally opens a door that
points alone wouldn't — a long chain, a patient streak of clears, a lucky fortune —
but there is always a points-based door nearby, so no play style is ever stuck.

Secrets (#050 Polar Night, #080 Stormglass, #100 Morning Star) use condition rules
and show only a `?` in the collection until found.

## 4. How unlocks surface (in game)

- The moment a rule is met, a soft capsule appears under the counter:
  **“✦ new pop · Gloaming.”** It fades on its own; it never blocks a tap.
- New pops join the field **from the next field onward** — the current field is
  never disturbed.
- The Journey screen (✧ button) shows the collection: 100 cells, unlocked pops in
  their own paint, locked ones dim with their hint one tap away, secrets as `?`.

## 5. Featuring and Drift

The player chooses how fields are painted:

- **Featured pop** — tap any unlocked pop in the Journey screen; every orb in new
  fields uses it. For sitting with one mood.
- **Drift** (default) — each new field mixes orbs from everything unlocked. The
  collection you've built *is* the game you're playing.

Both are one tap, both restart into a fresh field immediately, neither affects
points or unlocking. There is no wrong choice.

## 6. Persistence

All progression lives in `UserDefaults` on device (`ProgressionStore`): points,
counters, per-pop tallies, featured selection. Unlocks are *derived* from counters
at read time — there is no separate unlock state to corrupt or migrate. Pre-1.1
lifetime counters carry over via their original keys. Nothing leaves the device.
