# Vesper — Delivery Roadmap (One World build)

*The execution plan for `docs/gdd/` Phase 0a–0b, ending in a build the owner
and Kate can play. Every **work item** below is one dedicated engineering
subprocess (Opus 5) with a named owner and a written acceptance test. Every
**review gate** is a subprocess critique by the named board members. The
Director of Engineering approves this roadmap and rules on every gate dispute.*

**Status:** submitted to the Director of Engineering for approval. No work item
starts before her ruling lands in §6.

## 1. Objective

Ship a **playable One World build** on two surfaces:

1. **The app** — Swift, behind `WorldFlags.oneWorldEnabled`, CI-green, ready
   for the owner to run in Xcode and put on a device.
2. **The demo** — the browser build updated to the same navigation, so the
   owner and Kate can playtest *today*, without a Mac.

Both are playtest instruments, not the release. Release decisions come after
the owner's and Kate's sessions.

## 2. Standing rules for every work item

- The simulation stays **pure and deterministic**; no UI imports, no wall-clock.
- The old navigation stays behind the flag until R-NAV passes. Nothing is
  deleted early.
- Every item lands with tests where testable, and CI green.
- The pop's feel is never traded for scope (the cut order in `00`).
- Copy comes from the string catalog, never inline literals.

## 3. Epics and work items

### E0 — Foundations & the spike

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W01** | ARCH Ilya | `World/WorldCamera.swift`: pure camera state machine — `Place` (sky/field/journal), normalized offset, drag/settle/commit, threshold + velocity gate, Reduce Motion mode (crossfade, no drift), `isInterruptible`. No SwiftUI. | Unit-testable; no UIKit/SwiftUI import; every transition expressible without a view |
| **W02** | QA Aiko | `VesperTests/WorldCameraTests.swift`: place transitions, threshold/velocity commit, interrupt mid-settle, RM mode, no-move-unasked invariant, idempotent settle | ≥ 12 cases; all pass; deterministic |
| **W03** | INPUT Rafael | `World/WorldInputView.swift`: extend the UIKit tap layer to pan+tap arbitration — **pop fires on touch-down and always wins ties**; pan commits only past distance *and* velocity; ~10% edge dead zones; no `preferredScreenEdgesDeferringSystemGestures` | Tap latency unchanged vs v1.2 path; zero pops swallowed by pan in a 100-tap script |
| **W04** | REND Mei | `World/WorldView.swift` skeleton: one continuous scene, three layers positioned by camera offset, field canvas unchanged and position-independent; `WorldFlags` gate | Old `ContentView` still runs with flag off; new world runs with flag on |
| **GATE** | **R-ARCH** | Nadia (chair) · Ilya · Keiko (CONC) | Buildable, pure, testable, reversible; publishing-during-view-update hazard addressed |
| **GATE** | **R-SPIKE** | Jun Park · Imani Brooks · Viktor (PERF) | Go / fallback stage 1 (tap-labels primary) / fallback stage 2 (static field, in-world panels) |

### E1 — One World core

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W05** | REND Mei | Camera motion + parallax: finger-tracked 1:1, release-velocity settle (300–650 ms settle only), mote parallax across places, RM crossfade variant | 60/120 fps held during transition; motion has a source, nothing snaps |
| **W06** | REND Mei | `World/WhisperLabel.swift`: typographic wayfinding (`✦ the sky`, `your journal`) — breathes when idle, dims to a floor (never zero), never fades with assistive tech on, ≥44 pt hit region, tappable | Contrast floor met at min brightness; VoiceOver sees it always |
| **W07** | ARCH Ilya | `WorldModel` (ObservableObject): current place, camera binding, place-scoped lifecycle (sim pauses off-field), single source of truth for navigation | Sim steps only when the field is on screen; state survives backgrounding |

### E2 — The places

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W08** | DATA Tomás | `MapStore` → the **trace**: settled roads transmute into permanent constellation lines (never disappear); stones stay tappable; migration from the old fading model | Existing `MapStoreTests` updated and green; no stone is ever destroyed |
| **W09** | REND Mei | `World/SkyView.swift`: the Path as constellation — stars = stones at 60% orb scale with family paints, roads as dashed light, trace dimmer; tap a star → camera returns to field, field seeds from it; exit without choosing | Star hit areas ≥44 pt; overlapping stars resolve by tap-zoom |
| **W10** | DATA Tomás | `ProgressionStore` v2: fortunes archive (re-readable), the lamp as a **single warm aggregate** (absence structurally unrepresentable), keepsakes per completed family | No date axis anywhere; no field can reveal a skipped evening |
| **W11** | REND Mei | `World/JournalView.swift`: pages — evening (points, records, lamp) · collection · fortunes kept · keepsakes · **the quiet things** (sound, haptics, whispers, transition sounds, about, "begin again") | Settings reachable ≤2 gestures from the field; page turns are motion with a source |
| **W12** | INPUT Rafael | Quick-quiet affordance: mute sound/haptics in ≤2 gestures from anywhere; silent-switch honored; long-press "begin again" arming (empty space only; a press on an orb always pops) | **Mute in under 5 seconds, one-handed, first attempt** |
| **GATE** | **R-NAV** | Jun Park · Renata Cole · Dani | Can a real person find the sky and the journal, in bed, unprompted? |
| **GATE** | **R-SYS** | Marta Okafor | Does the trace/lamp/keepsake set still only ever accrue? |

