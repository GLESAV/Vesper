# The Pop Standard

*The formal definition of a "pop" — Vesper's unit of content. Schema:
`Vesper/Game/Pops/PopStandard.swift` · catalog: `PopCatalog.swift` · enforced by
`VesperTests/PopCatalogTests.swift`.*

## 1. What a pop is

A **pop** is a complete description of one way an orb can look, burst, sound, feel,
and ripple — expressed **purely as data**. The engine (simulation, renderer, audio,
haptics) interprets pop definitions; authoring a new pop never touches engine code.

```
PopDefinition
├── number      1…100, stable forever (append, never renumber)
├── name        one or two words, evening-flavored
├── family      vesper · ember · tide · bloom · frost · chime · lantern · current · prism · aurora
├── rarity      common (10 pts) · uncommon (25) · rare (60) · secret (150)
├── flavor      one calm line, written in the fortune voice
├── style       PopStyle      — how it looks
├── behavior    PopBehavior   — what one burst does (particles, sound, haptic)
├── chain       ChainBehavior — how its shockwave talks to neighbors
└── unlock      UnlockRule    — how a player earns it (docs/pop_progression.md)
```

### PopStyle — look
| Field | Meaning | Classic (#001) |
|---|---|---|
| `paints` | 1–5 fill+glow variants; each orb picks one at seed | the original five palette pairs |
| `particleShape` | `dot` `spark` `petal` `shard` `ring` | `dot` |
| `particleSizeRange` | debris size, pt | `1.2…3.4` |
| `haloOpacity` | additive glow strength | `0.18` |
| `highlightOpacity` | specular whisper | `0.14` |
| `shimmer` | subtle brightness pulse | `false` |

### PopBehavior — burst
| Field | Meaning | Classic |
|---|---|---|
| `particleCountBase` | debris count (+1 per pt of radius) | `18` |
| `particleSpeedRange` | initial debris speed | `1.2…6` |
| `particleGravity` | fall rate | `0.07` |
| `sound` | `startFreq / freqSpread / sweep / duration / decay / brightness` | `460 / 420 / 0.55 / 0.14s / 7.5 / 0` |
| `haptic` | `baseIntensity / intensityPerSize / sharp` | `0.35 / 0.5 / soft` |

### ChainBehavior — ripple
| Field | Meaning | Classic |
|---|---|---|
| `ringCount` | rings per burst (extras are visual echoes) | `1` |
| `maxRadiusBase` + `maxRadiusPerOrbRadius` | reach | `110 + 2.6·r` |
| `growthFactor` + `growthLinear` | wavefront speed | `0.1 / 1.5` |
| `shellThickness` | how forgiving the wavefront is | `24` |
| `disarmFraction` | ring stops chaining past this | `0.5` |
| `lifeDecay` | fade rate | `0.03` |

**Chain rule (inherited from v1.0, deliberately kept):** only the ring of a
*directly tapped* orb arms chain reactions. Rings born from chained pops are visual
echoes. One tap = one wavefront; cascades have a natural, bounded rhythm.

## 2. Authoring rules

1. **#001 is sacred.** Pop #001 "Vesper" codifies the original game exactly; its
   numbers come from `GameConfig` and the original palette. It never changes.
2. **Stay in the envelope.** Every field has a tested range (see
   `testEveryPopStaysInsideTheStandardEnvelopes`): sounds 200–800 Hz starts,
   50–500 ms, rings 1–3, halo 0.1–0.4, gravity ≤ 0.15, etc. The envelope *is* the
   aesthetic: nothing harsh, loud, or frantic can be expressed inside it.
3. **Muted colors only.** Fills live in the pastel band (roughly 150–245 per
   channel); glows are slightly deepened fills. No saturated primaries, no pure white.
4. **Flavor is a fortune.** One line, lowercase-calm, kind, never instructive.
5. **Names are evenings.** Short, concrete, dusk-adjacent. No numbers, no puns
   that wink too hard.
6. **A pop must be tellable apart** from its family neighbors by at least two of:
   paint, shape, sound, chain feel. Otherwise it's a duplicate, not a pop.
7. **Rarity is celebration, not power.** Rarity changes point value and how it
   feels to find one — never gameplay advantage. There is no "better" pop.

## 3. The 100

Ten families of ten, in catalog order — each family one mood of the same calm:

| # | Family | Mood | Signature |
|---|--------|------|-----------|
| 001–010 | Vesper | the original dusk | soft dots, the classic tone |
| 011–020 | Ember | warmth without harm | sparks, quicker warm tones |
| 021–030 | Tide | the weight of water | slow heavy rings, deep tones |
| 031–040 | Bloom | soft things opening | petals that float |
| 041–050 | Frost | clarity, kept cold | glassy shards, bright chirps |
| 051–060 | Chime | the sound holds longer | ring debris, long bell tones |
| 061–070 | Lantern | carried light | big halos, amber warmth |
| 071–080 | Current | gentle electricity | double rings, crisp sparks |
| 081–090 | Prism | light, taken apart kindly | shimmer, multi-paint variants |
| 091–100 | Aurora | the sky's slow applause | wide rings, drifting shimmer |

Secrets: **#050 Polar Night**, **#080 Stormglass**, **#100 Morning Star** (Vesper's
other name — the finale of the collection).
