import CoreGraphics
import Foundation

// ANIMAL POPS — the balloon animals.
//
// Owner: "the pops look too similar across the 100 … make animal pops, like a
// balloon animal, that hides across the screen (is hard to pop) and has pop
// health."
//
// THE LINE THIS WALKS. "Hides" and "hard to pop" are, read literally, a
// request for a thing that can be missed and a thing that can be failed —
// which is the one shape this game may not have. A creature that successfully
// evades is not charming, it is a boss fight in a game about going to sleep.
//
// So it is SHY, not evasive, and the difference is entirely in `shyness`,
// which decays. Early in its life it keeps to the edges and eases away from a
// finger; left alone it settles, comes out, and waits in the open. It is hard
// to catch for as long as chasing it is fun and no longer, and nobody has to
// know that is why. The field cannot be finished without it, so it must be
// catchable by everyone, including someone who is tired and not really trying.
//
// `health` is the other half: it takes a few taps, and each one startles it
// into a short dart. That is what makes it feel like a creature rather than a
// target — it reacts — and it is the same mechanic as a `.taps` generator,
// where the last press is the reward.
struct AnimalPop: Equatable {

    /// The silhouette. Balloon animals: a few joined lobes, never a drawing.
    enum Shape: String, CaseIterable {
        case cat, bird, fish, rabbit, fox, bear, deer, frog

        /// Lobes as (offset from centre, radius), both in units of the orb's
        /// radius. Read by the renderer; kept here so the shape and the
        /// creature that has it live in one file.
        var lobes: [(CGPoint, CGFloat)] {
            switch self {
            case .cat:
                return [(CGPoint(x: 0, y: 0.15), 0.86), (CGPoint(x: 0, y: -0.72), 0.52),
                        (CGPoint(x: -0.34, y: -1.08), 0.20), (CGPoint(x: 0.34, y: -1.08), 0.20),
                        (CGPoint(x: 0.78, y: 0.52), 0.20)]
            case .bird:
                return [(CGPoint(x: 0, y: 0.1), 0.80), (CGPoint(x: 0.1, y: -0.74), 0.44),
                        (CGPoint(x: 0.62, y: -0.78), 0.16), (CGPoint(x: -0.72, y: 0.34), 0.34)]
            case .fish:
                return [(CGPoint(x: 0.1, y: 0), 0.88), (CGPoint(x: -0.86, y: -0.3), 0.30),
                        (CGPoint(x: -0.86, y: 0.3), 0.30), (CGPoint(x: 0.66, y: -0.5), 0.22)]
            case .rabbit:
                return [(CGPoint(x: 0, y: 0.22), 0.82), (CGPoint(x: 0, y: -0.62), 0.48),
                        (CGPoint(x: -0.26, y: -1.28), 0.24), (CGPoint(x: 0.26, y: -1.30), 0.24)]
            case .fox:
                return [(CGPoint(x: 0, y: 0.16), 0.84), (CGPoint(x: 0, y: -0.68), 0.50),
                        (CGPoint(x: -0.40, y: -1.06), 0.22), (CGPoint(x: 0.40, y: -1.06), 0.22),
                        (CGPoint(x: -0.86, y: 0.46), 0.28)]
            case .bear:
                return [(CGPoint(x: 0, y: 0.18), 0.92), (CGPoint(x: 0, y: -0.70), 0.54),
                        (CGPoint(x: -0.44, y: -1.02), 0.24), (CGPoint(x: 0.44, y: -1.02), 0.24)]
            case .deer:
                return [(CGPoint(x: 0, y: 0.20), 0.80), (CGPoint(x: 0, y: -0.66), 0.44),
                        (CGPoint(x: -0.36, y: -1.20), 0.18), (CGPoint(x: 0.36, y: -1.20), 0.18),
                        (CGPoint(x: -0.54, y: -1.52), 0.13), (CGPoint(x: 0.54, y: -1.52), 0.13)]
            case .frog:
                return [(CGPoint(x: 0, y: 0.10), 0.90), (CGPoint(x: -0.52, y: -0.62), 0.28),
                        (CGPoint(x: 0.52, y: -0.62), 0.28), (CGPoint(x: -0.88, y: 0.44), 0.24),
                        (CGPoint(x: 0.88, y: 0.44), 0.24)]
            }
        }

