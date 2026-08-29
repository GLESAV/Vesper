# Vesper v2 — Master Plan: "One World"

*The end-to-end AAA plan. Read this page, then the docs it points to.
Status: adopted · supersedes ROADMAP M2+ · the baseline gate runs first,
then Phase 0a, then Phase 0 — which blocks all other feature work.*

> **Phase 0 has landed.** One World is what the app launches: `VesperApp` picks
> `WorldView`, and the icon toolbar, the Path sheet, the Journey sheet and the
> settings screen survive only under `VESPER_CLASSIC_NAV`, which CI keeps
> building so they stay releasable. W08 shipped with it. The ordering above is
> kept because it is what the plan was adopted with, not because anything is
> still blocked by it.
>
> Feature work has since resumed and shipped: the scrollable sky, weather,
> balloon animals, fireworks, the staged field mechanics, and the Anima
> animation engine (which is in the binary but wired into nothing on the glass).
> `docs/e2e_walkthrough.md` describes what a device actually does today; this
> page remains the plan, and the two are not the same document.

## Why this plan exists

v1.2 built AAA **systems** (a pure simulation, a 100-pop content engine, kind
progression, an infinite map, tests, CI) on top of MVP **surfaces** — four
cryptic icons and stacked modal sheets. For the mission (*a stress-free, fun
mobile game*), the goal (*enjoyable*), and the audience (**women 25–35**), the
surfaces are the product. This plan rebuilds the experience end to end around
one idea:

> **The game is one continuous place.** The Path is the sky above the field.
> The collection is a journal below it. Navigation is movement, not menus.
> Nothing interrupts; nothing demands; everything is one gesture from a pop.

## The document suite (the AAA artifact set)

| Doc | What it decides |
|---|---|
| **01 Vision** | Mission, high concept, experience goals, 5 pillars w/ veto tests (new P4: One Beautiful Place; P5: Her Evening, Respected), anti-goals |
| **02 Audience & Market** | Personas (commuter / wind-down / collector), session contexts, comps analysis, positioning triangle, 6 binding design consequences |
| **03 Game Design (GDD)** | The five fun sources, three loops, systems kept/reframed/added (arrival, evening light, keepsakes, the lamp, shareable stillness), content & success definitions |
| **04 Navigation & UX** | *The centerpiece:* honest critique of current nav, the One World model (Sky / Field / Journal), wireflows W1–W6, first-60-seconds onboarding, copy system, ergonomics |
| **05 Art Direction** | The held-evening world, color law, light-as-material, shape & type systems, the disappearing-chrome standard, per-place specs |
| **06 Audio Direction** | ASMR bar, family voices, world-move sounds, mixing rules, the silent (haptic) mix, the 1 a.m. test |
| **07 Narrative & Writing** | Canon, the voice, forbidden vocabulary, fortune-writing rules, naming law |
| **08 Production Plan** | Baseline gate, Phase 0a spike, Phases 0–3 with exit tests, QA + target-audience playtest panel, risk register, post-launch calendar, definition of done |
| **09 Business** | Free/no-ads/no-IAP as identity, organic growth loops, ASO, launch beats, surveillance-free success metrics |

Foundation docs that remain in force underneath: `docs/pop_standard.md`,
`pop_points.md`, `pop_progression.md`, `pop_map.md` (systems), `STRATEGY.md`
(engineering standards), `CLAUDE.md` (guardrails — Phase 0 has landed and
`CLAUDE.md` now describes the One World tree, but its five guardrails still
predate P4/P5 and have not been rewritten around them).

## The shape of v2 in one view

```
              ✦ the sky        — the Path as constellation (stones = stars)
   swipe ↑  ───────────────
              the field        — home; play; launch lands here; counter says "set free"
   swipe ↓  ───────────────
              your journal     — points, records, collection, fortunes, keepsakes,
                                 the lamp, and (last page) the quiet things
```

