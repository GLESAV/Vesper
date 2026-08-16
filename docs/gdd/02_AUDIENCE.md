# Vesper — Audience & Market

*Who this is for, when they play, what already serves them, and where Vesper fits.
Every claim below is tagged: **[evidence: …]** cites a source; **[assumption: …]**
names the check that validates it. The dated validation plan at the end of this
doc says which assumptions block work and which proceed under a revisit rule.
Where this doc touches success numbers, the single measurement protocol
(00 §measurement protocol) is the only definition; this doc defines no metrics
of its own.*

## Target audience

**Women, 25–35.** Working, busy, phone-native. The most underestimated and most
valuable cohort in mobile: they built the casual and cozy genres, they pay for
quality, and they abandon anything that disrespects their time or intelligence.
[evidence: casual/cozy genre demographics — industry reports (Newzoo, Quantic
Foundry motivations data) consistently place women 25–40 as the majority and
highest-spending casual audience]

### What the research says about this cohort (design-relevant)

- **Sessions are pockets:** 2–8 minutes — commute, queue, couch decompression,
  and the single biggest one: **in bed, winding down**. Design the whole game to be
  excellent one-handed, in the dark, lying down.
  [assumption: verify session-length and time-of-day distribution in TestFlight
  aggregates during the baseline gate]
- **Completion is the fun:** clearing, finishing, tidying — the "done" feeling —
  outranks winning. (Two Dots, Unpacking, and every match-3 run on this.)
  [evidence: genre precedent; assumption for Vesper: the baseline fun gate —
  described as *fun*, not only relaxing]
- **Collection over competition:** finishing a set is delightful; ranking against
  strangers is a reason to delete.
  [evidence: Quantic Foundry motivation profiles — completion high, competition
  lowest for this cohort]
- **Aesthetic is a feature:** they screenshot beautiful games and share them; ugly
  or noisy UI reads as low-quality *and* stressful.
  [assumption: the share-card gate below — the panel actually posts, unprompted]
- **Interruption is constant:** the game must pause perfectly, resume instantly,
  and never punish absence. (This is why the Path's roads *fading kindly* must
  never read as loss — see 03 §Path.)
  [assumption: W6 interruption audit + context-matched exit tests, in bed and
  on transit]
