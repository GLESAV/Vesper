# The Classic Navigation — Keep the Flag, or Delete It

*A decision memo for the owner, written before the v1.3 submission. It gathers
the evidence and makes a recommendation; the decision is not the memo's to
make. Nothing in the repository was changed to write this.*

*Subject: `Vesper/Views/` (the v1.2 navigation), `Vesper/Support/WorldFlags.swift`,
the `VESPER_CLASSIC_NAV` compilation condition, and the `classic` leg of
`.github/workflows/ci.yml`. Evidence gathered at `b365468`, on branch
`claude/vesper-pop-aaa-optimization-2n5oc2`.*

---

## 1. What the flag is, and why it exists

Vesper shipped v1.2 with a navigation made of a field, a top bar of four icon
buttons, and three modal sheets. The One World rebuild replaced all of it with
one vertical axis — sky above, field in the middle, journal below.

Rather than delete the old screens, Phase 0 kept them behind a switch.
`VesperApp` reads `WorldFlags.oneWorldEnabled` exactly once, at launch, and
chooses a root view:

```swift
WorldFlags.oneWorldEnabled ? AnyView(WorldView()) : AnyView(ContentView())
```

Two rulings in `docs/gdd/DELIVERY_ROADMAP.md` §6 shape it, and both are worth
restating because the decision turns on them:

- **Ruling 10** — the flag has exactly one read site. It is forbidden in view
  bodies, in `GameViewModel`, and in every store, because the stores are shared
  singletons over one `UserDefaults`: branch deeper and you have two navigations
  writing one save file, which is the one state the flag could not then reverse.
- **Ruling 11** — the flag is a compile-time *condition* over a runtime `Bool`,
  never an `#if` wrapped around the call sites, and **both branches must compile
  in either configuration**. CI therefore builds a `world` matrix leg and a
  `classic` matrix leg on every push and pull request.

The stated purpose, in `WorldFlags.swift`'s own header, is this: *"the shipped
v1.2 navigation stays releasable on any day of the rebuild."* That sentence is
the thing this memo is really testing.

The flag is currently doing one other job, which is separate and still live:
`docs/PLAYTEST.md` §2a and §4 Q4 tell the owner to build with
`VESPER_CLASSIC_NAV` and pop for a minute in each build, back to back, to answer
whether the new input layer stole anything from the feel of a pop. That is a
real, unretired use, and §5 below takes it seriously.

---

## 2. What is classic-only, with numbers

### 2.1 Files that exist only for the classic navigation

| File | Lines | What it is |
| --- | ---: | --- |
| `Vesper/Views/ContentView.swift` | 207 | The v1.2 root: canvas, tap layer, HUD, top bar, three `.sheet` presentations |
| `Vesper/Views/JourneySheet.swift` | 277 | Points, records, next-unlock, the 100-cell collection, Drift |
| `Vesper/Views/PathSheet.swift` | 176 | The Path as stepping stones in a scroll view |
| `Vesper/Views/SettingsSheet.swift` | 93 | Three toggles, three stats, a credit line |
| `Vesper/Views/TapCatcherView.swift` | 34 | `UITapGestureRecognizer` over the canvas |
| **Total** | **787** | |

Nothing outside `ContentView` references any of these four other files, and
nothing outside `VesperApp` references `ContentView`.

### 2.2 The parts of shared files that are classic-only

- **`Vesper/Views/Cards.swift`** (247 lines) is **shared**. `FortuneWhisper`
  (lines 46–100) and `DoneCard` (lines 102–238) are what `WorldView` draws;
  `CardPalette` (241–247) serves `DoneCard`. Only **`FortuneCard`, lines 3–44
  (≈42 lines)**, is classic-only — `ContentView` is its sole call site. The file
  survives deletion; the struct does not.
- **`Vesper/Support/WorldFlags.swift`** (29 lines) exists only to express the
  choice. With one branch gone there is nothing left to choose.