**Deleted:** the icon toolbar; all first-party modal sheets used as navigation
(system modality — the share sheet, permission prompts, OS alerts — stays
native and is exempt: the ban governs how *we* move her through the world, not
how iOS speaks); the standalone settings screen — with instant sound/haptic
control preserved at one gesture from the field, so going quiet never requires
a journey (mute in under 5 seconds, one-handed, first attempt is a Phase 0
exit-test task); exposed reset — its purpose survives as the "begin again" row
on the journal's last page, so starting over remains possible without ever
being a button she can hit by accident; the word DETONATED.

**Kept:** the simulation, pop engine, catalog, points, unlock rules, MapStore —
untouched *unless the baseline fun gate fails*. If it fails, a loop-depth
workstream opens with the existing discipline intact: one `GameConfig` constant
at a time, sim stays pure and deterministic, every change re-run through the
unit tests. The fence is the default, not a license to ship an un-fun game.

**Added:** onboarding W1, arrival, evening light, journal rituals (keepsakes,
the lamp), share card (conditional — see below).

## Before anything: the baseline fun gate

Before Phase 0 begins, the recruited panel plays **v1.2 exactly as shipped**
for about one week: first-hour session recorded on video, then a short nightly
diary. This produces two things no later phase can produce:

1. **The baseline** the measurement protocol needs — return behavior, tap
   success rate, session shape of the current game, so v2 has a number to beat
   rather than a feeling to assert.
2. **The fun verdict** — is the core loop described as *fun*, not only
   relaxing? If yes, the simulation fence above holds for the whole plan. If
   no, the loop-depth workstream slot opens before any surface work compounds
   the problem.

