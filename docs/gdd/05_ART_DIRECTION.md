# Vesper — Art Direction Bible

*The look is the promise: dusk, glow, softness. A place, not an interface.*

## 1. The world

One continuous dusk. Not space, not night — **the fifteen minutes after sunset**,
held forever. Everything in the game exists inside that light: the field is the
air, the Path is the first stars, the Journal is a book on the windowsill.

## 2. Color

- **Grounds:** the existing dusk gradient (#16151F → #100F18 → #09080E) is the
  world's base and is correct. **Evening light** (03 §Added) tints it ±4% toward
  warm at daytime hours, toward deep blue-violet after midnight — always subtle,
  always dark-room-comfortable at minimum brightness, and never allowed to pull
  any functional surface below the contrast floors in §2.2.
- **The pastel band:** all content color lives in the established muted band
  (~150–245/channel, low saturation). The 100-pop family palettes (PopCatalog)
  are the color system — UI never introduces hues the catalog doesn't own.
- **Forbidden:** saturated primaries, pure white (#FFF caps at 96%), pure black,
  red of any kind (alarm register), and any color used as a warning.

### 2.1 Semantic tokens (the values we actually type)

Every color in code resolves through this table — no literal hex outside it.
*Fixed* tokens never change; *family* tokens derive from the live pop family's
palette. **Live-color cap:** at most **three** family-derived tokens may be on
screen at once outside the field (the field itself is the family's home).

| token | value | opacity | blend | source |
|---|---|---|---|---|
| `ground.top` | #16151F | 100% | normal | fixed |
| `ground.mid` | #100F18 | 100% | normal | fixed |
| `ground.deep` | #09080E | 100% | normal | fixed |
| `journal.paper` | #181622 warmed +3% | 100% | normal | fixed |
| `text.whisper` | #E8E4DA | 70–85% idle · 40% floor in play | plusLighter | fixed |
| `text.counter` | #DCD8CE | 85% | plusLighter | fixed |
| `text.fortune` | #EDE9DF | 90% | plusLighter | fixed |
| `orb.halo` | family hue | 35% | plusLighter | family |
| `orb.body` | family hue | 100% | plusLighter | family |
| `orb.highlight` | #F5F2EA (96% white cap) | 90% | plusLighter | fixed |
| `star.gem` | family paint | 80% | plusLighter | family |
| `road.line` | #D9D6E8 | 20–25% | plusLighter | fixed |
| `lamp.pool` | #E8C89A | 30% | plusLighter | fixed |
| `card.scrim` | #09080E | 55% | normal | fixed |
| `confirm.dim` | field luminance × 0.6 | — | normal | fixed |

### 2.2 Contrast floors (measured, not felt)

- **Standard: APCA.** It is the accurate model for this product's regime —
  low-luminance light type on near-black OLED. Floors: **Lc ≥ 60** for
  functional text (whispers at their play-time floor, counter, journal body,
  settings rows); **Lc ≥ 45** for decorative/ambient text and roads.
- Floors are computed at the **final composited opacity** — token opacity ×
  breath state × any dim — on an OLED device at **minimum brightness**. A value
  that passes at 85% idle but fails at its 40% play floor fails.
- One-time **WCAG 4.5:1 spot-check** on functional text for conventional
  compliance reporting; APCA remains the working standard and the tool named in
  reviews.
- **Daylight clause:** the dark room is the home condition, not the only one.
  Every functional surface is also checked in the *sunny train* condition —
  bright ambient light, auto-brightness high — where additive glow washes out
  first. Whispers and the counter must stay readable there without any special
  mode.

## 3. Light is the material

Everything luminous renders additively (the plusLighter discipline already in
the renderer). Rules:
- Glow is earned by importance: orbs > stars > text whispers > chrome (chrome
  ideally has none — see §6).
- Nothing blinks. Light *breathes* (≥ 2 s cycles) or *drifts*.
- The brightest moment in the game is, and must remain, **the pop**.
- **Cascade luminance budget:** within any 25%-of-screen region, at most
  **3 above-threshold brightness flashes per second**. Chains that would exceed
  the cap render as **staggered, lower-peak glows** riding the existing chain
  stagger — every pop still lands, the light just takes turns. This is a hard
  render-side cap, not a tuning suggestion: additive flashes on near-black is
  the photosensitive pattern, and this is a bedtime product for dark-adapted
  eyes.
- **Gradient dither:** large gradients get 1% noise dither to kill OLED
  banding, with a luminance floor — dither never dips a pixel below
  `ground.deep`.

## 4. Shape language

Circles and soft curves only. The orb is the atom; stones, journal page corners,
cards, and even text blocks echo its radius family (11/18/22 pt radii — keep the
existing scale). No sharp corners; no straight-edged panels floating on the
world. The Journal's pages may have gentle deckle texture — the one permitted
texture in the game.

## 5. Typography

- **Serif (New York), light weights** — all meaning: counters, whispers, names,
  fortunes. Italic for the game's voice (fortunes, whispers).
- **Sans (SF), 9–13 pt, tracked caps** — only for micro-labels, and fewer of
  them every release.
- Type is lit, not printed: whispers at 70–85% opacity idle, never full — and
  never below the 40% play-time floor (§6).
- **Dynamic Type everywhere it means something:** all functional and reading
  text — whispers, journal body, fortunes, settings rows, cards — scales
  through the **AX sizes** (up to AX5). Reflow rules: text wraps, surfaces
  grow, nothing ever truncates or overlaps an orb's hit region; whispers that
  would wrap past two lines swap to their canonical short forms (07). The
  field's counter scales on its own **named ramp** — 21 → 27 → 34 pt across
  the standard/large/AX bands — independent of field zoom, so the field never
  reflows under the player's hands.

## 6. Chrome: the disappearing act

The end state is **zero chrome**: no bars, no buttons, no icons (banned in
navigation per 04). Wayfinding is typographic whispers; controls are gestures
and world-objects (a star, a page, a lamp). Any control that must exist renders
as a *thing in the world* — the test: could it appear in a screenshot without
looking like UI?

Zero chrome is only honest if it stays legible. The floors:

- **Whispers dim, never vanish.** During play the wayfinding whispers dim to a
  committed floor of **40% opacity** — never to zero. The dark-room test is the
  doc's own bar; an invisible exit fails it. With VoiceOver, Switch Control, or
  any assistive technology running, whispers **do not fade at all**.
- **Hit regions ≥ 44 pt, always invisible, always larger than the visual.**
  The lamp keeps its 24 pt visual with a ≥ 44 pt hit footprint; the same rule
  applies to page corners, stars, and whispers.
- **The top-edge sky whisper vs the bottom-60% rule (04 §5):** resolved. The
  bottom-60% rule governs *primary actions*; the primary way to the sky is the
  anywhere-swipe, which is fully one-handed. The `✦ the sky` whisper at the top
  edge is wayfinding whose tap is an auxiliary path, and under VoiceOver the
  sky is reachable from anywhere in the element tree (§6.2) — reachability
  never depends on the top-edge tap.

### 6.1 The interactive-object grammar

One rule distinguishes a control from scenery, everywhere in the world:

> **breathing = touchable · static = scenery**

Everything interactive carries the ≥ 2 s light breath (whispers, the lamp, page
corners, stars, the done card's `again?`). Nothing decorative ever breathes.
No exceptions, no third state — the grammar only works if it is absolute.

**Validation:** a 5-user no-prompt find test at the Phase 0 gate — five fresh
players are handed the field and observed until they find the sky, the journal,
and the quiet things, with no prompting. The grammar passes only if all five
find all three unaided; a hint given is a fail, and the grammar (not the
player) gets revised.

### 6.2 The accessibility contract (the non-visual world)

Zero chrome must be zero *visual* chrome only. The world exposes a complete
non-visual counterpart, built in Phase 0 with the navigation, not after it:

- **Destinations are permanent.** `the sky`, `your journal`, and every
  world-object control live in the accessibility tree **at all times**,
  regardless of visual fade state. What the eye loses to the dim, the screen
  reader never does.
- **Every world-object control is an accessibility element** with a lowercase
  label in the game's voice (`the lamp`, `your journal`, `begin this field
  again`), the button trait, and its ≥ 44 pt invisible hit region.
- **VoiceOver flows exist for W1–W6** (04 §3): each wireflow has a specified
  traversal — headings per place, reading order, and what is announced at each
  beat. Custom actions on the field element carry navigation (`go to the sky`,
  `open your journal`, `begin this field again`), and the two-finger-Z escape
  always returns to the field from anywhere.
- **VoiceOver play is specified, not incidental:** orbs are individually
  focusable and pop on double-tap with full sound + haptic payoff; chain pops
  are announced as one grouped, calm summary (`three more let go`), never a
  flood; fortune and done cards are announced on arrival and dismissible by
  escape.
- **Audio session under VoiceOver — decided:** the session stays **mixable**,
  so VoiceOver speech is never ducked or interrupted by the game; pop
  confirmation under VO is carried by the haptic plus the pop tone, with VO
  announcements reserved for cards, fortunes, and place changes.
- **The QA bar:** an eyes-closed VoiceOver round trip — field → sky → choose a
  star → field → journal → quiet things → field, plus a full clear — performed
  with the screen curtain on, is part of the §10 checklist and the Phase 0
  exit criteria (08).

## 7. Motion principles

1. Everything eases; nothing snaps. World moves are **finger-attached**; the
   300–650 ms band applies **only to the settle after release** (80–140 ms for
   feedback).
2. Motion always has a source in the world (camera drift, mote flow) — no
   "panel slides" or "modal zooms".
3. The frame factor discipline (dt-clamped, 120 Hz-ready) applies to UI motion
   as much as sim motion.
4. Every move is interruptible; a new touch always catches the camera.
5. Reduce Motion is a first-class rendition of the game, not a degraded one —
   the full policy is §7.3.

### 7.1 The camera in the hand (committed values)

The transit feel is specified here, not left to engineering:

- **Finger-tracked 1:1** during the drag — the world moves exactly with the
  thumb.
- **On release,** the camera settles at release velocity, eased, within the
  300–650 ms band; a slow release settles short, a flick carries through.
- **The camera never moves unasked.** The only autonomous camera motion in the
  game is the idle field's ambient micro-drift (≤ 2 pt amplitude); every
  transit is initiated by the player's finger or its released momentum.
- **Transit input policy:** during a settle, taps do not reach the sim; any
  touch catches the camera where it is.
- **The sim pauses off-field:** when the camera has left the field, orbs hold
  and no chains resolve unseen. The field is exactly as she left it when she
  drifts back.

### 7.2 Holds and the reset (the confirm treatment)

- **One long-press meaning on things: `hold to keep`.** Pressing and holding a
  fortune or a keepsake keeps it; a one-time discovery whisper teaches it the
  first time a keepable thing appears, and it is never taught again.
- **The reset** is the only long-press on *nothing*: it arms **only on empty
  space** — a press that lands on an orb always just pops the orb. On arm, the
  field dims to `confirm.dim` and the remaining orbs gather gently toward
  center under the whisper `begin this field again?`. A **single tap** on the
  whisper confirms — never a second timed hold. Any other touch releases the
  dim and nothing is lost. `begin again` also exists as a plain row on the
  journal's last page and as a VoiceOver custom action (§6.2), so no one needs
  the gesture.

### 7.3 Reduce Motion: the matrix

**Standing rule: no animation ships without a defined reduced variant.** A new
motion without a row here fails the §10 review. **Parity means:** every
destination reachable, every state readable, and no information carried by
motion alone.

| named motion | full | under Reduce Motion |
|---|---|---|
| camera transit (field ↔ sky ↔ journal) | finger-tracked drift, parallax streaks | instant crossfade between places |
| idle camera micro-drift | ≤ 2 pt slow drift | static frame |
| parallax mote layers | 2-layer drift | motes still *(shipped v1.2 behavior, retained)* |
| mote assembly (arrival, W2) | ~1.5 s gather | field fades in assembled, ~400 ms |
| star descent (onboarding, W1) | star drifts down into view | star fades in in place; `the sky noticed.` unchanged |
| journal page-turn glow | pressed lights sweep alight on turn | pages crossfade; glow appears without sweep |
| evening tint | continuous hue drift with the hour | stepped: set once at arrival, no live drift |
| shockwave ring | expanding ring | radial fade in place; particles halved *(shipped, retained)* |
| breathing whispers | ≥ 2 s opacity breath | held steady at idle opacity (70–85%) — grammar carried by §6.2's tree instead |
| done-card drift-in | drifts in like a note | fades in in place |
| reset dim-and-gather | orbs gather toward center | dim only; orbs hold position |

- **World-move sounds always play under Reduce Motion,** retimed to the
  crossfade — when motion is removed they are the orientation cue, so the
  arrival/departure sounds (06) are never stripped by RM. A separate
  all-users *transition sounds* toggle lives beside sound and haptics in the
  quiet things; suppression is only ever the player's explicit choice, never a
  side effect of an accessibility setting.
- This matrix subsumes and extends the shipped RM behavior (fewer particles,
  static motes) — those remain as rows, not as the whole policy.
- **The RM path is tested first-class:** the motion-screened panelists on the
  recruited playtest panel (08) run the full RM rendition through every gate
  the default rendition passes.

## 8. Per-place art specs

- **Field:** as shipped (halo/body/highlight orbs, motes) + evening light.
- **Sky:** stars = stone circles at 60% field-orb scale with the family paints
  as tiny gems; constellation roads = **≥ 1.5–2 pt** soft-edged light at
  `road.line` (20–25%) — verified on an OLED device at minimum brightness, per
  §2.2. Depth via 2 parallax mote layers. Cleared stars sink slightly and dim —
  settled, not spent. **Families read without color:** each family's gems carry
  a small shape signature (facet count / notch in the gem silhouette), so the
  sky still sorts itself in grayscale.
- **Journal:** deep-dusk paper (`journal.paper`), serif-led layout, pops as
  "pressed lights" (soft-edged discs that glow faintly on page-turn), keepsakes
  as embossed emblems. The lamp: a 24 pt warm ellipse whose light pools softly,
  with a ≥ 44 pt hit footprint.

## 9. App-facing assets

Icon: a single lit orb on the dusk gradient (exists; keep). Screenshots: the
5-scene narrative (exists) re-shot after One World ships. App Preview video:
30 s cut per demo/DEMO_SCRIPT.md with the new camera drift as the hero move.

## 10. Review checklist for any new art

□ Lives inside the dusk (no new hues; colors resolve through the §2.1 tokens)
□ Breathes, doesn't blink — and breathes *only if touchable* (§6.1)
□ Softer than it needs to be
□ Meets the APCA floors at final composited opacity (§2.2), at minimum
brightness on OLED — and survives the sunny train
□ Still reads in grayscale
□ Has a defined Reduce Motion variant (§7.3) and stays inside the luminance
budget (§3)
□ Passes the eyes-closed VoiceOver round trip if it touches navigation (§6.2)
□ Would look natural in a player's screenshot
□ Makes the pop look *better*, not smaller.
