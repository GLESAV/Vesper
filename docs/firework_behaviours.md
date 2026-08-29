# Two Firework Behaviours That Were Written But Not Built

*Schema: `Vesper/Game/Firework.swift` · catalog: `FireworkCatalog.swift` ·
break: `GameSimulation.burst` · draw: `SceneRenderer.drawParticle`.*

`FireworkBurst` carries two flags — `splits` and `twinkles` — that describe how
a shell behaves after it breaks. Both are authored. Neither is read. A
repo-wide search finds them set in `FireworkKind.burst` and nowhere else: no
consumer in the simulation, none in the renderer, none in the tests. A
crossette breaks as a plain sphere and a strobe fades once, slowly, like
everything else on the glass.

Nothing about that is broken. The shells still look good and the field still
plays exactly as it is tuned to. But the catalog reads as though the
behaviours ship, and five entries carry flavour lines that promise them, so
this note exists to say plainly what is there and what is not, and to put the
question in front of the owner rather than leaving it in the code.

A third field, `FireworkBurst.gravity`, is in the same state and is described
at the end.

---

## 1. `splits` — the crossette

**What it was meant to do.** A crossette star flies out, and part-way through
its life it breaks a second time into a small number of stars that fly apart
crosswise. It is the one shell in a real display whose break has two beats
instead of one.

**Who sets it.** `FireworkKind.crossette` — the only kind with `splits: true`.
Two catalog entries use that kind:

| # | Name | Flavour |
|---|---|---|
| 12 | crossette | "It thinks better of itself halfway out." |
| 13 | rose crossette | "Four smaller ideas from one." |

Both lines are about the second break. #13 names a count the field does not
produce. #12 is the whole gesture in six words, and today nothing happens
halfway out.

**Where it would have to be consumed.** `GameSimulation.stepParticles(_:)`, in
`Vesper/Game/GameSimulation.swift`. That loop already walks every particle each
frame with the clamped frame factor; a split is a particle noticing it has
crossed a threshold in its own life and replacing itself with a few children.

**Roughly what it would take.**

- A way for a star to know it is a splitting star and that it has not split
  yet. `Particle` has no such field, so this means one added flag (or a life
  threshold plus a marker) on a value type the whole field is made of — a
  memory cost paid by every particle in the game, not just these.
- A child-spawning branch in `stepParticles`, respecting `GameConfig.particleCap`
  the way `burst` already does, and halving under `reduceMotion` the way
  `burst` already does.
- Determinism: children must be drawn from the simulation's seeded RNG, or the
  sim stops being reproducible and several tests stop meaning anything.
- Tuning: a count, a speed, a life for the children, and a threshold for when
  the parent goes. This is gameplay tuning, which is sacred — one constant at a
  time, in `GameConfig`.

The cheap version — spawn the children inside `burst` at break time, on a
delay — is not the same thing. The pleasure of a crossette is the pause.

---

## 2. `twinkles` — the strobe

**What it was meant to do.** Strobe stars do not fade along one curve. They
come and go, on and off, and go out at different moments, which is why a strobe
break reads as many small far-away things rather than one dimming cloud.

**Who sets it.** `FireworkKind.strobe` — the only kind with `twinkles: true`.
Three catalog entries use that kind:

| # | Name | Flavour |
|---|---|---|
| 24 | strobe | "It cannot decide whether to be there." |
| 25 | lilac strobe | "Slow blinking, like something far away." |
| 26 | sea strobe | "Light on water, from above." |

#24 and #25 describe the behaviour outright — indecision, and blinking. #26
survives without it.

**Where it would have to be consumed.** `SceneRenderer.drawParticle`, in
`Vesper/Rendering/SceneRenderer.swift` — a modulation of alpha, not of state.
The simulation should not know about it. A star that flickers in the sim is a
star whose position and lifetime become frame-shaped; a star that flickers in
the renderer is a drawing decision, which is what this is. `drawParticle`
would need to know which shell a particle came from — `Particle.fireworkID` is
already there and already used for the tint — and modulate opacity by a slow
per-particle phase.

