# Anima — the 2-D animation engine

Anima is Vesper's own engine for authoring **new 2-D objects, new performances
and new sounds** as data, previewing them in a browser, and shipping them
without a single imported asset.

Everything it produces is generated from numbers in this repository. There is
no stock art, no sample library, no licensed audio and no third-party runtime
anywhere in it, so **every asset it makes is originated by and owned outright
by Vesper Pop.**

---

## 1. Why it exists

The game was already fully procedural — there is not one `.png` or `.wav` in
the app — so ownership was never the problem. **Throughput** was.

Three costs, all of them real and all of them measurable:

**A new object costs an engineer a day.** The game draws five different
vocabularies of 2-D object and no two share a line of code: orbs are ellipses
in `SceneRenderer`, balloon animals are unions of circles in
`AnimalRendering`, sky stars are rounded polygons in `SkyRenderer.gemPath`,
fireworks and weather are their own again. A sixth object reuses none of it.

**A new sound is a 200-line edit.** `PopSoundEngine.makePopBuffer` is one
synthesis loop with a ten-way `switch` inside it. Adding an eleventh voice
means opening that loop, reasoning about a shared envelope and a shared gain,
and listening on a device.

**Nothing can be animated on a timeline at all.** Motion is either physics in
the simulation or a single SwiftUI easing. There is no way to express "the ear
droops, then the body settles, then it looks up" — which is what *animation*
means, as distinct from *movement*.

And underneath all three: **seeing any change costs about five minutes** —
edit, build, launch the simulator, play far enough in to reach the content.
That needs a Mac with Xcode and someone comfortable in it. An author gets
maybe ten looks an hour and cannot get any alone.

---

## 2. What it is

| File | What it owns |
|---|---|
| `Anima/AnimaCurve.swift` | Easings and keyframed curves. Time. |
| `Anima/AnimaShape.swift` | Parametric primitives → outlines. Form. |
| `Anima/AnimaFigure.swift` | Parts, transforms, hierarchy, poses. |
| `Anima/AnimaClip.swift` | Timelines, channels, follow-through. |
| `Anima/AnimaVoice.swift` | Declarative synthesis → PCM. Sound. |
| `Anima/AnimaLibrary.swift` | The authored content. **Edit this one.** |
| `Anima/AnimaPop.swift` | The hundred catalogue assets, generated per pop (§5a). |
| `Anima/AnimaStudio.swift` | JSON export for the previewer. |
| `Rendering/AnimaRenderer.swift` | The only file that imports SwiftUI. |
| `tools/anima-studio/index.html` | The browser previewer. |

The core is **Foundation and CoreGraphics only** — no SwiftUI, no UIKit, no
wall-clock, no dependencies — the same discipline `GameSimulation` keeps, for
a bigger payoff: because sampling is pure, the same sample can be drawn on the
glass, asserted in a test, and shipped to a previewer that runs in a browser.

---

## 3. The authoring loop

```sh
TEST_RUNNER_ANIMA_EXPORT_DIR="$PWD/tools/anima-studio" \
  xcodebuild test -project Vesper.xcodeproj -scheme Vesper \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:VesperTests/AnimaStudioTests/testWriteTheStudioExport

open tools/anima-studio/index.html
```

Scrub any performance, hear any voice, read the authoring note. If the browser
refuses `fetch()` on `file://`, serve the folder:
`python3 -m http.server -d tools/anima-studio 8000`.

The export is opt-in through `TEST_RUNNER_ANIMA_EXPORT_DIR`, so **CI never
writes anything** on an ordinary run.

### Checking the page itself

The gallery is JavaScript, so no Swift test reaches it. CI syntax-checks it
(`node --check` over the extracted `<script>` — a syntax error there ships a
blank gallery rather than failing anything). Beyond that it is driven in
headless Chromium against a fixture: 100 cards, family grouping, search,
family and rarity filters, the Reduce Motion toggle, and zero console errors.

That is deliberately **not** wired into CI, because it would mean adding
Playwright to a repository whose first rule is zero dependencies. It is a
procedure to re-run when the page changes, not a gate.

### Why the previewer cannot lie

This is the failure that kills tools like this: the preview reimplements the
runtime, the two drift, and the tool starts quietly lying to whoever is
authoring against it. The lie is worse than having no tool, because it is
believed.

Two decisions make drift *structurally impossible* rather than merely
unlikely:

1. **The previewer does almost no animation maths.** It is handed each part's
   rest outline and, per frame, a *resolved* affine matrix — already keyed,
   eased, lagged, merged, composed and depth-sorted by `AnimaClip.pose`. There
   is no easing function in the JavaScript to disagree with `AnimaEase`,
   because there is no easing in the JavaScript at all; likewise no keyframe
   interpolation, no hierarchy, no `lag`, and no `exp` (which area-preserving
   squash needs, and which therefore stays on the Swift side).
