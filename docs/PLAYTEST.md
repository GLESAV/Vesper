# Vesper — Playtest Guide (the One World build)

*Written for two people: the owner, and Kate. No engineering knowledge is
assumed past "I can open Xcode and press a button". Work item W22; the
TestFlight path in §2 is W23. The motion-safety screen in §3 is Amara Osei's
barrier condition from R-SPIKE and is not optional.*

This build exists to answer **one question**: does the game read as *one
place* you move through, or as three screens with a fancy transition? Nothing
else about it is finished, and it is not trying to be.

It is not a release. It is not v2.0. It is a question with a phone attached.

---

## 1. What is real, and what is deliberately not there

Read this before you play, so you don't spend your evening reporting absences
we chose.

**Real, and worth judging:**

- The whole navigation model — one continuous vertical world: the **sky**
  above, the **field** in the middle, the **journal** below. Swipe, or tap the
  faint words at the top and bottom edges.
- The camera: finger-tracked while your thumb is down, then it settles.
  Interruptible — touch it mid-settle and it stops where it is.
- The **sky** is your real Path. Those are your actual stones, drawn as stars
  in their families' colours, with your real roads between them. Tap a star and
  the field re-seeds from it. Leaving without choosing changes nothing.
- The **journal**: three pages — *the evening* (your numbers), *the collection*
  (the hundred pops), *the quiet things* (sound, haptics, point whispers,
  begin again). Pages turn by **tapping** the words along the foot, never by
  swiping.
- The pop engine, sounds, haptics, points, unlocks, fortunes, chains — all
  untouched from v1.2. If a pop feels different, that is a finding, because
  nothing in the pop was changed.
- The counter now says **`set free`**. The word *DETONATED* is gone.

**Deliberately deferred — not bugs, please don't report them:**

| Missing | Why |
|---|---|
| **Onboarding and the arrival sequence** (W15) | The build drops you straight into a field. Only a fresh player can judge a first run, and neither of you is fresh. |
| **Evening light** (W16) | The background does not shift hue with the hour yet. It cannot be judged in one evening anyway. |
| **Keepsakes, the lamp, the fortune archive** (W10) | These need a change to the save file that this build is not allowed to make. |
| **Older stones you may remember** (W08) | The sky draws the stones your phone still has. Ones the old map pruned away are gone and are not coming back in this build. A sparse sky is expected. |
| **Long-press on the field to begin again** | Not in yet. `begin this field again` lives on the journal's *quiet things* page. |
| **A transition-sounds toggle** | Not in yet. |

If it isn't in the table above and it feels wrong, tell us.

---

## 2. How to run it

Two paths. **(a)** is the owner, with a Mac and a cable. **(b)** puts it on
Kate's phone with no Mac anywhere near her.

### 2a. From Xcode (the owner)

**What you need in the room:**

- A Mac with **Xcode 16.4 or newer**.
- An **iPhone running iOS 18.5+** and a cable. Use the *oldest* iPhone you
  have — an A12-class phone (XR / XS era) is the one that tells the truth
  about frame pacing. Test the newest one too, but don't only test that one.
- Your Apple ID signed into Xcode (**Xcode → Settings → Accounts**), on team
  **4J888JWA8C**. That team is already written into the project; you should not
  have to type it anywhere.

**Steps:**

```sh
git fetch origin
git checkout claude/vesper-pop-aaa-optimization-2n5oc2
git pull
open Vesper.xcodeproj
```

1. Plug the phone in. Unlock it. If it asks, tap **Trust**.
2. Top of the Xcode window: scheme **Vesper**, destination **your iPhone**
   (not a simulator — a simulator has no haptics and lies about touch).
3. Press **▶ Run** (⌘R).
4. First time only, the phone will refuse to launch it: on the phone, go to
   **Settings → General → VPN & Device Management**, tap your developer
   profile, **Trust**. Then press Run again.

**The One World navigation is what you get by default.** There is no toggle
inside the app; the flag is compiled in (`Vesper/Support/WorldFlags.swift`).

**To build the old v1.2 app for comparison** — you will want this for the feel
question in §4 — build with `VESPER_CLASSIC_NAV` defined:

- In Xcode: select the project in the sidebar → the **Vesper** *target* →
  **Build Settings** → search for **Active Compilation Conditions** → click the
  **Debug** row and add `VESPER_CLASSIC_NAV` on its own line. Run. You now have
  v1.2's four icons and sheets.
- **Remove that line again** when you're done, or you'll keep testing the old
  app by accident.
- Or from the command line, without touching the project file:

```sh
xcodebuild build -project Vesper.xcodeproj -scheme Vesper \
  -destination 'platform=iOS,name=YOUR IPHONE NAME' \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) VESPER_CLASSIC_NAV'
```

