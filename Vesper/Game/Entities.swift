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
    /// Set when this star came from a shell rather than from a pop, so the
    /// renderer takes its colour from `FireworkCatalog`. Fireworks have their
    /// own palette — hotter and more luminous, because a thing in the air at
    /// night IS brighter than a thing on a table — and a shell whose stars
    /// were pop-coloured would look like an orb that learned to fly.
    var fireworkID: Int? = nil
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

    /// She lit a fuse. The cord starts burning; nothing has flown yet.
    case fuseLit(Firework)

    /// She tapped a burning fuse and pushed it along.
    case fuseHurried(Firework)

    /// A shell was touched and is on its way. Carries the kind so the sound
    /// can whirr in the right register.
    case fireworkLaunched(Firework)

    /// A shell broke. Nothing was popped and nothing is owed — the field is
    /// clear when the ORBS are gone, and a shell she never touched simply
    /// fades with the field.
    case fireworkBurst(Firework)

    /// A generator closed on its own terms: spent, or settled. Deliberately
    /// distinct from `.popped` — nothing was popped, and nothing was lost.
    case generatorClosed(orb: Orb)

    /// A balloon animal was touched and did not go: one health less, and it
    /// darted. Distinct from `.popped` because nothing popped, and distinct
    /// from silence because something DID happen — a touch that lands has to
    /// be answered or it reads as a missed tap, which is the one thing this
    /// mechanic cannot afford to feel like.
    case startled(orb: Orb)
}