- **Labeled beats clever:** mystery-meat icons test terribly; words in a warm
  voice test wonderfully. Navigation should say *the sky*, *your journal* — not ⚙ ✦ ⑂.
  [assumption: Phase 0 wayfinding exit test at the protocol's pass bar]

## Personas

**Maya, 28 — the commuter.** Product marketer, 40 min train each way. Plays with
headphones, one thumb, standing. Needs: instant load, one-handed reach, sessions
that end cleanly at her stop. Fears: anything that needs two hands or makes noise
without permission.

**Dani, 33 — the wind-down.** Nurse, irregular shifts, plays in bed at 1 a.m.
Needs: dark, quiet, zero pressure, something to empty her head. Fears: bright
flashes, "daily streak lost!", anything that makes her feel behind at 1 a.m.

**Priya, 26 — the collector.** Grad student. Screenshots pretty things, finishes
sets, reads flavor text. Needs: a collection worth caring about, discovery,
things to look forward to. Fears: FOMO events, paywalled completion.

**Ren, 31 — the churner.** Ops manager. Downloads every pretty calm game, loves
it for three evenings, then drifts back to her match-3 because "nothing new
happened." Needs: a reason night four differs from night one; discovery that
keeps arriving without asking anything of her. Fears: nothing — that's the
problem; she doesn't rage-quit, she quietly forgets. Ren is the persona the
variety layer (01 §why she returns, 03 §field generation) exists to keep, and
she is a required recruitment criterion for every panel — a panel of only
enthusiasts cannot detect the plan's biggest retention risk.

## The research panel (who we recruit; logistics and gate schedule live in 08)

- **Recruit 15–18 to net 10–12** active panelists — attrition is certain and a
  shortfall delays a gate, never lowers the bar (00 §exit tests).
- **Primarily outside the owner's network.** Friends cannot fail a calm game
  honestly. The owner's-network panel is acceptable only for the v1.2 baseline.
- **Personas map to study types:** wind-downs anchor the diary cohort and the
  return-rate read; commuters run context-matched transit tasks; collectors run
  the journal/keepsake studies; churners are oversampled in the 2-week
  variety-layer validation.
- **Motion-sensitivity screening** at recruitment, with **≥ 2 panelists who
  answer yes**; their Reduce-Motion path is tested first-class — first, not as
  a parity afterthought. A product promising physical calm cannot ship a camera
  its motion-sensitive players can't stomach.
- **Moderated remote video** for phases 0–1 studies (solves consent and
  tooling); unmoderated diaries only for the separate qualitative cohort per
  the measurement protocol.
- **Incentives: ~$300 in gift cards** across the panel. This is the plan's
  first cash cost and a named line item that **requires explicit owner
  approval** before recruitment begins; unpaid panels sourced from strangers
  do not show up on evening seven.

## Comparative landscape ("comps", not competitors)

| Game | What it proves | What Vesper takes | What Vesper refuses |
|---|---|---|---|
| **Two Dots** | This audience adores tactile clearing + gorgeous restraint | pop-feel bar, art discipline | lives, levels, energy timers |
| **Monument Valley** | They pay for beauty; short is fine | one-continuous-world navigation | finite content ceiling |
| **Alto's Odyssey** | Calm and *game* coexist; the world is the menu | spatial nav, ambient mood | score-chase framing |
| **Unpacking** | Completion + gentleness = deeply fun | "done" as the reward | — |
| **Animal Crossing: New Horizons (Switch) / Pocket Camp (mobile)** | Ritual visits without punishment — and, in Pocket Camp, how mobile pressure mechanics curdle the same warmth | the feeling of a place worth revisiting, carried by systems already in the game | timed events, FOMO, Pocket Camp's monetized cadence |
| **Calm/Headspace** | The wind-down slot is real and valuable | the bedside context | subscription pressure |

A load-bearing caveat on the ritual rows: Vesper's steady-state ritual rests on
**existing systems** — the infinite Path, the 100-pop catalog, the fortune pool —
not on a content treadmill. Arrivals are a bonus rhythm (only arrival #1 is
publicly committed; see 08's post-launch calendar), so no comps cell here may
be read as committing a solo team to Animal-Crossing-scale ongoing content.

**Positioning:** *the game in the wellness slot, the wellness in the game slot.*
Nothing on the store is simultaneously (a) a real, tactile game, (b) genuinely
pressure-free, (c) gorgeous enough to live on the home screen's first page. That
triangle is the moat. [assumption: validated by the market evidence package
below — the triangle is currently an internal belief, not a market fact]

## The market evidence package

The comps table above is design inspiration. It is not a market map: it omits
the products actually occupying the 1 a.m. slot and the search results Vesper
will sit next to. Before Phase 3 store assets are authored, this package is
built:

1. **Substitutes / search-neighborhood table.** For each ASO keyword theme
   (calm games, cozy, satisfying, bubble pop, no ads): the top 5 results, plus
   the named direct substitutes — **Antistress, Pop It / fidget apps,
   bubble-wrap simulators, Calm's bubble-style exercises** — each row recording
   monetization model, rating and volume, screenshot conventions, and one line
   of differentiation Vesper can honestly claim against it. The table's output
   is **2–3 concrete store-listing requirements** (what the screenshots and
   subtitle must do to read as distinct in that exact grid), handed to 09.
2. **Positioning-triangle validation.** A 10–15-app audit scoring each
   neighbor against the three triangle criteria, to confirm no product already
   holds all three. Optionally, an **n≈30 screenshot preference test** run
   through an async panel tool (the heaviest research item in the plan —
   descoped by default; run it only if the audit leaves the screenshot
   direction genuinely contested between two candidates).
3. **Per-persona "where they find us" channels**, each with one measurable
   acquisition hypothesis:
   - *Priya:* cozy-gaming communities (r/CozyGamers, #cozygames TikTok/
     Instagram). Hypothesis: one seeded launch post produces ≥ 1 organic
     repost or screenshot share within two weeks.
   - *Dani:* late-night App Store search in the calm/sleep neighborhood.
     Hypothesis: Vesper appears on page 1 for at least two of its keyword
     themes within 60 days of launch.
   - *Maya:* word of mouth from the share card in transit-length social
     scrolling. Hypothesis: the share-card gate below passes — panelists post
     unprompted.
   - *Ren:* the App Store "you might also like" shelf beside her match-3.
     Hypothesis: reviews mentioning "kept coming back" appear unprompted by
     day 60 (counted passively, per the ratings decision in 09).

**The share-card gate (binds 09's growth model):** the stillness card must
produce **organic, unprompted posts from the TestFlight panel before launch**.
If it does not, the screenshot loop is demoted from primary growth channel and
09's growth model re-weights toward community seeding and ASO. The card itself
is constrained by the pillar-veto form recorded in 00: field + fortune by
default, tonight's count explicit opt-in, lifetime totals never shareable.

## The business model, reconciled

The strongest fact in this doc — this cohort **pays for quality** — must be
squared honestly with a free game. The math: Vesper is owner-funded as a craft
project, with an annual budget ceiling and a post-launch sessions-per-quarter
cap set in 09 §Sustainability; at that scale, free-with-nothing-to-sell is
affordable indefinitely, and "asks nothing" is the single strongest
differentiator in the neighborhood the substitutes table maps (everything in
the 1 a.m. slot is ad-soaked or subscription-gated). Free also powers the
zero-friction share loop the growth model depends on. So **free-as-identity
holds for v2.0** — but it is a funded choice, not a hope: the dignified paid
doors (a "leave a lantern" tip jar; a supporter edition) are pre-approved
fallbacks in 09 with numeric triggers, decided now so no monetization decision
is ever made under duress. Duress-monetization later would break "asks
nothing" worse than never having promised it.

## Done-feeling without difficulty (the retention question)

Vesper's core reward is completion without challenge — and that is exactly
Ren's churn pattern: games that feel lovely and identical on night three. The
plan's answer is the variety layer: one small surprise per ordinary evening
(01), a field-generation space and catalog rule that make field 500 still worth
reading (03). This doc holds the hypothesis and the tripwire:

- **Falsifiable retention hypothesis:** with the variety layer in place, the
  panel holds the wind-down return threshold (00 §measurement protocol)
  **through week two, not only week one**, and week-two diary entries still
  name a specific new thing noticed that evening. Churner-persona panelists
  are oversampled in this read.
- **Pre-agreed fallback:** if the 2-week diary study falsifies it, (a) the
  field-generation variety work in 03 is pulled forward ahead of Phase 2's
  ritual features, and (b) context anchoring (01) is promoted from
  optional-later to a designed Phase 2 item. What is *not* on the fallback
  menu: pressure mechanics of any kind. If gentle variety cannot hold her,
  Vesper accepts being a shorter ritual rather than becoming a hook.

## Design consequences (bind on all docs)

1. One-handed, thumb-zone-first layout everywhere; the top of the screen is for
   looking, the bottom half for touching.
2. Dark-first art direction; comfortable at minimum brightness in a dark room.
3. Session arc has a *clean exit* at every field clear — never a cliffhanger
   mechanic. The working figure of **~90 seconds per field is an unmeasured
   claim**: before anything builds on it, the median field-clear time of the
   tuned v1.2 build is measured with a stopwatch across play styles (deliberate
   chainers and rapid tappers) and the measured value is recorded here. If the
   real number differs materially, downstream session-arc design retunes to the
   measurement — the sacred `GameConfig` constants are never retuned to rescue
   the claim. *Measured value: pending — a Phase 0 blocker, see validation
   plan.*
4. All progression frames as *keeping and finding*, never *losing and missing*.
5. Navigation in words and places, not icons and sheets (see 04).
6. Sound designed headphone-first but perfect on mute (haptics carry the feel).

## Validation plan (dated 2026-08-16)

Phase 0 proceeds under tagged assumptions — a solo production cannot afford a
research-blocked critical path — with **two exceptions that block because they
are cheap and load-bearing**. Every other assumption carries a named check and
a written revisit rule.

| Assumption | Check | Pass bar | Blocks? | Revisit rule on failure |
|---|---|---|---|---|
| ~90 s median field clear | Stopwatch the tuned v1.2 build, both play styles | Measured median recorded in consequence 3 | **Yes — before Phase 0 builds on it** | Session-arc design retunes to the measured value; `GameConfig` untouched |
| Swipe nav coexists with tap-to-pop | Phase 0a gesture spike (00) | Spike's written go/no-go | **Yes — before Phase 0** | Fallback stages 1–2 (08), pre-written |
| Session pockets, 2–8 min, bed-heavy | TestFlight aggregates, baseline gate | Distribution roughly matches; bed slot present | No | Re-weight persona priorities; re-check consequence 1–2 emphasis |
| Completion is fun for *this* game | Baseline fun gate (00) | Described as fun, not only relaxing | No (but failure opens the loop-depth workstream) | Per 00: sim fence conditionally lifts |
| Variety layer sustains return | 2-week diary study, churners oversampled | Retention hypothesis above | No | Pre-agreed fallback above, before Phase 1 features lock |
| Screenshot loop is the growth engine | Share-card gate, pre-launch | Organic panel posts occur | No | Demote loop; 09 re-weights growth model |
| Positioning triangle is open | Market evidence package, before Phase 3 store assets | Audit finds no product holding all three | No | Reposition store listing against the occupying product |

Success numbers, instruments, and cohorts referenced anywhere in this plan are
defined once, in 00 §measurement protocol.