Both builds are the same app with the same bundle ID, so **they share one save
file**. Switching between them keeps all your points, stones and unlocks. That
is intended — but see §6 before you reset anything.

### 2b. TestFlight, internal (so Kate needs no Mac)

**What the owner must have — all of it, before starting:**

- A **paid Apple Developer Program** membership (the $99/year one). A free
  Apple ID can run the app on a cable but cannot upload to TestFlight.
- Access to **App Store Connect** for `com.gregorysavage.vesper`, team
  **4J888JWA8C**. Both are already in the project.
- **Kate's Apple ID email address** — the one on her iPhone.

Internal TestFlight builds go out **without App Review**, usually within half
an hour of upload. Nothing here touches the public App Store listing.

**Steps:**

1. **Bump the build number.** Every upload needs one nobody has used before.
   Xcode → the **Vesper** target → **General** → **Build**. It currently says
   `1`; make it `2`, then `3` next time. Leave **Version** at `1.2` — this
   isn't a release and the version number is not a claim.
2. Destination menu (top of the window): choose **Any iOS Device (arm64)**.
   Archive will not offer itself while a simulator is selected.
3. **Product → Archive.** This takes a few minutes and builds in Release,
   which matters: Release strips the debug-only reset in §6.
4. The **Organizer** window opens with your archive. **Distribute App** →
   **TestFlight Internal Only** → **Distribute**. Let Xcode manage signing when
   it asks.
5. Wait for the upload, then for Apple to process it — usually 5 to 20
   minutes. You get an email when it's ready. There is no export-compliance
   question to answer; the project already declares no non-exempt encryption.
