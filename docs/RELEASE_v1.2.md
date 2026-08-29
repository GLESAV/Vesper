# v1.2 Release & Review Prep — "The Feel & Collection Update"

> **This is the record of the v1.2 submission, and v1.2 is not the build in the
> repository any more.** It was written against the *classic* navigation — a
> top bar of icons, the Path as a sheet, the Journey as another sheet — all of
> which now compiles only under `VESPER_CLASSIC_NAV`. `MARKETING_VERSION` has
> not moved off 1.2 through the One World rebuild, so the version number no
> longer distinguishes the two builds.
>
> Keep this page for what it records: the screenshot provenance (§1), the
> submission mechanics (§3), and the privacy answers, all of which are still
> accurate. **Do not run §2 or paste §4 for a build off `main`** — §2 tests
> screens that are gone and describes the map as fading rather than settling,
> and §4 tells a reviewer to look for two buttons that no longer exist.
> `docs/e2e_walkthrough.md` is the device pass for the current build; a release
> of that build needs a prep page of its own, and this is not it.

Everything needed to take the `claude/vesper-pop-aaa-optimization-2n5oc2` branch
from merged to App Store review. Items marked ⚙ are done on this branch; items
marked 🖐 need a human with hardware/credentials.

## 1. State of the build

- ⚙ CI green on head commit: build + 4 test suites (simulation, catalog,
  progression, map) on iPhone 16 simulator
  *(as of v1.2. `VesperTests` now holds well over thirty suites, and CI builds
  and tests both navigation configurations on every PR.)*
- ⚙ `MARKETING_VERSION = 1.2`, `CURRENT_PROJECT_VERSION = 1`
  (🖐 bump build number per TestFlight upload)
- ⚙ Release notes, description, promotional text updated for v1.2
- ⚙ Screenshots: 5-scene narrative per size (play → path → journey → fortune →
  done), 6.9" 1320×2868 and 13" 2064×2752, in `fastlane/screenshots/en-US/`

### About the screenshots

They were composed with `fastlane/screenshots/harness/` (compose.html +
capture.js, headless Chromium) porting the real renderer math and catalog
palette. They are faithful drafts — **type is rendered with Linux fallback
fonts, not New York/SF**. Before submitting, either:

1. accept them as-is (layout, colors, and geometry match the app), or
2. 🖐 re-capture on a simulator for pixel-perfect type: run the app with the
   same composed states and `xcrun simctl io booted screenshot`, keeping the
   same filenames.

## 2. 🖐 Manual device pass (blocking) — *as run for v1.2; superseded*

Run the full checklist in `docs/BUILD_PLAN.md` §5 on the oldest supported
iPhone and a ProMotion device, plus these v1.2-specific checks:

1. First launch (fresh install): field seeds with classic pops only; first
   unlock ("Gloaming") arrives within the first session or two.
2. Upgrade path: install v1.0 build, play a little, then update — lifetime
   pops/fields carry over into the Journey.
3. The Path: clear the first stone → "the path continues/forks" note; new
   stones playable next field; kill and relaunch → map persists; set device
   clock +4 days → road behind fades, current stone + roads ahead remain.
4. Visitors: a stone hosting a locked pop plays it for that field only; the
   Journey still shows it locked.
5. Points: whispers can be toggled off in Settings and points still accrue;
   chain multiplier matches the "chain of N" whisper.
6. Audio: rapid pops across two different families (different sound profiles)
   with no crackle; field seed causes no hitch (buffer banks pre-rendered).
7. VoiceOver on the Path and Journey screens: every stone/cell labeled.

## 3. 🖐 Submission steps

```sh
# 1. Archive + upload build (Xcode Organizer or fastlane gym/pilot)
# 2. Push metadata + screenshots:
bundle exec fastlane deliver
# 3. In App Store Connect: attach build, confirm privacy answers unchanged
#    ("Data Not Collected"), submit.
```

## 4. App Review notes as submitted for v1.2 — *do not reuse verbatim*

> Vesper is a calm, offline stress-relief game. No account or sign-in exists;
> the app makes no network calls and collects no data. All progression
> (pop points, unlocks, the map) lives in UserDefaults on device.
> To see the new features: tap the dotted-path button (top left) for The Path
> map; tap the sparkles button (top right) for the Journey collection.
> Points and unlocks are purely affirming — nothing is purchasable, nothing
> expires, and there is no failure state.

## 5. Post-release

- Tag the release commit `v1.2`
- Watch MetricKit / crash reports in Xcode Organizer for a week (no
  third-party analytics exist, by design)
- M2 candidates live in `docs/ROADMAP.md`
