# Vesper Roadmap

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
- [x] The Journey (`docs/pop_progression.md`) — six phases, kind unlock rules,
      featured pop / Drift, collection + records screen
- [x] Catalog + progression test suites

**Acceptance:** classic pop byte-identical (tests); no pressure mechanics added
(points only accrue, unlocks only open); CI green.

## M1.6 — The Path Update (v1.2) ✅ *delivered in this branch*

The infinite pop map (`docs/pop_map.md`): navigation that lets go of itself.

- [x] Stepping-stone map: one stone to start; a first clear opens 1–3 roads;
      every visible stone playable and replayable
- [x] Each stone fields 1–2 pops (rarely 3), distinct from parent/siblings;
      ~35% host a locked "visitor" pop, playable there only
- [x] The road behind fades after 3 days, down to the anchor stone + its roads
- [x] Deterministic seeded generation; JSON persistence; launch still lands
      straight in a field (pillar P1)
- [x] PathSheet map screen + soft "the path continues / forks" notes
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
      the device)
- [ ] App Shortcuts / App Intent: "Pop some orbs" opens straight in

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

- Marketing versions: v1.1 (M1) → v1.2 (M2) → v1.3 (M3); build number increments per
  TestFlight upload.
- No deadlines. Vesper ships when it's calm. Each milestone ends with the manual
  device pass in `docs/BUILD_PLAN.md` §5.