### E3 — Voice & the first hour

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W13** | ARCH Ilya | `Support/Strings.swift`: centralized catalog; every user-facing string moves in; `DETONATED` → **set free**; the canonical whispers | No inline user-facing literals remain in views |
| **W14** | QA Aiko | `VesperTests/StringsTests.swift`: forbidden-vocabulary test (streak, fail, miss, expire, lose, blast, destroy, kill, score, limited, hurry, last chance) over the whole catalog | Fails loudly on any violation; runs in CI |
| **W15** | REND Mei | W1 onboarding: five-orb first field, three whispered lines, the first star descending; **zero tutorial screens**; plus the arrival moment (motes assemble the field, skippable by tapping) | Cold install → first pop < 15 s |
| **W16** | REND Mei | Evening light: ambient hue drifts with local time on-device; dimmest and gentlest after midnight | ±4% shift only; comfortable at min brightness in a dark room |
| **GATE** | **R-VOICE** | June Ashford · Aria Vale | Every string passes the 1 a.m. kitchen test |
| **GATE** | **R-ART** | Sofia Lindqvist · Aria Vale | Does it read as the held evening, not as software? |

### E4 — Parity & proof

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W17** | A11Y Lena | Accessibility contract: VoiceOver flows for every place (destinations always in the tree regardless of visual fade), custom actions, labels on world-objects, ≥44 pt invisible hit regions, Dynamic Type in the journal | Eyes-closed VoiceOver round trip: field → sky → field → journal → quiet things |
| **W18** | A11Y Lena | Reduce Motion matrix: every named motion has a defined reduced variant; world-move sounds **always** play under RM as the orientation cue | No motion-only information anywhere |
| **W19** | AUDIO Priya | World-move sounds (rising shimmer to sky, page-weight to journal, derived from the pop synth), settle haptic tick, transition-sounds toggle | Nothing exceeds the pop's peak; muted parity intact |
| **W20** | QA Aiko | Regression + instrumentation: all suites green, tap-success within 2% of v1.2 baseline via the deterministic sim, zero unintended camera transitions in a scripted pop storm | CI green; false-trigger criterion measured, not asserted |
| **GATE** | **R-A11Y** | Imani Brooks · Amara Osei (VEST) | Is parity designed in, and is the camera safe for motion-sensitive players? |

### E5 — Playtest delivery

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W21** | TOOLS Sam | Browser demo → One World parity: the same three places, the same gestures, whispers, quiet things — the surface the owner and Kate can play today | Plays on a phone browser; no icons; sky and journal reachable by swipe and by tap |
| **W22** | TOOLS Sam | `docs/PLAYTEST.md`: how to run the app in Xcode, how to open the demo, what to look for, and the three questions to answer after playing | A non-engineer can follow it end to end |
| **GATE** | **R-SHIP** | Hana Sato · Marcus Bell (REVIEW) · Aiko | Is this honestly playtestable and safely reversible? |
| **GATE** | **R-BOARD** | Full board | Checkpoint on the built artifact against the mission |

## 4. Sequencing

```
E0 ─ R-ARCH ─ R-SPIKE ─┬─ E1 ─ E2 ─ R-NAV ─ R-SYS ─┬─ E3 ─ R-VOICE ─ R-ART ─┐
                       │                            │                        │
                  (fallback stages                   └── E4 ─ R-A11Y ─────────┤
                   if R-SPIKE blocks)                                         │
                                                        E5 ─ R-SHIP ─ R-BOARD ┘
                                                                   ↓
                                                    owner + Kate playtest
```

Work items inside an epic run in parallel where they do not share files;
gates are barriers. A **block** at any gate returns the item to its owner with
the finding, and the epic does not advance until it clears or Nadia rules.

## 5. Definition of done for this roadmap

- The app builds and passes CI with One World behind the flag, and the flag on
  is the default for playtest builds.
- The browser demo plays the same navigation.
- Every gate has been run and recorded, with blocks resolved.
- `docs/PLAYTEST.md` exists and is followable by the owner and Kate.
- Nothing in the shipped v1.2 experience is deleted or degraded.

## 6. Director of Engineering rulings

*Applied to this roadmap at approval — see the approval record appended below.*
