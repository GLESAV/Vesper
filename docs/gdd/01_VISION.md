# Vesper — Vision

*The one-page truth every other document serves. If a decision contradicts this
page, the decision is wrong.*

## Mission

**A stress-free, genuinely fun mobile game.** Not a meditation app wearing a game's
clothes, and not a game that secretly stresses you — a real game whose fun *is* the
calm: tactile, beautiful, generous, and finishable in the length of a deep breath
or a cup of tea.

## High concept

> **You pop soft glowing orbs; they chain; nothing is timed, ranked, or sold.**
> That is the whole promise, and it is the sentence worth repeating to a friend.
> The rest is atmosphere: Vesper is the evening you keep in your pocket — a dusk
> sky where each pop is a small, perfect burst of light, sound, and touch, and
> chains bloom like quiet fireworks. Above the field, a path of stars opens as
> you go. Below it, a journal remembers everything kindly.

## Where the fun comes from

Calm is the mood; it is not the fun. The sanctioned fun engine has two parts:

- **Invisible mastery.** The chain physics reward reading the field — where to
  tap, when to wait, which orb sets off the sky. Mastery deepens with play, but
  it is never scored, named, or gated: **a better-read chain is more beautiful,
  never more rewarded.**
- **Discovery cadence.** New pops, stones, fortunes, and small compositions of
  the field keep arriving through ordinary play, so curiosity — not obligation —
  is what there is to look forward to.

## Why she returns (the hypothesis, named)

The core bet is **in-fiction variation**: every ordinary evening contains one
small surprise — a composition of the field, a pop she hasn't met, a fortune, a
shift in the light — so that night four is observably different from night one,
and the place itself is worth coming back to. Context anchoring (a widget, a
Shortcuts/Focus hook, a bedtime association) is a later, optional layer, off by
default; it may support the ritual but must never carry it.

Both halves of this hypothesis are validated in the 2-week diary study before
any Phase 1 feature locks (instrumented per the measurement protocol in 08).

## Before Phase 0: the baseline fun gate

Before any rebuild work begins, the recruited panel plays **v1.2 exactly as
shipped for about one week** — first-hour session video plus the diary — to
establish the baseline the one metric must beat, and to answer the only
question that matters first: *is the core loop fun?* The qualitative bar is
explicit: **players describe it as fun, not only relaxing.**

The simulation is kept untouched **unless this gate fails.** On failure, a
loop-depth workstream opens with the existing discipline — one `GameConfig`
constant at a time, deterministic tests intact — until the loop passes. The
fence is a default, not a license to ship an un-fun game.

## Experience goals — what a player should *feel*

Each goal carries an observable proxy; instruments, cohorts, and numeric
thresholds live in the single measurement protocol (08).

1. **"Oh, that feels good."** (first 10 seconds) The pop is a fused sensory event —
   sight, sound, touch — that lands like bubble wrap made of light.
   *Proxy: visible or spoken delight at the first pop in first-session video;
   no panelist calls the pop merely "fine."*
2. **"One more field."** (first 5 minutes) Cascades, fortunes, and the next stone
   pull gently. Wanting more is fine; *needing* more is designed out — the test:
   **skipping a week changes nothing she has, owes, or can access.**
   *Proxy: panelists clear a second field unprompted in their first session.*
3. **"This is mine."** (first week) A growing collection, a path only they walked,
   a journal of their own evenings. Ownership without obligation.
   *Proxy: by day 7, diary entries name a specific pop, stone, or fortune as hers.*
4. **"I go there to exhale."** (steady state) Vesper becomes a ritual object — the
   thing you open on the train, in bed, between meetings. It always welcomes,
   never asks.
   *Proxy: the one metric — unprompted evening return at the protocol's
   threshold, read from TestFlight aggregates.*

Across all four sits the qualitative fun gate: in her own words, the game is
**fun, not only relaxing.**

## Pillars (each with a veto test)

| # | Pillar | Veto test |
|---|--------|-----------|
| P1 | **Instant calm** — launch straight into play; every surface is one gesture from the field | Does this add a step between the player and a pop? |
| P2 | **Tactile joy** — the pop is sacred; every interaction must feel this good | Would this interaction embarrass the pop? Do sight, sound, and touch land together within one frame? |
| P3 | **Generous, never grasping** — progress only accrues; content only opens; nothing expires, ranks, or upsells | Could this make anyone feel behind, judged, or sold to? |
| P4 | **One beautiful place** — a single continuous world, not screens; navigation is movement, not menus | Does this feel like software or like the sky? Can she mute it — in the dark, one-thumbed — in under 3–5 seconds? |
| P5 | **Her evening, respected** — designed for her real sessions: the subway commute, 1 a.m. in bed, five stolen minutes between meetings; interruptible, resumable, private | Does this survive all three — a subway stop mid-chain, a dark bedroom with a sleeping partner, a glance over the shoulder at work? |

P4 is the direct answer to the navigation critique: **modal sheets and icon
toolbars are banned.** The Path, the Journal, and the quiet things are *places
in the world*, reached by moving through it.

**Precedence.** When pillars collide, the lower number wins — calm before
tactility, tactility before generosity, and so on down — and no pillar
overrides the mission.

**The P4 carve-out.** Critical controls — sound, haptics, leaving — are
reachable in **at most two gestures from anywhere**. "Navigation is movement"
is a rule for places, never an excuse to make reaching for quiet a journey.
The precedence rule and the carve-out compose: P4 shapes the world; P1 and P5
guarantee the exits.

## Kindness guardrails (the journal's oath)

The journal remembers kindly or not at all. It never surfaces time played,
days missed, calendars, or anything readable as a report card — and no
arrangement of what it keeps may let her reconstruct an evening she skipped.
Absence is structurally unrepresentable, not merely unmentioned.

## Anti-goals (rejected forever, not deferred)

Ads · IAP · currencies that spend · timers · lives · leaderboards · social
comparison · push notifications that demand · loss-framed streaks · data
collection · fail states · skill gates · punishment.

## The one-sentence brief for every discipline

- **Design:** make wanting-to-continue feel like being welcomed, never like being hooked.
- **Art:** dusk, glow, softness — a place, not an interface.
- **Audio:** ASMR-grade pops; silence is a valid mix.
- **Writing:** lowercase-kind; the game speaks like a wise friend at dusk.
- **Engineering:** invisible; always at the display's native refresh rate; nothing ever janks the breath.