- **`Vesper/VesperApp.swift`** — the `root` computed property and its comment
  (lines 27–41, ~15 lines) collapse to `WorldView()`.

### 2.3 What is *not* classic-only, and would be wrong to delete

Everything the classic path draws with, it borrows. `GameViewModel`,
`GameSimulation`, `SceneRenderer` (and through it `WeatherRenderer`,
`AnimalRendering`, the firework drawing), `SettingsStore`, `ProgressionStore`,
`MapStore`, `PopCatalog`, `Strings`, `HapticsEngine`, `PopSoundEngine` — all of
it is the world build's too. Two renderer parameters carry defaults *for*
the classic path (`SceneRenderer.draw`'s `moteParallax: 0` and
`horizon: .none`, both documented in their own comments as accommodations for
"the v1.2 field, which has no camera at all"), and one view-model property does
(`simActive` defaults to `true` "so v1.2's ContentView, which never writes it,
behaves exactly as it always has"). Those three defaults are sensible on their
own terms and can stay whatever happens; they are the entire footprint the
classic path leaves in shared code.

### 2.4 The size of the thing

**≈858 lines of source** would be deleted outright (787 + 42 + 29), plus ~15
trimmed from `VesperApp`. The app is 20,743 lines of Swift. The classic
navigation is **4.1% of the app** — small enough that "it costs space" is not
an argument, and large enough that "nobody will notice it" is not one either.

---

## 3. What it costs to keep

### 3.1 The CI cost is close to zero, and the CI *benefit* is zero

This is the part where the intuition and the evidence part company, so here are
the measurements.

The repository is **public**, so GitHub-hosted runner minutes — macOS included —
are not billed. The two matrix legs run in parallel, so the second leg adds no
wall-clock time to a run. Three recent runs, job by job:

| Run | `world` job | `classic` job |
| --- | ---: | ---: |
| #91 (`1afe11f`, main) | 4 m 32 s | 2 m 29 s |
| #90 (`ae14cc40`, this branch) | 3 m 57 s | 4 m 06 s |
| #88 (`92048f3`, main) | 2 m 38 s | 3 m 20 s |

Neither leg is systematically slower; the spread is simulator boot and runner
variance. So keeping the flag costs roughly **one extra macOS job of three to
four minutes per push, free of charge, off the critical path**. On the money and
the clock, this is not a reason to delete anything.

The benefit, however, is genuinely nil, and the reason is ruling 11 itself.
`VESPER_CLASSIC_NAV` appears in exactly **one `#if` in the whole source tree** —
`WorldFlags.swift` line 23. Because ruling 11 forbids wrapping the call sites,
**the `world` job already compiles `ContentView`, all three sheets,
`TapCatcherView` and `FortuneCard`**. There is no UI-test target (the project
has two targets: the app and a unit-test bundle), and no test in
`VesperTests/` reads `WorldFlags` or launches a root view. The `classic` job
therefore compiles an identical source set and runs an identical test bundle,
differing only in the value of one `Bool` that nothing under test observes.

The run history bears this out. Across all 92 CI runs — 52 success, 17 failure,
22 cancelled, 1 in flight — the matrix-era failures break down like this:

- **14 runs where both legs failed together.**
- **1 run (`32474325276`) where `classic` passed and `world` failed.**
- **0 runs where `classic` failed and `world` passed.**

In the entire life of the matrix, the classic configuration has never once
caught something the world configuration did not. It cannot, structurally. The
second leg is a duplicate that pays for itself with nothing.

### 3.2 The maintenance tax is small but real, and it is paid in the wrong place

Four commits have touched `Vesper/Views/` since `WorldView` landed
(`fc61ef9`, 2026-08-16):

| Commit | Date | What it did to `Views/` |
| --- | --- | --- |
| `8c91c32` | 08-17 | Rebuilt `DoneCard` (scrim removed, copy from `Strings`) and fixed `FortuneCard`'s VoiceOver label — shared file |
| `987081c` | 08-18 | Added `FortuneWhisper` beside `FortuneCard` — shared file |
| `d5ef933` | 08-19 | Gave `DoneCard` its `verse` parameter — shared file |
| `62a3f50` | 08-21 | **Copied the balloon-animal accessibility block from `WorldView` into `ContentView`** — twelve lines, classic-only |

Three of the four are `Cards.swift`, which is shared and would still be edited
after a deletion. Only `62a3f50` is the tax proper: a twelve-line accessibility
element written twice, once for each navigation, because the field's VoiceOver
label is the only place a balloon animal can be named.

Twelve lines in five months is not a burden. What the tax actually reveals is
which way the leak runs — and §4 is about the many places where nobody paid it.

### 3.3 Where the two navigations have already diverged

This is the substantive cost. The classic path is not a frozen v1.2; it is a
half-updated v1.2 that has been drifting for two weeks while CI stayed green,
because CI cannot see any of it.

**Voice and copy**

1. **`DETONATED`.** `ContentView` line 109 still renders the counter caption
   `Text("DETONATED")` in tracked capitals. `Strings.swift`'s header names this
   word as the specific thing the catalog exists to keep out of the owner's
   hands; `StringsTests` has a test called
   `testDetonatedIsGoneFromTheCatalog`. But that test enumerates
   `Strings.allStrings` — the *catalog* — and `ContentView` never joined the
   catalog (the header says so: the sheets and cards were deferred as "a merge
   war against three concurrent view rewrites"). So the guardrail passes on
   every commit while the word is still on screen in one of the two builds CI
   certifies.
2. **`TAP AN ORB TO BLOW IT UP`.** `ContentView` line 158, tracked capitals,
   imperative. The world says `Strings.firstHint` — "tap an orb. let it go."
   `docs/gdd/03_GAME_DESIGN.md` §72 lists both replacements together as one copy
   pass; only half of it was applied.
3. **Title Case chrome.** "Settings", "The Journey", "The Path", "Sound",
   "Haptics", "Drift" — the sheets are inline literals in sentence case, against
   07 §2's lowercase-calm rule that `StringsTests` enforces for everything that
   made it into the catalog.
4. **`PathSheet` states something that is no longer true.** Its footer reads
   "the road behind fades after three days", and its file header says the road
   "dissolves after a few days". W08 (`7069dbb`, 2026-08-17) removed the pruning
   pass: nothing is ever deleted, and settling is derived at draw time. The
   caption has been wrong for twelve days. `docs/RELEASE_v1.3.md` §4 already
   flags this exact sentence as one of the reasons the v1.2 screenshots
   misrepresent the build — it just does not note that the sentence is still in
   the binary.

**Layout and behaviour**

5. **The notes stack.** `ContentView` lines 123–151 render `chainNote`,
   `pathNote` and `unlockNote` as three independent `if let`s, so all three can
   be on screen at once, under a 62 pt counter, over a running `pop points`
   line. `docs/pop_points.md` §3 specifies "One HUD slot, rarest first … never
   two at once", and `WorldView` lines 800–818 implement exactly that as an
   `if / else if / else if` chain. The classic HUD can show five stacked
   elements where the world shows two.
6. **The running points line.** `ContentView` lines 113–121 still draw
   `"\(sessionPoints) pop points"` under the counter. `pop_points.md` §3 records
   that this line "shipped, and it was removed when the top of the field was
   decluttered."
7. **The fortune is still a card.** `ContentView` line 56 presents
   `FortuneCard` — a bordered, shadowed, centre-screen panel that must be
   dismissed. `FortuneWhisper`'s own doc comment records why it replaced it:
   *"the text pop up is annoying"* — the owner, after his first session. The
   classic build still does the thing the owner asked to have removed.
8. **No closing verse.** `DoneCard` gained a `verse` parameter in `d5ef933`
   with a default of `""`. `WorldView` passes `game.closingVerse`;
   `ContentView` does not. The verse never appears in the classic build.
9. **Reduce Motion is not honoured on the counter.** `WorldView` guards the
   per-pop counter spring with `guard !reduceMotion` (barrier condition 11);
   `ContentView`'s `onChange(of: model.count)` springs unconditionally.
10. **Fog has no hole.** `GameViewModel.pointerMoved(to:)` — which sets
    `sim.pointer`, which is what `WeatherRenderer.drawFog` thins around a
    finger — is called from `WorldView` only. Weather otherwise renders fine in
    classic, because it lives in the shared `SceneRenderer`; but the single most
    distinctive image in the release (`RELEASE_v1.3.md` §4, screenshot 2) does
    not happen there.
11. **`PathSheet` does not window its history.** `SkyView` draws the map
    "windowed by the scroll's `maximumHistory`" (2,600 pt). `PathSheet` lays out
    every stone the store has ever kept, at 128 pt per generation, and resolves
    each road with `map.stones.first(where:)` inside a loop over all stones —
    O(n²) in a `Canvas` whose height grows without bound. Written when the map
    pruned itself after three days; W08 removed the pruning. I have not measured
    this on a device and cannot say at what map size it becomes visible, but the
    shape of it is not in doubt.
12. **Dynamic Type.** `JournalView` uses semantic fonts (`.body`, `.caption`,
    `.title3`) and re-lays out at accessibility sizes; every font in the three
    sheets and in `ContentView` is a fixed `size:`. Someone who sets large text
    gets no larger text anywhere in the classic navigation.

None of these twelve are compile errors. That is the point: the configuration
CI certifies twice a day cannot fail on any of them.

---

## 4. Is the classic build actually still releasable?

No. Not today.

The twelve items above are, individually, the kind of thing a shipping app
survives. There is a thirteenth that it does not.

`GameViewModel.scheduleOnward()` runs unconditionally whenever a field is
cleared — it is in the view model, not in the world layer, and the view model is
shared. It does two things on a timer:

```
t + 0.65 s   doneRevealDelay    completion chime, done card appears
t + 3.40 s   onwardToSkyDelay   skyRequest += 1
t + 5.60 s   onwardInSkyPause   map.setActive(next.id) ; restart()
```

In the world build this is the onward sequence the owner asked for: the camera
rises to the sky, the roads ahead light up, and — only if there is exactly one
road — she is carried onto the next stone and back down to a new field. Every
step of it is *visible*, because `skyRequest` and `fieldRequest` are observed by
`WorldView`, which moves the camera in response.

In the classic build, `skyRequest` is observed by nothing. `fieldRequest` is
observed by nothing. But `scheduleStepOnward` still fires. So the classic build
does this: the field goes quiet, the chime plays, the done card fades in — and
**5.6 seconds later, with no motion, no explanation and no way to see it, the
active stone silently changes and the field restarts.** The done card is
animated away by `restart()`. The `again?` she was reading vanishes under her
thumb. She is now standing on a stone she never chose, and the only screen that
could have shown her that is a sheet that is closed.

A single road ahead is the common case — `MapStore.recordClear` makes one to
three children, and the copy distinguishes "the path continues" (one) from "the
path forks" (more). So this happens on most clears.

The onward sequence landed in `a782a970` on 2026-08-21. The classic
configuration has been building green, twice per push, for the eight days since.

That is the honest answer to the flag's stated purpose. `WorldFlags.swift` says
the v1.2 navigation "stays releasable on any day of the rebuild." It has not
been releasable since 2026-08-21, and the mechanism that was supposed to
guarantee it — a compiler that checks the other branch as often as it checks
this one — was never able to detect the difference between a navigation that
works and one that throws the player off a cliff five seconds after she
finishes, because compiling is not the same as running and the flag's own
architecture guarantees both configurations compile identically.

**The flag has not been protecting a fallback. It has been protecting the
belief that there is one.**

---

## 5. What it costs to delete

Four real losses. Two of them are cheap to mitigate; one is not a loss at all
once you look at it; one is a genuine orphan.

### 5.1 The A/B comparison, and the playtest that still wants it

`docs/PLAYTEST.md` §4 Q4 — "does a pop still land?" — is a back-to-back test:
build classic, pop for a minute, build world, pop for a minute, and say in plain
words whether the pop happens the instant your finger lands. It is a good test
and it is not yet answered.

Two things soften this. First, the pop *itself* has moved on: PLAYTEST's own
scope note records that after it was written, each of the ten families got its
own voice, its own haptic rhythm and its own burst gesture, so "a pop should
feel different from v1.2, and only a difference in the tap itself … is a
navigation finding." The classic build is no longer a clean control for anything
except tap latency. Second, tap latency is the one part of Q4 that is already
measured in CI and does not need a build:
`VesperTests/TapBaselineTests.swift` computes the v1.2 tap-success rate from the
v1.2 hit-test rule and pins it; `WorldRegressionTests` (W20) runs the world's
arbiter against that same control and asserts the two resolve the same touches.
Those tests do not need `ContentView` and would survive its deletion untouched.

What genuinely goes is the *subjective* comparison — the feeling in the thumb.
If the owner wants that, he needs the classic build before it is deleted, not
after. **That is the one argument for waiting rather than for keeping.**

### 5.2 The fallback if One World proves wrong on device

This is the loss the flag was built for, and §4 has established that it is not
currently available. It could be made available again: the onward defect is a
few lines (a `guard` in `scheduleStepOnward`, or a call-site check), and the
twelve divergences are each a small fix. But that is *restoring* a fallback, not
keeping one — and it is worth being precise about what the restored fallback
would be worth. Reverting to the classic navigation would ship a build with
no sky (the constellation, the settled roads, the scrollable history all live in
`SkyView`), no journal, a fortune the owner asked to have removed, `DETONATED`
on the counter, and a map screen whose footer describes a behaviour the app no
longer has. It would not be v1.2 either — the stores, the pops, the weather and
the animals have all moved. It would be a third thing, untested on a device, and
building it into something shippable is days of work, not an afternoon.

A shipped App Store release also has a cheaper fallback than a compile flag: the
v1.2 binary is already on the store, and phased release with the ability to halt
is the ordinary mechanism for "this was wrong."

### 5.3 Something the classic sheets do that the journal does not

Yes — one thing, and the review that flagged it was right.

`JourneySheet.nextUnlockBlock` (lines 119–164) draws a small panel headed
**"somewhere ahead"**: the name of the nearest un-owned pop, its unlock hint,
and — when the unlock is points-based — a `ProgressView` showing how far along
she is toward it. The sort prefers the nearest points threshold and falls back
to catalog order for condition unlocks.

`JournalView` has no equivalent. Its collection page shows a count
("37 of 100"), and a locked cell answers a press with a kind hint pinned at the
foot, but there is nothing that volunteers *what is next* and nothing anywhere
in the world build that draws progress toward a threshold. Verified by reading
all 722 lines of `JournalView.swift`: no "ahead", no `nextUnlock`, no
`ProgressView`.

Whether that is a loss is a design question, not an engineering one, and it cuts
both ways. A progress bar toward a reward is the most game-shaped object either
navigation has ever drawn, and guardrail 1 asks for numbers that only accrue and
unlocks reached through ordinary play. "Somewhere ahead" is affirming in its
copy — but a bar filling toward a goal is the grammar of a goal. It may have
been left out of the journal on purpose. **I could not find a document that says
either way**, and there is no note in `04_NAVIGATION_UX.md` or
`pop_progression.md` retiring it. If it was dropped by accident, deleting
`JourneySheet` is the moment it becomes irrecoverable without someone
remembering it existed — hence the task in §7 that captures the design before
the code goes.

I looked for other orphans and found none. Everything else in the three sheets
has a journal equivalent that is equal or better: points, the four records, the
100-cell grid with locked hints, Drift, featuring a pop, sound, haptics, point
whispers. The journal adds `hush` (one tap, both senses), `begin again` with an
arming step, pinned hints, VoiceOver values and custom page actions, and Dynamic
Type. The sheets add a ✕ button and a grabber.

### 5.4 The comments

`ContentView`'s tap-layer comment ("Kept separate from the TimelineView so it
isn't rebuilt every frame — that rebuild was cancelling some taps
mid-recognition") is a v1.2 lesson written down at the moment it was learned.
`WorldInputView.swift` already cites it twice and `WorldView.swift` line 724
cites it again, so the knowledge survives the file. Worth noticing anyway,
because it is the kind of thing a deletion loses quietly.

---

## 6. The middle option: keep the code, drop it from CI

Delete the `classic` matrix leg; leave `Vesper/Views/`, `WorldFlags` and the
compilation condition in the tree.

This is the worst of the three options, and `WorldFlags.swift`'s own header says
why in one sentence: *"an unbuilt configuration rots within days."*

But the sharper objection is that the middle option **saves nothing and costs
the one thing the second leg does buy.** Recall §3.1: the `world` leg already
compiles `ContentView` and all three sheets, because ruling 11 forbids
`#if`-ing the call sites. So the classic leg's only marginal coverage is the
compilation of one `Bool`. Dropping it therefore does not stop the classic
*code* from being compiled — that continues regardless — and it does not save
money on a public repository or wall-clock time on a parallel matrix.

What it does do is remove the one place where a reader is reminded, twice per
push, that the second navigation exists. The code would stay, compiled but
uncertified, unrunnable without hand-editing build settings, drifting further
each week — and with the CI leg gone, nobody would have any occasion to think
about it at all. That is how 858 lines become 858 lines nobody dares touch.

The middle option is only defensible as a **deliberately dated waypoint**: drop
the leg, and open a task to delete the code by a named date. If that is the
choice, put the date in `docs/RELEASE_v1.3.md` §9 so it is attached to something
that gets read.

---

## 7. What deletion would involve

Concretely, as a task list. It is mostly `git rm`. The one part that needs
judgement is the first task, and it is a design question, not an engineering
one.

**Do first — capture what is only in the code**

0. **Decide the fate of "somewhere ahead" (§5.3) before deleting
   `JourneySheet.swift`.** Either (a) accept it as deliberately retired and note
   the decision in `docs/pop_progression.md`, or (b) write it up — the block's
   copy, its sort rule, its progress bar — as a journal task, with a note on
   whether the bar survives guardrail 1. Do not silently drop it.

**Source**

1. `git rm Vesper/Views/ContentView.swift Vesper/Views/JourneySheet.swift
   Vesper/Views/PathSheet.swift Vesper/Views/SettingsSheet.swift
   Vesper/Views/TapCatcherView.swift` (787 lines). `Vesper/` is a
   `PBXFileSystemSynchronizedRootGroup`, so **no `project.pbxproj` edit is
   needed** — the owner's rule about not letting an agent touch the project file
   is not in play here.
2. In `Vesper/Views/Cards.swift`, delete `FortuneCard` and its `// MARK: -
   Fortune card` heading (lines 3–44). Keep `FortuneWhisper`, `DoneCard` and
   `CardPalette` exactly as they are — they are the world's. Consider moving the
   file to `Vesper/World/Cards.swift`, since `Views/` is then empty; this is
   optional and a synchronized group makes it free.
3. `git rm Vesper/Support/WorldFlags.swift` (29 lines).
4. In `Vesper/VesperApp.swift`, replace the `root` property and its comment
   (lines 27–41) with `WorldView()` inline in the `WindowGroup`, and drop
   `AnyView`. Keep the `scenePhase` handling and the W08 note untouched.

**CI**

5. In `.github/workflows/ci.yml`: remove the `strategy.matrix`, the
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS` line from the `xcodebuild` invocation,
   and the header comment about the two configurations. Rename the job from
   `Build & test (${{ matrix.config }})` to `Build & test`. Everything else —
   the simulator-discovery step, the timeout, the concurrency group — stays.
   **Check whether `Build & test (world)` is a required status check on `main`
   before merging**, or the rename will block the PR that performs it. That is
   the only step in this list that can go wrong in a way that is annoying to
   undo.

**Tests**

6. Nothing to do. **No test in `VesperTests/` references `ContentView`,
   `TapCatcherView`, `SettingsSheet`, `JourneySheet`, `PathSheet`, `FortuneCard`
   or `WorldFlags`** — verified by grep across all 34 suites and 18,887 lines.
   The many hits for the word "classic" are `PopCatalog.classic`, pop #001,
   which is unrelated and stays. `TapBaselineTests` and `WorldRegressionTests`
   reason about the *v1.2 tap rule* arithmetically and never touch the v1.2
   views; they are unaffected.

**Docs — where `VESPER_CLASSIC_NAV` is named and would become a lie**

7. `CLAUDE.md`: the `Vesper/Views/` block in the repository layout (lines
   103–107), the `VesperApp.swift` line (55), the `TapCatcherView` sentence in
   the touch-handling architecture rule (~164), the `WorldFlags` mention in the
   `Support/` block (101), and the Phase 0 paragraph that says CI still builds
   the v1.2 screens (~196).
8. `docs/PLAYTEST.md`: §2a (the whole "to build the old v1.2 app" recipe, lines
   112–133), §4 Q4 (the back-to-back feel test — it needs rewriting as a
   single-build question, or retiring with a note saying why), and the shared
   save-file warning in §6 (~531), which stops being true when there is one
   build.
9. `docs/e2e_walkthrough.md` §15: drop the first accepted rough edge (line 301).
10. `docs/RELEASE_v1.3.md` §1: the sentence "The classic navigation still
    compiles behind `VESPER_CLASSIC_NAV` and is unreachable in the shipping
    build."
11. `docs/pop_map.md`: the italic header note pointing at `Views/PathSheet.swift`
    as the v1.2 map screen.
12. `docs/gdd/DELIVERY_ROADMAP.md`: **do not rewrite it.** It is the record of a
    plan that was executed, and rulings 10 and 11 were correct decisions for the
    period they governed. Add one dated line to its head noting that the flag
    was retired after Phase 0, and leave the rulings as they stand.
13. `docs/gdd/00_MASTER_PLAN.md` and `04_NAVIGATION_UX.md` mention `DETONATED`
    and the old top bar as *problems being solved*. Those are historical and
    correct. Leave them.

**Finally**

14. Delete this memo, or move its §4 finding into `docs/RELEASE_v1.3.md` §9 as a
    note on why the flag went. A decision memo outlives its decision by about a
    week.

An agent can do 1–6 and 9–11 mechanically. Items 0, 8 and 12 want the owner or a
careful human.

---

## 8. Recommendation

**Delete it. Before the v1.3 submission, and after one evening with a phone.**

The order matters, so the recommendation is really two things:

**First, if the owner still wants PLAYTEST Q4 — the feel of a pop, back to back
— take that evening now, while the classic build still exists.** It is the one
thing deletion forecloses that cannot be recovered afterwards. It costs an hour.
If he does not want it, say so and skip straight to the deletion.

**Then delete it,** for these reasons in this order:

1. **It is not what it claims to be.** The flag's entire justification is a
   sentence in its own header: the v1.2 navigation stays releasable on any day.
   Since 2026-08-21 the classic build has silently thrown the player onto a
   different stone five seconds after she clears a field (§4). It has not been
   releasable for eight days, and CI certified it green through every one of
   them. A safety net that has a hole in it and reports that it does not is
   worse than no net, because it is the one you plan around.
2. **The mechanism could never have worked.** Ruling 11 says both branches must
   compile in either configuration — which means the `world` job already
   compiles every classic file, which means the `classic` job's only unique
   coverage is one `Bool` no test reads (§3.1). In 92 runs the classic leg has
   never once failed alone. It was structurally incapable of detecting any of
   the thirteen divergences, all of which are behavioural. The flag protects the
   compiler's opinion of code nobody runs.
3. **The divergences are the real cost, and they are the kind that embarrass.**
   `DETONATED` and "TAP AN ORB TO BLOW IT UP" are still in the shipping binary
   — unreachable, but there — in a product whose string catalog exists
   specifically to keep the first of those words away from the owner. `PathSheet`
   still tells the player the road behind fades after three days, twelve days
   after the release decided that nothing is ever deleted. These are not
   maintenance costs; they are the app carrying around a copy of itself that
   says things it has decided not to say.
4. **The fallback story has a better answer.** v1.2 is on the App Store. Phased
   release exists. A compile flag is the wrong instrument for "what if the new
   navigation is wrong", and by the time it were needed, restoring the classic
   build to shippable would take days and produce a third thing that is neither
   v1.2 nor v1.3 (§5.2).
5. **It is cheap and it is safe.** No test references any of it. No
   `project.pbxproj` edit. One CI file, five files deleted, one struct excised,
   one property inlined, six documents corrected. The only step that can bite is
   the required-status-check rename (§7 task 5).

**The strongest argument the other way**, and it deserves stating plainly: the
release is not out yet. The device pass in `RELEASE_v1.3.md` §5 has not been
run; the screenshots have not been recaptured; there is an unsettled
swipe-direction discrepancy in §7. This is exactly the period a fallback is for,
and deleting the alternative the week before a submission is the sort of tidying
that reads as confidence right up until it doesn't. I weigh it below the other
five because the fallback in question does not presently work — but if the owner
would rather hold a broken net than none at all until the device pass is done,
that is a defensible position, and the cost of waiting two weeks is one extra
free CI job per push. In that case take the middle option **with a date on it**
(§6), not the middle option on its own.

What I would not do is nothing. The flag is currently making a promise the code
does not keep, and the least acceptable outcome is shipping v1.3 with that
promise still written in `WorldFlags.swift`'s header.

---

## 9. Where the evidence is thin

Stated plainly, so none of it reads as more certain than it is.

- **The `PathSheet` scaling concern (§3.3, item 11)** is read from the source,
  not measured. I do not know at what map size it becomes perceptible, and it
  may never matter on a real device.
- **Whether "somewhere ahead" was dropped on purpose (§5.3)** is genuinely
  unknown. I found no document that retires it and no document that asks for it
  in the journal. Somebody who was there may know in one sentence.
- **I did not build or run either configuration.** There is no Linux toolchain
  for this project. Everything behavioural above — the onward defect especially
  — is read from the source and the timings in `GameConfig`, and traced through
  the observers in `WorldView` that `ContentView` lacks. The reasoning is
  simple and I am confident in it, but it has not been watched happening on a
  phone. **If one thing in this memo gets verified on a device before the
  decision, make it §4:** clear a field in a `VESPER_CLASSIC_NAV` build, then
  watch the done card for ten seconds without touching anything.
- **CI failure attribution (§3.1)** covers the 15 matrix-era failures and one
  in-flight run; I read per-job conclusions for all of them. Cancelled runs
  (22 of 92, nearly all `cancel-in-progress` supersessions) were not
  attributed, since a cancellation says nothing about either configuration.
- **The maintenance-tax survey (§3.2)** covers commits that touched
  `Vesper/Views/`. A change that *should* have touched it and did not leaves no
  trace in the log; §3.3's list of divergences is the closest thing to a measure
  of those, and it is a floor rather than a total. I read `ContentView`,
  `WorldView`'s HUD and card layers, all three sheets and all of `JournalView`
  to build it, but I will not claim it is exhaustive.
