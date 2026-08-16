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

## 7. Gate log

### R-SPIKE — **GO (with notes)** · Jun Park · Viktor Sørensen · Amara Osei

The camera bet holds. All three reviewers returned go-with-notes; Amara's
vestibular review — the barrier — passes *conditionally*, and her conditions
bind W01/W05 before any camera reaches a person. Director's rulings on the
findings, all adopted:

**Fixes to the spike itself (W03′, Rafael):**

1. **Delete the input layer's hit test.** Emit `.pop(p)` unconditionally on
   touch-down while the field is at rest; `GameSimulation.tap` stays the single
   authority on what an orb is. *Jun and Viktor found this independently: a
   second copy of the hit-test rule can only ever subtract pops, and it drifts
   against a field that keeps moving. It also keeps the W20a baseline a
   like-for-like comparison.*
2. **`fieldAtRest` becomes a closure queried at touch-down**, never a snapshot
   pushed through `updateUIView`. *SwiftUI's update pass is not ordered against
   UIKit touch delivery, so a pushed copy is wrong for about a frame at each end
   of a settle — and being wrong there costs a pop.*
3. **Add `.settleToNearest`.** A transit grab released without a decisive
   gesture settles to the nearer place by current offset — a near-complete move
   completes, an early catch springs home. *`.cancelToRest` cannot express this,
   and today a 90%-complete move would be thrown away.*
4. **Scope the dead zones to commits, not to catches.** During transit a touch
   anywhere — dead zone included — grabs the camera; the dead zone still
   suppresses commits. *Otherwise an edge touch mid-settle produces total
   silence, breaking "every move is interruptible."*
5. **Clamp release velocity** (`Config.maxCommitVelocity`). *The arbiter must
   not be able to hand the camera a number the camera is not allowed to honour.*
   — **Superseded at W05a.** The requirement stands; the location was wrong.
   `maxCommitVelocity` is deleted and the camera's clamp made total, so the
   guarantee no longer depends on an upstream file staying correct. See below.
6. **Housekeeping:** batch outcomes across the coalesced-touch loop and collapse
   consecutive `.panChanged` to one write per frame; mutate the sample buffer in
   place; iterate `touches` in deterministic (timestamp) order; retain velocity
   samples by time rather than count; add the thumb-stall test (move fast, hold
   still, lift → `.cancelToRest`).

**Design rulings (mine, prompted by the gate):**

7. **The bottom whisper is the primary path to the journal and to quiet; the
   down-swipe is the enhancement.** *Jun showed the down-swipe is the weakest
   gesture on the screen — a one-handed thumb starting low has ~144 pt of runway
   and must spend 93 of it. The five-second mute target may not depend on the
   weakest gesture. This adopts part of fallback stage 1 for the downward
   direction, deliberately and now, rather than under duress later.*
8. **Journal pages turn by tap, not by horizontal swipe.** *The arbiter owns one
   axis. A second axis solved later with a scroll view is exactly the recognizer
   conflict this layer exists to avoid.*
9. **Cards and whispers are world-level overlays that survive transit.** *A
   navigation swipe that begins on an orb pops it — Rafael estimates 20–30% of
   swipe starts on a ~11-orb field. Nothing is lost when that happens, but a
   fortune revealed on the way to the sky must still be readable when she gets
   there.*

**Amara's barrier conditions — named pass conditions at R-ARCH (W01) and on
W05:**

10. Commit the inter-place travel distance as a named camera constant in
    screen-height units, and a hard peak optical-flow ceiling; the clamped
    velocity above serves it.
11. **Reduce Motion is the default whenever the system setting is on**, observed
    live (`onAppear` + `onChange`), never read once at launch. Under RM the
    camera produces **zero translation** — places crossfade — while drag still
    gives proportional non-translating feedback, so the control never feels dead.
12. **The settle must be monotone and non-overshooting** — critically damped or
    single-signed ease-out, terminal velocity converging to zero, no rubber-band
    past the destination at any seeded velocity. *A direction reversal at the end
    of a large-field flow event is a substantial vestibular provocation.*
13. **Damp repeated spring-backs:** a return beginning within ~1 s of a previous
    return is slower and shorter, so re-attempts cannot build a low-frequency
    vertical oscillation.
14. **Attenuate pop and chain-flash peak luminance while camera speed exceeds a
    named threshold** — the light takes turns during transit, exactly as it does
    during a dense cascade.
15. **A motion-safety screen runs before any continuous-camera build reaches a
    person — Kate and the owner included, not exempt as insiders.** It ships as
    part of `docs/PLAYTEST.md` (W22): supine and seated, dark room, minimum
    brightness, forced repeated transits, and a plain "stop if you feel unwell"
    instruction with symptom notes before and after.

**The shared outcome contract** (fixed here so W01 and W03′ cannot drift):

```swift
enum InputOutcome: Equatable {
    case pop(CGPoint)                                // never retracted, ever
    case panBegan
    case panChanged(translation: CGFloat)            // cumulative, from anchor
    case commit(WorldDirection, velocity: CGFloat)   // clamped
    case settleToNearest                             // transit grab, released undecided
    case cancelToRest
}
```

### R-ARCH — **PASS (with notes)** · Nadia Rhee (chair) · Keiko Yamada

Two blocking rounds, then clean: zero blockers remaining. What the gate caught,
in order — commit resolving its destination from the place of record rather
than the camera's actual position; a Reduce Motion crossfade riding on a signed
scalar that inverts at the commit instant (found independently by both
reviewers); anti-oscillation damping that self-terminated, then leaked across a
completed commit and broke 1:1 finger tracking; a per-commit cap with a
discontinuity at the place centre; and a pause predicate naming a value that
cannot wake a SwiftUI view.