        /// Lowercase-calm, for VoiceOver and the journal.
        var name: String { rawValue }
    }

    var shape: Shape

    /// Taps left before it goes. Small on purpose: this is a creature that
    /// reacts, not a thing with a health bar.
    var health: Int

    /// How much it wants to keep to itself, 1 down to 0.
    ///
    /// **This decaying is the whole safety argument.** While it is high the
    /// animal keeps to the edges and eases away from a finger; as it falls it
    /// comes out and waits in the open. The field cannot be finished without
    /// it, so "hard to pop" has to be a phase and never a property — anyone
    /// who simply keeps playing will meet it in the open before long.
    var shyness: CGFloat = 1

    /// A brief impulse after being tapped: it darts, then settles.
    var startle: CGFloat = 0
}

// MARK: - The silhouette, joined

extension AnimalPop.Shape {

    /// `lobes`, plus the small joining lobes that make the shape ONE unbroken
    /// balloon instead of a constellation of dots.
    ///
    /// A balloon animal is one tube twisted into segments, so nothing in the
    /// silhouette may float free — a deer's antler sits clear of its ear by
    /// about a tenth of an orb radius, and drawn as written it reads as a
    /// speck beside a head. Every lobe is therefore linked back to the
    /// nearest lobe already placed, with interpolated circles small enough to
    /// overlap their neighbours and tapered toward the smaller end, which is
    /// what gives the joint its pinch.
    ///
    /// Pure geometry in units of the orb radius, so the renderer only has to
    /// scale and offset it, and a test can assert the silhouette is connected
    /// without a screen.
    var joinedLobes: [(CGPoint, CGFloat)] {
        let base = lobes
        guard base.count > 1 else { return base }
        var out = base
        for k in 1..<base.count {
            let (b, rb) = base[k]
            // The nearest lobe already placed — the one it grew out of.
            var bestIndex = 0
            var bestGap = CGFloat.greatestFiniteMagnitude
            for j in 0..<k {
                let (a, ra) = base[j]
                let gap = hypot(b.x - a.x, b.y - a.y) - (ra + rb)
                if gap < bestGap { bestGap = gap; bestIndex = j }
            }
            guard bestGap > 0 else { continue }   // already touching

            let (a, ra) = base[bestIndex]
            let d = hypot(b.x - a.x, b.y - a.y)
            let smaller = min(ra, rb)
            guard smaller > 0.0001, d > 0.0001 else { continue }

            // ONLY THE GAP IS FILLED, not the whole span between the centres —
            // a deer's ear clears its head by three hundredths of an orb
            // radius and wants one joining lobe, not eight. Joiners run from
            // one surface to the other.
            let ux = (b.x - a.x) / d
            let uy = (b.y - a.y) / d
            let start = CGPoint(x: a.x + ux * ra, y: a.y + uy * ra)
            let end = CGPoint(x: b.x - ux * rb, y: b.y - uy * rb)

            // Spacing below half the smaller radius guarantees each joiner
            // overlaps its neighbours and both ends, so the tube never beads.
            let n = min(8, max(1, Int((bestGap / (smaller * 0.5)).rounded(.up))))
            for step in 1...n {
                let t = CGFloat(step) / CGFloat(n + 1)
                let centre = CGPoint(x: start.x + (end.x - start.x) * t,
                                     y: start.y + (end.y - start.y) * t)
                out.append((centre, (ra + (rb - ra) * t) * 0.74))
            }
        }
        return out
    }

    /// How far the silhouette reaches from the orb's centre, in orb radii.
    /// The renderer sizes the halo from this, so a long-eared shape is not lit
    /// as though it were a ball.
    var reach: CGFloat {
        lobes.reduce(CGFloat(1)) { max($0, hypot($1.0.x, $1.0.y) + $1.1) }
    }
}

