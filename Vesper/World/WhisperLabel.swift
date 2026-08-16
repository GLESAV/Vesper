import SwiftUI
import UIKit

// The only navigation signage in Vesper. Icons are banned from the world
// (04 §2, 05 §6), so these two whispers — `the sky` at the top edge and
// `your journal` at the foot — are how a person who does not know the swipe
// finds out there is anywhere else to go.
//
// Three review findings shaped this file, and each one is a rule here rather
// than a preference:
//
//   1. It dims, it never vanishes (04 §9, 05 §6). A control that fades to
//      nothing is a control she cannot find at 1 a.m., and the dark-room test
//      is this product's own bar. The floor is committed in
//      `WhisperPresentation` and proven in WhisperLabelTests.
//   2. With an assistive technology running it does not fade at all — not to
//      the floor, not in a breath. Fading is a *visual* affordance decision
//      taken on behalf of someone reading the screen; when the screen is being
//      read to her, or driven by a switch, the whisper simply stays lit.
//   3. It is tappable, with a ≥44 pt hit region. See `minimumHitEdge` — the
//      Director's R-SPIKE ruling 7 makes this tap the *primary* route to the
//      journal, not a courtesy.
//
// This view owns no layout: where the whispers sit, and whether the field is
// in play, are the world view's business (W05). It takes its text and its
// accessibility label from `Strings` via the call site — no literals live here.

// MARK: - Presentation (pure, testable)

/// Everything about how a whisper is lit, with no SwiftUI and no clock in it.
///
/// It exists as its own value type for one reason: the opacity floor and the
/// assistive-technology override are the two things a review will ask us to
/// *prove*, and a number buried in a view modifier cannot be proven in CI.
struct WhisperPresentation: Equatable {

    // MARK: Committed values

    /// Top of the idle breath. `text.whisper` idles at 70–85% (05 §2.1, §5);
    /// this is the lit end of that band and the value used whenever the
    /// whisper is held steady.
    static let idleHigh: Double = 0.85

    /// Bottom of the idle breath — the *breath*, not the play-time dim.
    static let idleLow: Double = 0.70

    /// The committed play-time floor (04 §9, 05 §2.1/§6). Never zero.
    ///
    /// The two docs can be read two ways — 40% of idle (≈0.34) or a flat 40%.
    /// We take the flat, brighter reading deliberately: it is the one that
    /// still clears the APCA Lc ≥ 60 floor for functional text at final
    /// composited opacity (05 §2.2), and when a legibility floor is ambiguous
    /// the legible reading wins. If the on-device APCA measurement at minimum
    /// brightness disagrees, this constant moves up, never down.
    static let playFloor: Double = 0.40

    /// One full breath, in seconds. "Nothing blinks. Light *breathes*
    /// (≥ 2 s cycles)" (05 §3) — so this may never drop below 2.
    static let breathPeriod: Double = 3.2

    /// The short crossfade between two steady states (idle ↔ play dim). Long
    /// enough that the whisper never flicks; inside 05 §7's feedback band.
    static let settleDuration: Double = 0.5

    /// Minimum edge of the invisible hit region (04 §9, 05 §6, 10 pt-ish text
    /// notwithstanding). The visual is small on purpose; the target is not.
    static let minimumHitEdge: CGFloat = 44

    // MARK: State

    /// The field is being played — orbs on screen, hands busy.
    var isPlaying: Bool
    /// VoiceOver, Switch Control, or another assistive technology is running.
    var assistiveTechRunning: Bool
    /// The system Reduce Motion setting.
    var reduceMotion: Bool

    init(isPlaying: Bool, assistiveTechRunning: Bool, reduceMotion: Bool) {
        self.isPlaying = isPlaying
        self.assistiveTechRunning = assistiveTechRunning
        self.reduceMotion = reduceMotion
    }

    // MARK: Derived

    /// The pure form of the override, so the truth table can be tested without
    /// a device: any assistive technology at all counts.
    static func assistiveTechIsRunning(voiceOver: Bool, switchControl: Bool) -> Bool {
        voiceOver || switchControl
    }

    /// Whether this whisper animates at all.
    ///
    /// It breathes only when the field is idle, no assistive technology is
    /// running, and Reduce Motion is off. Under Reduce Motion the grammar
    /// "breathing = touchable" (05 §6.1) is carried by the accessibility tree
    /// instead (05 §6.2, §7.3), so the whisper is simply held steady.
    var breathes: Bool {
        !assistiveTechRunning && !reduceMotion && !isPlaying
    }

