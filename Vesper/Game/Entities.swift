import CoreGraphics

// Value types for everything the simulation moves. Deliberately UI-free:
// looks are referenced by pop number + paint-variant index (into
// PopCatalog / PopStyle.paints) so the sim never imports SwiftUI.

struct Orb {
    var pos: CGPoint
    var vel: CGVector
    var r: CGFloat
    var baseR: CGFloat
    var popNumber: Int
    var variantIndex: Int
    var phase: CGFloat
    var alive: Bool = true
    var spawn: CGFloat = 0
    var isFortune: Bool = false

    /// What this orb does beyond drifting and popping. Defaulted, so every
    /// existing construction site and test still reads as it did.
    var kind: OrbKind = .plain
}

struct Particle {
    var pos: CGPoint
    var vel: CGVector
    var life: CGFloat
    var decay: CGFloat
    var size: CGFloat
    var popNumber: Int
    var variantIndex: Int
}

struct Ring {
    var pos: CGPoint
    var r: CGFloat
    var maxR: CGFloat
    var life: CGFloat
    var popNumber: Int
    var variantIndex: Int
    var popped: Bool
}

struct Mote {
    var pos: CGPoint
    var vel: CGVector
    var size: CGFloat
    var alpha: CGFloat
    var phase: CGFloat
}

// A soft line of text that drifts up and fades (point whispers).
struct FloatNote {
    var pos: CGPoint
    var text: String
    var life: CGFloat
}

enum GameEvent {
    case popped(orb: Orb, chained: Bool)
    /// A fortune orb went. Carries WHERE, so the words can rise from the
    /// place the orb was instead of arriving in the middle of the screen.
    case fortuneRevealed(at: CGPoint)
    case cleared(total: Int)

    /// A splitter opened into children. Carries the parent (for where and what
    /// colour) and how many arrived.
    case split(from: Orb, into: Int)

    /// A generator produced an orb — by its own interval, or because she
    /// pressed it and it gave one up without closing.
    case emitted(orb: Orb, byTap: Bool)

    /// An orb rose from below into room she had just made. Distinct from
    /// `.emitted`: nothing was created here, something that was already in
    /// the field came up into view.
    case rose(orb: Orb)

    /// A generator closed on its own terms: spent, or settled. Deliberately
    /// distinct from `.popped` — nothing was popped, and nothing was lost.
    case generatorClosed(orb: Orb)
}
