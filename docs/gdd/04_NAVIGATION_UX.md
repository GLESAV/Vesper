# Vesper — Navigation & UX Blueprint

*The centerpiece of the v2 plan. The current navigation is the biggest gap
between "great start" and "AAA game" — this document owns that critique and
replaces the model.*

## 1. Honest critique of the current navigation

The shipped v1.2 navigation is **software, not a place**:

| Problem | Why it fails the mission |
|---|---|
| Four unlabeled utility icons (⚙ ⑂ ✦ ↻) floating over the field | Mystery-meat nav; the audience research is unambiguous — cryptic glyphs read as effort, and effort reads as stress |
| Core content (the Path! the collection!) hidden behind the two most cryptic icons | The game's biggest sources of fun are invisible to a new player; discovery relies on curiosity-clicking, which this audience rightly doesn't do |
| Modal sheets stacked on the game | Sheets are interruptions — the field stops being a place and becomes a launcher for panels; breaks P4 ("one beautiful place") |
| A permanently exposed reset button | A destructive action at equal rank with everything else; anxiety-by-layout |
| "DETONATED" as the biggest label in the game | Wrong register entirely for a stress-free game aimed at grown women |
| No onboarding, no arrival, no session framing | First-run players see 11 orbs and four icons and must infer a whole game |

None of the underlying *systems* are wrong. The *surfaces* are.

## 2. The new model: **One World** (three places, one axis, one gesture)

The entire game is one continuous vertical space. Navigation is **movement**,
not menus:

```
        ✦ THE SKY  (the Path)
        stones as stars in the dusk above
        — drift up —
   ─────────────────────────────
        THE FIELD  (home, play)
        orbs, counter, nothing else
   ─────────────────────────────
        — drift down —
        THE JOURNAL  (the Journey + fortunes,
        keepsakes, the lamp, and the quiet
        things: sound, haptics, whispers)
```

- **One gesture:** swipe up anywhere → the camera drifts up into the Sky.
  Swipe down → down into the Journal. Swipe back → the Field. The three places
  are physically continuous — motes and background parallax carry through; you
  can *see* the lowest stars from the field's edge and the journal's ribbon at
  its foot. (How swiping and popping share one surface is specified in §4 —
  the pop always wins.)
- **Words as wayfinding:** at the field's top edge, a faint serif whisper —
  `✦ the sky` — and at the bottom — `your journal`. They breathe in when the
  field is idle and dim during play — to a committed floor, never to nothing
  (§9) — and are tappable for the gesture-averse. No icons anywhere in the
  world. **Icons are banned from navigation.**
- **The Sky is the Path, literally:** stones become stars; roads become faint
  constellation lines; the current stone glows nearest the field. Choosing a
  star drifts the camera back down and the field seeds from it — the map and the
  game share one space, so "which level am I on" is answered by *looking up*.
  Leaving without choosing is always allowed: swipe down (or tap the `the
  field` whisper) returns home with nothing changed.
- **The Journal is everything she owns:** the evening page — tonight's numbers,
  the lamp, and the quiet things (sound, haptics, whispers — see §7, they must
  be instantly reachable, not buried); turnable pages — the collection (pops as
  pressed lights, per-family), fortunes she's found (re-readable!), keepsakes,
  and `about`. In this world even preferences are personal effects, not
  machinery — but the ones she reaches for in the dark sit on the first page,
  not the last.
- **Start over** is deliberate, discoverable, never looming, and never a timed
  ritual — the full design is §6.
- **Interruption-proof:** every place fully resumable; app always reopens on the
  Field (P1), with the camera exactly where the field is.

### Why this is the AAA answer

Monument Valley, Alto's, Journey, Sky: the hallmark of premium calm games is that
**the world absorbs the UI**. Sheets and toolbars are the tell of an MVP. One
World keeps P1 (cold-launch lands *in play*), fixes discoverability (both core
surfaces are visibly adjacent to the field at all times), removes all modal
state, and gives the game its "wow, this is one place" moment — the thing
reviewers and players screenshot.

