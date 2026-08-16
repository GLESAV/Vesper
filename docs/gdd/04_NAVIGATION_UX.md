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
        keepsakes, the lamp, and — on its
        last page — the quiet things: settings)
```

- **One gesture:** swipe up anywhere → the camera drifts up into the Sky.
  Swipe down → down into the Journal. Swipe back → the Field. The three places
  are physically continuous — motes and background parallax carry through; you
  can *see* the lowest stars from the field's edge and the journal's ribbon at
  its foot.
- **Words as wayfinding:** at the field's top edge, a faint serif whisper —
  `✦ the sky` — and at the bottom — `your journal`. They breathe in when the
  field is idle, fade fully during play, and are tappable for the gesture-averse.
  No icons anywhere in the world. **Icons are banned from navigation.**
- **The Sky is the Path, literally:** stones become stars; roads become faint
  constellation lines; the current stone glows nearest the field. Choosing a
  star drifts the camera back down and the field seeds from it — the map and the
  game share one space, so "which level am I on" is answered by *looking up*.
- **The Journal is everything she owns:** left page — the evening's numbers and
  the lamp; turnable pages — the collection (pops as pressed lights, per-family),
  fortunes she's found (re-readable!), keepsakes. The **last page** holds the
  quiet things: sound, haptics, whispers, about. Settings inside the journal —
  because in this world even preferences are personal effects, not machinery.
- **Start over** is a long-press on the field → the whisper `begin this field
  again?` → press-and-hold to confirm. Deliberate, discoverable, never looming.
- **Interruption-proof:** every place fully resumable; app always reopens on the
  Field (P1), with the camera exactly where the field is.

### Why this is the AAA answer

Monument Valley, Alto's, Journey, Sky: the hallmark of premium calm games is that
**the world absorbs the UI**. Sheets and toolbars are the tell of an MVP. One
World keeps P1 (cold-launch lands *in play*), fixes discoverability (both core
surfaces are visibly adjacent to the field at all times), removes all modal
state, and gives the game its "wow, this is one place" moment — the thing
reviewers and players screenshot.

## 3. Wireflows (described; UI sketches to be produced from these)

**W1 — First launch (the first 60 seconds):**
5 orbs only, no labels, no counter. Whisper: `tap an orb. let it go.` → first
pop (full sensory payoff) → silence, no more copy → player clears the 5 →
chime + `that's it. that's the whole idea.` → the counter fades in; the sky
whisper appears; one star descends into view above the field → `the sky
noticed.` End of onboarding. (No tutorial screens, no coach marks, ever.)

**W2 — Daily arrival:** open → motes assemble the field (~1.5 s, skippable by
tapping) → evening-light hue per local time → play.

**W3 — Going to the sky:** swipe up → camera drifts (600 ms, eased, particles
streak subtly) → stars/roads → tap a star → drift back down, field re-seeds
from that stone's pops → whisper names the stone (`ember · clover`).

**W4 — Visiting the journal:** swipe down → journal opens on the evening page
(lamp lights if first visit today) → swipe through pages → last page: quiet
things → swipe up to return.

**W5 — Field clear:** last pop → 650 ms of afterglow → chime + done card
*in-world* (it drifts in like a note, not a modal) → card shows: count set
free, +points, lifetime line → `again?` (tap) or just leave — swiping away is a
valid, unpunished exit.

**W6 — Interruption:** app backgrounds mid-cascade → on return, one clamped
frame, field exactly as left, no summary popups.

## 4. Copy system (with 07)

All navigation copy is lowercase serif whispers. Canonical strings:
`the sky` · `your journal` · `set free` (counter label) · `tap an orb. let it
go.` · `again?` · `begin this field again?` · `the road behind folded itself
away.` · `the sky noticed.`

## 5. Reachability & ergonomics

- All interactive targets ≥ 44 pt; primary actions in the bottom 60% of screen.
- The swipe gestures work from anywhere, not from edges (one-handed, in bed).
- Full VoiceOver traversal per place; places announced as headings ("the sky,
  the path of stones"). Reduce Motion: camera cuts crossfade instead of drift.
- Left/right-handedness irrelevant by design (no corner-anchored controls).

## 6. What gets deleted

The four-icon top bar · all `.sheet` presentations · the standalone settings
screen · the permanent reset button · the word DETONATED. The pop engine,
points, unlock, and map *systems* are untouched — this is a surface rebuild
(see 08 for phasing: it is Phase 0, before any new features).
