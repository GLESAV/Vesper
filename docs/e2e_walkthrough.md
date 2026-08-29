# Vesper — definitive e2e walkthrough

A device pass over everything that shipped since v1.2: One World navigation,
the sky scroll, weather, balloon animals, field mechanics, fireworks, the
journal, and the quality fixes from the swarm review. Every claim below was
verified against the code at the commit this file landed in; file references
are in `docs/` history and the PR description if something reads wrong.

**Build to test:** this branch (or `main` after it merges). The sky scroll
(§6) and several fixes (§13) exist only from this branch onward.

**Device suggestions:** one ProMotion iPhone (120 Hz — §13 has fixes specific
to it), one iPad if available (no haptics — sound must carry the pop alone).

**Resetting:** there is no in-app reset (the debug reset has no UI). Delete
and reinstall to start fresh. A fresh install is worth testing first — several
features only appear with lifetime progress (noted per item as *needs: …*).

Progress gates, so you can plan the session: **stage = fields cleared ÷ 3**
(capped 6). Splitters at stage 2, drifters 3, generators 4, deeper splits 5,
two generators 6. Fireworks on alternating stones from stage 2; balloon
animals on the *other* alternating stones from stage 3. Weather from field 1.

---

## 1. First launch and the core loop

- [ ] App opens **straight into the field** — no menu, no onboarding. Status
      bar hidden, dark background, soft glowing orbs drifting.
- [ ] Foot of the screen: "tap an orb. let it go." — disappears after the
      first pop, never returns.
- [ ] Tap an orb: it pops with a particle burst, a ring, a soft synthesized
      tone (deeper for bigger orbs), a haptic scaled to orb size. The counter
      at the top pulses and increments. Counter reads "N orbs set free" to
      VoiceOver.
- [ ] Pops land on touch-DOWN, not release — resting a finger then sliding
      does not un-pop.
- [ ] A directly tapped pop's ring can **chain**: orbs caught in the expanding
      shell pop a beat later, echoes are slightly quieter/lighter. Only the
      tapped pop's first ring chains — echo rings are visual.
- [ ] Pop 3+ within ~a second (chain or fast fingers): a "chain of N" whisper
      appears in the HUD slot for ~1.4 s.
- [ ] "+N" point whispers drift up from pops (if the setting is on). There is
      **no running points total on the field** — that is deliberate.
- [ ] Exactly **one fortune orb per field** (never on a splitter/generator/
      animal): popping it releases an unbordered sentence that fades in,
      drifts, and leaves by itself (~5.5 s). +50 points. With VoiceOver or
      Switch Control running it stays until replaced.
- [ ] Clear the field: ~0.65 s later a completion chime, a success haptic,
      and the done card — "the field is quiet now.", an original verse
      (verses do not repeat until the deck is exhausted), "N set free",
      "+P pop points", a lifetime line, and an "again?" button.
- [ ] The done card has no scrim — the world stays live behind it; swiping
      up/down is a valid way to leave it.
- [ ] "again?" reseeds the same stone. **Replaying a cleared stone doubles
      the field the second time, triples from the third** — expected, not a
      bug.

## 2. Quiet (the battery test)

- [ ] Clear a field and let effects fade, then leave the phone alone: the
      render loop pauses (no way to see this directly; the phone should not
      warm and the battery should not drain sitting on a cleared field).
- [ ] **Fixed this PR:** clear a *display* field (one with fireworks) while
      leaving shells untouched — the shells fade away with the field and the
      pause still engages. Previously they sat there and kept the clock
      running forever.
- [ ] **Fixed this PR:** clear a snowy/rainy/foggy field — the weather fades
      out (~2 s) after the clear instead of freezing mid-fall under the done
      card.

## 3. One World navigation

The world is one vertical axis: **sky above, field, journal below**. Adjacent
places sit 0.75 screens apart, so the neighbours already peek at the edges.

- [ ] Whispers name the ways: "the sky" at the top of the field, "your
      journal" at the foot; from the sky only "the field"; from the journal
      only "the field". Tapping a whisper travels. They dim (never vanish)
      while the field is in play and breathe when idle.