// MARK: - What VoiceOver says

extension AnimalPop {

    /// Names the creature, and says which phase it is in.
    ///
    /// The phase matters more here than anywhere else on the field: a shy
    /// animal is the one thing on the glass that is deliberately awkward to
    /// reach, and someone who cannot see it keeping to the edges deserves to
    /// be told, in the same voice, that it will come out. Lowercase-calm, and
    /// never a warning.
    var accessibilityLabel: String {
        shyness > 0.35
            ? "a balloon \(shape.name), keeping to the edges"
            : "a balloon \(shape.name), out in the open"
    }
}

// MARK: - How it moves

/// The animal's motion, as pure functions.
///
/// They live outside `GameSimulation` on purpose. `orbs` is `private(set)`, so
/// nothing outside that file can move an orb — which is the right constraint,
/// and it also means the interesting half of this mechanic would otherwise
/// have had to be written inside the simulation's own file. Instead the
/// simulation asks these two functions what the animal wants and applies the
/// answer, and every guarantee below is provable without a field, a clock or a
/// screen.
enum AnimalMotion {

    /// One frame of shyness: the phase decays, it keeps toward the perimeter
    /// while the phase lasts, it eases away from a finger at mid range, and
    /// the startle it was left with runs down.
    ///
    /// THE THREE THINGS THAT KEEP THIS FROM BEING A CHASE are the drifter's,
    /// deliberately copied rather than re-derived (`GameSimulation.evade`):
    ///
    ///   1. **It surrenders up close.** Inside `GameConfig.evadeSurrenderRadius`
    ///      there is NO evasion at all — moving at it always catches it.
    ///   2. **It is slower than a finger.** `GameConfig.animalMaxSpeed` is
    ///      about twenty-five points a second; a moving thumb is an order of
    ///      magnitude past that, so a follow always gains.
    ///   3. **It gives up in a corner.** Evasion fades as it nears a wall, and
    ///      the perimeter-seeking turns around inside the band, so a cornered
    ///      animal settles rather than vibrating against the edge.
    ///
    /// And the fourth, which is this mechanic's alone: **every term above is
    /// multiplied by `shyness`, which only ever falls.** At `shyness == 0` this
    /// function is arithmetically identical to leaving the orb alone. The field
    /// cannot be finished without the animal, so "hard to catch" is a phase
    /// with an end and never a property.
    static func step(_ animal: AnimalPop,
                     pos: CGPoint,
                     vel: CGVector,
                     pointer: CGPoint?,
                     bounds: CGSize,
                     topInset: CGFloat,
                     bottomInset: CGFloat,
                     reduceMotion: Bool,
                     f: CGFloat) -> (AnimalPop, CGVector) {
        var next = animal
        var v = vel
        let damp: CGFloat = reduceMotion ? GameConfig.animalReduceMotionScale : 1

        // The phases run down first, so a frame's motion uses the shyness it
        // is leaving with rather than the one it arrived with. Both only ever
        // fall, and neither is raised by anything except a tap.
        next.shyness = max(0, animal.shyness - f / GameConfig.animalShyFrames)
        next.startle = max(0, animal.startle - f / GameConfig.animalStartleFrames)
        let shy = next.shyness

        // Room to each wall, and the nearest one. `topInset`/`bottomInset` are
        // the bands the field may not enter, so this is the playable room and
        // not the screen's.
        let left = max(0, pos.x)
        let right = max(0, bounds.width - pos.x)
        let up = max(0, pos.y - topInset)
        let down = max(0, bounds.height - bottomInset - pos.y)
        let room = min(min(left, right), min(up, down))

        if shy > 0 {
            // KEEPING TO THE EDGES, and the band is why this is not a corner
            // trap. It seeks a DISTANCE from the nearest wall rather than the
            // wall itself: outside the band it drifts out, inside the band it
            // drifts back in, and it comes to rest in the margin where a shy
            // thing would actually sit. Nothing here ever presses the glass.
            let toward: CGVector
            if room == left        { toward = CGVector(dx: -1, dy: 0) }
            else if room == right  { toward = CGVector(dx: 1, dy: 0) }
            else if room == up     { toward = CGVector(dx: 0, dy: -1) }
            else                   { toward = CGVector(dx: 0, dy: 1) }

            let band = GameConfig.animalEdgeBand
            let err = max(-1, min(1, (room - band) / max(band, 0.0001)))
            let pull = GameConfig.animalEdgeSeek * err * shy * f
            v.dx += toward.dx * pull
            v.dy += toward.dy * pull
        }

        // EASING AWAY FROM A FINGER — the drifter's contract, gated by shyness.
        if let finger = pointer, shy > 0 {
            let dx = pos.x - finger.x
            let dy = pos.y - finger.y
            let d2 = dx * dx + dy * dy
            let radius = GameConfig.animalEvadeRadius
            let surrender = GameConfig.evadeSurrenderRadius
            if d2 < radius * radius {
                let d = max(sqrt(d2), 0.0001)
                // THE SURRENDER. Closer than this there is no evasion at all,
                // and the comparison is against the drifter's own constant so
                // the two mechanics can never quietly drift apart.
                if d > surrender {
                    let span = radius - surrender
                    let t = (d - surrender) / max(span, 0.0001)
                    let falloff = sin(t * .pi)
                    let cornered = min(1, max(0, room) / GameConfig.evadeWallEasing)
                    let push = GameConfig.animalEvadeStrength * falloff * cornered * shy * damp * f
                    v.dx += dx / d * push
                    v.dy += dy / d * push
                }
            }
        }

        // THE CEILING, and the only place a startle is allowed above it. The
        // dart is a briefly raised ceiling that decays with `startle`, so the
        // animal returns to its ordinary crawl on its own — there is no state
        // in which it is permanently fast.
        let ceiling = max(GameConfig.animalMaxSpeed,
                          GameConfig.animalStartleSpeed * next.startle * damp)
        let speed = sqrt(v.dx * v.dx + v.dy * v.dy)
        if speed > ceiling {
            let k = ceiling / speed
            v.dx *= k
            v.dy *= k
        }

        return (next, v)
    }