    /// The opacity the whisper rests at — the value it holds when it is not
    /// breathing, and the dim end of the breath when it is.
    var restingOpacity: Double {
        // Finding 2 first, and unconditionally: with an assistive technology
        // running the whisper does not fade, in play or out of it.
        if assistiveTechRunning { return Self.idleHigh }
        if isPlaying { return Self.playFloor }
        return breathes ? Self.idleLow : Self.idleHigh
    }

    /// The lit end of the breath. Equal to `restingOpacity` whenever the
    /// whisper is static, which is what makes "static" fall out of the same
    /// arithmetic instead of needing a second code path.
    var litOpacity: Double {
        breathes ? Self.idleHigh : restingOpacity
    }

    /// The opacity to render, given where the breath currently is.
    func opacity(atBreathPeak: Bool) -> Double {
        atBreathPeak ? litOpacity : restingOpacity
    }
}

// MARK: - Assistive technology, observed live

/// Live assistive-technology state.
///
/// Read once at launch, this is wrong for everyone who turns VoiceOver on
/// *while playing* — which is most of the people it matters to — so the two
/// status notifications are observed instead (the same "observed live, never
/// read once at launch" discipline Amara set for Reduce Motion at R-SPIKE).
///
/// It is a singleton with no `deinit` on purpose: its lifetime is the app's,
/// so there is never an observer to tear down.
///
/// Not `@MainActor`: the object is deliberately plain so that a SwiftUI view
/// can hold it in a property initializer without isolation friction. Its one
/// mutable value is only ever written from the notification observers below,
/// which are registered on `.main` — main-thread mutation is a property of the
/// registration, not of an annotation.
final class AssistiveTechMonitor: ObservableObject {

    static let shared = AssistiveTechMonitor()

    @Published private(set) var isRunning: Bool

    private init() {
        isRunning = Self.currentValue()

        let names: [Notification.Name] = [
            UIAccessibility.voiceOverStatusDidChangeNotification,
            UIAccessibility.switchControlStatusDidChangeNotification
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isRunning = AssistiveTechMonitor.currentValue()
            }
        }
    }

    private static func currentValue() -> Bool {
        WhisperPresentation.assistiveTechIsRunning(
            voiceOver: UIAccessibility.isVoiceOverRunning,
            switchControl: UIAccessibility.isSwitchControlRunning
        )
    }
}

// MARK: - The view

/// A single wayfinding whisper: lowercase serif italic, breathing when idle,
/// dimmed but never gone in play, and always a button to whatever it names.
struct WhisperLabel: View {

    /// The visible whisper. Comes from `Strings` at the call site.
    let text: String
    /// The VoiceOver label — `Strings.skyA11y` / `Strings.journalA11y`.
    let accessibilityLabel: String
    /// What happens on activation, in the game's voice. Supplied by the call
    /// site so this file stays literal-free; it belongs in the 07 §5 string
    /// catalog and should move into `Strings` the moment that catalog grows a
    /// slot for hints. It is deliberately non-optional: a whisper that ships
    /// without a hint is a review failure, and a defaulted parameter is how
    /// that happens quietly.
    let hint: String
    /// True while the field is in play — the only input to the dim.
    let isPlaying: Bool
    let onTap: () -> Void

    /// The whisper's only initializer, written out by hand rather than
    /// synthesized.
    ///
    /// The private state below (the assistive-technology monitor, the breath,
    /// the scaled hit edge) would make the memberwise initializer private, and
    /// a private initializer means no other file in the module can build a
    /// whisper — which is how the world shipped with no tappable wayfinding at
    /// all. This initializer is `internal` on purpose and takes exactly the
    /// four values a call site is allowed to decide, so the state that proves
    /// the accessibility findings stays private and unreachable from outside.
    init(text: String,
         accessibilityLabel: String,
         hint: String,
         isPlaying: Bool = false,
         onTap: @escaping () -> Void) {
        self.text = text
        self.accessibilityLabel = accessibilityLabel
        self.hint = hint
        self.isPlaying = isPlaying
        self.onTap = onTap
    }

    @ObservedObject private var assistive = AssistiveTechMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the breath currently is. A single Bool is the whole animation
    /// state: the opacity it maps to is decided by `WhisperPresentation`, so a
    /// whisper that is not breathing maps both ends of it to one value and the
    /// static case needs no second code path.
    @State private var breathUp = false

    /// The hit region scales with Dynamic Type but is floored at 44 pt: at the
    /// small end `@ScaledMetric` would otherwise shrink the target below the
    /// standard, and the target is the one thing that may never get smaller.
    @ScaledMetric(relativeTo: .footnote) private var scaledHitEdge: CGFloat = WhisperPresentation.minimumHitEdge

    private var presentation: WhisperPresentation {
        WhisperPresentation(isPlaying: isPlaying,
                            assistiveTechRunning: assistive.isRunning,
                            reduceMotion: reduceMotion)
    }

