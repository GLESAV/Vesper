# Vesper — Delivery Roadmap (One World build)

*The execution plan for `docs/gdd/` Phase 0a–0b, ending in a build the owner
and Kate can play. Every **work item** is one dedicated engineering subprocess
(Opus 5) with a named owner and a written acceptance test. Every **review gate**
is a subprocess critique by named board members. The Director of Engineering
approved this roadmap with amendments; her rulings are §6 and are binding.*

**Status:** approved with amendments by the Director of Engineering. Rulings in
§6 are applied throughout this document.

## 1. Objective

A **playable One World build on a real device**, behind
`WorldFlags.oneWorldEnabled`, CI-green, installable by the owner and by Kate —
with real haptics, real audio, and real frame pacing. This build exists to
answer one question: **does the world read as one place, and does moving
through it feel better than tapping icons?**

It is not a release, and it does not try to be the whole plan.

## 2. Standing rules for every work item

- The simulation stays **pure and deterministic**; no UI imports, no wall-clock.
- **The camera's continuous offset is never `@Published`** (ruling 7).
- **The input layer is never rebuilt by camera motion**, and the field `Canvas`
  is pinned to a constant size at every camera position (ruling 8).
- `WorldFlags.oneWorldEnabled` is read in **exactly one place** — `VesperApp`
  choosing `ContentView()` or `WorldView()` (ruling 10).
- CI builds **both** flag configurations on every PR (ruling 11).
- Persisted-schema changes are out of scope for this build (rulings: W08/W10
  deferred) — the flag protects surfaces, not save files.
- Accessibility is co-authored into each world item as it lands, never
  retrofitted (ruling 12).
- Copy for new surfaces comes from the string catalog (ruling 14 scope).

## 3. Epics and work items

### E0 — The spike (runs alone, first)

The vertical camera bet is proven before any production code exists. W03 is a
throwaway; nothing else starts until R-SPIKE rules.

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W03** | INPUT Rafael | Input arbitration: a single `UIView` subclass over raw `touchesBegan/Moved/Ended/Cancelled` — **no** `UIPanGestureRecognizer`, **no** `require(toFail:)`, `delaysTouchesBegan`/`cancelsTouchesInView` false (ruling 5). A touch beginning on an orb **pops immediately in `touchesBegan` and continues to be tracked as a potential pan; both may resolve** — the pop is never cancelled by pan, the pan never by the pop (ruling 4). ~10% edge dead zones; no `preferredScreenEdgesDeferringSystemGestures`. The arbitration core is a **pure struct** so it is provable without a device. | Pure `InputArbiter` unit-tested; **20 consecutive swipes begun directly on an orb → 20 pops fired, 20 camera commits** (ruling 6); tap-to-pop median and p99 measured on device and reported against the v1.2 touch-**up** baseline, with the input-model change stated (ruling 3) |
| **W20a** | QA Aiko | Capture the **v1.2 tap-success baseline** through the deterministic simulation, before any world code lands (ruling 15) | A committed number, reproducible in CI |
| **GATE** | **R-SPIKE** *(barrier)* | Jun Park · Viktor (PERF) · **Amara Osei (VEST) as a barrier condition** (ruling 18) | Go / fallback stage 1 (tappable whispers primary) / fallback stage 2 (static field, in-world panels). Motion safety is a pass condition, not a note. |

**Device reality:** the oldest supported device is **A12-class (iPhone XR/XS
era, iOS 18.5)**. On-device latency and frame pacing are measured by the owner
on real hardware; everything provable in software is proven in CI first
(ruling 16).

