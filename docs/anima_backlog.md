# Anima — the build loop

The ordered plan an autonomous loop works through. **This file is the loop's
memory.** Each iteration reads it, does the first unchecked item, ticks it, and
commits. Nothing else carries state between iterations.

## The iteration contract

1. `git pull` the working branch.
2. **Check CI on the open PR first.** If it is red, fixing it *is* this
   iteration — stop after pushing the fix. Assets are never authored against
   an engine that does not compile.
3. If CI is green, do the **first unchecked item** below. One item per
   iteration, no skipping ahead.
4. Tick it, commit with a message that says what was learned, push.
5. If every item is ticked and CI is green, the loop is done.

## Definition of done

- [ ] 100 demo assets, one per pop number 1–100, each in its `PopFamily`
- [ ] Every asset validated against the pop paradigm by a test
- [ ] A hub page showing all 100, published and reachable
- [ ] CI green on both configurations
- [ ] Export under 8 MB and the page usable on a phone

---

## Phase E — finish the engine

Assets cannot be authored until these are done, and the order matters.

### E1 — Shrink the export by ~55×  ⟵ **blocks everything**

- [x] E1 — **done.** CI measured format 1 at **9,253,479 bytes for six
      objects** (1.54 MB each → 154 MB for a hundred), confirming the estimate
      below almost exactly. Format 2 ships each part's rest outline once and a
      resolved affine matrix plus opacity per frame — seven numbers per part
      per frame instead of a hundred and twenty-eight.

Measured, not estimated. The exporter currently writes a full 64-point outline
per part **per frame**:

| | |
|---|---|
| average parts per object | 4.8 |
| bytes per object | 1.50 MB |
| **100 objects** | **150 MB** |

That is unshippable, un-openable in a browser, and would blow the 12 MB test
cap on roughly the ninth asset. Four changes, together ~55×:

1. **Export a resolved affine matrix per part per frame, and each part's
   outline exactly once.** Six numbers instead of 128. This is the big one.
2. **Round coordinates to 4 decimal places.** In unit space 1e-4 is 0.0034 pt
   at the largest orb — three orders of magnitude below a pixel.
3. **32-point outlines for export** (the app keeps 64). The previewer draws at
   ~200 px; the sagitta at 32 points is well under one CSS pixel there.
4. **24 fps, not 30.**

**The drift rule still holds, and it is worth restating because this change is
exactly where it could be lost.** The previewer must still contain no easing,
no interpolation, no hierarchy composition and no `exp`. Export the final
**affine matrix** (a, b, c, d, e, f) — already resolved through rest, merge,
lag and parentage by `AnimaClip.pose` — so the previewer's only arithmetic is
`x' = a·x + c·y + e`. Do **not** export `squash` and recompute the axes in
JavaScript; that would put `exp` on both sides of the fence.

Keep `AnimaPose` itself unchanged for the app. Add the matrix to
`AnimaPosedPart`, and keep the verification honest by having it reconstruct
the outline from matrix × rest-outline and compare to the app's posed outline.
Done as `testExportedFramesReconstructTheApplicationsOwnPoses`, at a tolerance
of 0.002 — which is the 4dp rounding, not slack.

### E2 — Reduce Motion variants

- [x] E2 — **done.** `AnimaClip.reduced`, computed rather than authored so an
      author cannot forget to write one and it cannot go stale when a clip is
      retimed.

04 §11: every motion needs a defined reduced variant, and none may carry
information. The two clauses pull in opposite directions, so the two kinds of
clip reduce differently:

- **A looping idle reduces to stillness** — structurally, by carrying no
  tracks at all, so "a reduced idle is still" holds exactly rather than to
  within a tolerance. Its opacity goes with it: `SkyView` already settled this
  for the stars ("the breath is an affordance, never information, so removing
  it may not also dim them"), so a reduced idle is fully lit and still.
- **A one-shot keeps its opacity exactly and damps everything else** (×0.35).
  Here the opacity *is* the information — a part fading to nothing in
  `release` is the whole message — and damping it would lose meaning, which is
  §11's second clause. Not damped to zero either: deleting the motion deletes
  the feedback, trading an accessibility problem for a usability one.

The three direction-reversing easings (`anticipate`, `overshoot`, `settle`)
are flattened to `easeInOut`. A reversal is what a vestibular system objects
to, far more than distance travelled.

Five tests, all measuring **peak travel from rest** rather than inspecting
curve values — which would only prove the arithmetic, not the result.

### E3 — The pop-paradigm bridge

- [x] E3 — **done.** `AnimaPop.object(for:)` generates a drawable object for
      every one of the hundred catalogue pops, wearing that pop's own paints
      and played on the instrument its own definition asks for.

The 100 assets are not free-standing art; they are the visual half of the
existing 100-pop catalog. Add `AnimaPopBinding`:

- keyed by `PopDefinition.number` (1–100, stable forever)
- a **family shape signature** on `PopFamily`, exactly parallel to the `voice`
  / `burst` / `haptic` signatures it already carries — the family is the
  silhouette vocabulary, the ten pops in it are variations on it
- paints drawn from the bound `PopDefinition.style.paints`, never invented
- a test that every binding's number exists in `PopCatalog`, that its family
  matches, and that its paints are the pop's own

Ten families × ten pops is the paradigm; a hundred one-offs is not.

**How it came out.** The ten silhouettes are a disc with a moon (vesper), a
flame and its sparks (ember), a drop over a ripple (tide), petals about a
heart (bloom), a radial crystal (frost), a hanging bar (chime), a body with a
handle (lantern), a streamer (current), a hard shard with a beam (prism), and
stacked open bands (aurora). A test computes each family's structural
fingerprint — part count plus primitive kinds — and fails if any two match,
because shape reads before colour and two families that cannot be told apart
as black shapes are one family.

**The ten notes inside a family** come from `AnimaVariation`: four knobs
(`trait`, `accent`, `count`, `tilt`) whose meaning each family's builder
decides for itself. Deliberately not named for shapes — a knob called
`earLength` would be meaningless in nine families out of ten. Until a pop's
variation is authored it derives one from its own number, so all hundred are
previewable now and each phase-A batch replaces derivation with intent.

**Voice coverage** had to be completed for the mapping to be total: `tone`,
`pluck`, `crackle` and `shimmer` were added, verified numerically against
every voice invariant before any Swift was written. `AnimaLibrary.voice(for:)`
has no `default:`, so a new `SoundVoice` case stops the build rather than
silently inheriting a fallback and making two families sound alike.

### E4 — The hub page

- [x] E4 — **done.** A gallery of all 100 plus the six reference figures,
      grouped by family, filterable by family and rarity, searchable by name,
      number and flavour, with a Reduce Motion toggle that plays the engine's
      own reduced variants.

Three things this needed beyond the page itself:

- **Revision 3 makes voices a table.** A hundred pops share ten instruments,
  so inlining PCM per object shipped each instrument about ten times — some
  2.5 MB of duplicated audio, most of the file. Written once and referenced by
  name it is ~350 KB however many objects there are.
- **Every performance ships its reduced variant beside it.** §11 is not only
  an app property: an author reviewing a hundred assets has to see what
  someone who asked for less motion actually gets, and the only honest way to
  show it is the engine's own `reduced` through the same export path. A
  reduced idle carries no tracks, so it exports as **one** frame rather than
  thirty-two identical ones.
- **Only visible tiles animate**, via `IntersectionObserver`. A hundred
  canvases redrawing at once is a lot of a laptop for no benefit.

Measured before pushing: **2.16 MB** for all 106 objects, against an 8 MB
gate.

### E5 — Publish it

- [x] E5 — **built and verified as far as it can be from here.** Two things
      remain outside the loop's reach; both are named below rather than
      quietly ticked.

The workflow runs the export on the macOS runner — the only toolchain in this
picture — and uploads it unconditionally as a build artifact. Measured on the
full gallery: **673,791 bytes zipped** (`index.html` + `library.json`), 106
objects.

**The page itself is verified**, which no Swift test can do, because the page
is JavaScript. Driven in headless Chromium against a hand-built revision-3
fixture:

| check | result |
|---|---|
| cards rendered | 100 |
| family groups / buttons | 10 / 10 |
| canvases actually painted | 16 — the `IntersectionObserver` working; only visible tiles animate |
| search `pop 042` | 1 card |
| family filter `frost` | 10 cards |
| Reduce Motion toggle | all 100 switch to a `(reduced)` clip |
| console errors | none |

That run found two real defects, both fixed: a missing favicon (the browser
requests `/favicon.ico`, gets a 404, and logs a console error on a page whose
whole job is to be trusted) and "1 instruments".

CI now also runs `node --check` over the page's extracted `<script>`. A syntax
error there fails nothing upstream — it ships a **blank gallery**, to an
author with no way to tell a broken page from an empty library. Free, since
the runner already has node, and no new repository dependency.

#### Still blocked, and not by anything the loop can do

1. **GitHub Pages is not enabled.** Settings → Pages → Source: *GitHub
   Actions*. The `Publish to Pages` job is written to skip rather than fail
   without it, so nothing else is held up — but there is no public URL until
   this is flipped.
2. **The publish job only runs on `main`**, which is correct (a PR branch must
   not overwrite the live site) and means the deploy path itself is unproven
   until this branch merges.

The full-fidelity check — the real export, in the real page, on the real URL —
is one command once Pages is on:
`python3 -m http.server -d tools/anima-studio 8000` against a downloaded
artifact, or simply the deployed page.

---

## Phase A — the 100 assets

One family per iteration, ten assets each, in catalog order. Each asset is an
`AnimaObject` bound to its pop number, using its family's shape signature, its
pop's own paints, and one authored performance beyond the shared `wake` /
`release`.

- [x] A1 — **vesper** 001–010 · the original dusk. `trait` = how far the
      companion sits, `accent` = how large and high, `tilt` = the angle of the
      pair. Authored to each flavour line rather than spread evenly — an even
      spread is a gradient, and a gradient is not ten things. Reach spans
      1.00–1.33; closest pair in the variation plane 0.13. **#001 is pinned at
      exactly 1.00**, the most orb-like of the hundred (guardrail 5), by a test.
- [ ] A2 — **ember** 011–020
- [ ] A3 — **tide** 021–030
- [ ] A4 — **bloom** 031–040
- [ ] A5 — **frost** 041–050
- [ ] A6 — **chime** 051–060
- [ ] A7 — **lantern** 061–070
- [ ] A8 — **current** 071–080
- [ ] A9 — **prism** 081–090
- [ ] A10 — **aurora** 091–100

### Standing rules for every asset

- **Silhouette first.** A family must be recognisable at arm's length in the
  dark, before colour is read. If two families would be confused as black
  shapes, the second one is wrong.
- **Reuse the shared performances.** `wake` and `release` work on every figure
  because of the one-root-named-`body` convention. An asset that needs its own
  copy of a generic performance is a signal the convention was broken.
- **Muted palette, no pure white, no outlines** — guardrail 4, enforced by
  `AnimaTests`.
- **Nothing is wired into gameplay.** These are demo assets and a preview.
  Guardrail 5 holds; adoption is a separate change with its own before/after.

---

## Phase Z — close out

- [ ] Z1 — Full `AnimaTests` pass, export under 8 MB, hub page verified
- [ ] Z2 — Update `docs/anima.md` and `CLAUDE.md`; mark PR ready for review