## 3. Phase 0a — the spike that earns the rebuild

One World is the plan's highest-risk bet, and every other feature queues behind
it. So it is not built first — it is **proven** first, in a timeboxed (two
weeks), throwaway prototype whose only job is to answer four questions on a
real device:

1. **The pop survives the swipe.** On the *oldest supported device*, with the
   camera system live, tap-to-pop must measure equal to v1.2 in tap latency and
   frame pacing. `TapCatcherView` is **extended, not replaced** — it stays the
   UIKit layer that made taps reliable, and grows pan recognition alongside.
2. **She can find her way lying down.** A 5-user wayfinding test, phones in
   hand, lying down, lights low: find the sky, find the journal, get home,
   quiet the game. The go/no-go criteria are written before the test runs
   (below), not after.
3. **Quiet is instant.** Mute the game in under 5 seconds, one-handed, on the
   first attempt (§7).
4. **It survives interruption.** The W6 interruption audit (backgrounding
   mid-cascade, mid-transit, mid-onboarding — see W1a/W6) passes on device.

**Exit test (go/no-go, written now):** all four above pass, at the standard
panel bar (n≥8 fresh testers, ≥7/8, no shared-cause failures, one
fix-and-retest cycle — see 08). Until One World passes this exit test on
device, **the v1.2 navigation is not deleted** — both navigations live behind a
build flag, and the game stays shippable every day of the rebuild.

**Fallback sequence (decided now, so a failed spike re-scopes instead of
stalls — full text in 08):**

- **Stage 1:** keep the camera and the continuous world, demote swipes to an
  enhancement — the tappable whisper-labels become the primary navigation.
- **Stage 2** (only if the camera itself fails the performance or
  motion-sensitivity gates): static field, full-screen in-world panels that
  keep the fiction — no continuous camera.

**Risk register (mirrored in 08):**

| Risk | Signal | Response |
|---|---|---|
| Swipe recognition degrades pop latency on oldest device | Spike measurement vs v1.2 baseline | Fallback stage 1 (tap-labels primary) |
| Camera motion fails motion-sensitivity screen | Panel motion-screened testers report discomfort | Fallback stage 2 (static field, in-world panels) |
| Lying-down wayfinding test fails | <7/8 or shared-cause failure | One fix-and-retest cycle; then fallback stage 1 |
| Rebuild stalls mid-way | Flagged old nav still present | Ship on old nav; One World slips, game doesn't |

## 4. Gestures: arbitration and the per-place map

The core loop and the navigation model share one surface. That only works if
the rules are absolute:

- **The pop fires on touch-down** — not on touch-up, not after a
  disambiguation delay. A touch that lands on an orb pops it, instantly,
  every time. **In any tie, the pop wins.**
- **A nav swipe commits only past *both* a distance and a velocity
  threshold.** The spike starts at ~10–12% of screen height plus a velocity
  gate; on-device testing picks the final numbers and this section records the
  *measured* values, not a guess. Below threshold, the camera springs home and
  nothing happens — a hesitant half-swipe is free.
- **Dead zones, no deferral.** The top and bottom ~10% of the screen are dead
  to the game's nav swipes so the system's own edge gestures (Control Center,
  Home) always work instantly — "her evening, respected" means the OS is never
  made sticky via `preferredScreenEdgesDeferringSystemGestures`. The wayfinding
  whispers live inside these dead regions, so the zones are covered by tappable
  affordances, not wasted.
- **One axis, one meaning per place.** Vertical always means *moving through
  the world*. Anything that scrolls or turns inside a place uses the
  horizontal axis. No axis does two things in the same place.

