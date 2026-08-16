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
  always dark-room-comfortable at minimum brightness.
- **The pastel band:** all content color lives in the established muted band
  (~150–245/channel, low saturation). The 100-pop family palettes (PopCatalog)
  are the color system — UI never introduces hues the catalog doesn't own.
- **Forbidden:** saturated primaries, pure white (#FFF caps at 96%), pure black,
  red of any kind (alarm register), and any color used as a warning.

## 3. Light is the material

Everything luminous renders additively (the plusLighter discipline already in
the renderer). Rules:
- Glow is earned by importance: orbs > stars > text whispers > chrome (chrome
  ideally has none — see §6).
- Nothing blinks. Light *breathes* (≥ 2 s cycles) or *drifts*.
- The brightest moment in the game is, and must remain, **the pop**.

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
- Type is lit, not printed: whispers at 70–85% opacity, never full.
- Dynamic Type respected in the Journal (reading surface); the field's counter
  scales independently.

## 6. Chrome: the disappearing act

The end state is **zero chrome**: no bars, no buttons, no icons (banned in
navigation per 04). Wayfinding is typographic whispers; controls are gestures
and world-objects (a star, a page, a lamp). Any control that must exist renders
as a *thing in the world* — the test: could it appear in a screenshot without
looking like UI?

## 7. Motion principles

1. Everything eases; nothing snaps (300–650 ms for world moves; 80–140 ms for feedback).
2. Motion always has a source in the world (camera drift, mote flow) — no
   "panel slides" or "modal zooms".
3. The frame factor discipline (dt-clamped, 120 Hz-ready) applies to UI motion
   as much as sim motion.
4. Reduce Motion: crossfades replace drifts; particles halve; motes still. Full
   parity of function, always.

## 8. Per-place art specs

- **Field:** as shipped (halo/body/highlight orbs, motes) + evening light.
- **Sky:** stars = stone circles at 60% field-orb scale with the family paints
  as tiny gems; constellation roads = 1 px dashed light at 12% white; depth via
  2 parallax mote layers. Cleared stars sink slightly and dim — settled, not
  spent.
- **Journal:** deep-dusk paper (#181622 warmed 3%), serif-led layout, pops as
  "pressed lights" (soft-edged discs that glow faintly on page-turn), keepsakes
  as embossed emblems. The lamp: a 24 pt warm ellipse whose light pools softly.

## 9. App-facing assets

Icon: a single lit orb on the dusk gradient (exists; keep). Screenshots: the
5-scene narrative (exists) re-shot after One World ships. App Preview video:
30 s cut per demo/DEMO_SCRIPT.md with the new camera drift as the hero move.

## 10. Review checklist for any new art

□ Lives inside the dusk (no new hues) □ Breathes, doesn't blink □ Softer than
it needs to be □ Reads at minimum brightness in the dark □ Would look natural
in a player's screenshot □ Makes the pop look *better*, not smaller.
