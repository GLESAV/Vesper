# CLAUDE.md

This file gives Claude Code (and any other agent or contributor) the context needed to
work productively in this repository.

## What this project is

**Vesper** ("Vesper Pop" on the App Store) is a small, calm iOS stress-relief game.
Soft glowing orbs drift on a dark screen; tapping one pops it with a gentle synthesized
tone, a haptic tap, and a shockwave that can chain-pop nearby orbs. Occasionally an orb
reveals a short, kind "fortune" message. Clearing the field shows a quiet completion
card. There is deliberately **no score to chase, no timer, no failure state, no ads,
no accounts, and no data collection**.

That core is unchanged, and a great deal has grown around it. The app is now
**one continuous vertical world** — the Path as a constellation in the sky
above, the field, the journal below — and a field can carry weather, a balloon
animal, a firework display, splitters, drifters and generators, arriving one
idea at a time as fields accrue. None of it can be lost or failed; all of it is
deterministic from a stone's seed, so a stone is the same field every time she
returns to it. `docs/e2e_walkthrough.md` walks the whole of it.

Created by Kate Wu. Bundle ID: `com.gregorysavage.vesper`. iOS 18.5+, iPhone + iPad.

## Product guardrails (do not break these)

The calm is the product. Any change must preserve:

1. **No pressure mechanics.** No timers, leaderboards, lives, streaks-with-loss, or
   fail states. Progression exists (pop points, unlocks — see `docs/pop_points.md`
   and `docs/pop_progression.md`) but must stay **affirming-only**: numbers only
   ever accrue, nothing is spent/lost/reset/time-limited/compared, every unlock is
   reachable through ordinary play, and locked content shows a kind hint, never a
   wall. This extends to the field's own mechanics: a generator that closes on a
   timer draws no countdown and costs nothing when it closes, an animal is shy
   for a while but can never outrun a thumb, and a field is longer rather than
   harder. **More engaging, never more difficult** is the phrasing to test
   against.
2. **No monetization or dark patterns.** No ads, IAP prompts, rating nags, or push
   notifications that demand attention.
3. **No data collection.** No analytics SDKs, no network calls, no accounts. Privacy is
   a feature (see `PRIVACY.md`).
4. **The aesthetic.** Dark background, muted pastel palette, serif accents, lowercase
   calm copy, soft sounds. Nothing harsh, bright, or loud.
5. **Gameplay tuning is sacred.** Orb sizes, speeds, chain-reaction behavior, and pop
   feel are tuned. Constants live in `Vesper/Game/GameConfig.swift`; change them only
   deliberately and one at a time.

## Repository layout

