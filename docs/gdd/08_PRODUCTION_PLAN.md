# Vesper — Production Plan (to v2.0 "One World")

*How the plan becomes the game. Phases are sequential and each ends playable.
No dates — Vesper ships when it's calm — but each phase is sized in focused
work-sessions (solo dev + AI pair, the studio model that built v1.2).*

## 0. Ground rules

- The simulation core, pop engine, catalog, points, and map **systems** are
  stable and stay (they are v2's foundation; only surfaces change).
- Every phase keeps CI green, tests grow with systems, tuning contract holds.
- The v1.2 branch is merged; v2 work proceeds in the same PR-per-wave rhythm.
- **Phase 0 blocks everything** — no new features on the old navigation.

## Phase 0 — One World navigation rebuild *(the critique, answered)*

Scope (from 04): the vertical camera world (Sky/Field/Journal as one scene) ·
gesture + whisper wayfinding · Sky = the Path re-surfaced (constellation
rendering over the existing MapStore) · Journal = Journey + fortunes archive +
quiet things (settings) as pages · delete top bar, sheets, reset button ·
long-press start-over · copy warmth pass ("set free" etc.) · Reduce
Motion/VoiceOver parity for all of it.

Engineering notes: one `WorldView` owning a camera offset; field canvas is
already position-independent; sheets' content migrates into in-world surfaces;
sim untouched. Est. 3–4 sessions. **Exit test:** a new player finds both the
sky and the journal inside two minutes without any prompt, on video, 5/5
testers.

## Phase 1 — First hour & arrival

W1 onboarding (5-orb first field, whispered lines, the first star) · the
arrival moment · evening light · interruption audit (W6) · App Store metadata
refresh to the new surfaces. Est. 2 sessions. **Exit test:** cold install →
first pop < 15 s; 0 tutorial screens; testers can explain "the sky" unprompted.

## Phase 2 — Ownership & ritual

Journal pages v2: fortunes archive, keepsakes, the lamp · shareable stillness
card · chime voicings · world-move sounds + haptic ticks · fortune-orb dreamy
tell. Est. 2–3 sessions. **Exit test:** playtesters voluntarily show someone
their journal (the "this is mine" behavior).

## Phase 3 — Reach & release

The breath (optional) · quiet room tone toggle · widget spike (lamp + count) ·
iPad "big sky" pass · new 5-scene screenshots + App Preview video from the
live app · localization prep (string catalog; es/fr/de/ja/zh-Hans per 07 voice
rules) · v2.0 submission via docs/RELEASE checklist pattern. Est. 3 sessions.

## QA & Playtesting (runs through all phases)

- **Automated:** existing 4 suites + new WorldView navigation tests (camera
  state machine is pure and unit-testable) + string-registry test enforcing the
  07 forbidden-vocabulary list.
- **Playtest panel:** 8–12 women 25–35 from the target contexts (commuter /
  wind-down / collector), recruited via TestFlight link in owner's network +
  a cozy-games community post. Sessions: unmoderated first-hour video (phases
  0–1), one-week diary study (phase 2), regression pass (phase 3). Incentive:
  credited in the journal's last page ("with thanks to the first evenings of…").
- **Device matrix:** oldest supported iPhone, ProMotion iPhone, iPad, always at
  minimum brightness + 1 a.m. test (06 §5).

## Risks

| Risk | Mitigation |
|---|---|
| One World camera fights SwiftUI (gesture/canvas conflicts) | Prototype the camera + TapCatcher interplay first session; the UIKit tap layer already isolates input |
| Scope creep via "one more ritual" | Pillar veto tests; phases 2–3 features each need a named fun-source (03 §1) |
| Onboarding whispers feel like a tutorial | Test W1 with copy off — the field must teach itself; words only *bless* discoveries |
| Solo-dev burnout | Phases end playable; any phase is a shippable v1.x |
| Playtest recruitment stalls | Fall back to TestFlight public link + r/CozyGamers; 5 testers minimum viable |

## Definition of v2.0 done

All four phase exit tests passed · pillars veto-audited · CI green · device
matrix + accessibility pass · App Store package updated · the one metric:
panelists open it the next evening, unprompted.
