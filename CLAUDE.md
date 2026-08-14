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

Created by Kate Wu. Bundle ID: `com.gregorysavage.vesper`. iOS 18.5+, iPhone + iPad.

## Product guardrails (do not break these)

The calm is the product. Any change must preserve:

1. **No pressure mechanics.** No timers, leaderboards, lives, streaks-with-loss, or
   fail states. Progression exists (pop points, unlocks — see `docs/pop_points.md`
   and `docs/pop_progression.md`) but must stay **affirming-only**: numbers only
   ever accrue, nothing is spent/lost/reset/time-limited/compared, every unlock is
   reachable through ordinary play, and locked content shows a kind hint, never a
   wall.
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
├── VesperApp.swift         @main entry; scene-phase → audio lifecycle
├── Game/
│   ├── GameConfig.swift    All gameplay tuning constants (single source of truth)
│   ├── Entities.swift      Orb / Particle / Ring / Mote / FloatNote value types (UI-free)
│   ├── SeededRandom.swift  SplitMix64 deterministic RNG
│   ├── GameSimulation.swift  Pure, deterministic sim: seeding, taps, chain physics.
│   │                         No SwiftUI/UIKit imports. Emits GameEvents. Unit-tested.
│   ├── Fortunes.swift      Fortune message strings
│   ├── GameViewModel.swift ObservableObject; bridges sim → UI, audio, haptics,
│   │                       points, unlocks
│   └── Pops/
│       ├── PopStandard.swift  The formal pop schema (style/behavior/chain/unlock)
│       └── PopCatalog.swift   All 100 pops as data; #001 codifies the v1.0 pop
├── Rendering/
│   └── SceneRenderer.swift Palette + Canvas drawing (motes, orbs, rings, particles)
├── Audio/
│   └── PopSoundEngine.swift  AVAudioEngine; pre-rendered pop buffers, completion
│                             chime, interruption + lifecycle handling
├── Haptics/
│   └── HapticsEngine.swift Soft impact per pop (scaled by orb size), success on clear
├── Support/
│   ├── SettingsStore.swift UserDefaults-backed toggles (sound/haptics/whispers)
│   └── ProgressionStore.swift  Pop points, lifetime stats, unlock evaluation
└── Views/
    ├── ContentView.swift   Layer composition (canvas / tap layer / HUD / cards)
    ├── TapCatcherView.swift  UIKit tap recognizer (see note below)
    ├── SettingsSheet.swift Toggles + headline stats
    ├── JourneySheet.swift  Collection grid, records, featured-pop selection
    └── Cards.swift         Fortune card + done card

VesperTests/                Unit tests for GameSimulation (XCTest, @testable)
Vesper.xcodeproj/           Project + shared scheme (scheme runs the tests)
.github/workflows/ci.yml    Build + test on iOS Simulator for every push/PR
docs/                       STRATEGY.md, ROADMAP.md, BUILD_PLAN.md
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
- **Tap handling stays UIKit-backed.** `TapCatcherView` exists because SwiftUI gestures
  are unreliable over a continuously redrawing `TimelineView`/`Canvas`. Keep it a
  separate, stable layer.
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

- `docs/STRATEGY.md` — what "AAA" means for Vesper, engineering/UX standards, budgets
- `docs/ROADMAP.md` — milestones M0–M3 with acceptance criteria
- `docs/BUILD_PLAN.md` — file-level build plan, test plan, release checklist
- `docs/pop_standard.md` — the formal pop schema, envelopes, and authoring rules
- `docs/pop_progression.md` — the journey: phases, unlock rules, featuring/Drift
- `docs/pop_points.md` — scoring formula and how stats surface in/out of game
