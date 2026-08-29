# Pop Progression — "The Journey"

*How the 100 pops are earned. Implementation: `Support/ProgressionStore.swift`,
unlock rules on each entry in `PopCatalog.swift`, UI on the journal's
*collection* page (`World/JournalView.swift`). `Views/JourneySheet.swift` is the
v1.2 screen this replaced; it compiles only under `VESPER_CLASSIC_NAV`.*

## 1. Design position: are there levels?

**No.** Vesper has no levels, no XP bars to fail, no gates that close. Progression is
a single continuous **journey** that only ever moves forward:

- Nothing is ever lost, spent, or reset. Every counter only goes up.
- Nothing is time-limited. There are no dailies, streaks, or expiring anything.
- Nothing is comparative. There are no leaderboards; the journey is yours alone.
- Every pop is reachable through ordinary play — no purchases, no grinding walls.
  The first new pop arrives in the first session; the whole catalog opens over a
  season of evenings (§2), never in a weekend.
- Locked pops show a *kind hint* ("arrives at 700 pop points", "arrives after a
  chain of 5"), never a wall or a timer. The hints are deliberately **stative,
  not imperative**: read one at a time each of `gather` · `set` · `clear` ·
  `find` · `ride` was kind enough, but a hundred of them on one page is a task
  list, and a task list is an obligation. Every number stayed the same when the
  wording changed (`UnlockRule.hint`).

Instead of levels, the catalog opens in six **phases of the evening** — named bands
that describe where you are, purely cosmetically. A phase never gates anything; it's
how the journey talks about itself.

**The phases are a design vocabulary, not a feature.** No phase name appears
anywhere in the app or in `ProgressionStore`; they exist so this document, and
the people tuning the ladder, have a way to say *where* in the hundred a pop
sits. If they ever become something a player reads, that is a change to build,
not a change to describe.

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

**Validation (Phase 2 workstream — planned, none of it built yet).** Because the
simulation is pure and `ProgressionStore` is UI-free, pacing is *meant* to be
checked in code rather than by feel. As of this writing none of the three exists;
the thresholds in §3 are still the inherited curve and have never been measured
against the evening bands above.

1. **Deterministic sim harness** — would replay persona play profiles (Maya /
   Dani / Priya, GDD 02) through `ProgressionStore` with fixed seeds and assert
   each lands inside its target band. **Not written.** `VesperTests` contains no
   pacing or persona test; `ProgressionStoreTests` pins the store's arithmetic
   and its doors, not how long the journey takes.
2. **Diary extension** — the playtest diary running 3 weeks with the nightly
   probe *"did anything new happen tonight?"*. `docs/PLAYTEST.md` is a
   single-question navigation playtest and does not carry this probe.
3. **Exit criterion** — **no persona goes more than 5 evenings without a
   discovery in weeks 1–4.** A discovery is any first: a new pop, a secret, a
   first fortune of a set, a keepsake, a visitor on the Path.

## 3. Unlock rules

Each pop carries exactly one `UnlockRule`:

| Rule | Counts | Used for |
|------|--------|----------|
| `start` | — | #001 only. The classic is always there. |
| `points(n)` | lifetime pop points (docs/pop_points.md) | **69 pops** — thresholds rise smoothly from 100 to a Morningside ceiling of **109,000** |
| `totalPops(n)` | lifetime orbs set free | **10** — one per family band (150 → 60,000) |
| `fieldsCleared(n)` | fields fully cleared | **8** (5 → 110; secret #100 at 100) |
| `fortunesFound(n)` | fortune orbs found | **6** (3 → 35; secret #080 at 25) |
| `bestChain(n)` | longest single cascade | **6** (4 → 10; secret #050 at 10) |

Counts and ranges above are read from `PopCatalog.swift` and are the values that
ship. They remain *working* values in the sense that the §2 harness is meant to
re-derive them against the evening targets — but that harness does not exist yet,
so nothing has re-derived them, and this table is the ladder as it stands.

Condition rules are sprinkled so that *how* you play occasionally opens a door that
points alone wouldn't — a long chain, a patient streak of clears, a lucky fortune —
but there is always a points-based door nearby, so no play style is ever stuck.

Secrets (#050 Polar Night · a chain of 10, #080 Stormglass · 25 fortunes,
#100 Morning Star · 100 fields) use condition rules and show only a `?` in the
collection until found — and keep their names as well as their paint until then,
so a secret is a shape in the grid rather than a labelled absence.

## 4. How unlocks surface (in game)

- The moment a rule is met, a soft capsule appears in the single note slot under
  the counter: **“✦ new pop · Gloaming”**, or **“✦ 2 new pops found”** when a
  clear opens more than one at once. It fades by itself after ~3.5 s; it never
  blocks a tap. The slot holds one thing at a time and the capsule outranks the
  path note and the chain whisper, because an unlock happens once and a chain
  happens often.
- New pops join the field **from the next field onward** — the current field is
  never disturbed.
- The journal's *collection* page shows the hundred: `N of 100`, then 100 cells.
  Unlocked pops wear their own paint and their name; locked ones are a dim disc
  under `· · ·` and answer a tap with their hint, pinned at the foot of the page
  rather than inserted into the grid — a hint that scrolls off screen is silence
  in reply to a deliberate press. Secrets show `?`.

## 5. Featuring and Drift

The player chooses how fields are painted, on the journal's *collection* page:

- **Featured pop** — tap any unlocked cell; every orb in new fields uses it. For
  sitting with one mood.
- **Drift** (default) — the `drift` row above the grid. Each new field mixes orbs
  from everything unlocked. The collection you've built *is* the game you're
  playing.

Both are one tap. Both also **step off the Path** (`GameViewModel.leavePath`
clears the active stone) and reseed a fresh field immediately, then carry you
back to it — free play and the Path are the same field, differently seeded, and
tapping any star in the sky steps back on. Neither affects points or unlocking.
There is no wrong choice.

## 6. Persistence

All progression lives in `UserDefaults` on device (`ProgressionStore`): points,
counters, per-pop tallies, featured selection. Unlocks are *derived* from counters
at read time — there is no separate unlock state to corrupt or migrate. Pre-1.1
lifetime counters carry over via their original keys. Nothing leaves the device.
