# v1.3 Release & Review Prep — "One World"

Everything needed to take this branch from merged to App Store review.
Items marked ⚙ are done in the repo; items marked 🖐 need a human with
hardware, Xcode, or App Store Connect credentials.

Shape and conventions follow `docs/RELEASE_v1.2.md`.

## 1. What is in the release

Everything that has landed on `main` since v1.2. Verified against
`docs/e2e_walkthrough.md`, which describes current behaviour.

- **One World navigation.** Sky / field / journal on a single vertical axis,
  tracked 1:1 under the finger, adjacent places 0.75 screens apart. The v1.2
  modal sheets and the top bar of icon buttons are gone. The classic
  navigation still compiles behind `VESPER_CLASSIC_NAV` and is unreachable in
  the shipping build.
- **The sky.** The Path drawn as a constellation with family-shaped gems,
  walked/unwalked roads, auto-onward after a clear, and a scrollable history
  (~20 generations) that glides and can be caught mid-flight.
- **Weather.** Six airs from the first field — clear, rain, warm, snow, fog,
  storm — deterministic per stone. Rain carries the orbs, snow settles and
  melts, fog thins around a finger. Never changes hittability.
- **Balloon animals.** Eight silhouettes, stage ≥ 3, shy for ~25 s, 2–3 taps,
  ×2.5 points on the final pop.
- **Field mechanics.** Splitters (stage 2), drifters (3), generators (4),
  deeper splits (5), two generators (6), plus the depth/reserve system.
- **Fireworks.** Stage ≥ 2 on alternating stones. Rope fuses with real
  physics, 14 break patterns, entirely optional — an unlit shell never gates
  a clear.
- **The journal.** Three pages (the evening / the collection / the quiet
  things), `hush`, feature-a-pop and `drift`, the 100-cell grid with kind
  hints on locked cells and three secrets.
- **Progression.** 100 pops in ten families; pop points that only accrue.
- **Quality.** ProMotion parity for weather/fireworks/fuses, Reduce Motion
  honoured across camera, weather, animals, sky and fireworks, VoiceOver
  direct-touch field, corrupt-map bytes preserved rather than overwritten,
  render loop pauses on a cleared display or weather field.

## 2. Version and build numbers

**🖐 Owner's change — do not let an agent edit `project.pbxproj`.**