| Place | Tap orb / object | Tap empty space | Tap whisper | Swipe up | Swipe down | Swipe left/right | Long-press object | Long-press empty |
|---|---|---|---|---|---|---|---|---|
| **Field** | pop (touch-down) | nothing (soft ripple) | go to that place | to the Sky | to the Journal | nothing | pop (a press on an orb always pops) | arm *begin again* (§6) |
| **Sky** | choose star → descend, field re-seeds | nothing | `the field` → home | drift further up the path | to the Field (no star chosen, nothing changes) | nothing | hold to keep (favorite a stone) | nothing |
| **Journal** | that row's action | nothing | `the field` → home | to the Field | further down the page (page content scroll is vertical-free: pages *turn* horizontally) | turn pages | hold to keep (keepsake) | nothing |

No blank cells: "nothing" is a specified result, and it is always safe.

- **Stars are targets, not pixels:** every star has a ≥44 pt hit area. Where
  stars sit closer than 44 pt (dense path regions), a tap **zooms the cluster**
  instead of guessing — she picks from the zoomed view, and a swipe down backs
  out of the zoom before it backs out of the sky.

## 5. The camera

Feel-defining values are committed here, not left to engineering:

- **Finger-tracked, 1:1.** While her finger is down, the camera moves with it
  exactly. There is no scripted "transition" she watches — she *carries* the
  camera.
- **Release settles, 300–650 ms.** On release past the commit threshold, the
  camera settles into the destination with easing seeded by release velocity.
  The 300–650 ms band applies **only to the settle** — never to a full
  start-to-finish move she can't touch.
- **Every move is interruptible.** A touch during any settle catches the
  camera where it is. **The camera never moves unasked.**
- **Transit input policy:** during a settle, touch-down grabs the camera (it
  does not pop, does not choose a star); play input re-arms the moment the
  field is at rest on screen.
- **The sim pauses off-field.** While the camera is in the Sky or the Journal,
  `step(dt:)` is not advanced — her field waits exactly as she left it, and no
  chain resolves unseen.

## 6. Starting over

The permanent reset button is deleted; what replaces it can never fire by
accident and never demands a timed ritual:

- **Long-press on empty field space** arms it — a press that lands on an orb
  *always* pops instead, so reaching for play can never threaten the field.
- Arming shows the whisper `begin this field again?` with the dim-and-gather
  treatment (05): the field dims, the orbs draw softly together.
- **Confirm is a plain tap** on the whisper — not a second timed hold (timed
  holds exclude Switch Control users). Tapping anywhere else, or waiting,
  disarms with no consequence.
- The journal's evening page carries `begin again` as a plain row, and the
  field exposes it as a VoiceOver custom action — the same act, reachable
  without any gesture ritual at all.
- **One long-press grammar everywhere else:** on world objects, a long press
  always means *hold to keep* (keepsakes, favoriting a stone). A one-time
  discovery whisper (`press and hold, to keep a thing`) teaches it once, the
  first time a keepable thing appears, and never again.

## 7. Instant quiet

The audience's most common first-minute need — silence, one-handed, in the
dark — must be the easiest act in the game, not the hardest:

- **≤2 gestures from the field, always:** one swipe down opens the journal on
  the evening page; at its top sits `hush` — one tap silences sound and
  haptics together. Two gestures, under 5 seconds, one thumb. Individual
  sound / haptics / whispers rows sit directly beneath it, alongside the
  room-tone and transition-sounds toggles (06) — one quiet surface, first
  page.
- **The silent switch is honored.** The audio session is `.ambient`: flipping
  the phone's ring/silent switch mutes Vesper with **zero** in-app interaction.
  The game never overrides her phone's own quiet.
- The Phase 0a exit test (§3) includes: *mute in under 5 seconds, one-handed,
  first attempt, in the dark.*

## 8. Wireflows (described; UI sketches to be produced from these)

**W1 — First launch (the first 60 seconds):**
5 orbs only, no labels, no counter. Whisper: `tap an orb. let it go.` → first
pop (full sensory payoff) → silence, no more copy → player clears the 5 →
chime + `that's it. that's the whole idea.` → the counter fades in; the sky
whisper appears; one star descends into view above the field → `the sky
noticed.` End of onboarding. (No tutorial screens, no coach marks, ever.)

