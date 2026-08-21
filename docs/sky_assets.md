# Sky Assets — the brief

*What to commission, and what not to.*

Status: **spec, unbuilt.** The sky currently renders its dreaming entirely in
code (`SkyRenderer.drawDeepField`) with no assets at all. This document is for
the point at which that stops being enough.

---

## 1. Read this before commissioning anything

**The sky already works without assets, and that is a feature.** The deep
field is procedural: three depth tiers of star haze, two nebula washes, a
diagonal dust band, all seeded from a constant so it is the *same sky* every
evening. It costs nothing to download, scales to every screen and aspect
ratio, and cannot go stale.

So the question for any asset is not "would this look nice" but **"what can a
painted asset do that generated light cannot?"** There are real answers —
texture, hand-made irregularity, the sense that a person made this — and there
are expensive non-answers. The list in §3 is the first kind only.

**The budget rule.** Every megabyte here is a megabyte a woman downloads on
her commute for a game that promises to ask nothing of her. Total added
install size for the whole sky: **under 4 MB**. If a piece cannot fit that, it
is drawn in code or it is cut.

## 2. The constraints every asset must satisfy

These are not preferences. An asset that breaks one of them cannot ship.

| # | Constraint | Why |
|---|---|---|
| 1 | **Dark ground, always.** Nothing above ~12% luminance except individual star points. | The sky is looked at in bed with the lights off. |
| 2 | **No saturated colour.** Muted pastels only — the palette in `05 §2.1`. If a hue can be named without hesitating, it is too strong. | Guardrail 4. |
| 3 | **No pure white.** Ink caps at 96%. | 05 §2. |
| 4 | **Nothing sharp, nothing geometric, nothing that reads as UI.** No icons, no frames, no rules, no badges. | 05 §6. |
| 5 | **Tileable or edge-safe.** Screens run 375×667 to 440×956, plus iPad. Nothing may show a seam or a hard edge at any of them. | One asset, every device. |
| 6 | **Nothing that suggests time pressure.** No clocks, no falling stars with tails implying speed, no countdown imagery. | Guardrail 1, in pictures. |
| 7 | **Legible at 20% opacity.** Everything here sits *behind* the tree and must never compete with it. | The stones are the content. |
| 8 | **Reduce Motion safe.** Any animated asset needs a still frame that is complete on its own. | Amara's conditions 10–15. |

## 3. The asset list, in priority order

### A1 — Nebula plates · **highest value**
**What:** 3–4 soft cloud fields, each a single PNG with alpha, roughly
1400×1400, that replace the procedural radial washes.

**Why an asset beats code:** a radial gradient is perfectly smooth and reads as
a gradient. A painted nebula has *structure* — filaments, density variation,
places where it thins to nothing — and that structure is what the eye reads as
distance. This is the single biggest visual return available.

**Direction:** think of a long-exposure photograph of dust, not of a
space-opera nebula. Mostly empty. Density in one third of the frame at most.
Colour restricted to the palette's dusty violet and a cold sage; two hues per
plate, never three.

**Delivery:** PNG-8 with alpha where possible, ≤400 KB each. Composited at
4–6% opacity, so banding matters more than resolution — dither them.

### A2 — The tree's bark · **high value**
**What:** a set of 6–10 short curved stroke sprites, ~120×24, used in place of
the current stroked bezier branches.

**Why an asset beats code:** a stroked path is uniform. A real branch has a
line weight that varies along its length and an edge that is never perfectly
smooth, and that irregularity is most of what separates "grown" from
"diagram". The taper is already implemented; what is missing is *texture*.

**Direction:** ink on rough paper, not bark photography. Slight dry-brush
break-up at the thin end. Each stroke a different curvature so a long path
never repeats visibly.

### A3 — Star glyphs · **medium value**
**What:** 10 small sprites, ~64×64, one per pop family, replacing the drawn
polygon gems.

**Why an asset beats code:** `gemPath` gives each family a facet count and a
rotation, which sorts them in grayscale and is genuinely good — but they are
polygons, and they look it. Hand-drawn glyphs can carry the family's
*character* (ember's flicker, frost's brittleness) in a way a regular polygon
cannot.

**Caution:** this is the asset most likely to break constraint 4. A glyph that
becomes recognisable as a *symbol* — a flame, a snowflake — turns the sky into
an icon set. Keep them abstract: the *feeling* of a flame, never a flame.

### A4 — Horizon glow · **medium value**
**What:** one wide, very soft gradient plate, ~1200×400, sitting at the foot
of the sky where it meets the field.

**Why:** the sky and the field are one continuous world, and the join is
currently a colour crossfade with nothing in it. A faint glow at the bottom of
the sky reads as *the field's light, from above* — which is exactly the
relationship the navigation is trying to teach.

### A5 — Completion mark flourish · **low value, optional**
**What:** a single 96×96 ring sprite with hand-made line weight variation, to
replace the drawn circle on a cleared stone.

**Why low:** the drawn ring already works and is already meaningful (a circle
that meets itself). This is polish, and it is the first thing to cut.

### Explicitly NOT commissioning

- **A painted background of the whole sky.** It cannot tile, cannot adapt to
  aspect ratio, and would be the largest file in the app to replace something
  that already works.
- **Animated video or sprite-sheet loops.** Battery, size, and constraint 8.
- **Anything with a character, creature, or figure in it.** There is nobody in
  this world but her.
- **A logo, watermark, or signature in the art.** The sky is a place, not a
  frame.

## 4. Format and integration

- **Format:** PNG with alpha. No PDFs (the render cost is real at these
  sizes), no SVG (SwiftUI's support is not worth the trouble here).
- **Scales:** ship @2x and @3x only. @1x devices are not supported (iOS 18.5+).
- **Colour space:** sRGB. Display P3 buys nothing at 6% opacity and costs size.
- **Where they go:** `Vesper/Resources/Sky.xcassets`, which does not exist yet
  — creating it is part of the first asset PR, not part of the brief.
- **How they are drawn:** `SkyRenderer.drawDeepField` gains an optional image
  path per layer and keeps the procedural version as the fallback. **The
  procedural sky is never deleted** — it is what runs before assets load, and
  it is the answer if the asset budget is ever cut.

## 5. How to brief an illustrator in one paragraph

> Vesper is a calm iOS game played in bed at the end of a long day. The sky is
> a dark, quiet star map where a player's history is drawn as a tree growing
> downward from the top of the screen. I need background art that sits *behind*
> that tree at very low opacity and gives it depth. Think long-exposure
> astrophotography of dust — mostly empty, muted, no strong colour, nothing
> sharp, nothing that reads as an interface element. It should feel like
> something noticed rather than something shown. Nothing in it should suggest
> urgency, achievement, or anyone else being present.
