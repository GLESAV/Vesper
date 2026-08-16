import SwiftUI

// THE JOURNAL — the place below the field, and everything she owns.
//
// Three pages, turned by tap: `the evening` (what has accrued), `the
// collection` (the hundred pops as pressed lights), and `the quiet things`
// (sound, haptics, whispers, and the way to begin a field again). It is the
// v1.2 JourneySheet and SettingsSheet with the chrome taken off: no
// navigation bar, no close button, no `.sheet`, no modal — a place she walks
// into and out of on the world's one vertical axis (04 §2).
//
// ─────────────────────────────────────────────────────────────────────────
// FOUR RULES THIS FILE EXISTS TO HOLD. Each is a decision, not a style.
//
//   1. QUIET IS TWO GESTURES, ALWAYS (04 §7). One tap on the `your journal`
//      whisper opens this place, and it always opens on `the evening`, whose
//      first row is `hush`. Gesture two silences sound and haptics together.
//      That is why the journal RESETS to page one when she leaves it: a
//      resumable page is a nicer idea, and it would put the mute two taps
//      away on the evening she needed it in one. The full quiet surface has
//      its own page as well — the same act, reachable twice.
//
//   2. NOTHING HERE CAN REPRESENT AN ABSENCE (03 §3). There is no date, no
//      calendar, no "days since", no time played, no session history and no
//      streak — and not because the copy avoids them: there is no field on
//      this surface from which one could be reconstructed. Every number it
//      shows comes from `ProgressionStore`, which only ever counts up. The
//      veto test — *can any arrangement of what this shows reveal an evening
//      she skipped?* — is answered structurally: no ordering, filtering or
//      arithmetic over `popPoints`, `lifetimePops`, `fieldsCleared`,
//      `fortunesFound` and `bestChain` can name a day at all.
//
//   3. PAGES TURN BY TAP, NEVER BY SWIPE (the Director's ruling; 04 §4).
//      Vertical belongs to the world and the arbiter owns it; horizontal is
//      not borrowed here to compensate. The visible affordance is the ribbon
//      of page names at the foot — words, in the thumb zone, ≥44 pt, and
//      each one a direct jump rather than a step — plus invisible edge taps
//      and VoiceOver custom actions for next/previous.
//
//   4. IT IS THE READING SURFACE. Every size is a Dynamic Type text style,
//      every hit region is ≥44 pt, and the layout reflows into a single
//      column at accessibility sizes rather than truncating.
// ─────────────────────────────────────────────────────────────────────────
//
// COMPOSITION (W05). `JournalView` fills the screen, knows nothing about the
// camera, and is positioned by `WorldView`. It reads `model.place` for one
// purpose only — to refuse every touch unless the journal is the place she is
// in — so that a page laid over a crossfaded field can never take a tap meant
// for an orb. Its own touches must be able to REACH it: the world's moving
// body is `.allowsHitTesting(false)` and `WorldInputLayer` sits above it, so
// this view has to be composed ABOVE the input layer, like the cards, or it
// will render perfectly and never respond. Everything it does not consume —
// empty page space — falls through to the input layer beneath, which is what
// keeps the swipe back up to the field alive from anywhere on the page.

struct JournalView: View {

    // MARK: - The contract

    @ObservedObject private var model: WorldModel

    init(model: WorldModel) {
        self.model = model
    }

    // The two stores this place is a view onto. Shared singletons, exactly as
    // the v1.2 sheets read them.
    @ObservedObject private var progression = ProgressionStore.shared
    @ObservedObject private var settings = SettingsStore.shared

    // Observed live, never read once: both can be turned on mid-evening.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    // MARK: - Page state

    @State private var page: JournalPage = .evening
    // `begin this field again`, armed. Never a timed hold, never a timed
    // disarm — both exclude Switch Control users (04 §6).
    @State private var armed = false
    // The kind hint from a pop she has not met yet. It stays until she asks
    // for another or turns the page: content that removes itself on a timer
    // is content someone reading slowly never gets to read.
    @State private var lockedHint: String?

    // MARK: - Metrics

    @ScaledMetric(relativeTo: .caption) private var cellEdge: CGFloat = 62
    @ScaledMetric(relativeTo: .caption) private var swatchEdge: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 56