2. **The previewer does no synthesis.** It is handed PCM rendered by
   `AnimaVoice.render` — the arithmetic that reaches the phone's speaker. It
   has no oscillator.

**The one concession, stated plainly.** Format 1 shipped a fully transformed
outline per part per frame and contained literally no geometry in the page.
CI measured it at 9,253,479 bytes for *six* objects — 154 MB for a hundred,
which is not a preview anyone can open. Format 2 therefore asks the page for a
single affine multiply, `x' = a·x + c·y + tx`: six multiplications and four
additions, no transcendentals, no branches, nothing with a convention to get
backwards. That is the whole of it, and
`AnimaStudioTests.testExportedFramesReconstructTheApplicationsOwnPoses` does
exactly what the page does and holds the result against the app's own posed
outlines to within the 4dp rounding.

The previewer's *material* (halo, fill) is an approximation of
`SceneRenderer`'s three passes and does not claim otherwise. Shapes and timing
are exact; the material is the part nobody iterates on in a browser.

---

## 4. Authoring

### A new object

```swift
static let pebble = AnimaFigure(
    "pebble",
    parts: [
        AnimaPart("body", .polygon(sides: 7, roundness: 0.7),
                  rest: at(0, 0, scale: 0.9), paint: 0, depth: 6),
        AnimaPart("moss", .petal(sharpness: 0.4), parent: "body",
                  rest: at(-0.3, 0.2, scale: 0.4), paint: 1, depth: 8, lag: 0.05)
    ],
    paints: [sand, sage]
)
```

**One convention, held by a test: every figure has exactly one root part and
it is named `body`.** This is what makes performances *portable* — `wake` and
`release` are authored once and work on every object in the library, and on
the next one nobody has written yet. Without it, every object needs its own
copy of every generic performance, which is exactly the per-object cost this
engine exists to remove.

Primitives: `disc`, `capsule`, `petal`, `polygon`, `arc`, `blob`, `ribbon`.
All are sampled to outlines in unit space and scaled by the object's radius at
draw time, so nothing is authored at a fixed size.

### A new performance

```swift
static let nod = AnimaClip("nod", duration: 0.6, tracks: [
    AnimaTrack("body", .rotation, [
        AnimaKey(0.0, 0.0, .linear),
        AnimaKey(0.18, -0.12, .anticipate(1.4)),   // winds up
        AnimaKey(0.60, 0.0, .settle(6))            // rings down
    ])
])
```

Channels: `x`, `y`, `rotation`, `scale`, `squash`, `opacity`. `x`, `y`,
`rotation` and `squash` add onto the rest pose; `scale` and `opacity`
multiply into it.

**The principles are named, not improvised.** `.anticipate` winds up before
going, `.overshoot` passes the target and returns, `.settle` rings down. These
three are what make procedural motion read as *performed*, and they are the
three a designer reaches for constantly and cannot express with `easeInOut`.

**Squash and stretch is one field, not two scale channels.** `AnimaTransform`
derives both axes from a single `squash`, so area is preserved by construction
and a channel swinging symmetrically about zero returns to exactly its rest
shape. With two independent channels it does not, and an object bouncing in a
loop slowly shrinks with nobody able to see why.

**Every performance has a Reduce Motion variant, and nobody authors it.**
`AnimaClip.reduced` is computed, so it cannot go stale when a clip is retimed
and an author cannot forget to write one. A looping idle reduces to stillness
(no tracks at all); a one-shot damps its movement to 35%, flattens the three
direction-reversing easings, and keeps its **opacity exactly** — because in a
one-shot the opacity is the information, and 04 §11 asks that a reduced
variant lose none.

**Follow-through is one number.** `AnimaPart.lag` delays a part — *and
everything above it in the hierarchy* — by some seconds, so when the head
stops the ear is still arriving. It is the cheapest thing that separates a
rigid puppet from something with soft parts, and it costs one subtraction.

### A new sound

```swift
static let hush = AnimaVoice(
    "hush", duration: 0.75,
    partials: [
        AnimaPartial(1.0, gain: 0.20, decay: 3.0, detune: 0.7),
        AnimaPartial(1.5, gain: 0.12, decay: 4.0, detune: 1.1)
    ],
    noise: AnimaNoise(gain: 0.10, decay: 5.0, lowpass: 0.06),
    attack: 0.09
)
```

Integer `ratio`s are harmonic and read as pitched; non-integer ones are
inharmonic and read as struck metal or glass. That is the entire difference
between a tone and a bell, and it is one number.