6. **Add Kate as a person on the team** (once, ever):
   [App Store Connect](https://appstoreconnect.apple.com) → **Users and
   Access** → **+** → her name and Apple ID email → role **Developer** →
   Invite. She'll get an email; she must accept it before step 7 will find her.
7. **Put her on the build:** App Store Connect → **Apps → Vesper → TestFlight**
   → **Internal Testing** → your internal group (create one called
   `evening` if none exists) → **Testers +** → tick Kate → add. Then make sure
   the new build is attached to that group.
8. **On Kate's phone:** install **TestFlight** from the App Store, open the
   invitation email on the phone, tap **View in TestFlight**, then **Install**.
   Vesper appears on her home screen like any app.

**Tell Kate two things:** the build stops working after 90 days (that's normal,
not a crash), and TestFlight will ask her to send feedback with a screenshot —
she can, but §7's three questions in a message to you are worth more.

**If it goes wrong:**

- *"No accounts with App Store Connect access"* → Xcode → Settings → Accounts,
  sign in with the Apple ID that owns the developer membership.
- *Signing/provisioning errors* → target → **Signing & Capabilities** →
  **Automatically manage signing** ticked, Team = the one ending `4J888JWA8C`.
- *Kate doesn't appear in the tester list* → she hasn't accepted the Users and
  Access invitation yet. That has to happen first.

---

## 3. The motion-safety screen — before the first real session

**This runs before anyone plays this build for the first time, and that
includes both of you.** You are testers here, not insiders with an exemption.
The person who created the game is exactly the person most likely to push
through a symptom in order to like her own work, and the owner is exactly the
person most likely to think a rule about safety is for other people.

A continuous camera moves the whole screen under your eyes while your inner ear
says you are lying still. That mismatch makes some people ill. Amara Osei made
this screen a condition of the camera reaching anybody at all.

It takes about eight minutes. Do it in one sitting, at the time of day you
would normally play — the evening, in the dark, is the honest condition.

### Before you start — write this down

On paper or in a note, score each of these **0 to 3** (0 = not at all, 3 = a
lot), *right now, before opening the app*:

```
headache          0 1 2 3
queasy / nausea   0 1 2 3
dizzy or swimmy   0 1 2 3
eye strain        0 1 2 3
unusually tired   0 1 2 3
```

Also write down: are you someone who gets carsick or seasick? Is **Reduce
Motion** on or off on this phone right now (Settings → Accessibility → Motion)?
For this screen, leave it **off** — the screen exists to test the motion.

### The screen itself

Dark room. Phone brightness at **minimum**. Sound however you like.

1. **Seated, about two minutes.** Deliberately travel back and forth:
   field → sky → field → journal → field. Do that **ten full round trips**, at
   a normal pace, one after another. This is more travel than a real evening
   contains, on purpose.
2. **Then five fast ones.** Flick up and down quickly, five times, without
   pausing between them.
3. **Lying on your back, about two minutes.** Phone held above your face —
   the position the game is actually for. **Ten more round trips.** This
   position provokes more than sitting does; that's why it's here.
4. **Then a minute of ordinary play**, still lying down. Pop some orbs. Let
   the field be a field.

### Stop at the first sign of anything

Queasiness, a swimming or floating feeling, a headache starting, breaking a
sweat, sudden tiredness, wanting to close your eyes — **stop immediately**.
Put the phone face down and look at something across the room for a minute.

Stopping is a **result**, not a failure. It is arguably the most valuable
result this build can produce, and it is the one thing that will change the
design fastest. Do not push through to be helpful. Do not finish the ten round
trips out of politeness.

### After — write the same list again

Score the same five, 0 to 3, immediately after. Then check again **twenty
minutes later** and write down whether anything was still there, and for how
long.

**If anything scored higher after than before**, even by one point:

- Stop the playtest for tonight. The rest of the evening's data isn't worth it.
- Tell the team, with the numbers and which part it started in (seated? lying
  down? the fast flicks?).
- Before touching the build again, turn on **Settings → Accessibility → Motion
  → Reduce Motion**. Under Reduce Motion this build's camera does not translate
  at all — the places crossfade instead, and dragging still gives you feedback
  so the control doesn't feel dead. Then play only in that mode.

If both of you get through it clean, note that too — "no change, seated or
supine" is a real reading and it's the one the camera needs.

---

## 4. What to look for

Four questions. They are the reason the build exists; everything else is
detail. Answer them in that order, and give the first two an unspoiled run —
**you each only get to be surprised once.**

### Q1 — The navigation question: one place, or three screens?

The whole bet. Play for ten unhurried minutes: pop a field, go up to the sky,
choose a star, come back, look at the journal, come home.

Then put the phone down and, without looking at it, say out loud **where the
journal is**. If the sentence that comes out is *"below the field"* — a
direction — the world reads as one place. If it's *"in the menu"* or *"that
other screen"* — a container — it reads as three screens with a transition,
and we learned something expensive and important.

Also worth noting: did you ever feel like you had *left* the game to go and do
admin? That feeling is the thing One World is built to delete.

### Q2 — The primary-path question: did you find your way unprompted?

**This one is Kate's, it happens once, and the owner must say nothing.** No
pointing, no "try swiping", no hovering. Hand her the phone and let her play.

Watch, and write down afterwards:

- What did she try first to leave the field — a swipe, or a tap on the words?
- Did she notice the words at the top and bottom **at all**? How long before
  she looked at them?
- Did she find the sky? Did she find the journal? Which came first?
- Did she ever get stuck somewhere, and how did she get home?
- Did she try anything the game simply didn't answer?

If she found both without help, in under a couple of minutes, this build is
working. If she found neither, don't help her for a full minute first — the
length of that minute is data.

### Q3 — The quiet question: silence in under five seconds

The target, written before the build existed: **mute in under five seconds,
one-handed, on the first attempt, in the dark.**

Set it up honestly — sitting or lying down, one hand, the way you would if the
sound suddenly felt like too much. Have the other person time it from the
moment you decide to mute. First attempt only; the second attempt is a
different question.

The path is: get to the journal (swipe down, or tap `your journal`), then tap
**`hush`** at the top of the evening page — it silences sound and haptics
together. Two gestures.

Write down: the time, and **which gesture you actually used to get down there
— the swipe or the word.** That second detail settles an open design argument
about which one is the real path.

### Q4 — The feel question: does a pop still land?

Nothing in the pop was changed. So if it feels different, something in the new
navigation layer is stealing from it, and that is serious.

Do this as a back-to-back, same phone, same volume, same room:

1. Build with `VESPER_CLASSIC_NAV` (§2a) — the v1.2 app. Pop for one minute.
2. Build the default — the world. Pop for one minute.

Then answer in plain words: does the pop happen **the instant your finger
lands**, or a hair later? Is the little haptic tap the same weight? Does the
sound arrive with the light, or behind it? Do chains still cascade the way they
did? And most of all: **did any pop feel like it didn't happen?**

---

## 5. The device-only checks

Four things the reviewers said can only be learned on real hardware, in a real
hand. None of them needs Xcode open — just the app, a quiet room, and paper.

### 5a. Twenty swipes that begin on an orb

The single most important check in this document. When your thumb lands on an
orb and then keeps going, **both** things are supposed to happen: the orb pops,
*and* you travel. Neither one is allowed to eat the other.

Wait for a full field. Then, twenty times:

> Put your finger down **directly on an orb** and immediately swipe up, in one
> motion, without pausing.

Keep two tallies:

```
attempt   did it pop?   did you move?
   1          y/n           y/n
   ...
   20
```

**Expect 20 out of 20 in both columns.** If the pops are 20 and the moves are
17, say so. If it's the other way round, say that. A number below 20 in either
column is the headline of your report — write down what the near-misses had in
common if you can (small orb? near the edge? mid-settle?).

Then the same twenty swiping **down**.

### 5b. The low one-handed swipe, in bed

Lie down. One hand. Now start a swipe **downwards** with your thumb already low
on the screen — where a thumb naturally rests — and try to reach the journal.
Ten attempts. Count how many actually arrive versus how many spring back.

Then ten more starting from the middle of the screen, for comparison.

We already suspect the low downward swipe is the weakest gesture on the phone —
a thumb starting low has barely any runway. That is exactly why the word
`your journal` is tappable and is meant to be the real path down. So:

- If the low swipe mostly fails, that is **expected**, not a bug. Say how many.
- The finding we actually need: **when it failed, did you notice the word and
  use it — or did you feel stuck?** Feeling stuck is the failure.

### 5c. Reduce Motion: travel, or a cut?

Turn on **Settings → Accessibility → Motion → Reduce Motion** while Vesper is
still running — don't quit it, we want to see it change under you. Then go back
and travel between all three places several times.

Nothing should slide. The places should crossfade, and dragging your thumb
should still give you *some* proportional response so the screen doesn't feel
dead.

The question, and it is a judgement, not a measurement: **does it feel like you
went somewhere, or like the screen was swapped?** A cut is a failure of the
whole "one place" idea for every person who has that setting on — and many of
this game's players do. Say which it felt like, in a sentence, and whether you
could still tell *which direction* you had gone.

Leave Reduce Motion on for a few minutes of ordinary play before turning it
off, and note whether the game is still legible without any motion at all.

### 5d. Did it ever ignore you?

Play normally for ten minutes with no agenda. Every time you feel — even
faintly — that the app didn't respond to something you did, stop and write down
one line: **what you did, and what was on screen at the time** (were you
mid-travel? had you just popped? was a card showing?).

This is the one check where a vague feeling is exactly the data we want. "It
felt like it missed one about a minute in, just after I came back from the sky"
is more useful than any number.

One deliberate variant: **pop as fast as you can for thirty seconds** in the
middle of a full field, and watch whether the camera ever moves when you didn't
ask it to. It must never move unasked. If the screen ever drifts on its own
during a flurry of popping, that is a stop-the-line finding.

---

## 6. Resetting between sessions

Three different things, easy to confuse:

**`begin this field again`** — journal → *the quiet things* → the row near the
foot, then confirm. This reseeds **the field in front of you**. It keeps your
points, your collection and your path. Use it whenever you want a fresh field.

**A fresh install** (the DEBUG-only reset) — journal → *the quiet things*, one
action, and everything local is wiped: pop points, unlocks, the collection, the
whole path. The next field is a first field. It exists so a playtest session
can be repeated from a known start.

- It appears **only in builds run from Xcode**. Release builds — which is what
  TestFlight sends — do not contain it at all, by design. Kate will not see it,
  and should not.
- **If you don't see it, your build predates it.** Deleting the app from the
  phone and installing again does exactly the same thing. Everything Vesper
  knows lives on the phone; nothing is on a server, so nothing survives a
  delete and nothing can be restored.

**A warning worth reading twice:** the world build and the classic v1.2 build
share one bundle ID and therefore one save file. A reset wipes your **real**
numbers — every pop since v1.0, the whole path. If the owner cares about his
own lifetime count, do the resets on a second phone, or accept the loss
deliberately before tapping it.

---

## 7. How to report back

Write **prose**, not a form. A few paragraphs in a message beats any checklist,
because the sentence you'd naturally use is usually the finding.

Three questions are worth answering properly:

**1. Where did you think you were?**
When you were in the journal, or the sky — did it feel like a place below or
above the field, or like a screen the game had switched to? Say it however it
comes out. If you found yourself saying "go back" rather than "come down", say
that too; the word you reach for is the answer.

**2. What did you reach for that wasn't there?**
Anything you tried that did nothing. Any moment you looked for something and
couldn't find it. Any place you expected a way out and had to hunt. Include the
things you assume are too small to mention — those are usually the real ones.

**3. What did the evening feel like, against v1.2?**
Better, worse, or different-but-even — and then the specific moment that
decided it for you. Not "it felt nicer": *"coming back down from the sky and
landing in my own field was the moment"*, or *"I lost a pop and it annoyed me
enough that I noticed"*. One moment, named, is worth a page of adjectives.

Attach alongside, plainly:

- The **motion-safety numbers**, before and after, for both of you (§3). These
  come first even if they're all zeros.
- The **twenty-swipe tally** — pops and moves (§5a).
- The **mute time**, and whether you swiped or tapped the word (§4 Q3).
- One list of anything that looked broken, each with what you were doing at the
  time.

And if a session ended early because someone felt unwell: that is the report.
Send it on its own, and don't add anything to it.

---

*This build is a question, not a release. If it comes back "these are three
screens", that is a good evening's work and we will have spent a fortnight
instead of a season learning it.*