**W1a — Onboarding, interrupted:** the toddler test applies to the first
session most of all. Backgrounding at any onboarding step → on return, the
field is exactly as left and the current whisper breathes back in; nothing
restarts, nothing is re-demanded. If the app is killed, onboarding resumes at
the step reached, never from the beginning. Clearing the 5 remains the only
requirement, however many sittings it takes.

**W2 — Daily arrival:** open → motes assemble the field (~1.5 s, skippable by
tapping) → evening-light hue per local time → play.

**W3 — Going to the sky:** swipe up → the camera rides the finger, then
settles (§5; particles streak subtly) → stars/roads → tap a star → drift back
down, field re-seeds from that stone's pops → whisper names the stone
(`ember · clover`). Or: swipe down, choose nothing, and the field is
untouched.

**W4 — Visiting the journal:** swipe down → journal opens on the evening page
(lamp lights if first visit today; `hush` and the quiet rows at top) → swipe
horizontally through pages → swipe up to return.

**W5 — Field clear:** last pop → 650 ms of afterglow → chime + done card
*in-world* (it drifts in like a note, not a modal) → card shows: count set
free, +points, lifetime line → `again?` (tap) or just leave — swiping away is a
valid, unpunished exit.

**W6 — Interruption:** app backgrounds mid-cascade → on return, one clamped
frame, field exactly as left, no summary popups. The full interruption audit —
mid-cascade, mid-transit, mid-arm, mid-onboarding (W1a) — is part of Phase 0's
exit criteria (§3), not a later polish pass.

## 9. Legible in the dark (zero-chrome that still works)

Zero chrome is only calm if it is *findable*. The floors, measured — not
felt:

- **Whispers dim, never vanish.** During play, wayfinding whispers dim to a
  committed floor of ~40% of idle opacity — never zero. With VoiceOver or any
  assistive technology active, they do not fade at all.
- **Contrast is measured in APCA** (the design standard for this product's
  regime — low-luminance text on near-black OLED; tool named in 05): whispers
  Lc ≥ 60, decorative text Lc ≥ 45, computed **at final composited opacity, on
  an OLED device, at minimum brightness** — not in the design file. A one-time
  WCAG 4.5:1 spot-check on functional text covers conventional compliance
  reporting.