- [ ] Direction, so you can tell a bug from the design: a finger moving UP
      the screen travels UP the axis, to the sky; a finger moving down goes
      to the journal. (`WorldCamera`'s sign convention: an upward finger makes
      a negative translation, which is a negative offset, which is the sky.)
- [ ] Swipe up/down: the world tracks your finger 1:1. A release commits only
      with **both** real distance (~11% of screen) **and** real velocity —
      a slow drift or a short flick springs home instead.
- [ ] The top/bottom ~10% of the screen never *commit* a swipe — Control
      Center and Home always win. (A swipe that starts mid-screen and ends in
      the edge still commits.)
- [ ] Touch the glass mid-travel: you **catch** the world where it is, with
      no slop; release undecided and it settles to the nearest place.
- [ ] Flick up from the sky (or down from the journal): no bounce — a soft
      glow acknowledges the end of the axis, dimmer on each repeat.
- [ ] Travel cues: the scene dims ~5% mid-trip; dust motes lag the field;
      the ground crossfades (field charcoal / sky blue-black / journal warm
      brown-black); a horizon glow lives in the permanent sky/field overlap.
- [ ] Rotate the device / Split View mid-rest: the world re-lays out without
      travelling anywhere.
- [ ] **Fixed this PR:** rest one thumb on empty sky and tap a star with
      another finger — the star responds (previously the resting thumb
      silently disabled every control and dimmed the world).

## 4. The sky — The Path

- [ ] Your real stones drawn as a constellation: stars carry small
      family-shaped gems (disc/triangle/diamond/… per family). The anchor
      star (where you stand) has a brighter rim.
- [ ] Cleared stars carry a **closed ring** just outside the stone — never a
      checkmark.
- [ ] Roads: walked = solid, unwalked = dashed; onward roads brighter;
      3-day-old roads settle dimmer but **never disappear** (see §11).
- [ ] Tap any star (44 pt target): the field reseeds from that stone and the
      world carries you back down.
- [ ] Clearing a stone's field opens 1 road (~45%), a fork (~45%), or a
      three-way (~10%). Replays open nothing new. Each child stone leans a
      family — a fork should read as "the ember road vs the tide road".
- [ ] ~35% of stones host a **visitor** — a pop you have not unlocked,
      playable on that stone only.
- [ ] After clearing: HUD note "the path continues" / "the path forks — N
      roads ahead".

## 5. Auto-onward

- [ ] Clear a field and touch nothing: after ~3.4 s the world rises to the
      sky by itself. If exactly one road leads on, ~2.2 s later it steps onto
      the next stone and carries you down to a fresh field. A fork halts in
      the sky with the roads lit, waiting for your choice.
- [ ] Any touch during the sequence cancels it for that field.

## 6. The sky scroll — NEW, exists only from this branch

*Needs: a map taller than one screen (≳6 generations of stones).*

- [ ] At the sky, drag **down**: the constellation itself slides down,
      revealing older generations above. The world does not travel and does
      not dim while the sky still has history to give.
- [ ] One unbroken drag: walk back up the path, run out of history, and the
      **same finger-stroke** carries you toward the field — the leftover
      after the history runs out is what counts toward the travel gates.
- [ ] Scrolling never *accidentally* exits the sky: a drag the history fully
      absorbed commits nothing on release, however far the finger travelled.
- [ ] Release with speed: the constellation **glides** briefly (≤ ~0.45 s)
      and eases to rest — the drawn stars and their tap targets move
      together (previously the drawing snapped while invisible targets kept
      gliding).
- [ ] Catch a glide mid-flight: the constellation freezes under your finger
      exactly where it is — no leap.
- [ ] Scrollback is capped (~20 generations); arriving at the sky always
      opens at the growing tip.
- [ ] Tap a star while scrolled back: it works — the field seeds from it.

## 7. Weather

*From the very first field. Deterministic per stone — revisiting a stone
replays its air.* Odds: clear 44 / rain 16 / warm 12 / snow 10 / fog 10 /
storm 8. Weather **never changes hittability** — orbs stay catchable.

- [ ] **rain** — two travelling wave crests visibly *carry* the orbs, a foam
      line rides over the pops, splash droplets where crests meet orbs.
- [ ] **snow** — 72 flakes fall, settle at the bottom, rest a few seconds,
      melt and fall again; orbs move grippy, in stepped little jerks.
