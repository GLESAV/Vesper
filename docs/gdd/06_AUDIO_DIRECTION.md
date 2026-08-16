# Vesper — Audio Direction

*The pop is half sound. The mix is designed for headphones at 1 a.m. and for
total silence on a train.*

## 1. Principles

1. **ASMR bar:** every sound must be pleasant at the 500th repetition. Soft
   attacks, exponential decays, micro-variation per instance (the engine already
   detunes ±12 Hz — keep and extend).
2. **Silence is a valid mix:** with sound off, haptics carry the entire feel;
   nothing in the game references audio a muted player can't perceive.
3. **Her music wins:** `.ambient` session, mixWithOthers, forever. Vesper never
   ducks or interrupts a podcast or playlist.
4. **Nothing startles:** no sound exceeds the pop's peak; no sound arrives
   without a player action except the (optional) room tone.

## 2. The sound palette

- **Pops (exists):** synthesized sine sweeps per family profile (freq, spread,
  sweep, duration, decay, brightness). The family voices are the melody of the
  game — Tide deep and round, Frost bright and glassy, Chime long and belled.
  v2 additions: a third harmonic option for `secret` pops; ±3 ms haptic-audio
  alignment audit on device.
- **The chime (exists):** C5–E5–G5 completion arpeggio. v2: 4 gentle voicings
  rotated by field, so consecutive clears never repeat exactly.
- **World moves (new):** camera drift to Sky = a rising airy shimmer (filtered
  noise, 500 ms, -18 LUFS-ish quiet); to Journal = a soft page-weight sound.
  Both derived from the pop synth (same DNA), both skippable by Reduce Motion.
- **Journal (new):** page turns as filtered paper noise; the lamp lighting = a
  single warm sine blip; keepsake reveal = a two-note kindness.
- **Room tone (new, optional, off by default):** an almost-silent dusk pad
  (slow filtered noise + faint detuned drone, -30 dB) for the bedside sessions.
  A "quiet room" toggle in the journal's last page.

## 3. Mixing rules

Pop peak = reference 0 dB (internal). Chime -4. Whisper/world sounds -14 to
-20. Room tone -30. Master soft-limited; nothing clips at max device volume.
All synthesis stays procedural (no assets) — the zero-dependency, tiny-binary
promise is part of the product.

## 4. Haptics (the silent mix)

Grammar (exists, keep): soft impact per pop scaled by size; chained pops
echo lighter; success on clear. v2 additions: a barely-there tick when the
camera settles in a place; the lamp lighting = one warm tap. Never more than
one haptic meaning per pattern; haptics-off parity guaranteed.

## 5. QA bar

Device matrix listening pass (speaker + 3 headphone types) per release; the
"1 a.m. test": full session at minimum volume in a quiet room — nothing should
ever make the player reach for the volume rocker.
