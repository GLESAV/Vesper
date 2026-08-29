# Vesper — Formal Strategy: "AAA, quietly"

*Status: adopted · Owner: engineering · Last updated: 2026-08-14*

> **What this document still governs, and what it no longer does.** §§2–5 —
> the pillars, the architecture rules, the CI gate, the performance and latency
> budgets, the UX standards — are in force and are the standard every change is
> still held to. §1's position that Vesper would add *no content and no systems*
> was overtaken by the product: the game has since grown a hundred-pop catalog,
> a progression, an infinite map, weather, balloon animals, fireworks, staged
> field mechanics and an animation engine, and `docs/gdd/01_VISION.md` is where
> that argument now lives. It also renumbers the pillars: its five are P1 Instant
> calm, P2 Tactile joy, P3 Generous never grasping, **P4 One beautiful place**
> and **P5 Her evening, respected** — so "Invisible tech", P4 in the table below,
> is not the GDD's P4. Invisible tech survives as this document's engineering
> standard rather than as a product pillar. §7's success criteria are
> the MVP's and were met. Read §1 as the founding argument for *why nothing may
> add pressure*, which is still exactly right, rather than as a claim about the
> shape of the app today.

## 1. Vision

Vesper is already the right game. It is small, kind, and complete: tap a glowing orb,
feel it pop, watch the chain ripple, breathe. The strategy is therefore **not** to add
content, systems, or monetization. It is to raise every dimension of *execution quality*
to the level of a first-party Apple app or a boutique AAA title — while the game itself
stays exactly as calm and simple as it is today.

> **Definition of AAA for Vesper:** not scale, but *feel*. Flawless input latency,
> multisensory feedback (visual + audio + haptic) that lands as one event, zero jank,
> zero crashes, zero pressure, and craftsmanship visible in every detail a player can
> touch — and invisible everywhere else.

## 2. Product pillars

Every decision is tested against these four pillars, in priority order:

| # | Pillar | Meaning | Veto test |
|---|--------|---------|-----------|
| P1 | **Instant calm** | Cold launch straight into the game. No menus, splash flows, tutorials, or interstitials. | Does this add anything between the user and the first pop? |
| P2 | **Tactile joy** | A pop is one fused sensory event: burst + tone + haptic within the same perceptual frame. | Does this make popping feel better, or at least not worse? |
| P3 | **Zero pressure** | No score-chasing, timers, failure, streaks-with-loss, ads, or nags. Numbers may only affirm. | Could this make anyone feel behind, judged, or sold to? |
| P4 | **Invisible tech** | The engineering never shows: no dropped frames, no audio glitches, no battery drain, no crashes. | Would a player ever notice the machinery? |

**Non-goals (explicit):** multiplayer, accounts, analytics/telemetry SDKs, ads, IAP,
notifications, level progression, difficulty, content treadmills. These are not
deferred — they are rejected. Privacy ("collects no data") is a shipped feature.

## 3. Engineering strategy

### 3.1 Architecture

- **Deterministic core.** Game logic lives in a pure `GameSimulation` (Foundation +
  CoreGraphics only): seeded RNG injected, time passed in as `dt`, side effects
  expressed as returned `GameEvent`s. This one decision buys testability, reproducible
  bug reports, and frame-rate independence.
- **Thin layers around the core.** `GameViewModel` (event → UI/audio/haptics/stats),
  `SceneRenderer` (read-only draw), Views (composition only). Each file has one job.
- **Zero third-party dependencies.** The whole app is platform frameworks. Supply-chain
  surface: none. Binary stays tiny; App Review stays trivial.

### 3.2 Quality gates (CI-enforced)

- Every PR, and every push to `main`, builds and runs the unit-test suite on an
  iOS Simulator via GitHub Actions — **in both navigation configurations**,
  `world` and `classic` (`VESPER_CLASSIC_NAV`), because an unbuilt configuration
  rots within days. Red CI blocks merge.
- Simulation behavior (seeding invariants, tap tolerance, chain physics, completion,
  particle cap, determinism, long-pause clamping) is covered by `VesperTests`.
- Manual pre-release pass on real hardware: oldest supported device + latest Pro
  (ProMotion), checklist in `docs/BUILD_PLAN.md`.

### 3.3 Performance & latency budgets

