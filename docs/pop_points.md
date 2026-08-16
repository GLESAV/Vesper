# Pop Points

*The scoring system: how popping is tracked AAA-style while staying zen.
Implementation: `GameViewModel.points(for:sizeNorm:fortune:)`,
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
points = rarityBase × sizeFactor × chainMultiplier  (+ fortuneBonus)
```

| Term | Value | Why |
|------|-------|-----|
| `rarityBase` | common 10 · uncommon 25 · rare 60 · secret 150 | finding rarer pops feels like finding them |
| `sizeFactor` | `1 + 0.5 × sizeNorm` → ×1.0 (smallest) … ×1.5 (largest) | big orbs pop deeper; the ear, hand, and score agree |
| `chainMultiplier` | `1 + 0.1 × (chainLength − 1)`, capped at ×2 | cascades feel abundant, never mandatory |
| `fortuneBonus` | +50 flat | a found fortune is a small gift |
| **field clear** | **+100 flat** | finishing the breath |

Chain length uses the same rolling 0.9 s window as the "chain of N" whisper, so what
the player sees and what they earn are one number. The cap at ×2 keeps chains a
pleasure, not a strategy to optimize.

Typical session math: a 13-orb field ≈ 200–350 points + 100 clear bonus, so an
ordinary wind-down evening (a handful of fields) earns roughly 1.5–2.5k points.
That **per-evening** figure — not points per hour — is what the unlock ladder in
`pop_progression.md` paces against: the binding target is the median evening
player reaching Morningside in 90–120 evenings, with even a heavy player never
finishing in under 30 days (GDD 03 §2). The formula's constants and the ladder's
thresholds are validated together by the Phase 2 deterministic sim harness
(persona profiles replayed through `ProgressionStore` against the target bands,
per `pop_progression.md` §2); the harness, not the inherited curve, owns the
final numbers.

## 3. Showing points *in game* (best practice: layered, quietest first)

Following AAA feedback layering — immediate → session → persistent — but tuned down
to Vesper's register:

1. **Point whispers** (immediate): a small serif `+12` drifts up from the pop and
   fades in ~1 s. Rendered in the Canvas with the same additive glow as everything
   else — it reads as part of the burst, not UI. Toggleable in Settings
   ("Point whispers"), because some players want pure silence; points still accrue.
2. **Session line** (ambient): under the DETONATED counter, a 9 pt
   `346 pop points` ticks up. No animation begging for attention.
3. **Chain feedback**: the existing "chain of N" whisper doubles as the multiplier
   readout — one concept, one number.
4. **Done card** (session summary): `+446 pop points`, then the lifetime line
   (`12,431 set free, all time`). The moment of completion is the only place the
   session is summed — no interstitial score screens.
5. **Unlock capsule**: when a total crosses a threshold — `✦ new pop · Gloaming` —
   the points system pays off in *content*, which is the entire reason it exists.

## 4. Showing stats *outside* the in-game experience

**The Journey screen** (✧ in the top bar — `Views/JourneySheet.swift`) is the
out-of-field stats home, styled like a quiet trophy room:

- lifetime **pop points** as the headline figure
- records row: orbs set free · fields cleared · fortunes · best chain
- "somewhere ahead": the next unlock with a soft progress bar
- the collection: 100 cells, each unlocked pop in its own paint (VoiceOver reads
  its per-pop tally), secrets as `?`

**Beyond the app**, in order of delivery:

1. **Journey dashboard (delivered with this change)** — a shareable web dashboard
   mock of the full AAA stats presentation (points, records, phase progress, the
   100-cell collection), used as the design reference for everything below.
2. **Home-screen widget (M2, planned)** — WidgetKit small/medium: lifetime points
   + "set free" count in the app's palette. Reads the shared `UserDefaults` app
   group; no network, nothing leaves the device.
3. **App Shortcuts (M2, planned)** — "How many orbs have I set free?" answered by
   Siri from on-device data.

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
