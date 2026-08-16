# Pop Progression — "The Journey"

*How the 100 pops are earned. Implementation: `Support/ProgressionStore.swift`,
unlock rules on each entry in `PopCatalog.swift`, UI in `Views/JourneySheet.swift`.*

## 1. Design position: are there levels?

**No.** Vesper has no levels, no XP bars to fail, no gates that close. Progression is
a single continuous **journey** that only ever moves forward:

- Nothing is ever lost, spent, or reset. Every counter only goes up.
- Nothing is time-limited. There are no dailies, streaks, or expiring anything.
- Nothing is comparative. There are no leaderboards; the journey is yours alone.
- Every pop is reachable through ordinary play — no purchases, no grinding walls.
  The first new pop arrives in the first session; the whole catalog opens over a
  season of evenings (§2), never in a weekend.
- Locked pops show a *kind hint* ("gather 700 pop points", "ride a chain of 5"),
  never a wall or a timer.

Instead of levels, the catalog opens in six **phases of the evening** — named bands
that describe where you are, purely cosmetically. A phase never gates anything; it's
how the journey talks about itself.

## 2. The six phases, and the pacing they must hit

The journey is measured in **evenings, not hours** — it is tuned to the target
player's calendar (a short wind-down most nights), not to an enthusiast's binge.
The binding target (03 §2 of the GDD):

- the **median evening player reaches Morningside in 90–120 evenings**;
- even a **heavy player never finishes in under 30 days**.

| Phase | Pops | Roughly (evenings) | Feel |
|-------|------|--------------------|------|
| **First Star** | #001–010 (Vesper) | evening 1 → ~3 | learning that letting go is repeatable |
| **Gloaming** | #011–030 (Ember, Tide) | ~3–15 | warmth and weight join the dusk |
| **Moonrise** | #031–050 (Bloom, Frost) | ~15–35 | softness and clarity; the first secret waits here |
| **Deep Night** | #051–070 (Chime, Lantern) | ~35–60 | longer sounds, carried light |
| **Starfall** | #071–090 (Current, Prism) | ~60–90 | gentle energy, light taken apart |
| **Morningside** | #091–100 (Aurora) | ~90–120 | the sky answers; ends at Morning Star |

The evening bands above are the design intent; the inherited point thresholds
are **not assumed correct** and are re-derived against them (see validation,
below). Two tuning constraints follow:

- **The discovery cadence matters more than the finish line.** Early bands are
  dense enough that something new happens most evenings; from Moonrise on, the
  spacing widens but never starves — see the exit criterion below.
- **The heavy-play floor is tuning, never a gate.** No visible wall, timer, or
  daily cap ever appears. Instead the late bands lean on counters that accrue
  across evenings more than within them (fortunes found, best chain, condition
  rules), so a long session stays delightful without becoming a fast-forward.
  If the harness shows raw play length still breaking the 30-day floor,
  late-phase rules shift further toward across-evening accrual.

**Validation (Phase 2 workstream).** Because the simulation is pure and
`ProgressionStore` is UI-free, pacing is checked in code, not by feel:

1. **Deterministic sim harness** — replays persona play profiles (Maya / Dani /
   Priya, GDD 02) through `ProgressionStore` with fixed seeds and asserts each
   lands inside its target band. Lives in `VesperTests`; runs in CI.
2. **Diary extension** — the playtest diary runs 3 weeks with the nightly probe
   *"did anything new happen tonight?"*.
3. **Exit criterion** — **no persona goes more than 5 evenings without a
   discovery in weeks 1–4.** A discovery is any first: a new pop, a secret, a
   first fortune of a set, a keepsake, a visitor on the Path.

## 3. Unlock rules

Each pop carries exactly one `UnlockRule`:

| Rule | Counts | Used for |
|------|--------|----------|
| `start` | — | #001 only. The classic is always there. |
| `points(n)` | lifetime pop points (docs/pop_points.md) | ~80% of the catalog; thresholds rise smoothly from 100 to a Morningside ceiling of ~200,000 (provisional — final values are set by the §2 sim harness, not inherited) |
| `totalPops(n)` | lifetime orbs set free | one per family band (150 → 60,000) |
| `fieldsCleared(n)` | fields fully cleared | 5 → 110 |
| `fortunesFound(n)` | fortune orbs found | 3 → 35 |
| `bestChain(n)` | longest single cascade | 4 → 10 (secret #050 at 10) |

All numeric thresholds in this table are working values: the §2 harness owns the
final numbers, band by band, against the evening targets.

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