    /// Punctuation, not copy: the separator the app already sets between
    /// clauses. It carries no meaning of its own and so has no catalog entry.
    private static let separator = " · "

    /// The gutters the edge taps live in. Page content is inset past them so
    /// nothing readable or tappable ever sits under one.
    private var gutter: CGFloat { WhisperPresentation.minimumHitEdge }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                pageBody
                    .padding(.horizontal, gutter + 4)
                edges
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // THE WORLD IGNORES THE SAFE AREA (WorldView), so this page keeps
            // its own head margin — generous enough to clear a Dynamic Island
            // on every supported iPhone, and the same 60 pt the world's own
            // `the field` whisper is inset by, so a scrolled page never runs
            // up under it. The whisper itself belongs to `WorldView`, above
            // the input layer where it can actually be tapped; the journal
            // does not draw one of its own.
            .padding(.top, 60)

            ribbon
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // RULE: the journal accepts touches only where it IS the place. A
        // full-screen page sitting inert over the field — visible or, under
        // Reduce Motion, crossfaded to nothing — would otherwise eat pops.
        // `place` is published at the commit instant, so this costs one view
        // update per journey, not one per frame.
        .allowsHitTesting(model.place == .journal)
        // And it leaves the accessibility tree with the same predicate. The
        // world keeps all three places mounted at all times, so without this a
        // VoiceOver user standing in the field would swipe straight into the
        // journal's rows — rows the line above has just made unactivatable.
        // The DESTINATIONS that never leave the tree (04 §10) are the
        // whispers, which live in the field's own layer, not in here.
        .accessibilityHidden(model.place != .journal)
        // A container, so the custom actions below have an element to hang
        // on. Deliberately unlabelled: `WorldView` already names this place,
        // and a second label here is the same sentence read twice.
        .accessibilityElement(children: .contain)
        // Page turning without a gesture at all, and the standard two-finger
        // escape home from anywhere in the book (04 §10).
        .accessibilityAction(named: Text(Strings.nextPage)) { turn(by: 1) }
        .accessibilityAction(named: Text(Strings.previousPage)) { turn(by: -1) }
        .accessibilityAction(.escape) { returnToField() }
        .onChange(of: model.place) { _, place in
            guard place != .journal else { return }
            // Rule 1: she always finds `hush` where she left it — first row,
            // first page — however deep in the book she was last time.
            page = .evening
            armed = false
            lockedHint = nil
        }
        .onChange(of: page) { _, _ in
            armed = false
            lockedHint = nil
        }
    }

    // MARK: - The pages

    @ViewBuilder
    private var pageBody: some View {
        Group {
            switch page {
            case .evening:    eveningPage
            case .collection: collectionPage
            case .quiet:      quietPage
            }
        }
        .id(page)
        .transition(.opacity)
    }

    // Page one. What has accrued, and the fastest quiet in the game.
    private var eveningPage: some View {
        pageShell(bottomBiased: false) {
            VStack(alignment: .leading, spacing: 24) {
                heading(Strings.theEvening)
                hushRow
                pointsBlock
                recordsBlock
            }
        }
    }

    // Page two. The hundred pops as pressed lights.
    private var collectionPage: some View {
        let unlocked = progression.unlockedNumbers()

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    heading(Strings.theCollection)
                    Spacer(minLength: 8)
                    Text("\(unlocked.count) \(Strings.collectionOf) \(PopCatalog.all.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(JournalPalette.dim)
                }

                if let hint = lockedHint {
                    Text(hint)
                        .font(.system(.footnote, design: .serif))
                        .italic()
                        .foregroundColor(JournalPalette.soft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(panel())
                }

                driftRow

                LazyVGrid(columns: [GridItem(.adaptive(minimum: cellEdge), spacing: 12)],
                          spacing: 16) {
                    ForEach(PopCatalog.all) { def in
                        popCell(def, isUnlocked: unlocked.contains(def.number))
                    }
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // Page three. The quiet things — and the whole page is laid out low, so
    // the toggles are both first in reading order and inside the thumb's
    // reach (04 §12: primary actions in the bottom 60%).
    private var quietPage: some View {
        pageShell(bottomBiased: true) {
            VStack(alignment: .leading, spacing: 14) {
                heading(Strings.quietThings)

                hushRow

                toggleRow(Strings.sound, Strings.soundDetail, $settings.soundEnabled)
                toggleRow(Strings.haptics, Strings.hapticsDetail, $settings.hapticsEnabled)
                toggleRow(Strings.pointWhispers, Strings.pointWhispersDetail,
                          $settings.pointWhispersEnabled)

                beginAgainBlock
                    .padding(.top, 10)

                Text(Strings.about)
                    .font(.caption2)
                    .foregroundColor(JournalPalette.dim.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - The evening's blocks

    private var pointsBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(progression.popPoints.formatted())
                .font(.system(.largeTitle, design: .serif).weight(.light).monospacedDigit())
                .foregroundColor(JournalPalette.bright)
            Text(Strings.popPoints)
                .font(.caption)
                .tracking(2)
                .foregroundColor(JournalPalette.dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(progression.popPoints) \(Strings.popPoints)"))
    }

    private var recordsBlock: some View {
        // Four across normally; two columns at accessibility sizes, where four
        // would either truncate or shrink the numbers out of legibility.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12),
                            count: typeSize.isAccessibilitySize ? 2 : 4)
        return LazyVGrid(columns: columns, spacing: 18) {
            record(progression.lifetimePops, Strings.setFreeLabel)
            record(progression.fieldsCleared, Strings.fieldsRecord)
            record(progression.fortunesFound, Strings.fortunesRecord)
            record(progression.bestChain, Strings.bestChainRecord)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .background(panel())
    }

    private func record(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted())
                .font(.system(.title3, design: .serif).weight(.light).monospacedDigit())
                .foregroundColor(JournalPalette.bright)
            Text(label)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(JournalPalette.dim)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(value) \(label)"))
    }

    // MARK: - The collection's rows

    // Featuring nothing: fields painted from everything she has found.
    private var driftRow: some View {
        Button {
            progression.featuredPop = nil
            model.game.leavePath()
            returnToField()
        } label: {
            row(title: Strings.drift,
                detail: Strings.driftDetail,
                marked: progression.featuredPop == nil)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Strings.drift))
        .accessibilityValue(Text(progression.featuredPop == nil ? Strings.featuredNow : ""))
        .accessibilityHint(Text(Strings.driftHint))
        .accessibilityAddTraits(.isButton)
    }

    private func popCell(_ def: PopDefinition, isUnlocked: Bool) -> some View {
        let isFeatured = progression.featuredPop == def.number
        let isSecret = def.rarity == .secret
        let paint = def.style.paints.first
        let fill = paint.map { Color(red: $0.fill.r, green: $0.fill.g, blue: $0.fill.b) }
            ?? JournalPalette.soft

        return Button {
            if isUnlocked {
                progression.featuredPop = def.number
                model.game.leavePath()
                returnToField()
            } else {
                // Never a wall: the pop says, kindly, what would bring it.
                lockedHint = isSecret
                    ? def.unlock.hint
                    : def.name + Self.separator + def.unlock.hint
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isUnlocked ? fill : Color.white.opacity(0.05))
                        .frame(width: swatchEdge, height: swatchEdge)
                    if isSecret && !isUnlocked {
                        Text(Strings.secretPopMark)
                            .font(.system(.footnote, design: .serif))
                            .foregroundColor(JournalPalette.dim)
                    }
                    if isFeatured {
                        Circle()
                            .strokeBorder(JournalPalette.accent, lineWidth: 1.5)
                            .frame(width: swatchEdge + 10, height: swatchEdge + 10)
                    }
                }
                .frame(width: swatchEdge + 12, height: swatchEdge + 12)

                Text(isUnlocked ? def.name : Strings.lockedPopName)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundColor(isUnlocked
                                     ? JournalPalette.soft
                                     : JournalPalette.dim.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(WhisperPresentation.minimumHitEdge, swatchEdge + 30))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(popCellLabel(def, isUnlocked: isUnlocked, isSecret: isSecret)))
        .accessibilityValue(Text(isFeatured ? Strings.featuredNow : ""))
        .accessibilityHint(Text(isUnlocked ? Strings.featureHint : def.unlock.hint))
        .accessibilityAddTraits(.isButton)
    }

    // Built from catalog words and a count. The locked form names the pop
    // unless it is a secret, which keeps its name until she meets it — and it
    // carries the unlock hint in the LABEL as well as the hint, because
    // VoiceOver hints can be switched off and the kind half of a locked pop
    // is the part she must not lose.
    private func popCellLabel(_ def: PopDefinition, isUnlocked: Bool, isSecret: Bool) -> String {
        if isUnlocked {
            let count = progression.popCounts[def.number] ?? 0
            return def.name + Self.separator + "\(count) \(Strings.popsSoFar)"
        }
        if isSecret {
            return Strings.lockedPopA11y + Self.separator + def.unlock.hint
        }
        return def.name + Self.separator + Strings.lockedPopA11y
            + Self.separator + def.unlock.hint
    }

    // MARK: - The quiet things

    /// Both off. The only state `hush` needs to know.
    private var isQuiet: Bool {
        !settings.soundEnabled && !settings.hapticsEnabled
    }

    // ONE TAP, BOTH SENSES (04 §7). It is a button and not a switch on
    // purpose: a switch labelled `hush` would have to be ON when the game is
    // LOUD, and a control that reads backwards at 1 a.m. is a control that
    // costs her a second attempt. Instead the row says what a tap will do,
    // and says something different once it has been done.
    private var hushRow: some View {
        Button {
            let bringBack = isQuiet
            settings.soundEnabled = bringBack
            settings.hapticsEnabled = bringBack
        } label: {
            row(title: isQuiet ? Strings.itIsQuiet : Strings.hush,
                detail: Strings.hushDetail,
                marked: isQuiet)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isQuiet ? Strings.itIsQuiet : Strings.hush))
        .accessibilityHint(Text(isQuiet ? Strings.unhushHint : Strings.hushHint))
        .accessibilityAddTraits(.isButton)
    }

    private func toggleRow(_ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundColor(JournalPalette.bright)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(JournalPalette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(JournalPalette.accent)
        .padding(.horizontal, 14)
        .frame(minHeight: rowHeight)
        .background(panel())
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(detail))
    }

    // `begin this field again`, as a plain row with a plain confirmation —
    // the same act the field's long-press arms, reachable with no gesture
    // ritual at all (04 §6). It is last on the last page: discoverable,
    // never looming.
    @ViewBuilder
    private var beginAgainBlock: some View {
        if armed {
            VStack(spacing: 10) {
                Button {
                    armed = false
                    model.game.restart()
                    returnToField()
                } label: {
                    row(title: Strings.beginAgainConfirm, detail: nil, marked: false)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Strings.beginAgainConfirm))
                .accessibilityHint(Text(Strings.beginAgainHint))
                .accessibilityAddTraits(.isButton)

                Button { armed = false } label: {
                    row(title: Strings.notNow, detail: nil, marked: false)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Strings.notNow))
                .accessibilityAddTraits(.isButton)
            }
        } else {
            Button { armed = true } label: {
                row(title: Strings.beginAgain, detail: Strings.beginAgainDetail, marked: false)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Strings.beginAgain))
            .accessibilityHint(Text(Strings.beginAgainHint))
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: - Page turning

    // The visible affordance: the three page names, in the thumb zone, each a
    // direct jump. Words, never icons (04 §2). At accessibility sizes the
    // ribbon stacks rather than truncating.
    private var ribbon: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    ForEach(JournalPage.allCases) { ribbonEntry($0) }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(JournalPage.allCases) { ribbonEntry($0) }
                }
            }
        }
        .padding(.horizontal, 12)
        // Clear of the home indicator, for the same reason as the head.
        .padding(.bottom, 34)
    }

    private func ribbonEntry(_ entry: JournalPage) -> some View {
        let isCurrent = entry == page
        return Button { turn(to: entry) } label: {
            Text(entry.title)
                .font(.system(.footnote, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(JournalPalette.bright)
                // Never to nothing: the page she is not on is still findable
                // in the dark (04 §9's floor, applied to the same kind of
                // signage the whispers are).
                .opacity(isCurrent ? 0.95 : 0.45)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: WhisperPresentation.minimumHitEdge)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.title))
        .accessibilityHint(Text(Strings.pageHint))
        .accessibilityAddTraits(ribbonTraits(isCurrent: isCurrent))
    }

    private func ribbonTraits(isCurrent: Bool) -> AccessibilityTraits {
        var traits: AccessibilityTraits = .isButton
        if isCurrent { traits.insert(.isSelected) }
        return traits
    }

    // The page edges. Invisible, ≥44 pt, and hidden from VoiceOver on
    // purpose: the ribbon above already exposes every page by name, and the
    // custom actions expose the turn itself. Two unlabelled hit regions in
    // the rotor would be noise.
    private var edges: some View {
        HStack(spacing: 0) {
            if page.neighbour(-1) != nil { edgeTap(-1) }
            Spacer(minLength: 0)
            if page.neighbour(1) != nil { edgeTap(1) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func edgeTap(_ delta: Int) -> some View {
        Button { turn(by: delta) } label: {
            Color.clear
                .frame(width: gutter, height: 220)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private func turn(by delta: Int) {
        guard let next = page.neighbour(delta) else { return }
        turn(to: next)
    }

    private func turn(to next: JournalPage) {
        guard next != page else { return }
        // 04 §11: the page-turn glow's reduced variant is a plain crossfade,
        // and under Reduce Motion there is no crossfade to animate at all.
        if reduceMotion {
            page = next
        } else {
            withAnimation(.easeInOut(duration: 0.4)) { page = next }
        }
    }

    // MARK: - Leaving

    // The one way back, and the same one the whisper and the swipe use. The
    // camera's own commit path — this view never touches the camera.
    private func returnToField() {
        model.handle([.commit(.up, velocity: 0)])
    }

    // MARK: - Shared pieces

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(.title3, design: .serif).weight(.light))
            .foregroundColor(JournalPalette.bright)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    // A page that fits is laid out still; a page that does not, scrolls.
    // `bottomBiased` puts the quiet page's controls low on the glass without
    // stopping them from being first in reading order.
    private func pageShell<Content: View>(bottomBiased: Bool,
                                          @ViewBuilder content: () -> Content) -> some View {
        let built = content()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)

        return ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                if bottomBiased { Spacer(minLength: 0) }
                Spacer(minLength: 0)
                built
                Spacer(minLength: 0)
            }
            ScrollView {
                built.padding(.vertical, 20)
            }
        }
    }

    private func row(title: String, detail: String?, marked: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundColor(JournalPalette.bright)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(JournalPalette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if marked {
                Circle()
                    .fill(JournalPalette.accent)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: rowHeight)
        .background(panel())
        .contentShape(Rectangle())
    }

    private func panel() -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(JournalPalette.card.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

// MARK: - The pages, as data

// Ordered as the book is: the evening, the collection, the quiet things.
// `the quiet things` is last because it is the page with the destructive-
// adjacent row on it; `the evening` is first because it is the page with
// `hush` on it, and that ordering is the whole of rule 1.
private enum JournalPage: Int, CaseIterable, Identifiable {
    case evening
    case collection
    case quiet

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .evening:    return Strings.theEvening
        case .collection: return Strings.theCollection
        case .quiet:      return Strings.quietThings
        }
    }

    // Clamped, never wrapped: a book that loops has no edges, and the edge is
    // how she knows where she is in it.
    func neighbour(_ delta: Int) -> JournalPage? {
        JournalPage(rawValue: rawValue + delta)
    }
}

// MARK: - Palette

// The same muted tones the rest of the world uses. Mirrored rather than
// shared because `WorldView`'s palette is private to that file; if a third
// place ever needs them too, this is the copy to lift out.
private enum JournalPalette {
    static let bright = Color(red: 244/255, green: 242/255, blue: 250/255)
    static let soft   = Color(red: 214/255, green: 204/255, blue: 230/255)
    static let accent = Color(red: 195/255, green: 175/255, blue: 220/255)
    static let dim    = Color(red: 139/255, green: 134/255, blue: 163/255)
    static let card   = Color(red: 24/255, green: 22/255, blue: 34/255)
}
