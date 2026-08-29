# Pop Points

*The scoring system: how popping is tracked AAA-style while staying zen.
Implementation: `GameViewModel.points(for:sizeNorm:fortune:kind:)`,
`Support/ProgressionStore.swift` · surfaced per §3–4 below.*

## 1. Philosophy

Pop points are a **diary, not a scoreboard**. They exist to make progress feel real
and unlocks feel earned — the AAA part — while refusing every pressure mechanic:

- Points **only accrue**. They are never spent, lost, decayed, or reset.
- There is **no failure case** that yields zero — every pop pays.
- There are **no comparisons** — no leaderboards, no friends' totals, no percentile.
- There is **no wallet** — points are not a currency; unlocks read the lifetime
  total, so "spending" can't exist.

## 2. The scoring formula

For each popped orb:

```
points = rarityBase × sizeFactor × chainMultiplier × animalMultiplier  (+ fortuneBonus)
```

| Term | Value | Why |
|------|-------|-----|
| `rarityBase` | common 10 · uncommon 25 · rare 60 · secret 150 | finding rarer pops feels like finding them |
| `sizeFactor` | `1 + 0.5 × sizeNorm` → ×1.0 (smallest) … ×1.5 (largest) | big orbs pop deeper; the ear, hand, and score agree |
| `chainMultiplier` | `1 + 0.1 × (chainLength − 1)`, capped at ×2 | cascades feel abundant, never mandatory |
| `animalMultiplier` | ×`GameConfig.animalPointsMultiplier` (**2.5**) on the final pop of a balloon animal; ×1 on everything else | a creature took two or three taps and a little patience to meet, so it gives more |
| `fortuneBonus` | +50 flat, added *after* the multipliers | a found fortune is a small gift |
| **field clear** | **+100 flat** | finishing the breath |

The product is rounded to the nearest whole point on the way out; every term is a
multiplication or an addition, so nothing in this formula can subtract. That
matters most for the animal: the two or three taps that did *not* finish it cost
nothing anywhere — they simply do not pay, and then the last one pays 2.5×.

Chain length uses the same rolling 0.9 s window as the "chain of N" whisper, so what
the player sees and what they earn are one number. The cap at ×2 keeps chains a
pleasure, not a strategy to optimize.

Typical session math: a 13-orb field ≈ 200–350 points + 100 clear bonus, so an
ordinary wind-down evening (a handful of fields) earns roughly 1.5–2.5k points.
That **per-evening** figure — not points per hour — is what the unlock ladder in
`pop_progression.md` paces against: the binding target is the median evening
player reaching Morningside in 90–120 evenings, with even a heavy player never
finishing in under 30 days (GDD 03 §2). The formula's constants and the ladder's
thresholds are *intended* to be validated together by the Phase 2 deterministic
sim harness (persona profiles replayed through `ProgressionStore` against the
target bands, per `pop_progression.md` §2). **That harness has not been
written** — there is no persona pacing test in `VesperTests` — so the numbers
below and the ladder in `pop_progression.md` are still the inherited curve, and
the per-evening figures in this paragraph are estimates rather than measurements.

## 3. Showing points *on the field*

Layered immediate → completion → persistent, and tuned down to Vesper's
register. **There is deliberately no running total on the field.** An earlier
draft of this section put a `346 pop points` line under the counter; it shipped,
and it was removed when the top of the field was decluttered. Three numbers in a
column made the score the subject of a screen whose subject is the orbs, so the
running figure now lives everywhere it can be *sought* and nowhere it has to be
*watched*.

1. **Point whispers** (immediate): a small serif `+12` drifts up from the pop and
   fades. Drawn in the Canvas with the same additive glow as everything else — it
   reads as part of the burst, not as UI. Toggleable on the journal's *quiet
   things* page ("point whispers"), because some players want pure silence;
   points still accrue when it is off.
2. **Chain feedback**: the "chain of N" whisper doubles as the multiplier
   readout — one concept, one number.
3. **One HUD slot, rarest first.** Under the counter sits a single slot that
   holds the unlock capsule, else the path note, else the chain whisper — never
   two at once. A field can therefore only ever show two things at the top: the
   number, and one sentence about what just happened.
4. **Done card** (the session, summed once): `N set free`, `+P pop points`, and
   the lifetime line (`12,431 set free, all time.`) when the lifetime figure
   has passed this field's count. Completion is the only place the session is
   totalled — there are no interstitial score screens.
5. **Unlock capsule**: when a counter crosses a threshold — `✦ new pop ·
   Gloaming`, or `✦ 2 new pops found` — the points system pays off in *content*,
   which is the entire reason it exists. It fades on its own after ~3.5 s and
   never blocks a tap.

## 4. Showing stats *away from the field*

**The journal** (`World/JournalView.swift`), one swipe down from the field or a
tap on the `your journal` whisper. Its first page, *the evening*, is the stats
home:

- `hush` — one tap silences sound and haptics together
- lifetime **pop points** as the headline figure
- records: set free · fields · fortunes · best chain

Its second page, *the collection*, holds the hundred: `N of 100`, the `drift`
row, and 100 cells — each unlocked pop in its own paint, VoiceOver reading its
per-pop tally; locked cells show `· · ·` and answer a tap with a kind hint
pinned at the foot; secrets show `?` and keep their names until they are met.

The v1.2 **Journey sheet** (`Views/JourneySheet.swift`) was this material's
previous home, reached by a ✧ button in a top bar. It still compiles under
`VESPER_CLASSIC_NAV` and is unreachable in the shipping build. One thing did not
come across with it: its *"somewhere ahead"* block, the next unlock with a soft
progress bar. The journal has no equivalent, by omission rather than by ruling —
see §4a.

### 4a. Not built

None of the following exists in the repository. They are listed so nobody looks
for them, and so nobody counts them as shipped:

- **"somewhere ahead"** — a next-unlock line in the journal. The Journey sheet
  had one; the journal does not.
- **Home-screen widget** — WidgetKit small/medium showing lifetime points and
  the "set free" count. Would read a shared `UserDefaults` app group; no network,
  nothing leaving the device. There is no widget extension in the project.
- **App Shortcuts** — "how many orbs have I set free?" answered from on-device
  data. No App Intent exists.
- **A web stats dashboard.** `web/` contains one file, the privacy page.

Anti-goals, permanently: Game Center leaderboards, share-to-social prompts,
weekly recap notifications. Stats are available when sought, silent otherwise.

## 5. Data model

| Key (UserDefaults) | Field | Notes |
|---|---|---|
| `vesper.progress.points` | lifetime pop points | headline figure |
| `vesper.stats.lifetimePops` | orbs set free | pre-1.1 key, carried over |
| `vesper.stats.fieldsCleared` | fields cleared | pre-1.1 key, carried over |
| `vesper.progress.fortunes` | fortunes found | |
| `vesper.progress.bestChain` | longest cascade | |
| `vesper.progress.popCounts` | per-pop tallies | `[popNumber: count]` |
| `vesper.progress.featured` | featured pop (0 = Drift) | |

Session points live only in the view model and die with the session — by design,
the only persistent number is the one that can't disappoint.
