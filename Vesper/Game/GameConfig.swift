import CoreGraphics
import Foundation

// Every gameplay tuning constant, transcribed 1:1 from v1.0.
// These values are the feel of the game — change deliberately, one at a time.
enum GameConfig {

    // MARK: Field

    static let orbCountRange: Range<Int> = 7..<20
    static let orbRadiusRange: ClosedRange<CGFloat> = 18...34
    static let orbMaxSpeed: CGFloat = 0.18
    static let edgeInset: CGFloat = 24
    static let spawnTopInset: CGFloat = 100
    static let fieldTopInset: CGFloat = 70
    static let paintCount = 5

    // MARK: Touch

    static let tapTolerance: CGFloat = 12

    // MARK: Orb motion

    static let wobbleAmount: CGFloat = 0.03
    static let wobbleSpeed: CGFloat = 0.02
    static let spawnGrowth: CGFloat = 0.05

    // MARK: Shockwave rings

    static let ringBaseMaxRadius: CGFloat = 110
    static let ringRadiusPerOrbRadius: CGFloat = 2.6
    static let ringGrowthFactor: CGFloat = 0.1
    static let ringGrowthLinear: CGFloat = 1.5
    static let ringLifeDecay: CGFloat = 0.03
    static let ringArmRadius: CGFloat = 18
    static let ringShellThickness: CGFloat = 24
    static let ringDisarmFraction: CGFloat = 0.5

    // MARK: Particles

    static let particleBaseCount = 18
    static let particleGravity: CGFloat = 0.07
    static let particleDamping: CGFloat = 0.986
    static let particleCap = 320

    // MARK: Ambient motes

    static let moteCount = 36

    // MARK: Frame stepping

    // dt is clamped so a long system stall or backgrounding never makes the
    // sim explode; 1 unit of f == one 60 fps frame's worth of motion.
    static let maxFrameDt: TimeInterval = 0.05

    // MARK: UI timing

    static let fortuneDisplayDuration: TimeInterval = 3.6
    static let doneRevealDelay: TimeInterval = 0.65
    static let chainNoteThreshold = 3
    static let chainWindow: TimeInterval = 0.9
    static let chainNoteDuration: TimeInterval = 1.4
}