### E1 — One World core

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W01** | ARCH Ilya | `World/WorldCamera.swift`: pure camera state machine — `Place` (sky/field/journal), normalized offset, drag/settle/commit with distance **and** velocity gates, Reduce Motion mode (crossfade, no drift), interruptibility. **Tests are folded into this item** (ruling 12) | No SwiftUI/UIKit import; ≥12 deterministic test cases incl. interrupt-mid-settle and the no-move-unasked invariant |
| **GATE** | **R-ARCH** *(barrier)* | Nadia (chair) · Ilya · Keiko (CONC) | Buildable, pure, reversible; **the non-`@Published` offset is a named pass condition** |
| **W04** | REND Mei | `World/WorldView.swift` skeleton + `Support/WorldFlags.swift`; flag read only in `VesperApp` | Flag off → v1.2 exactly; flag on → the world; field canvas constant-size at every offset |
| **W07** | ARCH Ilya | `World/WorldModel.swift`: publishes `place` only; **explicit `simActive` flag checked at the top of `GameViewModel.frame(date:size:)`** (ruling 9) | Sim provably steps only on the field; unit-tested, not inferred from SwiftUI |
| **W05** | REND Mei | Camera motion: finger-tracked 1:1, release-velocity settle (300–650 ms applies to settle only), mote parallax, RM crossfade variant | Input layer identity unchanged across a move; no per-frame world-body rebuild |
| **W06** | A11Y Lena | `World/WhisperLabel.swift`: `✦ the sky` / `your journal` — breathes when idle, dims to a floor (never zero), **never fades with assistive tech on**, ≥44 pt hit region, tappable | VoiceOver sees both destinations at all times |

### E2 — The places *(reassigned off Mei — ruling 13)*

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W09** | DATA Tomás | `World/SkyView.swift`: the Path as constellation over the **existing** `MapStore` (no migration) — stars = stones at 60% orb scale in family paints, roads as dashed light; tap a star → return to field, seed from it; exit without choosing | Star hit areas ≥44 pt; renders today's stones truthfully |
| **W11** | A11Y Lena | `World/JournalView.swift`: pages — evening (points, records) · collection · **the quiet things** (sound, haptics, whispers, transition sounds, about, "begin again") | Reachable ≤2 gestures from the field; VoiceOver-complete on arrival |
| **W12** | INPUT Rafael | Quick-quiet: mute sound + haptics in ≤2 gestures from anywhere; long-press "begin again" arms on empty space only (a press on an orb always pops) | **Mute in under 5 seconds, one-handed, first attempt** |
| **W13′** | ARCH Ilya | `Support/Strings.swift` — **scoped** (ruling 14): the counter label (`DETONATED` → **set free**), the canonical whispers, and new world strings only. Repo-wide literal migration waits for structural stability | No new inline literals; `DETONATED` gone from the build the owner sees |
| **W14** | QA Aiko | `StringsTests`: forbidden-vocabulary test over the catalog (streak, fail, miss, expire, lose, blast, destroy, kill, score, limited, hurry, last chance) | Fails loudly in CI on any violation |

### E3 — Proof & delivery

| ID | Owner | Work | Acceptance |
|---|---|---|---|
| **W20** | QA Aiko | Instrumented regression *(barrier)*: all suites green; tap success within 2% of the **W20a** baseline; **zero unintended camera transitions in a scripted pop storm** | Measured, not asserted; both flag configurations build |
| **W24** | QA Aiko | **New** (ruling: added): a DEBUG-only "fresh install" state reset so playtest sessions are repeatable and a first-run field can be seen again | One action; wipes progression + map; unavailable in release builds |
| **W23** | TOOLS Sam | **New** (ruling: added): TestFlight internal distribution path — the honest playtest surface: real device, real haptics, installable by Kate without Xcode; exercises the release pipeline early | Documented end to end; owner-executable |
| **W22** | TOOLS Sam | `docs/PLAYTEST.md`: how to run it (Xcode **and** TestFlight), what to look for, and the three questions to answer after playing | A non-engineer can follow it |
| **GATE** | **R-CRAFT** *(concurrent, advisory)* | Sofia Lindqvist · June Ashford · Aria Vale | Does it read as the held evening, and does every string pass the 1 a.m. kitchen test? Notes become work items; the line does not stop (ruling 19) |
| **GATE** | **R-A11Y** *(concurrent, advisory)* | Imani Brooks | VoiceOver/Dynamic Type review as items land; the motion-safety half already ran as an R-SPIKE barrier (ruling 18) |

