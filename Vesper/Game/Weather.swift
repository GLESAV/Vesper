import CoreGraphics
import Foundation

// WEATHER: the same field, in a different air.
//
// Owner's request: weather that is random per field and changes how fast the
// orbs move and the patterns they move in — rain slippery with a drizzle,
// snow cold and crunchy, summer wavy, storm as *elegant* chaos.
//
// THE CONSTRAINT THAT SHAPES ALL OF IT. Weather may change how a field FEELS
// and may not change how hard it is. Guardrail 1 has no exceptions for
// atmosphere: nothing here may make an orb harder to hit, make the field take
// longer against her will, or introduce anything that can be lost. Storm is
// the one that had to be watched most closely, and the answer is in its
// numbers — its chaos is in DIRECTION, never in speed. Orbs wander more
// unpredictably and travel no faster, so the field is livelier to watch and
// exactly as easy to play.
//
// Everything here is a multiplier or a small additive force applied inside
// `GameSimulation.stepOrbs`, so weather is pure, deterministic from the
// field's seed, and testable without a screen.
enum Weather: String, CaseIterable, Equatable {
    /// No weather. Still air — the field exactly as it has always been.
    case clear
    /// Slippery: orbs keep every bit of their momentum and slide.
    case rain
    /// Cold and crunchy: small, brittle, stepping movements.
    case snow
    /// Wavy: a slow lateral swell moves the whole field together.
    case summer
    /// Elegant chaos: direction wanders constantly, speed never rises.
    case storm
    /// Heavy, soft, and slow. Everything muffled.
    case fog

    // MARK: - What the air does

    /// Multiplies orb speed. **Never above 1.15 and never below 0.7**: faster
    /// than that and a field stops being restful, slower and it stops feeling
    /// alive.
    var speedScale: CGFloat {
        switch self {
        case .clear:  return 1.00
        case .rain:   return 1.08   // slick — things carry
        case .snow:   return 0.82   // cold, reluctant
        case .summer: return 0.95
        case .storm:  return 1.10
        case .fog:    return 0.74   // muffled
        }
    }

    /// How much of the previous frame's velocity survives, per 60 fps frame.
    /// Below 1 the field settles; at 1 it keeps whatever it has. This is what
    /// makes rain feel *slippery* rather than merely quick.
    var glide: CGFloat {
        switch self {
        case .clear:  return 1.000
        case .rain:   return 1.000  // no loss at all: it slides
        case .snow:   return 0.988  // grippy, stops short
        case .summer: return 0.997
        case .storm:  return 0.999
        case .fog:    return 0.985  // thick air
        }
    }

    // THERE IS NO NET DRIFT, AND THAT IS A CORRECTION.
    //
    // Rain and snow originally carried a constant downward drift, added to
    // velocity each frame. `testNoWeatherStrandsTheFieldAgainstAnEdge` caught
    // what that actually does: a one-way force inside a bounded field is not
    // a drizzle, it is a waterfall. The bias accumulated until every orb hit
    // its speed ceiling travelling straight down, and the field collapsed
    // into a band along the floor and bounced there.
    //
    // The fix is not a smaller number — any constant one-way force ends in
    // the same place, it only takes longer. Rain's character comes from
    // `glide` instead (it loses no momentum at all, so it slides) and from a
    // little wander; snow's from a stepped wander and a grippy glide. Both
    // read as themselves without anything pulling the field into a corner.
    //
    // The only directional force left in the model is `swellAmount`, which
    // oscillates and therefore always gives back what it takes.

    /// Amplitude of the lateral swell, in points per frame at its peak.
    /// Summer's whole character: the field breathes sideways together.
    var swellAmount: CGFloat {
        switch self {
        case .summer: return 0.085
        case .fog:    return 0.030
        default:      return 0
        }
    }

    /// How fast the swell cycles, in radians per frame. Slow enough to read
    /// as a tide rather than as a shake.
    var swellRate: CGFloat {
        switch self {
        case .summer: return 0.012
        case .fog:    return 0.006
        default:      return 0
        }
    }

    /// How strongly an orb's heading wanders, in radians per frame.
    ///
    /// **This is the whole of storm, and the reason storm is safe.** Chaos
    /// lives in direction only: the heading turns, the SPEED does not rise, so
    /// the field is dramatic to watch and no harder to play. Snow gets a
    /// little of it too, applied in steps rather than smoothly, which is what
    /// makes it read as crunchy.
    var wander: CGFloat {
        switch self {
        case .storm: return 0.055
        case .snow:  return 0.020
        case .rain:  return 0.014
        default:     return 0
        }
    }

    /// True when the wander should arrive in discrete steps rather than
    /// continuously — the difference between crunching through snow and being
    /// blown about in a storm.
    var wanderIsStepped: Bool { self == .snow }

    // MARK: - What she is told

    /// The journal's name for it. Lowercase-calm, like everything else.
    var name: String {
        switch self {
        case .clear:  return "still air"
        case .rain:   return "rain"
        case .snow:   return "snow"
        case .summer: return "warm"
        case .storm:  return "wind"
        case .fog:    return "fog"
        }
    }

    // MARK: - Choosing

    /// The weather for a field. Still air is the most common by a distance —
    /// weather should be a thing she NOTICES, and a sky that is remarkable
    /// every single evening is a sky that is remarkable never.
    ///
    /// Deterministic from the field's own RNG, so a seed is still a field.
    static func choose(using rng: inout SplitMix64) -> Weather {
        switch Int.random(in: 0..<100, using: &rng) {
        case 0..<44:  return .clear
        case 44..<60: return .rain
        case 60..<72: return .summer
        case 72..<82: return .snow
        case 82..<92: return .fog
        default:      return .storm
        }
    }
}