Three safety rules are **inherited from `PopSoundEngine`, not rediscovered**,
and enforced here so a data-authored voice cannot break them:

1. **No steep downward pitch sweep.** A fall of more than a few percent inside
   a pop's length is definitionally an arcade laser — it is what made the base
   pop sound like Space Invaders. A voice that does not set `allowsFall` has
   its glide floored at 0.94 however the catalog was written, so a mistyped
   sweep is a slightly flat pop rather than a phaser.
2. **A raised-cosine attack and release.** Any envelope that starts or ends at
   full amplitude clicks, and a click in a calm game is the loudest thing in
   it.
3. **Nothing is ever loud.** A master gain of 0.5 and a hard clamp, and a test
   that a voice does not *sit* on that clamp — the clamp is a guardrail, not a
   mixer.

---

## 5. What the tests hold

`AnimaTests` pins two different kinds of thing, and the second matters more.

**Engine invariants** — every easing lands exactly on 0 and 1, curves are
total under NaN and negative time, squash preserves area, posing is
deterministic.

**Authoring invariants** — every figure has one root named `body`; no part
names a parent that does not exist; no name is used twice; no track binds to a
part that was renamed; every paint index exists; the palette stays muted and
never pure white; no voice is a laser, loud, silent, or a duplicate of
another.

The second set protects the *product from the catalog*, which is the part that
will be edited by hand, often, possibly by someone who has never opened Xcode.
Every one of them is a mistake that is cheap to make and expensive to notice —
a track bound to a renamed part does nothing at all, silently, with no other
signal.

---

## 5a. The hundred assets

`AnimaPop` generates a drawable object for every catalogue pop — its own
paints, its family's silhouette, the instrument its definition asks for — and
`AnimaPop.variations` places each of the hundred along its family's own axes.

Ten silhouettes: a disc with a moon (vesper), a flame and its sparks (ember),
a drop over a ripple (tide), petals about a heart (bloom), a radial crystal
(frost), a hanging bar (chime), a body with a handle (lantern), a streamer
(current), a hard shard with a beam (prism), stacked open bands (aurora). A
test computes each family's structural fingerprint and fails if any two match:
two families that cannot be told apart as black shapes are one family.

Every variation is authored to the flavour line the catalogue already carries
— #003 Eventide is dead level because water finds its level; #033 Clover has
exactly three petals; #100 Morning Star is the narrowest sweep in aurora,
which is the closest an arc comes to closing into the circle #001 is.

**Adding an eleventh family, or an author's own object**, is the same job: a
builder that reads the four knobs, and rows in `variations`. Verify with
`tools/anima-reach.py` before spending a CI cycle — see `docs/anima_backlog.md`
for the two gates and what they have caught.

## 6. What is **not** done

**Nothing here is wired into gameplay, and that is still true.** Verified
against the tree: no file outside `Anima/` and `Rendering/AnimaRenderer.swift`
references `AnimaRenderer`, `AnimaPop` or `AnimaLibrary`. The engine ships in
the binary and nothing on the glass draws from it; its output is the browser
gallery, not the phone. Adoption is its own change, with its own
before-and-after, one system at a time — guardrail 5 says the tuning is sacred.

The adoption path, cheapest first:

1. **Sky stars.** `SkyRenderer.gemPath` is already `polygon(sides:roundness:)`
   by another name, and the sky has no physics to disturb. Lowest risk, and it
   proves the renderer in production.
2. **Balloon animals.** `AnimaLibrary.hare` is deliberately the same lobe
   vocabulary `AnimalPop` uses. If the silhouette matches, the animals move
   over without their shapes changing — which is the precondition for
   trusting the engine anywhere near the field.
3. **Sound.** Express the ten existing `SoundVoice` cases as `AnimaVoice`
   data, render both, and compare buffers numerically before switching. **All
   ten are now written** in `AnimaLibrary.voices` — `popVoice`, `tone`, `bell`,
   `pluck`, `breath`, `glass`, `wood`, `crackle`, `shimmer`, `drop`, plus
   `chime` and `hush` — and `AnimaLibrary.voice(for:)` maps a `SoundVoice` to
   its instrument with no `default:` case, so a new voice in the pop standard
   stops the build here rather than silently inheriting a fallback. The schema
   is proven; what remains is the numeric comparison and the switch, and
   neither has been done. `PopSoundEngine` still synthesises every pop the
   game plays.
4. **Pops.** Last, and only with a measured before-and-after. Pop #001 is the
   reference implementation of the game's feel and must not move at all.

Also not done: haptics — `HapticPattern` is a rhythm, which is a timeline,
and belongs in this engine eventually rather than beside it.
