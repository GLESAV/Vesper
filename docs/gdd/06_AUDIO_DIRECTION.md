# Vesper — Audio Direction

*The pop is half sound. The mix is designed for headphones at 1 a.m., for a
phone speaker on a nightstand, and for total silence on a train — with her own
playlist playing over all of it.*

## 1. Principles

1. **ASMR bar:** every sound must be pleasant at the 500th repetition. Soft
   attacks, exponential decays, micro-variation per instance (the engine already
   detunes ±12 Hz — keep and extend). The 500th-repetition judgment is made by
   real end-of-day players outside the dev team, not by the person who wrote
   the synth.
2. **Visual is the backbone; every event lands twice.** The visual channel is
   the one channel present on every device in every mode, so visual parity is
   the guaranteed baseline. On top of it, every meaningful event must land in
   at least two channels (visual + sound, visual + haptic, or all three), so
   that any single channel can be absent without the game going numb. Nothing
   in the game references audio a muted player can't perceive.
3. **Her music wins:** `.ambient` session, mixWithOthers, forever. Vesper never
   ducks or interrupts a podcast or playlist, and it honors the silent switch.
4. **Nothing startles:** no sound exceeds the pop's peak; no sound arrives
   without a player action except the (optional) room tone.
5. **Instant quiet:** sound and haptic controls (and the room-tone toggle) live
   one gesture from the field; a player can silence the game in under 5
   seconds, one-handed, on the first attempt. This is a Phase 0 exit test, not
   a settings-screen nicety.

## 2. The sound palette

- **Pops (exists):** synthesized sine sweeps per family profile (freq, spread,
  sweep, duration, decay, brightness). The family voices are the melody of the
  game — Tide deep and round, Frost bright and glassy, Chime long and belled.
  v2 additions: a third harmonic option for `secret` pops; on-device
  audio-haptic alignment audit per the route policy in §4.
- **The chime (exists):** C5–E5–G5 completion arpeggio. v2: 4 gentle voicings
  rotated by field, so consecutive clears never repeat exactly.
- **World moves (new):** camera drift to Sky = a rising airy shimmer (filtered
  noise, 500 ms); to Journal = a soft page-weight sound. Both derived from the
  pop synth (same DNA). Under Reduce Motion these sounds **always play** —
  retimed to the reduced transition, never removed — because when motion is
  gone they are the primary orientation cue that a move happened. A separate
  all-users "transition sounds" toggle lives in the same surface as sound and
  haptics, so suppression is the player's explicit choice, never the default.
- **Journal (new):** page turns as filtered paper noise; the lamp lighting = a
  single warm sine blip; keepsake reveal = a two-note kindness.
- **Room tone (new, optional, off by default):** an almost-silent dusk pad for
  the bedside sessions. Full lifecycle spec:
  - Seamless: either a loop ≥ 60 s with no audible seam, or fully procedural
    (slow filtered noise + faint detuned drone) so there is no seam to hide.
  - Enters and exits with 2–4 s fades; never a hard start or stop.
  - Auto-suppresses whenever other audio is playing on the device — her
    playlist is never asked to share the room.
  - Offered once, in fiction, at a natural quiet moment; thereafter it is the
    "quiet room" toggle surfaced alongside sound and haptics (see Principle 5),
    never buried.

## 3. Cascade voicing

The chain cascade is the signature audio moment and is specified, not left to
limiter behavior:

- **Polyphony:** maximum 6 simultaneous pop voices; when a 7th pop arrives, the
  oldest voice is stolen with a 10 ms fade — never a click, never a mute of the
  newest pop.
- **Per-voice gain curve:** each successive voice in a chain enters slightly
  quieter than the last (defined curve, tuned on device), so a 15-orb cascade
  swells and settles instead of stacking to a wall.
- **Chain pitch contour:** each family defines a per-chain pitch contour (e.g.
  Tide steps gently downward, Chime climbs) so a cascade is a phrase in that
  family's voice, not the same note repeated.
