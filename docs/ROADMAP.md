# Vesper Roadmap

> **Status note — read before anything below.**
>
> This page is the **v1 roadmap**, and it stopped being the plan at M1.6.
> Everything after that is superseded by the adopted end-to-end plan in
> `docs/gdd/00_MASTER_PLAN.md` ("One World"); M2/M3 items here survive only
> where the GDD suite re-adopts them.
>
> **What has shipped since this page was last true**, none of which appears
> below: the One World navigation rebuild (sky / field / journal on one camera
> axis — the plan's Phase 0, now landed and shipping by default, with the v1.2
> screens surviving only behind `VESPER_CLASSIC_NAV`); the sky as a scrollable
> constellation; W08 (the map's 3-day pruning replaced by settling — nothing is
> ever deleted); weather; balloon animals; fireworks; staged field mechanics
> (splitters, drifters, generators, depth/reserve); and the Anima animation
> engine with its browser previewer. `docs/e2e_walkthrough.md` is the current
> description of the shipping build; this page is history.
>
> The app is still at `MARKETING_VERSION = 1.2`. The version number has not
> moved since M1.6 even though the surfaces have been rebuilt underneath it —
> so "v1.2" in this repository means two different builds depending on which
> commit you are standing on, and the marketing version is not a reliable way
> to tell them apart.

Milestones are sequential; each one is shippable on its own. M0 + M1 together are the
MVP ("The Feel Update", v1.1). Later milestones are proposals, always subject to the
pillar veto tests in `docs/STRATEGY.md` §2.

---

## M0 — Foundation (engineering) ✅ *delivered in this branch*

Make the codebase AAA-grade before making the game feel AAA-grade.

- [x] Split the monolith into modules: `Game/` (pure sim), `Rendering/`, `Audio/`,
      `Haptics/`, `Support/`, `Views/`
- [x] Extract all gameplay tuning into `GameConfig` — values transcribed 1:1 from v1.0
- [x] Deterministic simulation: injected SplitMix64 seed, `dt`-driven stepping,
      event-based side effects
- [x] Unit-test target (`VesperTests`) covering seeding, taps, chain reactions,
      completion, particle cap, determinism, frame-gap clamping
- [x] Shared Xcode scheme + GitHub Actions CI (build + test on iOS Simulator)
- [x] `CLAUDE.md` + strategy/roadmap/build-plan docs

**Acceptance:** CI green; gameplay tuning identical to v1.0; every module has one job.

## M1 — The Feel Update (MVP, v1.1) ✅ *delivered in this branch*

Multisensory polish that makes every pop land, with zero new pressure.

- [x] **Haptics.** Soft impact per pop scaled to orb size; chained pops echo lighter;
      gentle success on clearing the field
- [x] **Audio 2.0.** Pops pre-rendered at init (zero-latency playback, 8 pitch buckets
      × 3 micro-variants); a soft three-note chime on completion; audio-session
      interruption recovery; engine pauses in background
- [x] **Ambient depth.** Faint drifting motes behind the orbs; a subtle specular
      highlight gives orbs a glassy bubble read
- [x] **Chain whisper.** A cascade of 3+ shows a fleeting "chain of N" note — an
      observation, not a score; it fades and is never stored
- [x] **Settings.** A quiet sheet: sound and haptics toggles (persisted), lifetime
      stats, credit line
- [x] **Gentle memory.** Lifetime orbs popped + fields cleared accumulate in
      UserDefaults; the done card notes them softly
- [x] **Accessibility.** VoiceOver labels; Reduce Motion halves particles and stills
      motes
- [x] **Efficiency.** Particle cap; render loop pauses when cleared-and-quiet;
      clamped frame steps; position-clamped edge bounces

**Acceptance:** STRATEGY §7 criteria all met.

## M1.5 — The Collection Update (v1.2) ✅ *delivered in this branch*

The pop engine: content as data, progression as a journey.

- [x] Formal pop standard (`docs/pop_standard.md`) — style/behavior/chain/unlock
      as pure data; engine interprets, authoring never touches engine code