**Roughly what it would take.**

- A per-particle phase so stars are not in unison. There is already `phase`-like
  precedent on orbs and motes; a stable hash of the particle's own values would
  do, and would keep `Particle` the same size.
- A modulation curve and rate, in `GameConfig`.
- A `reduceMotion` path. Under reduce-motion the modulation should be off
  entirely, not merely slower.

### The photosensitivity question, which is the real one

This game's first rule is that nothing is harsh, bright, or loud. A strobe is,
by name and by nature, the one effect in the fireworks vocabulary that has a
recognised accessibility hazard: repeated luminance changes across a large part
of the screen can provoke seizures in photosensitive people, and the published
guidance draws the line at around three flashes per second over a meaningful
area of the display.

A careful implementation stays a long way inside that line and would not
plausibly harm anyone: 34 small stars, each modulating on its own phase at
well under a hertz, never in unison, at the muted brightness the palette
already caps — that is not a strobe in the hazardous sense at all. It is
closer to how a distant light behaves in air.

But the distance between "a soft slow shimmer" and "a flash" is a couple of
tuning constants, and the constants are the sort of thing that gets nudged
later by someone chasing an effect. So if this is built, the safe range is not
a preference to be tuned freely; it is a bound to be written down beside the
constants and covered by a test, and reduce-motion must switch it off rather
than soften it. And the word `strobe` should probably stop being the name of
the thing in any surface a player sees.

An alternative worth considering: keep the twinkle as a *variation in when each
star goes out* rather than an on-off cycle. Stars that extinguish at scattered
moments give most of the same read — many small independent lights — with no
repeated luminance change at all, and no hazard to reason about. It is the
smaller change and it may be the better one.

---

## 3. `gravity`, found in the same state

`FireworkBurst.gravity` is authored per kind across the full range 0.02 to 0.16
— a willow at 0.11, a horsetail at 0.16, a comet at 0.02 — and is read by
nothing. `GameSimulation.stepParticles` takes each particle's fall rate from
`PopCatalog.definition(for: particles[i].popNumber).behavior.particleGravity`,
and every firework star is stamped with `PopCatalog.classic`, so all fourteen
shells fall at one rate.

This one is different from the other two in an important way: it is not a
missing feature, it is a *silent* one. `splits` and `twinkles` announce
themselves by being absent — a crossette that does not split is visibly not a
crossette. A willow that falls at a crackle's rate just looks like a slightly
wrong willow, and the fourteen authored numbers sit there looking as though
they are doing the work.

It is also the cheapest of the three to consume: `stepParticles` would need to
prefer a firework's own gravity over the pop's when the particle carries a
`fireworkID`. It is still a change to how the field moves, so it is still the
owner's call and still one constant at a time.

---

## 4. The decision

Three options, and doing nothing is not one of them, because the code and the
copy currently disagree with the field.

1. **Implement.** `gravity` first — it is small, it is the one whose absence is
   invisible, and it makes the fourteen shells fall differently, which is real.
   Then `splits`. Then `twinkles`, only with the bound written down and tested,
   or in the extinguish-at-scattered-moments form instead.

2. **Retire the flags.** Delete `splits` and `twinkles` from `FireworkBurst`
   and from the two kinds, and soften the five flavour lines so they stop
   promising a second break and a blink — #12, #13, #24 and #25 need new words;
   #26 already stands on its own. `gravity` would go the same way, or stay as a
   documented aspiration.

3. **Keep and mark.** What is done here as of this note: the flags stay, the
   declarations say plainly that nothing reads them, and the flavour lines stay
   as written. This is a holding position, not an answer — it is honest, but a
   player still reads "four smaller ideas from one" and sees one.

The copy is good. That is the argument for (1) over (2): the lines were worth
writing, and the shells are the one thing on the field that is allowed to be
theatrical. The argument for (2) is that five flavour lines are cheaper to
rewrite than three behaviours are to build, tune and keep safe — and that a
catalog which describes exactly what the field does is worth more than a
catalog that describes what it might one day do.