This is the cheapest study in the plan and everything downstream cites it.
The existing panel (owner's network) is acceptable for this baseline only;
every later gate uses the independently recruited panel (08).

## Sequence

**Baseline gate** (~1 week, v1.2 as-is) → **Phase 0a** gesture spike →
**Phase 0** One World rebuild → **Phase 1** first hour & arrival, **ships
v1.3** → **Phase 2** ownership & ritual → **Phase 3** release (v2.0). Each
phase ends playable with a named exit test (08). Phase 0a starts only after
this plan is approved by the owner.

### Phase 0a — the gesture spike (timeboxed, throwaway)

The vertical camera + swipe navigation is the plan's highest-risk item, so it
is proven cheap and early, in a throwaway prototype, before the rebuild:

- **(a) On-device proof** that swipe-to-move and tap-to-pop coexist at
  v1.2-equal tap latency and frame pacing on the *oldest supported device* —
  `TapCatcherView` extended, never replaced.
- **(b) A 5-user lying-down wayfinding test** with a written go/no-go before
  the test runs.
- **(c) The fallback sequence, written now, not under duress:** stage 1 —
  keep the camera, demote swipes to enhancement, tappable whisper-labels
  become primary navigation (least rework, preserves One World); stage 2 —
  if the camera itself fails performance or motion-sensitivity gates, a
  static field with full-screen in-world panels (no continuous camera, fiction
  preserved). A spike failure re-scopes; it never stalls the plan. Both stages
  live in 08.
- **(d) The flag rule:** the old navigation is not deleted until the new one
  passes its exit test on-device. Both live behind a flag; the game stays
  shippable through the entire rebuild.

### Phase 1 ships

Phase 1's exit includes an **actual App Store submission** — v1.3, the new
surfaces plus onboarding — not just a passed exit test. A live product must
not go stale for months while value accumulates in a branch; the mid-plan
ship also exercises the whole release pipeline before v2.0 depends on it.

### Phase 3 — release, bounded

Phase 3 is a bounded release phase, not a backlog: the iPad grandfathering
note (below), store assets, string-catalog extraction plus per-language voice
briefs, and submission — with its own exit test (regression suite green +
submission accepted + a final pillar veto audit). **Arrival #1 is built during
Phase 3** as the content-pipeline proof, with its real cost recorded and the
sustainability rule attached: one arrival costs ≤2 working sessions, or the
cadence stretches to quarterly. The post-launch calendar is owned by 08.

**v2.0 is iPhone-first.** The existing iPad layout ships grandfathered as-is;
iPad interaction design (One World does not trivially survive an 11–13-inch
landscape canvas) is its own v2.x arrival, not a Phase 3 pass.

## v2.0 scope and the cut order

v2.0 ships **arrival, evening light, the lamp, and keepsakes**. The **breath**
and the **home-screen widget** are a named v2.1 bucket. The **share card**
ships only if it holds the no-numbers constraint below.

When the craft bar slips — and on a solo production it will — the casualty
order is already written. **The pop's feel budget is never traded for scope.**

| Tier | Contents |
|---|---|
| **Protected** (never cut, never thinned) | The pop's feel (latency, sound, haptic, particles), tap reliability, instant quiet, the One World navigation once past its gate, onboarding W1 |
| **Negotiable** (thin before cutting) | Arrival #1's scope, evening light's range, keepsake count, lamp behaviors, journal ritual polish |
| **First to cut** | Share card, additional keepsakes, ambient flourishes, any Phase 3 nicety not on the release exit test |

The per-addition priority table — each ranked by which fun source it feeds and
its polish cost — lives in 03 §3.

## The share card

The share card passed the P3/P5 pillar veto **only in this form**, which is
now binding: the default card is **field + fortune, nothing else**. Tonight's
count appears only as an explicit per-share opt-in. Lifetime totals never
appear on any shareable surface. No streaks, no identifying stats. Sharing is
available from fortune cards as well as the done card. The product never
pushes a comparable number; she can choose to show one.

One gate travels with it (02): the card must produce organic posts from the
TestFlight panel before launch, or the screenshot loop is demoted from primary
growth channel and 09's growth model re-weights.

## Localization

**v2.0 is English-only, as decided canon** (restated in 07, 08, 09). The
voice — lowercase whispers, forbidden vocabulary, sentence-case fortunes —
does not survive vendor translation. Any future locale is a **per-locale
transcreation**: a native writer, a per-locale voice guide and forbidden list,
and the 1 a.m.-kitchen voice test as acceptance — each shipping as its own
gated arrival after v2.0. Phase 3 delivers only the string-catalog extraction
and the per-language voice briefs that make this possible later.

## Exit tests — the pass bar

Every gate in 08 uses one format: **n ≥ 8 fresh testers, pass at ≥ 7/8 with
no two failures sharing a common cause; one fix-and-retest cycle allowed per
gate; a recruitment shortfall delays the gate but never lowers the bar.**
Testers are recruited primarily outside the owner's network — friends cannot
fail a calm game honestly. Navigation gates additionally require the
false-trigger criterion (zero unintended camera transitions during active
popping; tap-to-pop success within 2% of the v1.2 baseline, checked via the
deterministic simulation) and context-matched tasks performed in context — in
bed, on transit. Phase 1 and 2 exits carry an enjoyment criterion, not only a
task-completion one.

## The measurement protocol

There is exactly one protocol. Every doc that mentions success cites this
section; no doc defines its own variant.

- **The single release bar:** wind-down return. Threshold: **≥ 60% of
  panelists play on at least 4 of their first 7 evenings.** One gate a solo
  dev can honestly decide against.
- **Instrument:** TestFlight aggregate session data (Apple-side, SDK-free,
  guardrail-compliant) is the primary return-rate instrument. A **separate
  diary cohort** provides qualitative texture only — diaries prime the
  behavior they measure, so the diary cohort never feeds the number. If
  TestFlight aggregates prove unusable, fall back to moderated day-7
  interviews and drop the "unprompted" claim rather than pretend to measure
  it.
- **Panel:** n ≥ 8 per gate, recruited primarily outside the owner's network
  from the target audience; the owner's-network panel is used only for the
  v1.2 baseline.
- **The fun gate (qualitative):** in first-hour videos and diaries, the game
  is described as *fun* — not only relaxing. Failing this opens the
  loop-depth workstream regardless of the return number.
- **Secondary signals, never gates:** commuter and collector behavioral
  criteria are monitored and inform iteration, but only wind-down return can
  block a ship. This is a closed decision, recorded here so it is not
  re-litigated: one bar is the only kind a solo team can hold.
- Per-experience-goal observable proxies live in 01; the panel logistics and
  gate schedule live in 08.