| Metric | Budget | Mechanism |
|--------|--------|-----------|
| Frame time | < 8.3 ms on ProMotion (120 Hz), < 16.6 ms everywhere | Canvas draw is allocation-light; particle cap; no per-frame view rebuilds |
| Tap → visible burst | next frame (≤ 1 frame) | UIKit tap recognizer, synchronous event application |
| Tap → audible pop | < 20 ms | Buffers pre-rendered at init; playback only schedules |
| Tap → haptic | < 20 ms | Generators prepared and kept warm |
| Cold launch → interactive | < 1.5 s | No splash, no blocking init; audio warms up off the critical path |
| Idle cost after clear | ~0 | `TimelineView` pauses when the field is cleared and effects fade |
| Memory | < 100 MB | No textures/assets; synthesized audio ≈ 1 MB of buffers |
| Battery | No audio session or render loop churn in background | Scene-phase lifecycle pauses the engine |

Long frame gaps (backgrounding, system stalls) are clamped (`dt ≤ 50 ms`) so the sim
never explodes or tunnels.

### 3.4 Reliability

- Audio failures are never fatal: every AVAudioEngine path degrades to silence.
- Audio session interruptions (calls, Siri) are observed and recovered.
- Persistence is UserDefaults-only and stays on the device: three toggles
  (`SettingsStore`), seven progression keys (`ProgressionStore`) and five map
  keys (`MapStore`). It is no longer small enough to call incorruptible, so the
  stores defend themselves instead: a tally that will not parse is dropped
  without taking the other numbers with it, duplicate-parsing keys merge rather
  than trap, and a map blob that fails to decode is moved to a keepsake key
  before anything can write over it — because it is her whole Path, and the
  contract is that nothing is ever lost, including to a bug.
- No networking, so no failure modes from it.

## 4. UX standards

- **Touch:** all controls ≥ 44 pt; orbs carry a 12 pt tap-tolerance halo so small orbs
  never feel unfair.
- **Haptic grammar:** soft impact per pop, intensity scaled to orb size, chained pops
  slightly lighter (the ripple feels like an echo), a single success note on clearing.
  Haptics are a language, not noise — one meaning per pattern, user-disableable.
- **Sound design rules:** synthesized, soft-attack, exponential-decay tones only;
  micro-variation per pop so repetition never grates; `.ambient` session that mixes
  with the user's own music; user-disableable; never louder than the user's world.
- **Motion:** everything eases; nothing blinks or bounces sharply. `Reduce Motion`
  halves particles and stills the ambient motes.
- **Accessibility:** VoiceOver labels on every control and the counter; contrast kept
  within the muted palette but ≥ 3:1 for text; no information conveyed by color alone.
- **Copy:** lowercase-calm, kind, brief; the fortune voice ("Whatever you just popped,
  it wasn't real anyway.") is the register for all new text.

## 5. Scalability

Vesper's "scale" is not servers — it is *devices, years, and contributors*:

- **Devices:** one adaptive layout (iPhone → iPad), frame-rate-independent sim
  (60/120 Hz), safe-area-aware bounds; no hardcoded screen assumptions.
- **Years:** zero dependencies to rot; tuning centralized in `GameConfig`; docs
  (`CLAUDE.md`, this folder) keep the intent legible to future maintainers, human or AI.
- **Contributors:** deterministic tests + CI mean a stranger (or an agent) can change
  the sim with confidence; product guardrails in `CLAUDE.md` keep the soul intact.

## 6. Risks

| Risk | Mitigation |
|------|------------|
| Polish creep breaks the calm (P3) | Guardrails in CLAUDE.md; every feature passes the four pillar veto tests |
| No Mac/CI parity while developing remotely | CI on macOS runners is the source of truth; sim kept UI-free so logic verifies via tests |
| Tuning drift during refactor | Constants transcribed 1:1 into `GameConfig`; behavior-level unit tests pin chain physics |
| Audio session edge cases (calls, route changes) | Interruption observer + scene-phase lifecycle; degrade to silence, never crash |

## 7. Success criteria for the MVP ("The Feel Update")

1. Gameplay is byte-for-byte the same tuning as v1.0 — existing players notice nothing
   *changed*, only that it feels better.
2. Every pop lands with synchronized burst + tone + haptic.
3. Settings exist (sound, haptics) and persist; lifetime stats quietly accumulate.
4. Reduce Motion and VoiceOver are respected.
5. CI is green: the sim test suite passes on a clean simulator build.
6. The app renders nothing (0% CPU render loop) once the field is cleared and quiet.