- **The interactive-object grammar** (05 §6.1) is the discoverability system:
  *breathing = touchable, static = scenery*, everywhere, with no exceptions —
  verified by a 5-user no-prompt find test ("without me telling you anything,
  what here can you touch?").
- **Constellation roads:** ≥1.5–2 pt stroke at 20–25% opacity, verified on
  device in the dark, not on a desktop monitor.
- **The lamp** keeps its 24 pt visual scale but carries a ≥44 pt hit
  footprint, like every world-object control.
- **Whispers meet every touch standard:** ≥44 pt hit regions, Dynamic Type
  respected.
- **Top edge vs the bottom-60% rule, resolved:** the `✦ the sky` whisper at
  the top edge is a *redundant* affordance, not a primary one — the primary
  act (swipe up) works from anywhere in the bottom 60%. No primary action
  requires reaching the top of the screen.

## 10. The accessibility contract

Gesture-only, zero-chrome navigation is built accessible from the first
prototype — retrofitting after Phase 0 would mean building the navigation
twice.

- **Destinations never leave the accessibility tree.** `the sky`, `your
  journal`, `the field` are always present as elements regardless of visual
  fade state.
- **VoiceOver flows exist for W1–W6** (and W1a), specified alongside the
  sighted flows, not derived from them afterward.
- **Custom actions + escape:** the field element exposes custom actions —
  *go to the sky*, *open your journal*, *begin this field again* — and the
  standard two-finger-Z escape returns to the field from anywhere.
- **VoiceOver play spec:** each orb is an accessibility element (lowercase
  label, e.g. `orb, small, drifting`); double-tap pops it with full sound and
  haptic payoff; chain pops announce as one quiet summary (`three more set
  free`), never a barrage; fortune and done cards read in full and dismiss
  with escape.
- **Every world-object control** (lamp, stars, journal rows, whispers) is an
  accessibility element with a lowercase label, the button trait, and a
  ≥44 pt invisible hit region.
- **Audio under VoiceOver, decided:** the session stays mixable `.ambient`
  (which also honors the silent switch, §7); under VoiceOver, pop audio ducks
  beneath announcements and the haptic remains the authoritative pop
  confirmation.
- **No timed holds required anywhere** (§6) — every hold-gated act has a
  tap-or-row alternative, for Switch Control users.
- **The eyes-closed round trip** — field → sky → choose a star → field →
  journal → hush → back, VoiceOver only, screen curtain on — joins the 05 §10
  review checklist and the QA bar, and is part of Phase 0's exit tests.

## 11. Reduce Motion: one policy, every motion

**Standing rule: no animation ships without a defined reduced variant.**
Parity means, concretely: every destination reachable, every state readable,
no information carried by motion alone.

| Motion | Full | Reduce Motion substitute |
|---|---|---|
| Camera drift between places | finger-tracked + settle (§5) | crossfade between places; swipe still navigates |
| Background parallax | multi-layer depth drift | static layers |
| Mote assembly (W2) | ~1.5 s gather | field fades in, motes pre-settled (v1.2's shipped "static motes" behavior stands as the floor) |
| Star descent (W1) | star drifts down into view | star fades in, in place |
| Page-turn glow | glow sweep across the fold | plain crossfade between pages |
| Evening-light tint | slow animated hue shift | tint applied instantly (color is information, not motion) |
| Shockwave / chain ring | expanding ring | brief stationary glow bloom at the pop; chain still readable pop-by-pop |
| Breathing whispers | opacity breathing | static at full committed opacity |
| Done-card drift (W5) | drifts in like a note | fades in, in place |
| Pop particles | full burst | fewer particles (v1.2's shipped behavior, kept) |

- **World-move sounds always play under Reduce Motion** — with camera motion
  removed they become the primary orientation cue — retimed to the crossfade.
  A separate all-users *transition sounds* toggle lives in the quiet surface
  (§7, 06), so suppression is her explicit choice, never the default, and the
  Reduce Motion user who needs the cue keeps it.
- The Reduce Motion path is tested first-class by the panel's motion-screened
  testers (08), not smoke-tested by the developer.

## 12. Reachability & ergonomics

- All interactive targets ≥ 44 pt; primary actions in the bottom 60% of screen
  (the top-edge sky whisper is redundant, per §9).
- Nav swipes work from anywhere outside the §4 dead zones (one-handed, in
  bed); the dead zones exist so the system's own gestures always win.
- Left/right-handedness irrelevant by design (no corner-anchored controls).
- **v2.0 is iPhone-first.** One World is a portrait thumb-swipe model; the
  existing iPad layout is grandfathered as-is for v2.0, and iPad interaction
  design is revisited as its own post-2.0 arrival rather than half-specified
  now.

## 13. Copy system (with 07)

All navigation copy is lowercase serif whispers (sentence-case is reserved for
fortunes, as 07's stated exception). The canonical strings used here —
`the sky` · `your journal` · `the field` · `set free` (counter label) ·
`tap an orb. let it go.` · `again?` · `begin this field again?` · `hush` ·
`press and hold, to keep a thing` · `the road behind folded itself away.` ·
`the sky noticed.` — are owned by the string inventory in 07 §5; that catalog
is the single source of truth, and changes land there first.

## 14. What gets deleted — and what must survive it

Deleted: the four-icon top bar · all `.sheet` presentations · the standalone
settings screen (**instant sound/haptic control is preserved at one gesture
from the field — §7 — before the screen goes**) · the permanent reset button ·
the word DETONATED.

Deleted *last*: the v1.2 navigation itself. It stays behind a build flag until
One World passes its Phase 0 exit tests on device (§3) — the game is shippable
on every day of the rebuild.

The pop engine, points, unlock, and map *systems* are untouched — this is a
surface rebuild (see 08 for phasing: it is Phase 0, before any new features).