- [x] Pop #001 codifies the original v1.0 pop exactly (test-pinned)
- [x] 100 unique pops across ten families, all inside the tested envelopes
- [x] Pop points (`docs/pop_points.md`) — affirming-only scoring: whispers,
      session line, done-card summary
      *(the running session line under the counter was later removed with the
      rest of the field's clutter — see `docs/pop_points.md` §3)*
- [x] The Journey (`docs/pop_progression.md`) — six phases, kind unlock rules,
      featured pop / Drift, collection + records screen
      *(the Journey sheet is now the journal; the six phases remain a design
      vocabulary and were never surfaced to a player)*
- [x] Catalog + progression test suites

**Acceptance:** classic pop byte-identical (tests); no pressure mechanics added
(points only accrue, unlocks only open); CI green.

## M1.6 — The Path Update (v1.2) ✅ *delivered in this branch*

The infinite pop map (`docs/pop_map.md`): navigation that lets go of itself.

- [x] Stepping-stone map: one stone to start; a first clear opens 1–3 roads;
      every visible stone playable and replayable
- [x] Each stone fields 1–2 pops (rarely 3), distinct from parent/siblings;
      ~35% host a locked "visitor" pop, playable there only
      *(later inverted: a child now **inherits** one of its parent's pops and
      carries 2–3 — `docs/pop_map.md` §2)*
- [x] The road behind fades after 3 days, down to the anchor stone + its roads
      *(later replaced by settling — W08. Nothing is deleted; the road behind
      becomes a permanent constellation line)*
- [x] Deterministic seeded generation; JSON persistence; launch still lands
      straight in a field (pillar P1)
- [x] PathSheet map screen + soft "the path continues / forks" notes
      *(the map screen is now `SkyView`; the notes survive unchanged)*
- [x] MapStoreTests: genesis, road opening, uniqueness, determinism, fading,
      persistence

**Acceptance:** no locked-state walls on the map; anchor + roads ahead never
fade; CI green.

## M2 — Depth, not breadth (v1.3 proposal)

More texture inside the same loop. Candidates (each needs pillar review):

- [ ] Orb variety by weight: bigger orbs drift slower, pop deeper, shake the field a
      touch more (pure feel, no mechanics)
- [ ] A "long-press to hold, release to pop" alternate touch verb — slower, more
      deliberate relief
- [ ] Evening palette drift: hues shift subtly with local time of day (on-device only)
- [ ] Breath pacing: the whole field gently inhales/exhales on a ~5.5 s cycle
- [ ] Home-screen widget: "N orbs set free" lifetime count (WidgetKit, no data leaves
      the device) — still unbuilt; there is no widget extension in the project
- [ ] App Shortcuts / App Intent: "Pop some orbs" opens straight in — still
      unbuilt; there is no App Intent in the project

**Acceptance:** still no score, timer, or failure; cold-launch and frame budgets hold.

## M3 — Reach (v1.4+ proposal)

Same game, more people, still no data collected.

- [ ] Localization of the ~30 user-facing strings (String Catalogs; start with es, fr,
      de, ja, zh-Hans) — fortunes need translation *with love*, not literally
- [ ] iPad-optimized layout pass (orb density scales with area, not count range)
- [ ] MetricKit crash/ hang reports (on-device Apple mechanism — no third-party SDK)
- [ ] App Store product-page refresh: preview video of a chain reaction with sound
- [ ] Apple Watch companion experiment: one orb at a time on the wrist (pillar review
      required — only if it stays calm)

---

## Versioning & cadence

- Marketing versions: v1.1 (M1) → v1.2 (M1.5/M1.6); build number increments per
  TestFlight upload. **The project has sat at 1.2 through the whole One World
  rebuild** — the next release number is a decision the master plan has not yet
  made, and nothing should read the marketing version as a description of what
  is in a build.
- No deadlines. Vesper ships when it's calm. Each milestone ends with the manual
  device pass in `docs/BUILD_PLAN.md` §5.