**Blocking acceptance carried onto W04** (a settle freezing mid-flight is the
failure these prevent):

- `WorldModel` publishes **`place` and `worldMoving`, and nothing else**.
  `worldMoving` is set in the same handler that calls `camera.consume(_:)` and
  cleared via a deferred `DispatchQueue.main.async` when a settle arrives — the
  render pass may never publish. The predicate is
  `paused: sim.isQuiescent && !model.worldMoving`; it may never read the camera.
- **Exactly one owner calls `camera.step(dt:)`** — the world's frame closure,
  every frame the world is on screen. A debug-build trap catches a second
  stepper (previews and debug overlays are the realistic offenders).
- Bind `isFieldAtRest` to **`{ camera.isAtRest && camera.place == .field }`**,
  not `{ camera.isAtRest }` — otherwise a touch-down while resting *at the sky*
  pops an off-screen field. `W07`'s `simActive` derives from the same predicate.
- **Ruling 8 structurally:** `WorldInputLayer` is a stable ZStack sibling —
  never inside the moving body, never `.id()`'d, never given the camera offset
  or a transform — and the field `Canvas` is pinned to a constant size.
- The view writes `camera.viewHeight` on layout and `camera.reduceMotion` from
  the live system setting (`onAppear` + `onChange`), and reads every per-frame
  scalar inside the `TimelineView` closure, never mirroring one into `@State`.

**Carried onto W05 — all closed.** Luminance attenuation consumes
`isTransitioning` and nothing else (W05b), shaped by the camera's own
crossfade so the gate opens and closes where the shape is ~0 rather than
stepping the full factor twice per navigation. The end-of-axis
acknowledgement is decided and built (W05c).

**Director's ruling on the end-of-axis acknowledgement: light, not movement.**
A soft brightening at the edge she tried to travel toward, peak opacity 0.10 —
exactly the alpha `SkyView` already gives a quiet star's halo. An iOS-style
rubber-band was rejected on three grounds: a bounce is an out-and-back
translation, which is the direction-reversal signature condition 12 removed
from the settle; under Reduce Motion it would need a second non-translating
variant, giving two behaviours to tune and two to test; and light costs zero
optical flow, so it cannot erode the ceiling condition 10 defends. It behaves
identically in both motion modes.

**W05c split `worldMoving` in two, amending an R-ARCH blocking condition.**
"`WorldModel` publishes `place` and `worldMoving` and nothing else" was written
when movement was the only per-frame camera state, so "keep the frame clock
running" and "the world is travelling" were one sentence. An acknowledgement
runs while the camera is at rest, which neither flag could express:
`worldMoving` (mirrors `!isAtRest`) gates hit-testing; `worldAwake` (mirrors
`!isIdle`) gates the pause predicate. Overloading the first would have made the
sky's stars untappable for a third of a second after every flick at the
ceiling; pausing on it would have frozen the glow mid-rise. Neither is derived
from the other — the staleness hazard R-ARCH refused. The condition's actual
prohibition, a per-frame value on that object, is unchanged and still checked
structurally.

**Closed at W05a — the two velocity ceilings are one.** The arbiter's
`maxCommitVelocity` (2400 pt/s) is deleted rather than converted, and
`WorldCamera.Config.maxOpticalFlow` (2.0 screen heights/s) is the only ceiling
on camera-generated motion in the codebase. The arbiter now reports the
finger's measured release velocity unbounded; the camera converts at the one
boundary that knows the view height, and its clamp is total over every finite
seed and reads a non-finite one as unseeded — nonsense makes this world slower,
never faster. Verified over 10 seeds x 14 start/direction pairs: peak optical
flow never exceeds the ceiling, every settle monotone and non-overshooting.

**Opened by W05a, for Amara at the next gate — the iPad ceiling.** The deleted
points ceiling bound *below* the screen-height one on any view taller than
1200 pt. On a 1366 pt iPad in portrait a whip flick used to peak at 1.76 screen
heights/s and now peaks at up to 2.0; every iPhone and every iPad in landscape
is bit-identical. The Director accepted 2.0 for the playtest build (see the
ruling below), but the open question is real and is not settled by that
acceptance: vestibular discomfort tracks *angular* flow, and a 13-inch iPad at
reading distance subtends far more visual angle than a phone, so the same
screen-height rate is genuinely more provocative there. The accident of unit
was, by luck, pointing the right way. Whether the ceiling should be a function
of device class rather than one constant is Amara's call, on iPad hardware, and
it does not block a build that two people will play on iPhones.

**Added to the device-only list by W05 (feel judgements no test can make):**
whether the mote parallax reads as depth or as the dust *swimming* — it is
out-and-back within a leg, because it must be exactly zero at both rest
offsets, so the dust falls behind and catches back up; whether a 5% transit dim
is felt at all, since it is deliberately at the conservative end and is the one
number that can be turned up without touching the camera; and whether a
luminance-only end-of-axis cue reads as "I heard you" in a bright room, which
is the one risk the ruling above accepts knowingly.

**Device-only, for the owner's pass:** ruling 6's twenty swipes begun on an orb;
tap latency median/p99 against the W20a baseline on A12-class hardware; whether
the 1.125-screen-height worst-case commit *feels* inside Amara's ceiling; and
whether a Reduce Motion crossfade reads as travel rather than as a cut.