| Setting | Current in repo | Recommended for this release |
| --- | --- | --- |
| `MARKETING_VERSION` (Vesper target, Debug + Release) | `1.2` | `1.3` |
| `CURRENT_PROJECT_VERSION` (Vesper target, Debug + Release) | `1` | `2`, then +1 per upload |
| `MARKETING_VERSION` (VesperTests target) | `1.0` | `1.3` (cosmetic; keeps the two targets from drifting further) |
| `IPHONEOS_DEPLOYMENT_TARGET` | `18.5` | unchanged |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.gregorysavage.vesper` | unchanged |
| `TARGETED_DEVICE_FAMILY` | `1,2` (iPhone + iPad) | unchanged |
| `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` | `NO` | unchanged — correct, and it keeps the export-compliance question off the submission form |

Why build `2` and not `1`: v1.2 shipped at build `1`, and any TestFlight
upload for the 1.2 train already burned that number. Build numbers are
cheapest when they only ever go up. Bump `CURRENT_PROJECT_VERSION` again for
every subsequent upload of 1.3.

**Open question for the owner (see §7):** whether this is 1.3 or 2.0. It is
a navigation rebuild plus five new systems; the argument for 2.0 is that it
is the "One World" release the `docs/gdd/` plan is named for.

## 3. Metadata

- ⚙ `description.txt` rewritten for the current build (3,119 / 4,000 chars).
- ⚙ `release_notes.txt` rewritten, every claim grounded in
  `docs/e2e_walkthrough.md` (2,219 / 4,000 chars).
- ⚙ `promotional_text.txt` (166 / 170), `subtitle.txt` (28 / 30),
  `keywords.txt` (99 / 100), `name.txt` (10 / 30) — all within limits.
- ⚙ URLs, copyright and category files reviewed and left as they are.
- ⚙ `web/vesper-privacy.html` updated: new date, a specific list of what is
  kept on device, the zero-dependency claim, and an honest note about Apple's
  own opt-in crash sharing.
- 🖐 Confirm in App Store Connect that the privacy answers are still
  **Data Not Collected** and that the age rating questionnaire is unchanged
  (see §6).

## 4. Screenshots — must be recaptured (blocking)

The ten files in `fastlane/screenshots/en-US/` are v1.2 and are now actively
wrong: they show the deleted top bar of four icon buttons, the counter
labelled `DETONATED` (a word `Strings.swift` exists specifically to keep out
of the owner's hands), `GO AGAIN` instead of `again?`, the old done-card copy
under a scrim, the two modal sheets titled "The Journey" and "The Path" with
grabbers and ✕ buttons, and the caption "the road behind fades after three
days" — which is no longer true (nothing is ever deleted; §12 of the
walkthrough). Shipping them would misrepresent the build.

Sizes to deliver, unchanged: **6.9" iPhone 1320×2868** and **13" iPad
2064×2752**, up to 10 per size.

The proposed eight, in store order — the first three are what most people
will ever see:

| # | Scene | Why it earns the slot |
| --- | --- | --- |
| 1 | The field in **rain**, orbs mid-drift, one pop bursting, the `the sky` and `your journal` whispers visible at the edges | Says what the game is and that it is one place, not a menu |
| 2 | **Fog**, with a hole thinned around a finger | The single most distinctive still image in the build; nothing else on the shelf looks like it |
| 3 | **The sky** — the constellation, a fork lit, walked roads solid and old roads settled | Shows the scope: this is a world, and it keeps everything |
| 4 | A **balloon animal** on the field, keeping to the edge | The most charming thing in the release, and the one a browsing player will remember |
| 5 | A **firework** mid-break, with a second shell waiting on its rope fuse | Shows the release has spectacle without pressure |
| 6 | The journal, **the collection** page — the 100-cell grid, some cells locked, a hint pinned at the foot | Communicates "a hundred pops, given not sold" better than a sentence can |
| 7 | The **done card** — "the field is quiet now.", a verse, the counts, `again?`, no scrim, the world alive behind it | The emotional close, and proof there is no fail state |
| 8 | A **fortune** drifting unbordered over the field | The small human moment the app is loved for |

Deliberately not included: the journal's *quiet things* page (a settings list
sells nothing) and a mid-travel camera frame (unreadable as a still).

How to capture:

1. `fastlane/screenshots/harness/compose.html` + `capture.js` (headless
   Chromium, exact store pixel sizes) is still the fastest route, **but it
   composes the v1.2 UI** — its `SCENES` list is `play|path|journey|fortune|
   done` and it draws the top bar, the sheets and the scrim. It needs new
   scene builders for rain, fog, sky, animal, firework, collection, done and
   fortune before it is usable for 1.3. Its type is also Linux fallback
   fonts, not New York/SF.
2. 🖐 Preferred for this release: capture on a simulator, where the type,
   weather and animals are the real thing —
   `xcrun simctl io booted screenshot`, iPhone 16 Pro Max (6.9") and iPad Pro
   13". Keep the existing filename convention (`6.9_01_…`, `13_01_…`) so
   `deliver` picks them up in order.

Reaching the scenes on a fresh install: stage = fields cleared ÷ 3. Nine
cleared fields gets fireworks *and* animals. Replaying one stone with
`again?` counts, and each replay doubles then triples the field, so a single
stone can carry the whole capture session.

## 5. 🖐 Manual device pass (blocking)

Run `docs/e2e_walkthrough.md` end to end — it is the checklist for this
release and supersedes the v1.2-specific list. Minimum coverage:

1. One ProMotion iPhone (§13 has fixes specific to 120 Hz) and one iPad
   (no haptics — sound alone must carry the pop).
2. A genuinely fresh install for §1 and §11's unlock ladder, and a session
   with ≥ 9 cleared fields for §8 and §10.
3. The multi-day check in §12: device clock +4 days, confirm roads settle and
   **nothing disappears**, then set the clock back and confirm it un-settles.
4. Upgrade path: install the shipping 1.2 build, play, then update — lifetime
   pops, fields, fortunes, the collection and the map all carry over into the
   journal, and the first launch lands in the field rather than a sheet.
5. Reduce Motion flipped mid-session, VoiceOver on all three places, Dynamic
   Type at an accessibility size, Split View on iPad.
6. Settings → Cellular / Battery: zero data for Vesper Pop, and no drain
   sitting on a cleared field.

## 6. App Review notes (paste into the review notes field)

> Vesper Pop is a calm, offline stress-relief game. There is no account, no
> sign-in, no in-app purchase, no advertising, and no network use of any
> kind — the app makes no outbound connections and collects nothing. All
> progress (pop points, unlocked pops, the map of stones) is stored in
> UserDefaults on the device. No demo account is needed or possible.
>
> HOW TO PLAY: the app opens straight into the field. Touch an orb and it
> pops. Clear every orb and a completion card appears; "again?" starts a new
> field. There is no timer, no score to beat, no lives and no fail state —
> the counter only ever counts up, and nothing is lost by stopping.
>
> HOW TO NAVIGATE: the whole app is one vertical world — the sky above the
> field, the journal below it. The simplest way to move is to tap the words:
> "the sky" at the top of the field takes you to a map of every field you
> have cleared (tap any star to play that field), and "your journal" at the
> foot takes you to three pages — your records, your collection of pops, and
> the settings (sound, haptics, whispers, and "begin this field again"). A
> vertical swipe travels the same way, and "the field" brings you back from
> either place. Turn journal pages with the words at the foot. There are no
> buttons or menus, by design.
>
> SEEING EVERYTHING: content arrives with ordinary play rather than being
> locked or sold, so a short session shows only the early game. To reach it
> faster, clear the same field repeatedly with "again?" — each replay is a
> larger field and still counts. After roughly nine cleared fields (about ten
> minutes) fields begin to include fireworks — tap a shell or its hanging
> fuse to light it — and, on alternating fields, a balloon animal, which is
> shy at first and takes two or three taps. Weather (rain, snow, fog, storm)
> appears from the very first field and varies per field.
>
> ACCESSIBILITY: with VoiceOver on, the field is a single direct-touch
> region — touching an orb pops it, with no double-tap. Sky stars and journal
> rows are ordinary buttons. Reduce Motion is honoured throughout.
>
> Contact for anything at all: gregory.leonardo.savage@gmail.com.

## 7. Risks and open questions

Detail and reasoning live with the release report; the short list:

- **Age rating.** Nothing in the build implies anything above 4+. Confirm the
  questionnaire is untouched, and note that the fortunes are gentle
  first-person encouragement, not medical advice.
- **Health-adjacent keywords.** "stress relief" and "anti stress" are kept
  because they describe the genre; no metadata anywhere claims a
  therapeutic or medical effect, and `anxiety` was dropped from the keywords
  to keep it that way.
- **Screenshots.** Blocking, §4.
- **Open for the owner:** 1.3 vs 2.0; whether the App Store Connect copyright
  field should read "Kate Wu" or the publishing entity in the privacy page's
  footer; whether the second sub-category stays `GAMES_PUZZLE`.

## 8. 🖐 Submission steps

```sh
# 1. Set MARKETING_VERSION = 1.3 and CURRENT_PROJECT_VERSION = 2 in Xcode.
# 2. Green CI on the head commit (build + tests, both nav configurations).
# 3. Full device pass, §5.
# 4. Recapture screenshots, §4.
# 5. Archive + upload the build (Xcode Organizer, or fastlane gym/pilot).
# 6. Push metadata + screenshots:
bundle exec fastlane deliver
# 7. In App Store Connect: attach the processed build, paste the review
#    notes from §6, confirm the privacy answers are still "Data Not
#    Collected", confirm export compliance (ITSAppUsesNonExemptEncryption is
#    already NO in the Info.plist), then submit.
```

## 9. Post-release

- Tag the release commit `v1.3`.
- Watch crash reports in Xcode Organizer for a week. There is no third-party
  analytics and there never will be — that is the only signal that exists,
  by design.
- Roll the accepted rough edges from `docs/e2e_walkthrough.md` §15 into the
  next tuning pass: the audio limiter, the detune/pentatonic interaction, the
  two unimplemented firework behaviours, and the sky backdrop redraw.
