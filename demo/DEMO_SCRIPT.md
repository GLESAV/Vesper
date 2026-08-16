# Demoing Vesper

Two ways to show the game, plus the words to say while you do.

## 1. The self-running demo (no device needed)

`demo/vesper-demo.html` is a faithful browser port of the real simulation —
same drift, wobble, chain physics, particle shapes, scoring, and the same
synthesized pop sound — driven by a director that plays a ~40-second session
on its own and loops.

```sh
open demo/vesper-demo.html   # click once anywhere to enable sound
node demo/run-demo.js        # records demo/out/vesper-demo.webm + stills
```

## 2. The real thing on a simulator (macOS + Xcode)

```sh
xcrun simctl boot "iPhone 16" 2>/dev/null || true
xcodebuild -project Vesper.xcodeproj -scheme Vesper \
  -destination 'platform=iOS Simulator,name=iPhone 16' build \
  CODE_SIGNING_ALLOWED=NO
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/Vesper-*/Build/Products/Debug-iphonesimulator/Vesper.app
xcrun simctl launch booted com.gregorysavage.vesper
# record while you play:
xcrun simctl io booted recordVideo --codec h264 vesper-live-demo.mov
```

The live demo beats the browser demo for: haptics talk, the Path and Journey
sheets, and Reduce Motion / VoiceOver moments.

## 3. Talk track — 90-second live demo

| Beat | Show | Say |
|---|---|---|
| 0:00 | Cold launch | "No splash, no menus — you're already in it. That's the whole philosophy: nothing between you and the first pop." |
| 0:08 | Pop 2–3 orbs slowly | "Every pop is one fused event — burst, tone, haptic, under 20 ms. The sound is synthesized live; no two pops are identical." |
| 0:20 | Pop into a cluster | "Shockwaves chain. Watch the little 'chain of 4' — that's the score system whispering. Points only ever go up. Nothing is lost, timed, or ranked." |
| 0:32 | A fortune orb | "Sometimes an orb hides a fortune." *(pause — let them read it)* |
| 0:42 | Clear the field | "A soft chime, a kind card, and how many you've set free — all time. That's the entire failure state: there isn't one." |
| 0:52 | Sparkles → the Journey | "A hundred pops to find, ten families — ember sparks, frost shards, chime rings. Each is data in a catalog; the original is pop #001, unchanged, forever." |
| 1:08 | Dotted path → the Path | "And the map: stepping stones, each a little field of its own pops. Clear one, the road forks ahead — and the road *behind* fades after three days. The navigation itself lets go. Nothing to grind, nothing to miss." |
| 1:25 | Settings | "Sound, haptics, point whispers — all optional. No ads, no accounts, and it collects nothing. That's a feature, not a footnote." |

## 4. 30-second App Preview cut list (from the live recording)

1. **0–6 s** — cold launch into a drifting field; two slow pops, close on the burst
2. **6–14 s** — a tap into a cluster; cascade + "chain of 5" + point whispers
3. **14–19 s** — fortune card appears; hold
4. **19–25 s** — the Path: tap a stone, field opens with new pops
5. **25–30 s** — field clears; chime; "Nicely done." card; fade on the counter

Capture with sound on — the pops *are* the pitch. No captions needed beyond
the App Store's; the game explains itself.