- [ ] **warm** — three leaning light shafts; the whole field breathes
      sideways together; specular pin-lights on orbs inside the shafts.
- [ ] **storm** — four visible turning eddies; gusts arrive over ~2 s with
      long faint streaks and real lulls; orbs wander in direction only.
- [ ] **fog** — seven banks drawn *in front of* the field, slow thick
      motion — and **the fog thins around your finger** (a real hole you can
      push through the banks).
- [ ] A waiting firework's rope fuse sways in weather.
- [ ] Reduce Motion on: weather is nearly still and never carries orbs.

## 8. Balloon animals

*Needs: stage ≥ 3 (9 fields cleared). Appears on the fields that do NOT have
fireworks; one per field; the same stone always spawns the same creature.*

- [ ] One of 8 balloon silhouettes (cat, bird, fish, rabbit, fox, bear,
      deer, frog) in the pop's own paint, facing the way it drifts.
- [ ] **Shy phase (~25 s):** keeps a band off the walls, eases away from a
      finger inside ~120 pt — but never evades inside ~38 pt, and its cruise
      is far slower than a thumb: following it always catches it. Shyness
      only decays; then it drifts like a plain orb.
- [ ] Takes 2–3 taps. A non-final tap lands *visibly*: a soft high startle
      note, a light haptic, and a short dart (~26 pt — shorter than its own
      tap radius, so tapping the same spot again still lands).
