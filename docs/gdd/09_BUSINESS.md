# Vesper — Positioning, Pricing & Launch

*The business plan for a game whose brand is "asks nothing." Every commercial
choice must itself be stress-free — including the choices about money, which
are made here, in daylight, not later under duress.*

## 1. Positioning

**The game in the wellness slot; the wellness in the game slot.** (02 §comps)
One line for the store and the pitch: *"the evening you keep in your pocket."*
Category: Games › Casual (primary), **Lifestyle (secondary — confirmed, not a
consideration)**. Vesper competes with Two Dots on feel, Monument Valley on
beauty, and Calm on the bedside slot — while being the only one that is
simultaneously free of pressure, free of ads, and a real game.

### 1.1 Market evidence package *(built in Phase 2, before store assets lock)*

The comps table in 02 is design inspiration; this is the market map — the
products actually occupying the 1 a.m. slot and the search results Vesper will
sit in.

- **Substitutes / search-neighborhood table.** For each ASO keyword theme
  (§3.2): the top 5 apps in that search result, plus the named substitutes —
  Antistress, Pop It (and clones), bubble-wrap simulators, Calm's bubble
  exercises. Columns: monetization model, rating + volume, screenshot
  conventions, and one line of per-row differentiation ("what Vesper is that
  this is not").
- **Acceptance:** the table produces **2–3 written store-listing
  requirements** (e.g. what the first screenshot must show to read differently
  from the ad-soaked pop games) that the Phase 3 asset work must satisfy.
- **Positioning-triangle validation:** a 10–15-app audit confirming the
  Two Dots / Monument Valley / Calm triangle is where players actually place
  us. *Optional extension:* an n≈30 screenshot preference test — descoped by
  default; run it only if the audit leaves the lead-screenshot choice
  contested, and only via an async panel tool (it is the heaviest research
  item here; keep it solo-feasible).

### 1.2 Where they find us *(one channel + one testable hypothesis per persona)*

| Persona (02) | Channel | Acquisition hypothesis (measurable in App Store Connect / by hand) |
|---|---|---|
| Wind-down | Cozy-gaming communities (r/CozyGamers, Discords) | one seeded launch post drives ≥ 100 product-page views inside a week (ASC sources) |
| Commuter | App Store search ("calm games", "satisfying") | search-sourced downloads ≥ 40% of total by day 60 |
| Collector | Screenshot/short-video shares (stillness + cascade cards) | cards appear unprompted in communities ≥ 5 times in the first 90 days (weekly scan) |

Each hypothesis has a check date and a consequence: if it fails, that channel
is dropped or reworked — no channel survives on hope.

## 2. Pricing & sustainability

**Free. No ads, no IAP, no subscription for v2.0.** Free is shipped brand and
identity — "no monetization" is the single strongest differentiator with this
audience — and the entire growth model (§3) is a zero-friction share loop that
paid-up-front would cut off at the door.

**The honest math.** Vesper has no servers, no SDKs, and no marginal cost per
player. Its real costs are the Apple developer fee (~$99/yr), the tfc.studio
domain, and the owner's time. It is **owner-funded** from income outside the
game, and that is a legitimate, named answer — not a deferral. The audience
doc's strongest fact (this cohort pays for quality) is real, and the premium
and tip-jar doors stay open below; free simply wins for v2.0 because the brand
promise and the share loop both depend on it.

**Budget & time ceilings (the sustainability contract):**

- Annual cash ceiling: **$500/yr** (fee + domain + incidentals). Any spend
  beyond this requires an explicit owner decision, not drift.
- **Playtest panel incentives, ~$300** — the plan's first cash line item.
  *Requires owner approval before commitment;* it is budgeted, not decided.
- Post-launch time cap: **≤ 6 focused work-sessions per quarter** across all
  Vesper work (arrivals, fixes, store upkeep). The game must fit inside a
  life, or the calm is a lie told by an exhausted developer.

**Pre-approved fallback ladder (decided now, never under duress).** Each step
is dignified, pillar-consistent, and has a numeric trigger:

1. **Tip jar** — trigger: annual cash costs exceed $500, or the owner funds
   two consecutive years wanting relief. Plain, non-canon language ("support
   the developer"), lives in settings/about only, never interrupts, never
   gates content. See the canon rule in §4.
2. **Supporter edition** — trigger: costs exceed $1,000/yr or the tip jar
   covers < 50% of costs after a year. A paid twin of the identical game for
   people who want to pay; the free app is never degraded.
3. **Graceful steady state** — trigger: development stops entirely. Vesper
   needs no server; it remains on the store as-is, with one final kind release
   note. The game never dies loudly and never starts asking on its way out.

Any step beyond this ladder needs its own pillar review.

## 3. Growth model (organic by design)

### 3.1 The screenshot loop

The game is built to be photographed (05); the shareable stillness card (03)
makes it one gesture, and **cascade screenshots are tracked alongside
stillness cards** — the chain-pop is the fun half of the brand. Quiet `vesper`
wordmark corner credit — discoverable, never watermark-loud.

### 3.2 ASO (a plan, not a vibe)

- **Keyword sheet:** 15–20 candidate terms scored for volume and difficulty
  (free-tier ASO tooling is sufficient), maintained by the owner, refreshed
  each major release. Themes: calm games, cozy, satisfying, bubble pop, no
  ads, relaxing. **"bubble pop" is reassessed against the substitutes table
  (§1.1)** — it is a crowded head term and may cost more than it earns.
- **The 100-char keyword string** is built from the sheet, not from memory.
- **Subtitle** must carry ≥ 2 indexable terms; "pop orbs, quietly let go"
  (shipped) is validated against the sheet and revised only if it fails that
  bar.
- Screenshots lead with the field + one whisper of copy each (never feature
  bullets), and satisfy the §1.1 listing requirements; preview video = the
  30 s cut (demo/DEMO_SCRIPT.md).
- **"anxiety" appears in no owned copy** — not keywords, subtitle,
  screenshots, or description. Owned surfaces never make health-adjacent
  claims. We passively count the word when players volunteer it in reviews
  (§5); their words are data, ours would be a claim.

### 3.3 Apple featuring (the biggest free lever)

A game that is beautiful, collects nothing, and asks nothing is exactly the
profile App Store editorial features.

- **Nomination via promote.apple.com, 6–8 weeks before the v2.0 submission
  target.** Owner: Kate. Date: the week the Phase 2 exit test passes.
- **Feature-ready assets** prepared with the Phase 3 store work: portrait +
  landscape key art, no-text visuals, the one-line pitch.
- **Editorial pitch:** *"a game that collects nothing"* — the privacy story
  and the calm story, told as one.
- Re-nominate at each major release and each shipped arrival.

### 3.4 Community seeding at launch

Cozy-gaming communities, calm-tech press (the "no data, no ads, no pressure"
story is genuinely newsworthy), and the playtest panel as first advocates.

### 3.5 The ratings ask (resolved)

Two surfaces, nothing else:

- **One system-mediated `SKStoreReviewController` request after the third
  field clear** — OS-throttled, dismissible, and fired **at most once per
  install, ever**. It has passed pillar review once; it is not revisited or
  escalated. **Removal condition:** if 2 or more panel testers react
  negatively to it in playtests, it is removed entirely.
- **A passive, player-initiated "rate vesper" link in the journal's quiet
  things** — always available, never surfaced by the app.

There is no other prompt, ever. The KPI this feeds lives in §5.

## 4. Brand voice outside the app

Same voice as in (07): lowercase-kind, wry, brief. The store listing, the
privacy page (tfc.studio/vesper), release notes ("The Feel & Collection
Update" register), and any social presence all speak it. Privacy is marketed
as a feature, always: **"Vesper collects nothing."**

**Canon rule: canon objects are never commercial vessels.** If the tip jar
ever ships (§2), it speaks plain, non-canon language — "support the
developer", never "leave a lantern" — and lives in settings/about. Dressing a
transaction in the world's language would make the whole world feel for-sale.

### 4.1 Localization

- **v2.0 ships in English only.** This is decided, not deferred by neglect
  (canon also in 07 and 08).
- Any future locale is **transcreation, never translation**: a native writer
  working from a per-locale voice guide and per-locale forbidden-vocabulary
  list, with the **1 a.m.-kitchen voice test as acceptance** — the lines must
  land at midnight in that language, or they don't ship.
- Each locale ships as **its own gated arrival**, one at a time, after v2.0.
  Phase 3 delivers only the string-catalog extraction and the per-language
  voice briefs that make this possible (08).

## 5. Success, measured without surveillance

All signals are Apple-provided aggregates (App Store Connect, opt-in users
only) or public review/community text. No in-app telemetry, ever. **Cadence:
one 15-minute App Store Connect check every Monday. Owner: Kate.** One
product-page-optimization (PPO) screenshot test per major release.

Every metric has a number, a check date, and a named fallback — a metric
without a consequence is decoration.

| Signal | Bar | Check | Fallback if missed |
|---|---|---|---|
| App Store rating | **≥ 4.7 with ≥ 50 ratings** | day 90 | verify the single request is firing and the passive link is findable; never add prompts |
| **Fun signal (equal weight with calm)** | play-language mentions ("satisfying", "the chain pops", "one more field") ≥ calm-language mentions | first 100 reviews | re-lead screenshots/preview with the cascade; flag to design — the game is reading as a wellness tool, not a game |
| Calm/sleep language (incl. "anxiety", harvested passively — never authored) | present unprompted | ongoing | none — this is texture, not a gate |
| Product-page conversion | ≥ Casual-category median (ASC benchmark) | day 60 | run the release's PPO test against the §1.1 listing requirements |
| Browse-vs-search mix | browse ≥ 30% of impressions | day 90 | re-nominate for featuring; second press push |
| Opt-in retention cohorts (ASC aggregate) | day-7 ≥ Casual benchmark | day 60 | revisit the nightly-variation bet (03); feed arrival #1's content choice |
| Persona channel hypotheses | as tabled in §1.2 | per-row | drop or rework the channel |
| Community shares | stillness **and cascade** cards appearing unprompted | weekly scan | reassess the share card's one-gesture flow (03) |
| Panel | next-evening unprompted return (the one metric, 03 §6) | pre-launch gate | this one gates the ship; see 08 |

## 6. Launch beats (v2.0)

1. TestFlight panel wave (Phase 2) → testimonials with consent.
2. Press/creator kit: the plan's one-pager, the stillness cards, the preview
   video, the "collects nothing" story.
3. v2.0 "One World" release with refreshed listing.
4. **When the first arrival ships** — the second press beat. No date is
   promised, publicly or internally; arrival #1 is built in Phase 3 as the
   pipeline proof with its true cost recorded (08).

**Launch ops.** Press and creator dates are set **only after App Review
approval** — a two-week review delay must never break beats 2–3, so nothing
external is scheduled against a submission date. Review replies: owner Kate,
in the (07) voice — lowercase-kind, brief, never defensive, never asking a
reviewer to change a rating. Support email: vesper@tfc.studio, listed on the
store page and privacy page, checked in the Monday cadence.

## 7. Content cadence (what we promise vs. what we plan)

The steady-state ritual rests on **existing systems** — the infinite Path, the
100-pop catalog, the fortune pool — not on a content treadmill; comps that
imply live-ops drops (02) are read for feel, not cadence. Arrivals are a bonus
rhythm on top:

- **Publicly committed: arrival #1 only** (beat 4). The 6–8-week cadence
  stays internal until three arrivals have shipped on time.
- **Sustainability rule:** one arrival costs **≤ 2 work-sessions**, or the
  cadence stretches to quarterly. The cap in §2 always wins.
- The post-launch calendar itself is owned by 08; this document only states
  what may be promised outside the studio.