```
Vesper/                     App source (Xcode file-system-synchronized group — new
│                           files added here are compiled automatically, no pbxproj edit)
├── VesperApp.swift         @main entry; picks WorldView (One World) unless the
│                           VESPER_CLASSIC_NAV flag is compiled; scene-phase → audio
├── Game/
│   ├── GameConfig.swift    All gameplay tuning constants (single source of truth)
│   ├── Entities.swift      Orb / Particle / Ring / Mote / FloatNote value types (UI-free)
│   ├── SeededRandom.swift  SplitMix64 deterministic RNG
│   ├── GameSimulation.swift  Pure, deterministic sim: seeding, taps, chain physics,
│   │                         weather application, fireworks, generators. No SwiftUI/
│   │                         UIKit imports. Emits GameEvents. Unit-tested.
│   ├── FieldPlan.swift     What a field contains per stage/generation (kinds dealt,
│   │                       display vs animal fields, replay multipliers)
│   ├── Weather.swift       The six airs and their tuning; WeatherField.swift moves them
│   ├── AnimalPop.swift     Balloon-animal silhouettes, shyness, startle motion
│   ├── Firework.swift      Shells, fuse ropes, break patterns; FireworkCatalog.swift
│   ├── Fortunes.swift      Fortune message strings; Verses.swift the done-card verses
│   ├── GameViewModel.swift ObservableObject; bridges sim → UI, audio, haptics,
│   │                       points, unlocks, the onward sequence
│   ├── Pops/
│   │   ├── PopStandard.swift  The formal pop schema (style/behavior/chain/unlock)
│   │   └── PopCatalog.swift   All 100 pops as data; #001 codifies the v1.0 pop
│   └── Map/
│       ├── PopMap.swift       MapStone + pure seeded generation (The Path)
│       └── MapStore.swift     Map state, persistence. NOTHING IS EVER DELETED (W08):
│                              3-day settling is derived at draw time, never pruned
├── World/                  One World: sky / field / journal on one camera axis
│   ├── WorldView.swift     Composition root; WorldModel.swift the glue
│   ├── WorldCamera.swift   The pure camera (offsets, commits, settles)
│   ├── WorldInput.swift    InputArbiter: pop vs pan vs sky-scroll arbitration
│   ├── WorldInputView.swift  The hosted UIKit touch layer (ruling 8: never rebuilt)
│   ├── SkyView.swift       The Path drawn as constellation; SkyScroll.swift its scroll
│   ├── JournalView.swift   Collection, records, settings as pages
│   ├── WhisperLabel.swift  Wayfinding whispers; FieldLayout.swift field metrics
├── Anima/                  2-D animation engine (pure; NOT wired into gameplay yet):
│                           shapes, figures, clips, voices, the 100 pop assets,
│                           AnimaStudio JSON export for tools/anima-studio
├── Rendering/
│   ├── SceneRenderer.swift Palette + Canvas drawing (motes, orbs, rings, particles)
│   ├── WeatherRenderer.swift  The drawn air; HorizonRenderer.swift the sky/field seam
│   ├── AnimalRendering.swift  Balloon-animal bodies; AnimaRenderer.swift (unused live)
├── Audio/
│   └── PopSoundEngine.swift  AVAudioEngine; pre-rendered pop buffers, completion
│                             chime, interruption/route-change/reset recovery
├── Haptics/
│   └── HapticsEngine.swift Soft impact per pop (scaled by orb size), success on clear
├── Support/
│   ├── SettingsStore.swift UserDefaults-backed toggles (sound/haptics/whispers)
│   ├── ProgressionStore.swift  Pop points, lifetime stats, unlock evaluation
│   ├── Strings.swift       The world's copy, lowercase-calm; WorldFlags.swift the
│   │                       nav flag; DevReset.swift DEBUG-only fresh install
└── Views/                  The CLASSIC v1.2 navigation — compiled but unreachable
    │                       unless VESPER_CLASSIC_NAV is set; kept as harness
    ├── ContentView.swift   Layer composition (canvas / tap layer / HUD / cards)
    ├── TapCatcherView.swift  UIKit tap recognizer (see note below)
    ├── SettingsSheet.swift / JourneySheet.swift / PathSheet.swift / Cards.swift

VesperTests/                Unit tests (XCTest, @testable): sim, world, camera, input,
                            sky scroll, weather, animals, fireworks, map, Anima
Vesper.xcodeproj/           Project + shared scheme (scheme runs the tests)
.github/workflows/ci.yml    Build + test (both nav configs) for every push/PR
.github/workflows/anima-pages.yml  Exports the Anima library, checks the previewer,
                            publishes tools/anima-studio to Pages on main
tools/anima-studio/         The static hub page previewing all Anima assets
docs/                       e2e_walkthrough.md (the current build, end to end —
│                           the most accurate description in the repo),
│                           PLAYTEST.md, pop_standard/points/progression/map.md,
│                           pop_puzzles.md + sky_assets.md (design, unbuilt),
│                           anima.md + anima_backlog.md, STRATEGY.md,
│                           ROADMAP.md, BUILD_PLAN.md, RELEASE_v1.2.md, gdd/
fastlane/                   App Store metadata + screenshots (deliver)
web/                        Static privacy page for tfc.studio/vesper/privacy
```

## Commands

There is no Linux toolchain for this project; building requires macOS + Xcode 16.4+.

```sh
# Build
xcodebuild build -project Vesper.xcodeproj -scheme Vesper \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

# Run unit tests (the CI gate)
xcodebuild test -project Vesper.xcodeproj -scheme Vesper \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

# Quick syntax check of a single file (no simulator needed)
swiftc -parse Vesper/Game/GameSimulation.swift

# Upload App Store metadata/screenshots (needs fastlane + App Store Connect auth)
bundle exec fastlane deliver
```

When working from an environment without Xcode: write conservative Swift, keep the
simulation free of UI imports, and rely on the CI workflow to verify the build.

## Architecture rules

- **Simulation is pure.** `GameSimulation` imports only Foundation/CoreGraphics, takes
  `dt` (not wall-clock), uses the injected seeded RNG, and returns `[GameEvent]` from
  `tap(at:)` and `step(dt:)`. All side effects (sound, haptics, animation, persistence)
  happen in `GameViewModel` in response to events. Keep it this way — it is what makes
  the game testable and deterministic.
