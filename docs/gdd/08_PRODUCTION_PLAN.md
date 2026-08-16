# Vesper — Production Plan (to v2.0 "One World")

*How the plan becomes the game. Phases are sequential and each ends playable.
No dates — Vesper ships when it's calm — but every phase is sized in sessions,
and a session means one thing: **one ~3-hour focused work block** (solo dev +
AI pair, the studio model that built v1.2). The v1.2 wave actuals are recorded
in this unit before Phase 0a starts, so every estimate below has a measured
baseline behind it.*

## 0. Ground rules

- The simulation core, pop engine, catalog, points, and map **systems** are
  stable and stay — **unless the baseline fun gate (00) fails**, in which case
  a loop-depth workstream opens under the existing discipline: one
  `GameConfig` constant at a time, sim pure and deterministic, every change
  re-run through the unit tests. The fence is the default, not a license to
  ship an un-fun game.
- Every phase keeps CI green, tests grow with systems, tuning contract holds.
- The v1.2 branch is merged; v2 work proceeds in the same PR-per-wave rhythm.
- **The flag rule:** the old navigation is not deleted until the new one
  passes its exit test on-device. Both live behind a flag; the game stays
  shippable through the entire rebuild.
- **Phase 0 blocks everything** — no new features on the old navigation. And
  Phase 0a blocks Phase 0: the riskiest bet is proven cheapest and first.

### Estimation discipline

- Estimates below assume **two attempts per exit test** — with behavioral
  gates, a failed first pass is the expected case, not a surprise. Each gated
  phase additionally carries **+2 reserve sessions**.
- **The drift rule:** actual session counts are recorded at every phase
  boundary. Any phase that runs to 2× its estimate forces a scope review
  before the next phase starts — drift-blindness, not any single overrun, is
  the solo-dev burnout mechanism.

## Measurement (one protocol)

