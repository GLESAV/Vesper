# Vesper — the team

*Who builds it, who reviews it, and who decides. The board (the critique panel)
advises and reviews; the engineering team builds; the Director of Engineering
owns the roadmap and has final say on its approval.*

## 1. Director of Engineering

**Nadia Rhee** — 20 years shipping premium mobile; three studios; known for
killing beautiful plans that could not be built and for protecting small teams
from their own ambition. Owns: roadmap approval (final say), sequencing, risk
posture, the quality bars, and the call on when something is done. Reports to
the board but is not overruled by it on execution; the board owns *whether the
thing is right*, Nadia owns *whether it can be built and how*.

## 2. Engineering team

| Code | Engineer | Owns |
|---|---|---|
| **ARCH** | **Ilya Novak** — Principal Engineer, Simulation & Architecture | The pure simulation, the camera state machine, determinism, module boundaries, the flag architecture |
| **REND** | **Mei Tanaka** — Senior iOS Engineer, SwiftUI & Rendering | `WorldView`, Canvas rendering, the continuous-scene composition, frame budget |
| **INPUT** | **Rafael Duarte** — Interaction Engineer, Input & Gestures | Gesture arbitration, `TapCatcher` extension, pop-on-touch-down, dead zones, thresholds |
| **AUDIO** | **Priya Raman** — Engineer, Audio & Haptics | `PopSoundEngine`, world-move sounds, haptic grammar, route policy |
| **A11Y** | **Lena Fischer** — Engineer, Accessibility & Platform | VoiceOver flows, Reduce Motion variants, Dynamic Type, lifecycle, interruption |
| **DATA** | **Tomás Herrera** — Engineer, Content & Data Systems | Catalog, `ProgressionStore`, `MapStore`, persistence, migrations, the trace |
| **QA** | **Aiko Sato** — QA & Test Engineer | Test suites, CI, exit-test instrumentation, device matrix, regression |
| **TOOLS** | **Sam Okonkwo** — Tools & Demo Engineer | The browser demo (the playtest surface available today), harnesses, build/release tooling |

Every engineer works to the same standing rules: the simulation stays pure and
deterministic; nothing ships without tests; CI stays green; the flag rule holds
(old navigation is not deleted until the new one passes on-device).

## 3. The board (advisory + review)

The critique panel from `CRITIQUE.md`, now standing as the board:

Aria Vale (Creative Director) · Dr. Renata Cole (Audience Research) ·
Jun Park (Interaction Design) · Marta Okafor (Systems) ·
Sofia Lindqvist (Art) · Theo Marsh (Audio) · June Ashford (Narrative) ·
Hana Sato (Production) · Colin Reyes (Growth) · Imani Brooks (Accessibility) ·
**Dani** and **Priya** (player advisors).

The board does not approve the roadmap — Nadia does. The board owns review
gates: it can **block** on mission violations (a pillar veto), and **advise**
on everything else. A blocked gate returns to the owning engineer with the
specific finding; Nadia rules on any dispute.

## 4. Specialists (called in, not standing)

| Code | Specialist | Called for |
|---|---|---|
| **PERF** | Viktor Sørensen — graphics/performance | Frame-budget work, the camera+Canvas composition, oldest-device proof |
| **VEST** | Dr. Amara Osei — vestibular/motion sensitivity | Any continuous-camera motion; the Reduce Motion matrix |
| **CONC** | Keiko Yamada — Swift concurrency & state verification | The camera state machine, publishing-during-view-update hazards |
| **REVIEW** | Marcus Bell — App Review & platform compliance | Release gates, privacy answers, store submission |

## 5. Review types (each is a subprocess critique)

| Gate | Reviewers | Question it answers |
|---|---|---|
| **R-ARCH** | Nadia (chair), Ilya, Keiko (CONC) | Is the design buildable, pure, testable, and reversible? |
| **R-SPIKE** | Jun Park, Imani Brooks, Viktor (PERF) | Do swipe-to-move and tap-to-pop coexist on the oldest device? Go / fallback stage 1 / fallback stage 2. |
| **R-NAV** | Jun Park, Renata Cole, Dani | Can a real person find the sky and the journal, in bed, unprompted? |
| **R-A11Y** | Imani Brooks, Amara Osei (VEST) | Is parity designed in — VoiceOver, Reduce Motion, contrast, hit regions? |
| **R-ART** | Sofia Lindqvist, Aria Vale | Does it look like the held evening, or like software? |
| **R-VOICE** | June Ashford, Aria Vale | Does every string pass the 1 a.m. kitchen test and the forbidden list? |
| **R-SYS** | Marta Okafor | Do the numbers produce the feelings the design claims? |
| **R-SHIP** | Hana Sato, Marcus Bell (REVIEW), Aiko | Is it releasable, regression-clean, and honest in the store? |
| **R-BOARD** | Full board | Checkpoint on the built artifact against the mission. |

Every gate returns one of: **pass** · **pass with notes** (build continues,
notes become work items) · **block** (named finding, returns to the owner).