## 4. Sequencing

```
W03 spike + W20a baseline ─ R-SPIKE (barrier, incl. motion safety)
   │
   ├─ go ──────────────► W01 ─ R-ARCH (barrier) ─ W04 ─ W07 ─ W05 ─ W06
   ├─ fallback stage 1 ─► tappable whispers primary, camera retained
   └─ fallback stage 2 ─► static field, in-world panels, no camera
                                  │
        W09 · W11 · W12 · W13′ · W14  (parallel, distinct owners and files)
                                  │
                  W20 (barrier) ─ W24 ─ W23 ─ W22 ─► owner + Kate playtest ─ R-BOARD
```

**Barriers are exactly three: R-SPIKE, R-ARCH, W20** (ruling 20). Everything
else advises and does not stop the line.

## 5. Deferred and cut (with reasons)

| Item | Ruling |
|---|---|
| **W21** browser-demo parity | **Cut.** The demo is an 811-line hand-written fork (7 of 100 pop families, a hardcoded lifetime, no haptics, no CoreAudio, browser touch fighting Safari's edge gestures). A gesture-arbitration playtest there would produce confident wrong answers about the exact risk R-SPIKE exists to retire, and two hand-written engines drift within a sprint. The v1.2 demo stays frozen as a v1.2 artifact. |
| **W08** trace / MapStore migration | **Deferred.** One-way persisted-schema change the view flag cannot protect; "no stone is ever destroyed" is retroactively unachievable because `prune()` has already deleted stones. The sky renders existing stones. |
| **W10** ProgressionStore v2 (lamp, keepsakes, fortune archive) | **Deferred.** Same one-way persistence exposure; not required to answer whether the world reads as one place. |
| **W15** onboarding + arrival | **Deferred, still Protected for v2.0.** Only fresh testers can evaluate a first run; neither the owner nor Kate is fresh. |
| **W16** evening light | **Deferred.** A ±4% hue drift cannot be judged in one evening and is orthogonal to the navigation question. |
| **R-SYS** | Drops out with W08/W10 — no new accrual surface in this build. |
| **R-SHIP** | **Cut for this build.** Its substance for a non-submitted build is "CI green and the flag reverses," which is W20's acceptance. |
| **R-BOARD** | **Moved** to after the owner's and Kate's sessions — a full-board review belongs on evidence, not on a hypothesis. |
| **R-NAV** → **R-NAV-SMOKE** | **Non-binding.** The real gate needs n ≥ 8 fresh testers recruited outside the owner's network at ≥7/8; this build's panel is two insiders, one of whom created the game. Recording it as a pass would contaminate every downstream measurement claim. The bar is not lowered to meet a schedule. |

## 6. Director of Engineering rulings *(binding, verbatim)*

1. Do not claim an approval the roadmap does not have. *A roadmap that claims an approval it lacks is the first sign a team will later claim a gate it did not pass.*
2. W03 is the spike; it runs alone, on a throwaway branch, **before** W01/W02/W04. *Otherwise a fallback-stage-2 ruling turns the camera, input layer, and world skeleton into landfill — the exact waste the spike exists to prevent.*
3. Strike "tap latency unchanged vs v1.2"; measure median and p99 on device against the v1.2 touch-**up** baseline and state the input-model change. *v1.2 fires on touch-up and W03 fires on touch-down, so "unchanged" can neither be met nor failed.*
4. A touch beginning on an orb pops immediately **and** continues as a potential pan; both may resolve. *With ~11 orbs on a portrait field, any rule where the pop suppresses the swipe makes navigation succeed or fail based on where orbs drifted — intermittent, unreproducible, indistinguishable from a bug.*
5. Implement as one `UIView` over raw touches: no pan recognizer, no `require(toFail:)`, `delaysTouchesBegan`/`cancelsTouchesInView` false. *A failure requirement reintroduces the disambiguation delay and swallowed touches that made this layer UIKit in the first place.*
6. R-SPIKE includes a scripted pass condition: 20 consecutive swipes begun on an orb → 20 pops, 20 commits. *It is the only interaction where the two systems actually collide.*
7. The camera's continuous offset is never `@Published`; `WorldModel` publishes `place` only. *A per-frame published offset rebuilds the TimelineView/Canvas/input subtree every frame — verbatim the condition v1.2 blames for cancelled taps.*
8. The input layer is a stable sibling never rebuilt by camera motion, and the field `Canvas` is pinned to a constant size at every camera position. *`GameSimulation.layout(size:)` re-seeds motes on size change; a resizing canvas scrambles the field mid-play.*
9. Pausing the sim off-field is an explicit `simActive` flag at the top of `frame(date:size:)`. *One line, deterministic, unit-testable — not an inference from undefined SwiftUI rendering behavior.*
10. `WorldFlags.oneWorldEnabled` has exactly one use: `VesperApp` choosing the root view. Forbidden in view bodies, `GameViewModel`, and stores. *The stores are shared singletons over shared UserDefaults; branch deeper and you have two games sharing one save file.*
11. CI builds both flag configurations on every PR. *An unbuilt configuration rots within days, and the flag's whole value is that v1.2 ships on any day of the rebuild.*
12. Fold W02 into W01; fold accessibility into each world item as co-authored acceptance. *QA cannot own tests for an API that does not exist, and retrofitting the accessibility tree onto gesture navigation means building it twice.*
13. Reassign W09 and W11 off Mei. *Seven items on one engineer and one file is a one-engineer-deep critical path the diagram hid.*
14. Scope W13 to the counter label, the canonical whispers, and new world strings. *A repo-wide literal migration during a view rewrite is a merge war for zero playtest value — but `DETONATED` never reaches the owner's hands.*
15. Capture the v1.2 tap-success baseline before any world code lands. *"Within 2% of baseline" is unmeasurable against a number nobody computed.*
16. Name the oldest supported device and confirm one is in the room before scheduling R-SPIKE. *A spike run only on the newest phone proves nothing about frame pacing under a continuous camera.*
17. Rename R-NAV to R-NAV-SMOKE and mark it non-binding for this build. *Two insiders cannot stand in for eight independently recruited strangers without contaminating every downstream claim.*
18. Split R-A11Y: motion-sensitivity screening becomes an R-SPIKE barrier; the rest runs concurrent. *No continuous camera goes in front of testers before someone qualified says the motion is safe — but VoiceOver labelling need not stop the line.*
19. Merge R-VOICE and R-ART into R-CRAFT, concurrent; cut R-SHIP and R-BOARD from this build. *R-SHIP's substance is already W20's acceptance; R-BOARD before anyone has played spends a full-board review on a hypothesis.*
20. Barriers are exactly three: R-SPIKE, R-ARCH, W20. *Eleven blocking gates on a pre-playtest build means more time in review than in Xcode.*

### Risks the Director owns

| Risk | Tripwire |
|---|---|
| **Pop-vs-pan on device** — the plan-killer | If the 20-attempt swipe-from-orb case fails, or p99 tap latency regresses on A12-class hardware, fallback stage 1 is called at R-SPIKE. No second attempt at threshold tuning — threshold-chasing is how two weeks becomes six. |
| **Published-per-frame camera state** re-entering the SwiftUI rebuild hazard | Any PR where camera offset reaches an `@Published` property, or the input layer's identity changes during a move, is blocked at review. One swallowed tap in the W20 pop storm stops W05 and calls in Keiko. |
| **Single-engineer critical path** on world composition | If W04 and W05 have not both landed within the first third of the build window, W09 or W11 becomes a static placeholder. The owner playing a slightly empty journal is a real playtest; the owner not playing anything is not. |