    private var hitEdge: CGFloat {
        max(scaledHitEdge, WhisperPresentation.minimumHitEdge)
    }

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(.footnote, design: .serif))
                .italic()
                .tracking(0.5)
                .multilineTextAlignment(.center)
                // Wraps and grows rather than truncating, so the whisper still
                // reads at AX5 (05 §5). Swapping to a shorter canonical form
                // past two lines is the string catalog's job, not this view's.
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(Self.whisperInk)
                .blendMode(.plusLighter) // `text.whisper` is lit, not printed (05 §2.1)
                .opacity(presentation.opacity(atBreathPeak: breathUp))
                // Two scoped animations, never one ambient one. The breath is
                // attached to `breathUp` and to nothing else; the crossfade
                // between steady states is attached to `presentation`. Sharing
                // a single `.animation` here would put a repeat-forever curve
                // on the play dim, which is the "whisper pulses while she is
                // popping" failure.
                .animation(breathAnimation, value: breathUp)
                .animation(settleAnimation, value: presentation)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                // THE HIT REGION IS THE PRIMARY PATH, NOT A COURTESY.
                // R-SPIKE ruling 7: the bottom whisper is the primary route to
                // the journal and to quiet, with the down-swipe demoted to an
                // enhancement, because a one-handed thumb starting low has too
                // little runway for a reliable down-swipe. The five-second
                // mute target rides on this tap. It is ≥44 pt on both axes and
                // invisible, per 04 §9 / 05 §6, and it is deliberately larger
                // than the text it wraps.
                .frame(minWidth: hitEdge, minHeight: hitEdge)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The whisper is a destination, and destinations never leave the
        // accessibility tree regardless of visual fade state (04 §10, 05
        // §6.2). The play-time floor above is what makes that true visually;
        // this block is what makes it true for VoiceOver — and not one line of
        // it is conditional on the whisper's current opacity or on whether it
        // is breathing.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(.isButton)
        .onAppear { syncBreath() }
        // Observed live, never read once: Reduce Motion and assistive
        // technology can both turn on mid-session, and the whisper has to stop
        // moving the moment they do.
        .onChange(of: presentation) { _, _ in syncBreath() }
    }

    /// `text.whisper` — #E8E4DA (05 §2.1). The only color this view knows.
    private static let whisperInk = Color(red: 232/255, green: 228/255, blue: 218/255)

    // MARK: Lighting

    /// The breath, or nothing at all. `nil` is what stops an in-flight
    /// repeat-forever cycle when Reduce Motion or an assistive technology
    /// comes on mid-breath.
    private var breathAnimation: Animation? {
        guard presentation.breathes else { return nil }
        return .easeInOut(duration: WhisperPresentation.breathPeriod / 2)
            .repeatForever(autoreverses: true)
    }

    /// The crossfade between two steady states (idle ↔ the play dim). `nil`
    /// under Reduce Motion, and `nil` under an assistive technology — where
    /// there is nothing to cross-fade anyway, since the whisper does not fade.
    private var settleAnimation: Animation? {
        if presentation.reduceMotion || presentation.assistiveTechRunning { return nil }
        return .easeInOut(duration: WhisperPresentation.settleDuration)
    }

    /// Starts or stops the breath by moving `breathUp` to the end the current
    /// state calls for.
    ///
    /// Stopping matters as much as starting: leaving `breathUp` at `true` on
    /// the way out of a breathing state would mean the next entry into one has
    /// no edge to animate across, and the whisper would sit lit and still
    /// while claiming to breathe.
    private func syncBreath() {
        breathUp = presentation.breathes
    }
}

// MARK: - The two destinations

extension WhisperLabel {

    /// `the sky` — the top-edge whisper. Redundant wayfinding by design: the
    /// primary way up is the anywhere-swipe, so nothing here has to be reached
    /// at the top of the screen one-handed (04 §9, 05 §6).
    static func sky(hint: String, isPlaying: Bool = false, onTap: @escaping () -> Void) -> WhisperLabel {
        WhisperLabel(text: Strings.skyWhisper,
                     accessibilityLabel: Strings.skyA11y,
                     hint: hint,
                     isPlaying: isPlaying,
                     onTap: onTap)
    }

    /// `your journal` — the foot of the field, and the primary path to the
    /// journal and to quiet (R-SPIKE ruling 7).
    static func journal(hint: String, isPlaying: Bool = false, onTap: @escaping () -> Void) -> WhisperLabel {
        WhisperLabel(text: Strings.journalWhisper,
                     accessibilityLabel: Strings.journalA11y,
                     hint: hint,
                     isPlaying: isPlaying,
                     onTap: onTap)
    }
}