- [ ] The final pop: bigger burst, bigger ring, **×2.5 points**.
- [ ] VoiceOver names it in the field label ("…and a balloon fox, keeping to
      the edges" / "out in the open").

## 9. Field mechanics by stage

- [ ] **Splitter** (stage ≥ 2) — faint inner ring, "the doll inside the
      doll". Popping releases 2 smaller children of the same family, thrown
      apart with a higher chirp. The field never ends on the splitter itself.
- [ ] **Drifter** (stage ≥ 3) — soft halo just outside the body. Eases away
      inside ~96 pt, gives up inside ~38 pt, settles when cornered.
      **Fixed this PR:** it settles against a bottom band instead of
      jittering against it.
- [ ] **Generator** (stage ≥ 4) — ~18% larger, two slow breathing rings.
      Emits a smaller orb every 2–3 s. Three closing rules mixed per field:
      *taps* (each press gives an orb + chirp; the 3rd–5th press pops it),
      *quota* (spent after 3–6, closes silently), *settles* (closes by
      itself after 15–25 s). Ambient emissions are deliberately silent.
      **Fixed this PR:** on a very crowded field a press always still yields
      its orb — no press is ever silently swallowed.
- [ ] **Depth/reserve** — at most ~14 orbs on the surface; the rest wait
      small and faint below and rise (~1 s) where you just made room.
- [ ] Everything above compounds: a stage-6 replay field is busy but must
      always be finishable, and the orb count never exceeds ~96 total.

## 10. Fireworks

*Needs: stage ≥ 2, on alternating stones (never sharing a field with an
animal). 2–6 shells. Entirely optional — never gates the clear.*

- [ ] A waiting shell: small tapered body, lit tip, **hanging rope fuse**
      with real physics. Tapping the shell **or anywhere on its cord**
      lights it: fuse tick + tiny haptic, a spark climbs the cord.
- [ ] Tapping a burning fuse **hurries it** (~22% per tap).
- [ ] Launch: a soft "thoomf" + whirr + swelling haptic; ~1 s climb with a
      kind-specific wobble; then the break — soft bloom, ripple haptic, one
      of 14 patterns, stacking smoke that thins slowly, a gentle shove to
      nearby orbs, and **3 orbs rise from the reserve** at the break point
      (never new orbs — a display never lengthens the field).
- [ ] An unlit shell simply sits there; the field clears around it. (Its
      post-clear fade is §2.)
- [ ] Reduce Motion: **fixed this PR** — the shell climbs straight (no
      wobble/zigzag) and the break's shove is damped.

## 11. The journal

Swipe DOWN from the field (the journal sits below), or tap "your journal".
Three pages, turned by the
serif ribbon at the foot (or edge taps; VoiceOver: custom actions). Pages
never turn by swipe. Leaving resets to page one.

- [ ] **the evening** — `hush` (one tap silences sound+haptics together,
      row becomes "it is quiet"; tap restores), pop points headline, records
      (set free / fields / fortunes / best chain).
- [ ] **the collection** — "N of 100"; the `drift` row (clears the featured
      pop, leaves the Path, returns to the field); the 100-cell grid.
      Unlocked cell: swatch + name; tap **features** that pop and returns to
      a field painted with it. Locked cell: dim disc + "· · ·"; tap pins a
      kind hint at the foot ("Gloaming · arrives at 100 pop points").
      Secrets (#50, #80, #100) show "?" and hide their names.
- [ ] **the quiet things** — hush again; sound / haptics / point whispers
      toggles; "begin this field again" (arm → confirm, "not now" backs
      out); "Vesper · made by Kate Wu · collects nothing".
- [ ] Early unlock ladder to spot-check: #2 Gloaming at 100 points,
      #3 Eventide 250, #4 Halflight 150 pops, #6 Duskfall 3 fortunes,
      #8 Violet Hush 5 fields, #10 Last Light chain of 4. The unlock
      capsule ("✦ new pop · …") shows in the HUD slot; new pops join from
      the *next* field.

## 12. The 3-day settling (multi-day check)

- [ ] Play a stone, then advance the device clock +4 days and reopen: the
      road behind is a thin, dim, solid line; the stone is dimmer and sits
      2 pt lower; **nothing is missing and the settled stone is still
      tappable**. Set the clock back: it un-settles. Nothing is ever
      deleted.
- [ ] **Fixed this PR (unobservable but worth knowing):** if the saved map
      ever fails to read (corruption), the app no longer silently starts a
      fresh Path over it — the unreadable bytes are kept aside for recovery.

## 13. Accessibility & devices

- [ ] **Reduce Motion (flip it mid-session — everything reacts live):**
      camera stops translating (places crossfade), particles halve, motes
      freeze, weather nearly still and never carries, animals dart gently,
      sky stars fully lit and still, journal pages cut instead of turning,
      firework rise straight + shove damped, counter pulse still.
- [ ] **VoiceOver:** the field is one direct-touch region ("touch the orbs
      directly to let them go") — touches pass through and pop on touch-down.
      Arrivals are announced on arrival. Sky stars are labelled buttons
      (newest first) with "you are here"/"walked"/"not yet walked";
      two-finger scrub escapes sky and journal to the field. Fortunes never
      auto-dismiss; whispers never dim.
- [ ] **Dynamic Type:** journal reflows at accessibility sizes; whisper
      targets keep a 44 pt floor.
- [ ] **iPad:** no haptics — sound alone must carry the pop. Split View:
      very short windows show a "not playable" guard rather than a broken
      field.
- [ ] **ProMotion (120 Hz), fixed this PR:** storm wander, snow crunch,
      fuse-spark rate and the rope's stiffness now match a 60 Hz device.
      Fireworks and weather should *feel* the same on both phones.

## 14. What you should NOT find

- No timers, scores-to-beat, lives, fail states, ads, IAP, rating prompts,
  notifications, accounts.
- No network use of any kind (verify: Settings → Cellular shows zero data).
- Nothing Anima-shaped on device — the animation engine ships in the binary
  but nothing in gameplay draws from it yet. Its output is the browser
  gallery (`tools/anima-studio`), not the phone.
- No in-app reset; no long-press gestures; weather is never named in UI.

## 15. Known rough edges (accepted, not bugs)

- The classic v1.2 navigation code still exists behind a compile flag and is
  unreachable in the shipping build.
- A very crowded sky row can leave an individual star's exclusive tap patch
  narrower than 44 pt (topmost wins; documented trade-off).
- The sky's deep-space backdrop redraws more often than it needs to while
  scrolling (a caching optimization was deliberately deferred).
- Two authored firework behaviors (`splits`, `twinkles` on crossette/strobe)
  are catalogued but not yet implemented — those two break like their base
  patterns.
- Audio: very large chains can in principle sum toward clipping (no
  limiter yet); the two detuned variants of each pop render nearly
  identically (pentatonic snapping happens after detune); split/emit/startle
  sounds clamp to the top pitch bucket. All noted for a future tuning pass —
  tuning is sacred and none of these were changed blind.