- **Rendering reads, never writes.** `SceneRenderer.draw` must not mutate sim state.
- **Published state changes must not happen during Canvas rendering.** Events produced
  by `step()` (chain pops) are applied via `DispatchQueue.main.async`; events from taps
  are applied synchronously. Don't "simplify" this — it avoids SwiftUI's
  publishing-during-view-update hazard.
- **Touch handling stays UIKit-backed.** In the shipping One World build this is
  `World/WorldInputView.swift`, hosting the raw touch stream that
  `World/WorldInput.swift`'s pure `InputArbiter` decides between pop, pan and
  sky-scroll; it is never rebuilt by camera motion (ruling 8). `TapCatcherView`
  is the equivalent layer in the classic navigation. Both exist for the same
  reason: SwiftUI gestures are unreliable over a continuously redrawing
  `TimelineView`/`Canvas`. Keep the touch layer separate and stable.
- **Frame-rate independence.** All motion scales by the clamped frame factor `f`
  (dt clamped to 50 ms, normalized to 60 fps). Any new motion must multiply by `f`.
- **Performance budget.** Target 60–120 fps; the particle cap
  (`GameConfig.particleCap`) is enforced in the sim, and rendering pauses
  (`TimelineView paused:`) once the field is cleared and effects have faded.

## Conventions

- Swift 5, SwiftUI-first, no external dependencies (keep it zero-dependency).
- Small files, one responsibility each; `// MARK:` sections within files.
- Colors are defined in the palette in `SceneRenderer.swift` / views — match the
  existing muted tones; never introduce saturated or pure-white UI.
- Copy (user-facing text) is lowercase-calm, kind, and brief. Match the voice of the
  existing fortune messages.
- Accessibility: interactive controls ≥ 44 pt, VoiceOver labels on all buttons and the
  counter, respect `accessibilityReduceMotion` (fewer particles, static motes).
- Tests live in `VesperTests/` and must not depend on rendering or timing; drive the
  sim with `step(dt:)` and fixed seeds.

## Planning docs

**The adopted end-to-end v2 plan lives in `docs/gdd/` — start at
`00_MASTER_PLAN.md`.** It supersedes the roadmap's M2+ and adds two pillars
(One Beautiful Place; Her Evening, Respected) that bind all new UI work:
navigation is movement through one world (sky / field / journal), never icons
or modal sheets.

**Phase 0 — the navigation rebuild — has landed.** One World is what launches;
the v1.2 screens survive only under `VESPER_CLASSIC_NAV`, which CI still builds
so they stay releasable. Weather, balloon animals, fireworks, the staged field
mechanics, the scrollable sky, W08's settling map and the Anima engine all
shipped after it. The app is nevertheless still at `MARKETING_VERSION = 1.2`,
so the version number does not distinguish this build from the v1.2 submission
— do not read anything into it.

**Read `docs/e2e_walkthrough.md` first.** It is a device pass over everything
that ships today and is the most accurate description of current behaviour in
the repository. Where an older doc disagrees with it, or with the code, the
older doc is the one that is wrong.

- `docs/e2e_walkthrough.md` — the current build, end to end, as a checklist
- `docs/PLAYTEST.md` — the One World navigation playtest (one question, live)
- `docs/STRATEGY.md` — what "AAA" means for Vesper, engineering/UX standards, budgets
  (§1's "add no content or systems" was overtaken by the product; §§2–5 are in force)
- `docs/ROADMAP.md` — milestones M0–M3; true through M1.6, superseded after it
- `docs/BUILD_PLAN.md` — the M0+M1 build plan; historical, but §5's device pass
  is still referenced
- `docs/pop_standard.md` — the formal pop schema, envelopes, and authoring rules
- `docs/pop_progression.md` — the journey: phases, unlock rules, featuring/Drift
- `docs/pop_points.md` — scoring formula and how stats surface in/out of game
- `docs/pop_map.md` — The Path: infinite stepping-stone map, roads, 3-day settling
  (the road behind settles into permanent trace; **nothing is ever deleted** — W08)
- `docs/anima.md` — the 2-D animation engine and its browser previewer. It ships
  in the binary and **nothing in gameplay draws from it yet**; adoption is its
  own change, one system at a time
- `docs/pop_puzzles.md`, `docs/sky_assets.md` — adopted design, deliberately
  unbuilt. Both say so in their own status lines; keep it that way
