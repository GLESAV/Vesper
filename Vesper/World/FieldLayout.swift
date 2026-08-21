import CoreGraphics

// THE FIELD'S VERTICAL BANDS, IN ONE PLACE.
//
// The owner found the sky whisper and the counter crashing into each other at
// the top of the field, and that was not a spacing slip — it was the absence
// of anything that owned the question. The whisper was placed 60 pt from the
// top, the counter 10 pt from the top, and the orbs kept above a hardcoded 70;
// three numbers in three files, none aware of the others, all measured from an
// edge that ignores the safe area. On a Dynamic Island phone the counter was
// under the island as well.
//
// WHY THEY CANNOT SIMPLY SHARE A STACK, which is the fix a reader will reach
// for first. The whispers must be siblings of the moving body — a whisper
// composed inside a place travels off screen exactly when she needs it (§3 of
// `composition`). The HUD must be inside the field — the counter belongs to
// the place and leaves the screen when she does, which is most of what makes
// the field somewhere rather than a screen. They are in different layers by
// design, so SwiftUI cannot lay them out relative to one another, and the only
// honest alternative is a contract they both read.
//
// THE COLLISION THAT MATTERS MOST IS NOT THE VISUAL ONE. The whisper is a
// Button in a layer ABOVE the input layer, so an orb drifting under "the sky"
// has its tap taken by the whisper: she aims at an orb and the world travels.
// That is a pop being stolen by navigation — the exact failure class R-SPIKE
// exists to prevent, arriving through layout rather than through arbitration.
// `orbCeiling` and `orbFloor` are what close it, and they are the reason the
// simulation's insets are now driven from here instead of from a constant.
//
// Pure, `Equatable`, no SwiftUI: it is a set of numbers derived from a size,
// the real safe-area insets, and the measured height of a whisper's target at
// the current Dynamic Type size.
struct FieldLayout: Equatable {

    let size: CGSize
    /// True safe-area insets, reported from UIKit — the world ignores the safe
    /// area, so these cannot be read from the SwiftUI geometry.
    let safeTop: CGFloat
    let safeBottom: CGFloat
    /// The whisper's actual target height at the current text size. Passed in
    /// rather than assumed, because it is `@ScaledMetric` and grows with
    /// Dynamic Type — assuming 44 is how this collision comes back at AX
    /// sizes for the people least able to absorb it.
    let whisperBand: CGFloat

    init(size: CGSize,
         safeTop: CGFloat,
         safeBottom: CGFloat,
         whisperBand: CGFloat = WhisperPresentation.minimumHitEdge) {
        self.size = size
        self.safeTop = max(0, safeTop)
        self.safeBottom = max(0, safeBottom)
        self.whisperBand = max(WhisperPresentation.minimumHitEdge, whisperBand)
    }

    // MARK: The constants of the contract

    /// Breathing room between two things that must not touch.
    static let gap: CGFloat = 14
    /// How far signage sits from the safe edge.
    static let edgeGap: CGFloat = 8
    /// The counter's line box at its 40 pt face.
    static let counterHeight: CGFloat = 48
    /// The one transient-note slot beneath the counter.
    static let noteHeight: CGFloat = 18
    static let hudSpacing: CGFloat = 6

    // MARK: The bands, top down

    /// Top of the sky whisper's tap target.
    var headWhisperTop: CGFloat { safeTop + Self.edgeGap }
    var headWhisperBottom: CGFloat { headWhisperTop + whisperBand }

    /// Top of the counter. Below the signage, never beside it.
    var hudTop: CGFloat { headWhisperBottom + Self.gap }
    var hudHeight: CGFloat { Self.counterHeight + Self.hudSpacing + Self.noteHeight }
    var hudBottom: CGFloat { hudTop + hudHeight }

    /// **No orb may go above this.** Keeps the field clear of both the
    /// signage (which would steal its tap) and the counter (which would be
    /// unreadable behind it).
    var orbCeiling: CGFloat { hudBottom + Self.gap }

    /// Bottom of the journal whisper's tap target, and the top of it.
    var footWhisperBottom: CGFloat { size.height - safeBottom - Self.edgeGap }
    var footWhisperTop: CGFloat { footWhisperBottom - whisperBand }

    /// **No orb may go below this**, for the same tap-stealing reason.
    var orbFloor: CGFloat { footWhisperTop - Self.gap }

    // MARK: What the views need

    /// Padding from the bottom edge for the foot whisper.
    var footWhisperInset: CGFloat { safeBottom + Self.edgeGap }

    /// Padding from the bottom edge for the first-run hint, so it sits clear
    /// of the journal whisper rather than under it.
    var hintBottomInset: CGFloat { size.height - footWhisperTop + Self.gap }

    /// What the simulation is told, so orbs bounce off the bands rather than
    /// drifting behind them.
    var simTopInset: CGFloat { orbCeiling }
    var simBottomInset: CGFloat { max(0, size.height - orbFloor) }

    /// The play area left over. Never negative; on a very short screen the
    /// bands win and this simply reports how little is left.
    var playHeight: CGFloat { max(0, orbFloor - orbCeiling) }

    /// True when the field still has somewhere to put orbs. A screen too
    /// short for the contract is a real possibility (Split View on iPad,
    /// a future small device), and the answer is to know it rather than to
    /// draw orbs into the signage.
    var isPlayable: Bool { playHeight >= 120 }
}
