# Vesper Build Plan — M0 + M1 (MVP "The Feel Update", v1.1)

Concrete execution plan for the roadmap's first two milestones. Checkboxes reflect the
state of this branch.

## 1. Workstream A — Architecture refactor (M0)

Target layout (all inside the file-system-synchronized `Vesper/` group, so no pbxproj
source-file edits are needed):

| File | Responsibility | Status |
|------|----------------|--------|
| `Game/GameConfig.swift` | Every tuning constant, transcribed 1:1 from v1.0 | ✅ |
| `Game/Entities.swift` | `Orb`, `Particle`, `Ring`, `Mote` value types; UI-free (`paintIndex` instead of `Color`) | ✅ |
| `Game/SeededRandom.swift` | SplitMix64 `RandomNumberGenerator` | ✅ |
| `Game/GameSimulation.swift` | Pure sim: layout/seed/tap/step/detonate; returns `[GameEvent]`; no UI imports | ✅ |
| `Game/Fortunes.swift` | Fortune strings (unchanged copy) | ✅ |
| `Game/GameViewModel.swift` | `ObservableObject`; event routing to audio/haptics/stats; fortune, chain-whisper, done-card timing; render-pause control | ✅ |
| `Rendering/SceneRenderer.swift` | Palette (unchanged colors) + all Canvas drawing | ✅ |
| `Audio/PopSoundEngine.swift` | Pre-rendered buffers, chime, lifecycle/interruptions | ✅ |
| `Haptics/HapticsEngine.swift` | Prepared generators; pop/cleared vocabulary | ✅ |
| `Support/SettingsStore.swift` | UserDefaults-backed toggles + lifetime stats | ✅ |
| `Views/ContentView.swift` | Layer composition + HUD | ✅ |
| `Views/TapCatcherView.swift` | UIKit tap layer (moved, unchanged behavior) | ✅ |
| `Views/Cards.swift` | Fortune + done cards | ✅ |
| `Views/SettingsSheet.swift` | Settings UI | ✅ |

**Tuning-preservation contract** (checked during review): orb count `7..<20`, radius
`18…34`, speed `±0.18`, tap tolerance `+12`, top inset 70 (bounce) / 100 (spawn), edge
inset 24, wobble `sin(phase)·0.03` at `0.02·f`, ring growth `(max−r)·0.1·f + 1.5·f`,
ring life decay `0.03·f`, shell thickness 24, chain trigger `r > 18`, particle counts
`18 + baseR`, gravity `0.07·f`, damping `0.986^f`, pop pitch mapping `460–880 Hz ±12`,
fortune display 3.6 s, done-card delay 0.65 s. All palette RGB values unchanged.

## 2. Workstream B — Feel features (M1)

- [x] Haptics: `.soft` impact, intensity `0.35 + sizeNorm·0.5`, chained ×0.8, success
      notification on clear; gated by settings; generators kept prepared
- [x] Audio: 8 pitch buckets × 3 detuned variants pre-rendered at init (~1 MB);
      3-note completion chime (C5–E5–G5, soft attack, exp decay); interruption
      observer; `setActive(_:)` driven by scene phase
- [x] Ambient motes: 36 faint drifting points with slow twinkle, wrap at edges,
      still under Reduce Motion
- [x] Orb specular highlight (subtle, additive layer)
- [x] Chain whisper: 3+ pops inside rolling 0.9 s windows → transient "chain of N"
- [x] Settings sheet: sound + haptics toggles, lifetime stats, credit footer
- [x] Stats: `lifetimePops`, `fieldsCleared` in UserDefaults; done card shows lifetime
      line once it exceeds the current session
- [x] Accessibility: VoiceOver labels (counter, settings, reset, done/fortune cards);
      Reduce Motion honored in sim
- [x] Efficiency: particle cap 320; `TimelineView(paused:)` when cleared and quiet;
      edge bounce clamps position (no jitter when out of bounds after rotation)

## 3. Workstream C — Tests + CI (M0)

- [x] `VesperTests` unit-test bundle target added to the Xcode project
      (`TEST_HOST` = Vesper.app; its own file-system-synchronized group)
- [x] Shared scheme `Vesper` (build + test) committed under `xcshareddata`
- [x] `.github/workflows/ci.yml`: macos-15, Xcode 16.4, `xcodebuild test` on
      iPhone 16 simulator, signing disabled
- [x] Test suite (`GameSimulationTests`):
  - seeding: orb count in range, in-bounds positions, exactly one fortune orb
  - tap: hit within tolerance pops exactly one orb; far tap pops none;
        taps ignored after completion
  - chain: a pop's ring detonates a neighbor within a few steps; event marked chained
  - completion: `.cleared` fires with correct total exactly once
  - restart: state fully reset, field reseeded
  - particle cap: never exceeded under mass pops
  - determinism: same seed ⇒ identical field
  - robustness: huge `dt` clamps; orbs stay in bounds over long runs

## 4. Workstream D — Release prep (M1)

- [x] `MARKETING_VERSION` 1.0 → 1.1
- [x] `fastlane/metadata/en-US/release_notes.txt` rewritten for The Feel Update
- [ ] Manual device pass (below) — requires physical hardware, post-merge
- [ ] TestFlight build + `fastlane deliver` — post-merge, owner runs

## 5. Manual device pass (pre-release checklist)

On the oldest supported iPhone and a ProMotion iPhone:

1. Cold launch → first pop < 1.5 s, no flash of wrong UI.
2. Pop feel: burst, tone, and haptic land as one event; no audio crackle during a
   10-orb chain.
3. Play music in the background → Vesper mixes over it; take a phone call → sound
   recovers afterwards.
4. Toggle sound/haptics off/on mid-session — both respond immediately and persist
   across relaunch.
5. Clear the field, wait for effects to settle → CPU/GPU at ~0 in Xcode gauges.
6. Rotate mid-session (and on iPad, resize) → orbs stay in bounds, no jitter.
7. Enable Reduce Motion → fewer particles, motes still, game fully playable.
8. VoiceOver: counter, settings, and reset are labeled and reachable.
9. Leave app 10 minutes, return → one clean clamped frame, no orb teleporting.
10. Airplane mode everything — the app must not care.

## 6. Definition of done (MVP)

All Workstream A–C boxes checked, CI green on the PR, tuning-preservation contract
verified in review, and release prep items D1–D2 landed. Items D3–D4 are the owner's
post-merge steps.