Success is measured exactly one way, defined once in **00 §"The measurement
protocol"**: TestFlight aggregates as the primary return-rate instrument, a
strictly separate diary cohort for texture, the ≥ 60%-of-panelists /
4-of-first-7-evenings release bar, and the qualitative fun gate ("described
as *fun*, not only relaxing"). Per-experience-goal proxies live in 01. This
document defines no metrics of its own; it owns the **panel, the gates, and
the schedule** that feed that protocol.

## The exit-test standard (applies to every gate)

Every phase exit test below is run to the same bar:

- **n ≥ 8 fresh testers** from the recruited panel (not the owner's network).
- **Pass at ≥ 7/8**, with **no failure sharing a common cause** — two testers
  lost the same way is a fail at any count.
- **One fix-and-retest cycle** is allowed per gate.
- **Recruitment shortfall delays the gate; it never lowers the bar.**
- **False-trigger criterion (every gate that touches the world):** zero
  unintended camera transitions during active popping, and tap-to-pop success
  within 2% of the v1.2 baseline — the latter checked continuously via the
  deterministic simulation, which makes it nearly free.
- **Context-matched tasks are performed in context** — in bed, on transit —
  not in a moderated desk grip.
- Phase 1 and Phase 2 exits carry an **enjoyment criterion** (the protocol's
  fun gate applied to the phase's new content), not only task completion.

## Baseline fun gate *(before Phase 0a — see 00)*

The recruited panel plays v1.2 as shipped for ~1 week: first-hour video +
nightly diary. Produces the return/tap-success baseline every later gate
compares against, and the fun verdict that decides whether the simulation
fence holds. The owner's-network panel is acceptable here only.

## Phase 0a — the gesture spike *(timeboxed, throwaway)*

The vertical camera + swipe navigation is the plan's highest-risk item; it is
proven in a throwaway prototype before the rebuild begins.

- **(a) On-device proof** that swipe-to-move and tap-to-pop coexist at
  v1.2-equal tap latency and frame pacing on the **oldest supported device**
  — `TapCatcherView` extended, never replaced.
- **(b) A 5-user lying-down wayfinding test**, with the go/no-go criteria
  written down *before* the test runs.
- **(c) The fallback sequence, written now, not under duress:**
  - **Stage 1** — keep the camera and the continuous world; demote swipes to
    an enhancement; tappable whisper-labels become primary navigation (least
    rework, preserves One World).
  - **Stage 2** — only if the camera itself fails the performance or
    motion-sensitivity gates: static field with full-screen in-world panels;
    fiction preserved, no continuous camera.
  - A spike failure re-scopes to the next stage; it never stalls the plan.
- **(d)** The flag rule above applies from the first Phase 0 commit.
- **Edge + threshold values:** ~10% edge dead zones, **no**
  `preferredScreenEdgesDeferringSystemGestures` — the OS exit gesture always
  works instantly; whispers verified to cover the dead regions. Swipe commit
  starts at ~10–12% of screen height plus a velocity gate; on-device testing
  picks the final numbers and **04 records the measured values**, not a guess.
- **Thumb-reach audit** (named deliverable): both small and large hand sizes
  on the largest supported iPhone; every navigation affordance reachable
  one-handed.

## Phase 0b — One World navigation rebuild

Scope (from 04): the vertical camera world (Sky/Field/Journal as one scene) ·
gesture + whisper wayfinding · Sky = the Path re-surfaced (constellation
rendering over the existing MapStore) · Journal = Journey + fortunes archive +
quiet things (settings) as pages · retire top bar, sheets, reset button
(behind the flag) · long-press start-over · copy warmth pass ("set free"
etc.) · Reduce Motion / VoiceOver parity for all of it.

The interaction spec is **completed during this build**, to 04 §5's committed
values — camera finger-tracked 1:1; release-velocity settle with the
300–650 ms band applying only to the settle; every move interruptible; the
transit input policy; the sim pauses off-field; **the camera never moves
unasked**. Likewise the reset redesign (arms only on empty space,
press-on-orb always pops, tap-confirm — never a second timed hold — with 05's
dim-and-gather treatment, plus "begin again" as a plain journal row with a
VoiceOver custom action) and the single long-press grammar (**hold to keep**,
taught once by a one-time discovery whisper). Reduced variants ship with
their motions per 05 §7.3's matrix and its standing rule — no animation
ships without a defined reduced variant; parity means every destination
reachable, every state readable, no motion-only information; world-move
sounds always play under RM.

Engineering notes: one `WorldView` owning a camera offset; the camera state
machine is pure and unit-tested; field canvas is already position-independent;
sheets' content migrates into in-world surfaces; sim untouched.

**Est. 6–8 sessions for Phase 0 total (0a + 0b), + 2 reserve.**
**Exit test** (per the standard above): a new tester finds both the sky and
the journal inside two minutes without any prompt, on video, in context;
false-trigger criterion holds; the **W6 + W1a interruption audit passes on
device** (backgrounding at every wireflow moment — mid-cascade, mid-transit,
mid-arm, mid-onboarding — resumes losslessly); the RM rendition passes the
same tasks with the motion-screened panelists.

## Phase 1 — First hour & arrival

W1 onboarding (5-orb first field, whispered lines, the first star) · the
arrival moment · evening light · App Store metadata refresh to the new
surfaces. Est. 2 sessions, + 2 reserve. **Exit test:** cold install → first
pop < 15 s; 0 tutorial screens; testers can explain "the sky" unprompted;
enjoyment criterion met; **and v1.3 is actually submitted to the App Store**
(new surfaces + onboarding). A live product must not go stale for months
while value accumulates in a branch — the mid-plan ship also exercises the
release pipeline before v2.0 depends on it.

## Phase 2 — Ownership & ritual

Journal pages v2: fortunes archive, keepsakes, the lamp · shareable stillness
card *(conditional — ships only if it passes the no-numbers constraint:
field + fortune by default, tonight's count strictly per-share opt-in,
lifetime totals never on shareable surfaces)* · chime voicings · world-move
sounds + haptic ticks (sounds always play under RM; a separate all-users
transition-sounds toggle lives in the quiet things) · fortune-orb dreamy tell.

**Pacing validation workstream** (the multi-week journey loop gets its only
possible test here):

- A deterministic sim harness replays persona play-profiles through
  `ProgressionStore` and checks them against 03 §2's target bands (median
  evening player reaches Morningside in 90–120 evenings; heavy player never
  under 30 days). The pure simulation makes this nearly free.
- The diary study extends to 3 weeks, probing "did anything new happen
  tonight?"

Est. 3–4 sessions, + 2 reserve. **Exit test:** playtesters voluntarily show
someone their journal (the "this is mine" behavior); enjoyment criterion met;
and **no persona profile goes more than 5 evenings without a discovery in
weeks 1–4** (harness + diary agreeing).

## Phase 3 — Release (v2.0)

- **iPad:** v2.0 is iPhone-first. The existing iPad layout is grandfathered
  as-is and stated as such in the release notes; iPad interaction design for
  One World is its own v2.x item, not a launch-window pass.
- Store assets: new 5-scene screenshots + App Preview video from the live app.
- **Localization:** v2.0 ships English-only — decided, not deferred. Phase 3
  delivers string-catalog extraction plus per-language voice briefs only.
  Any future locale is per-locale transcreation by a native writer (per-locale
  voice guide and forbidden list, 1 a.m.-kitchen voice test as acceptance),
  shipping as its own gated post-2.0 arrival.
- **Arrival #1 is built during Phase 3** as the content-pipeline proof, with
  its actual session cost recorded. **Sustainability rule:** one arrival must
  fit in ≤ 2 sessions, or the arrival cadence stretches to quarterly. Only
  arrival #1 is ever promised publicly; the 6–8-week rhythm stays internal
  until three arrivals have shipped on time (09).
- v2.0 submission via the docs/RELEASE checklist pattern.

Est. 3 sessions, + 2 reserve. **Exit test:** full regression suite green ·
App Store submission accepted · final pillar veto audit passed.

## v2.1 bucket *(named, not vague "later")*

- **The widget** (lamp + count spike).
- **The breath:** specified as ambient, un-earnable variation in the
  completion chime — no tell, no record, never explained or labeled anywhere,
  in-app or in store copy. If playtesters time their clears, the variation
  becomes random. Ships inside a v2.1 arrival.
- Quiet room tone toggle.
- Context anchoring (Shortcuts/Focus) — optional, off by default.
- First localization arrival(s), each gated by native-speaker voice review.
- iPad One World interaction design (own spec, own gate).

## Post-launch calendar *(this document owns it)*

This plan — not the marketing calendar — schedules post-launch work. 09's
launch beats reference it; beat 4 fires **when the first arrival ships**, not
on a promised date. The steady-state ritual rests on shipped systems (the
infinite Path, the 100-pop catalog, the fortune pool); arrivals are a bonus
rhythm on top, sized by the Phase 3 pipeline proof and governed by the
sustainability rule above.

## QA & Playtesting (runs through all phases)

- **Automated:** existing 4 suites + WorldView navigation tests (the camera
  state machine is pure and unit-testable — transitions, interruption,
  false-trigger cases) + the sim-driven tap-success regression against the
  v1.2 baseline + string-registry test enforcing the 07 forbidden-vocabulary
  list.
- **Playtest panel:** recruit **15–18 to net 10–12** women 25–35, **primarily
  outside the owner's network** (friends cannot fail a calm game honestly;
  the owner's network serves the v1.2 baseline only). Recruitment criteria
  cover the four personas — commuter, wind-down, collector, and the
  **churner** (loved a calm game for three evenings, went back to her
  match-3) — with personas assigned to study types: first-hour videos lean
  churner + wind-down; diaries lean wind-down + collector; commuters anchor
  the transit tasks.
- **Motion-sensitivity screening:** the screener asks about motion/vestibular
  sensitivity; the panel includes **≥ 2 "yes" panelists**, and the Reduce
  Motion rendition is tested first-class — every gate the default path
  passes, the RM path passes with these panelists first.
- **Sessions:** moderated remote video for phases 0–1 (solves consent and
  tooling in one move), diary study for phase 2 (3 weeks), regression pass
  for phase 3. **Context conditions:** ≥ 3 first-hour sessions and all diary
  participants include one-handed thumb-only play, with at least one
  commute/transit session each.
- **Incentives:** ~$300 in gift cards across the panel. *This is the plan's
  first cash cost and requires explicit owner approval as a named line item
  before recruitment begins.* Panelists are also credited in the journal's
  last page ("with thanks to the first evenings of…").
- **Device matrix:** oldest supported iPhone, ProMotion iPhone, largest
  supported iPhone (thumb-reach audit), iPad (grandfathered-layout regression
  only), always at minimum brightness + the 1 a.m. test (06 §5).

## Risks

| Risk | Mitigation |
|---|---|
| One World camera fights SwiftUI (gesture/canvas conflicts) | Phase 0a spike proves TapCatcher + camera coexistence on-device before any rebuild work; UIKit tap layer already isolates input |
| Spike fails its latency / frame-pacing bar | Fallback stage 1: camera stays, tappable whisper-labels become primary navigation, swipes demoted to enhancement |
| Camera fails motion-sensitivity or performance gates outright | Fallback stage 2: static field with full-screen in-world panels — fiction kept, continuous camera cut |
| Lying-down wayfinding test fails go/no-go | Written go/no-go forces the re-scope decision at minimum sunk cost; old navigation still shippable behind the flag |
| Accidental navigation kills the calm | False-trigger criterion in every gate: zero unintended transitions during popping, tap success within 2% of baseline via the sim |
| Estimates drift silently | Session unit defined, actuals recorded at phase boundaries, 2× overrun forces a scope review before the next phase |
| Exit tests fail first pass | Expected case: two attempts budgeted per gate + reserve sessions per phase |
| Scope creep via "one more ritual" | Pillar veto tests; phases 2–3 features each need a named fun-source (03 §1); written cut order keeps lamp/keepsakes negotiable before pop-feel budget |
| Onboarding whispers feel like a tutorial | Test W1 with copy off — the field must teach itself; words only *bless* discoveries |
| Solo-dev burnout | Phases end playable; v1.3 ships mid-plan; any phase is a shippable v1.x |
| Playtest recruitment stalls | Over-recruit 15–18 to net 10–12; shortfall delays a gate, it never lowers the bar or shrinks n below 8 |

## Definition of v2.0 done

All phase exit tests passed at the standard above · pillars veto-audited ·
CI green · device matrix + accessibility pass (RM rendition first-class) ·
App Store package updated · **the measurement protocol's release bar met
(00): ≥ 60% of panelists play on at least 4 of their first 7 evenings, with
the fun gate passed.**