    /// A touch that did not finish it: one health gone, and a short dart.
    ///
    /// This is what makes it read as a creature rather than a target — the tap
    /// that does not kill it still lands, visibly. The dart is deliberately
    /// SHORT: about twenty-six points over four tenths of a second, well
    /// inside the animal's own tap radius, so a second tap in the same place
    /// still finds it. A startle that moved it out from under her finger would
    /// be the mechanic punishing her for a hit, which is backwards.
    ///
    /// `source` is where it was touched; a chain — a shockwave rather than a
    /// finger — passes nil and the animal bolts along `angle`, which the
    /// simulation draws from its seeded RNG so the field stays deterministic.
    static func startled(_ animal: AnimalPop,
                         at pos: CGPoint,
                         from source: CGPoint?,
                         angle: CGFloat,
                         reduceMotion: Bool) -> (AnimalPop, CGVector) {
        var next = animal
        next.health = max(0, animal.health - 1)
        next.startle = 1

        var ux = cos(angle)
        var uy = sin(angle)
        if let source {
            let dx = pos.x - source.x
            let dy = pos.y - source.y
            let d = sqrt(dx * dx + dy * dy)
            if d > 0.0001 { ux = dx / d; uy = dy / d }
        }
        let damp: CGFloat = reduceMotion ? GameConfig.animalReduceMotionScale : 1
        let speed = GameConfig.animalStartleSpeed * damp
        return (next, CGVector(dx: ux * speed, dy: uy * speed))
    }
}

// MARK: - Finding it

extension GameSimulation {

    /// The animal on this field, if it has one — on the surface or still
    /// waiting below. Read-only, and the whole of what the rest of the app
    /// needs to know about it.
    var animalOnField: AnimalPop? {
        for orb in orbs where orb.alive {
            if case .animal(let animal) = orb.kind { return animal }
        }
        for orb in reserve {
            if case .animal(let animal) = orb.kind { return animal }
        }
        return nil
    }
}
