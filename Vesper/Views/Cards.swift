import SwiftUI

// MARK: - Fortune card

struct FortuneCard: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("✦")
                .font(.system(size: 15))
                .foregroundColor(Color(red: 214/255, green: 204/255, blue: 230/255).opacity(0.85))
            Text(text)
                .font(.system(size: 15, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .foregroundColor(Color(red: 232/255, green: 228/255, blue: 242/255))
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .frame(maxWidth: 290)
        .background(Color(red: 24/255, green: 22/255, blue: 34/255).opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .onTapGesture { onDismiss() }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        .accessibilityElement(children: .combine)
        // R-CRAFT J2 / R-A11Y C2. Copy read aloud is copy. The label was
        // `"Fortune: \(text)"` and the hint was `"Tap to dismiss"` — a system
        // string, capitalized, and the sentence every other app says. The
        // serif italic and the ✦ already tell a sighted reader what this is,
        // so the label is the fortune itself.
        //
        // `.isButton` because it IS one: it was hinted as tappable without
        // ever being announced as actionable, which is the combination that
        // makes a VoiceOver user distrust the hint.
        .accessibilityLabel(Text(text))
        .accessibilityHint(Text(Strings.fortuneDismissHint))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Fortune whisper

/// The fortune, as a line of light rising off the orb it came from.
///
/// **This replaces the card on the field** (owner, after his first session:
/// "the text pop up is annoying"). `FortuneCard` was a bordered, shadowed,
/// centre-screen panel that had to be dismissed — the grammar of an alert,
/// used for the one thing in this game that is meant to feel like a small
/// gift. It stopped the field to hand her a message.
///
/// What it is instead: no panel, no border, no shadow, no scrim, and nothing
/// to dismiss. The words fade in where the orb was, drift upward the way a
/// point whisper does, and leave on their own. She can keep popping straight
/// through it — `allowsHitTesting(false)` guarantees the words can never eat
/// a touch meant for an orb, which was the other half of the annoyance.
///
/// It keeps its own hit-free space rather than being drawn into the `Canvas`
/// with the other float notes, for one reason: a fortune is a SENTENCE, and
/// `Canvas` text does not wrap. SwiftUI `Text` does.
struct FortuneWhisper: View {
    let text: String
    let at: CGPoint

    @State private var lift: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(.system(size: 15, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .foregroundColor(Color(red: 232/255, green: 228/255, blue: 242/255).opacity(0.92))
                .shadow(color: .black.opacity(0.55), radius: 8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: min(300, geo.size.width - 56))
                // Vertically it sits just above the orb it came from, held
                // clear of the counter at the top and the whisper at the
                // foot. Horizontally it centres: the text can run to 300 pt,
                // so following the orb sideways would push a fortune from an
                // edge orb half off the screen for no gain.
                .position(x: geo.size.width / 2,
                          y: min(max(at.y - 52, 150), max(150, geo.size.height - 150)))
                .offset(y: lift)
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.easeOut(duration: 2.4)) { lift = -10 }
                }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityElement()
        .accessibilityLabel(Text(text))
    }
}

// MARK: - Done card

struct DoneCard: View {
    let count: Int
    let sessionPoints: Int
    let lifetimePops: Int
    let onRestart: () -> Void

    // R-CRAFT ITEM 1 — the one place this build stopped being a world.
    //
    // Three reviewers arrived at this view independently and found the same
    // sixty lines. What was here: a full-screen `.ultraThinMaterial` scrim
    // that swallowed every touch on the glass, so while the card was up the
    // swipe was dead and the `your journal` whisper sat underneath it,
    // washed out and untappable, with no escape for VoiceOver — the only
    // thing she could do with her phone, at the moment the field had just
    // gone quiet, was press the brightest object in the game and start
    // another field. It said `Nicely done.` in pure white, congratulating
    // her performance at a game with no performance, and `Nothing left to
    // worry about — for now`, which hands the worry back on the way out. It
    // said `GO AGAIN` in tracked semibold caps on a solid near-white slab
    // that emitted more light than any orb this game draws.
    //
    // 04 §8 W5 specifies the opposite in as many words: the done card
    // "drifts in like a note, not a modal … `again?` (tap) or just leave —
    // swiping away is a valid, unpunished exit."
    //
    // WHAT CHANGED, AND WHY THE SCRIM WENT RATHER THAN GAINING `.isModal`.
    // R-A11Y asked for `.isModal` so VoiceOver could not wander off the card
    // into the world behind it; R-CRAFT asked for the hold to end. Removing
    // the scrim answers both, and they only appeared to conflict because
    // both were reasoning from a modal that should not exist: with nothing
    // covering the world, reaching the whispers is not an escape from the
    // card, it is HOW SHE LEAVES. The card keeps its own bounds, the world
    // stays live underneath, and every exit — swipe up, swipe down, tap a
    // whisper, tap `again?`, or put the phone down — is equally valid and
    // none of them is punished.
    //
    // The words were already written, catalogued, shipped in the binary and
    // called from nowhere: `Strings.fieldIsQuiet` is documented in the
    // catalog as "the done card's chrome" and `Strings.again` as "the
    // invitation after a field is clear". This was a wiring bug wearing a
    // copy bug's clothes.
    var body: some View {
        VStack(spacing: 0) {
            // The checkmark and its ring are gone (05 §6: no icons). A
            // checkmark is also the wrong grammar — it is the mark a task
            // manager uses to say a duty is discharged, and nothing here was
            // a duty.
            Text(Strings.fieldIsQuiet)
                .font(.system(size: 26, weight: .light, design: .serif))
                // NOT `.white`. 05 §2 caps ink at 96% and this was the only
                // literal `.white` used as ink in the app.
                .foregroundColor(CardPalette.bright)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)

            // What she did, stated as a fact about the field rather than as
            // praise aimed at her. `set free` is the counter's own word.
            Text("\(count.formatted()) \(Strings.setFreeLabel)")
                .font(.system(size: 13.5, design: .serif))
                .monospacedDigit()
                .foregroundColor(CardPalette.soft.opacity(0.9))
                .padding(.bottom, 10)

            Text("+\(sessionPoints.formatted()) \(Strings.popPoints)")
                .font(.system(size: 12, design: .serif))
                .italic()
                .monospacedDigit()
                .foregroundColor(CardPalette.accent.opacity(0.9))
                .padding(.bottom, lifetimePops > count ? 6 : 26)

            if lifetimePops > count {
                Text("\(lifetimePops.formatted()) \(Strings.setFreeLabel), all time.")
                    .font(.system(size: 11, design: .serif))
                    .italic()
                    .monospacedDigit()
                    .foregroundColor(CardPalette.dim.opacity(0.85))
                    .padding(.bottom, 26)
            }

            // THE OFFER, NOT THE INSTRUCTION. Serif italic in `soft`, the
            // same grammar the whispers use for "this is touchable" — 05
            // §6.1 names the done card's `again?` as an instance of it. No
            // fill: the brightest moment in this game is the pop, and it
            // must remain the pop.
            Button(action: onRestart) {
                Text(Strings.again)
                    .font(.system(size: 15, design: .serif))
                    .italic()
                    .foregroundColor(CardPalette.soft)
                    .padding(.horizontal, 26)
                    // ≥ 44 pt, the criterion the rest of this build holds
                    // religiously and this button missed at ~40.
                    .frame(minHeight: WhisperPresentation.minimumHitEdge)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(Strings.again))
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 34)
        .frame(maxWidth: 340)
        .background(CardPalette.card.opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

// The cards' tones, which are the field's tones. R-CRAFT S3 asks for one
// `Tokens` type shared by all four palettes in the app and is right to; that
// is an after-playtest refactor, and this enum exists so the cards stop
// carrying loose hex in the meantime — it is the same five values as
// `WorldView`'s `Palette`, which is `private` to that file.
private enum CardPalette {
    static let bright = Color(red: 244/255, green: 242/255, blue: 250/255)
    static let soft   = Color(red: 214/255, green: 204/255, blue: 230/255)
    static let accent = Color(red: 195/255, green: 175/255, blue: 220/255)
    static let dim    = Color(red: 139/255, green: 134/255, blue: 163/255)
    static let card   = Color(red: 24/255, green: 22/255, blue: 34/255)
}