- **Acceptance test:** a scripted 15-orb chain, A/B'd against the naive
  all-voices-full mix, must be preferred by listeners and must stay within the
  calibrated ceiling below on both speaker and headphones.

## 4. Mixing rules

The mix is calibrated in absolute terms — no "-ish" values:

- **Anchor:** the pop transient peaks at **-6 dBFS**. Everything else is set
  relative to it: chime -4 dB below anchor; whisper/world sounds -14 to -20 dB
  below; room tone -30 dB below.
- **Ceiling:** master true peak never exceeds **-1 dBTP**, including the worst
  case (max cascade + chime + room tone) at max device volume. Soft limiting
  shapes the cascade only within the voicing rules of §3.
- **Spectral survivability:** every family voice carries enough harmonic
  content to survive an iPhone micro-speaker; each family's identity is
  distinguishable from the others below 2 kHz; the mix is mono-safe; the
  families remain blind-distinguishable at 50% device volume on the built-in
  speaker.
- All synthesis stays procedural (no assets) — the zero-dependency,
  tiny-binary promise is part of the product.
- The calibration pass (metering, device measurement, A/B listening) is a
  specialist workstream; it may be contracted out rather than done solo, but
  the spec above is the acceptance contract either way.

**Route-aware sync policy:** on wired headphones and the built-in speaker,
audio and haptic stay fused — alignment bound ≤ 10 ms, audited on device. On
Bluetooth routes, latency makes fusion impossible; the haptic is authoritative
and fires immediately as the tap confirmation, and the audio is accepted late.
The pop under the finger never lags to chase a wireless codec.

## 5. Haptics (the silent mix)

Grammar (exists, keep): soft impact per pop scaled by size; chained pops
echo lighter; success on clear. v2 additions: a barely-there tick when the
camera settles in a place; the lamp lighting = one warm tap. Never more than
one haptic meaning per pattern.

**Muted-with-her-own-music is a named primary listening mode**, not an edge
case — for a large share of real sessions the player's playlist replaces the
game's audio entirely. In this mode, richer haptic phrasing carries the feel
on iPhone: chain cascades get a distinct haptic contour (echoing the pitch
contour of §3), the completion moment gets its own success phrase, and world
moves keep their settle-tick. This is a funded iPhone enhancement layered on
the guaranteed visual backbone (Principle 2), because iPad has no Taptic
Engine — haptics can enrich a mode but can never be the parity floor.

**Event-feedback matrix:** every game event (pop, chain link, clear, fortune,
world move, lamp, keepsake) is listed against its visual, audio, and haptic
expression; every row must have at least two filled cells, and the visual cell
is never empty. The iPad sound-off + haptics-unavailable case is played
through this matrix and must still pass the 500th-repetition bar on visual
feel alone.

## 6. Audio under VoiceOver

The audio session behavior with VoiceOver running is a decided design, not an
accident: either the session runs as mixable `.playback` so pop sounds coexist
with VO speech, or pop feedback is delivered as VO-friendly announcements plus
haptics — decided by on-device testing in Phase 0 and recorded here as the
measured choice. Either way, a VO user gets timely, non-startling confirmation
of every pop, chain, and clear, and world-move sounds keep their orientation
role (§2).

## 7. QA bar

Per release:

- Device matrix listening pass: built-in speaker + 3 headphone types (wired,
  AirPods-class Bluetooth, over-ear Bluetooth), verifying §4's calibration and
  route policy.
- The "1 a.m. test": full session at minimum volume in a quiet room — nothing
  should ever make the player reach for the volume rocker.
- Full-session mode passes, each played end to end, not spot-checked:
  1. muted with the player's own music (the primary listening mode of §5),
  2. sound on / haptics off,
  3. both off on iPad (visual backbone only, judged against the
     event-feedback matrix),
  4. VoiceOver on (per §6).
- The 500th-repetition judgment for pop and cascade sound is made by real
  end-of-day players outside the dev team.
- Instant-quiet check: mute in under 5 seconds, one-handed, first attempt
  (Phase 0 exit test, re-verified per release).
