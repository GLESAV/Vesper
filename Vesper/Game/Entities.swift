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
    case fortuneRevealed
    case cleared(total: Int)
}
