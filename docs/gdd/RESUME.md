# Resume here — **stale; kept as the record of one pause**

> **Do not resume from this page.** It was written at a pause very early in the
> One World rebuild, when only the input arbiter existed. Everything on the
> critical path below has since been built and merged: `VesperApp` launches
> `WorldView` by default, the camera, whispers, sky, journal, scoped strings and
> the DEBUG reset all exist, `docs/PLAYTEST.md` was written, and W08 landed as
> well — it turned out to need no persisted-schema migration at all, which is
> the one constraint below that was simply wrong. Weather, balloon animals,
> fireworks, the staged field mechanics and the sky scroll all arrived
> afterwards and are not mentioned here at all.
>
> Two things on this page are still worth keeping: the **constraints** section,
> which is a list of rulings the code still obeys (bar the last one), and the
> **open question** about the playtest-panel budget. For where the build
> actually is, read `docs/e2e_walkthrough.md`.

*Working state for the One World build. Written at a deliberate pause so work
can restart cleanly — including in a fresh container, since everything below is
pushed to `claude/vesper-pop-aaa-optimization-2n5oc2`.*

## Where we are

The roadmap (`DELIVERY_ROADMAP.md`) is **approved with amendments** by the
Director of Engineering; her 20 rulings are §6 and are binding.

**Done and pushed:**

- `Vesper/World/WorldInput.swift` — the pure `InputArbiter` (W03)
- `Vesper/World/WorldInputView.swift` — the UIKit host over raw touches (W03)
- `VesperTests/WorldInputTests.swift` — incl. the 20-swipes-from-an-orb barrier case
- `VesperTests/TapBaselineTests.swift` — the v1.2 tap-success baseline (W20a)

**Nothing in the shipping app references any of this yet.** `VesperApp` still
launches `ContentView` exactly as v1.2 does, so `main` behaviour is unchanged
and the pause is safe.

*(No longer true. `VesperApp.root` reads `WorldFlags.oneWorldEnabled` and
launches `WorldView`; `ContentView` is reached only when `VESPER_CLASSIC_NAV`
is compiled.)*

## The next action, precisely

**Re-run the R-SPIKE gate.** It was in flight when work paused, so its verdict
is unknown. The spike agents replay from cache:

```
Workflow({
  scriptPath: "/root/.claude/projects/-home-user-Vesper/14cd7c47-181f-5629-8862-3cb836a1676b/workflows/scripts/one-world-e0-spike-wf_11696ca6-47b.js",
  resumeFromRunId: "wf_11696ca6-47b"
})
```

If that script or run is gone (fresh container), re-run the gate from scratch:
three Opus subprocesses reviewing the four files above — **Jun Park**
(interaction), **Viktor Sørensen** (performance), **Amara Osei** (vestibular —
her review is a *barrier*, not a note). Verdicts: go · go-with-notes ·
fallback-stage-1 (camera kept, tappable whispers primary) · fallback-stage-2
(static field, in-world panels) · block.

## Then, in order (the Director's critical path)

`W01` camera state machine (tests folded in) → **R-ARCH** (barrier) → `W04`
world skeleton + flag at app root → `W07` `WorldModel` + explicit `simActive` →
`W05` camera motion → `W06` whisper labels → `W13′` scoped strings
(`DETONATED` → **set free**) → `W12` instant quiet → `W09` SkyView →
`W11` JournalView → `W20` instrumented regression (barrier) → `W24` DEBUG
fresh-install reset → `W23` TestFlight path → `W22` `docs/PLAYTEST.md` →
**owner + Kate play it** → R-BOARD.

## Constraints that must not be forgotten

- The camera's continuous offset is **never** `@Published` (ruling 7).
- The input layer is **never** rebuilt by camera motion; the field `Canvas` is
  pinned to a constant size at every camera position (ruling 8).
- `WorldFlags.oneWorldEnabled` is read in **exactly one place** — `VesperApp`
  choosing the root view (ruling 10). CI builds both configurations (ruling 11).
- Barriers are exactly three: **R-SPIKE, R-ARCH, W20** (ruling 20).
- No persisted-schema migrations in this build (W08/W10 deferred). *(W08 has
  since shipped — and needed no migration: settledness is a pure reading of a
  stone's own dates, so the change was the deletion of the pruning pass and
  nothing else. W10 — keepsakes, the lamp, the fortune archive — is still
  deferred.)*

## Open question for the owner

The playtest-panel incentive budget (~$300) is marked *requires approval* in
`09_BUSINESS.md`. Not blocking any engineering work.
