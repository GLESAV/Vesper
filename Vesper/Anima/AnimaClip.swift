import CoreGraphics
import Foundation

// ANIMA — clips. A clip is a performance: which parts move, on which
// channels, along which curves.
//
// This is the file that turns the other two into an animation engine.

// MARK: - Channels

/// The animatable properties of a part.
///
/// A CLOSED SET, and small. Every channel here is one an author reaches for
/// constantly; anything rarer belongs in the shape's own parameters, not in
/// the timeline. A wide channel set looks like power and buys a library
/// nobody can read.
///
/// Values are ABSOLUTE, not deltas on the rest pose, except where noted. A
/// delta system reads nicely for one track and becomes impossible to reason
/// about the moment two tracks touch the same channel.
enum AnimaChannel: String, CaseIterable, Equatable {
    /// Offset from the part's rest position, in unit radii. Additive on rest
    /// — the one exception, and it is the right one: an author thinks "move
    /// it up a bit from where it lives", never "move it to 0.3 absolute".
    case x
    case y
    /// Radians, additive on rest, for the same reason.
    case rotation
    /// Uniform scale, MULTIPLIED into rest. 1 is unchanged.
    case scale
    /// Squash, additive on rest. See `AnimaTransform.squash`.
    case squash
    /// Opacity, multiplied into rest. 1 is unchanged.
    case opacity
}

// MARK: - Tracks

/// One curve, bound to one channel of one part.
struct AnimaTrack: Equatable {
    var part: String
    var channel: AnimaChannel
    var curve: AnimaCurve

    init(_ part: String, _ channel: AnimaChannel, _ curve: AnimaCurve) {
        self.part = part
        self.channel = channel
        self.curve = curve
    }

    init(_ part: String, _ channel: AnimaChannel, _ keys: [AnimaKey], loops: Bool = false) {
        self.init(part, channel, AnimaCurve(keys, loops: loops))
    }
}

// MARK: - Clips

/// A named performance over a fixed span of seconds.
struct AnimaClip: Equatable {
    var name: String

    /// How long the performance is. Authored rather than derived from the
    /// longest track, because a clip's length is a design decision — a pop
    /// that holds still for 200 ms after its last key is saying something —
    /// and deriving it would make that unsayable.
    var duration: Double

    var tracks: [AnimaTrack]

    /// Whether the whole performance repeats. Idles loop; reactions do not.
    var loops: Bool

    init(_ name: String, duration: Double, loops: Bool = false, tracks: [AnimaTrack]) {
        self.name = name
        self.duration = max(0.0001, duration)
        self.loops = loops
        self.tracks = tracks
    }

    /// The transform overrides for one part at one already-lagged time.
    ///
    /// Knows nothing about `lag` — that is applied by `pose`, one level up,
    /// because it has to delay a part's INHERITED motion as well as its own.
    /// See the note there.
    private func sample(part: AnimaPart, at time: Double) -> AnimaTransform {
        var out = AnimaTransform(offset: .zero, rotation: 0, scale: 1,
                                 squash: 0, opacity: 1)
        let t = localTime(time)
        for track in tracks where track.part == part.name {
            let v = track.curve.value(at: t)
            switch track.channel {
            case .x:        out.offset.x += CGFloat(v)
            case .y:        out.offset.y += CGFloat(v)
            case .rotation: out.rotation += v
            case .scale:    out.scale *= v
            case .squash:   out.squash += v
            case .opacity:  out.opacity *= v
            }
        }
        return out
    }

    /// Wraps or clamps a time into the clip's own span.
    ///
    /// A LOOPING CLIP WRAPS; A ONE-SHOT HOLDS ITS LAST FRAME. Holding is the
    /// only safe end state for a reaction: a one-shot that snapped back to
    /// its first frame would make every burst flicker on its last frame, and
    /// one that ran on would leave the screen.
    func localTime(_ time: Double) -> Double {
        guard loops else { return min(max(time, 0), duration) }
        var phase = time.truncatingRemainder(dividingBy: duration)
        if phase < 0 { phase += duration }
        return phase
    }

    /// The whole figure at one instant.
    ///
    /// PURE, AND THE ONLY WAY TO GET A POSE. Given a figure and a time this
    /// answers the same pose in a test, on a phone, and in the exporter that
    /// feeds the browser previewer. Nothing samples a clip any other way,
    /// which is what guarantees the previewer is not lying.
    func pose(of figure: AnimaFigure, at time: Double) -> AnimaPose {
        // LAG DELAYS THE WHOLE CHAIN ABOVE A PART, NOT JUST ITS OWN TRACKS.
        //
        // This is the entire mechanism of follow-through and it is easy to
        // get subtly wrong — the first version of this file did. If `lag`
        // only shifted the time at which a part's OWN curves were read, then
        // a part with no curves of its own (which is most of them: a
        // jellyfish's trails, a hare's ear) would be unaffected by its lag
        // and would move in perfect lockstep with its parent. The whole
        // figure moves as one plate, which is exactly the rigid-puppet look
        // the feature exists to remove, and nothing about it looks broken
        // enough to investigate.
        //
        // So the time travels UP the hierarchy: a part is evaluated at
        // `time − lag`, and its parent is evaluated at that same delayed time
        // minus the parent's own lag. Lag therefore accumulates down a chain,
        // which is what makes a chain of parts read as a tail rather than as
        // three separately-late objects.
        //
        // Not memoised. With lag the same parent is genuinely needed at
        // several different times, so a cache keyed on the part's name would
        // return the wrong pose for every branch after the first — and the
        // figures here are a dozen parts three deep, where the walk is
        // cheaper than the dictionary would have been.
        func world(of part: AnimaPart, at time: Double, depth: Int) -> AnimaTransform {
            // Depth-limited for the same reason `AnimaFigure.worldRest` is: a
            // parent cycle in a hand-typed catalog must draw something wrong
            // rather than hang the frame loop. `AnimaTests` rejects the cycle
            // outright, which is where an author should hear about it.
            guard depth < figure.parts.count else { return .identity }

            let t = time - part.lag
            // Rest MERGED with the animation (add/multiply per channel), then
            // the result composed under the parent. Merging and composing are
            // different operations and swapping them is a real bug — see
            // `AnimaTransform.merged(with:)`.
            let local = part.rest.merged(with: sample(part: part, at: t))
            guard let parentName = part.parent,
                  let parent = figure.part(named: parentName) else { return local }
            return local.concatenated(under: world(of: parent, at: t, depth: depth + 1))
        }

        var posed: [AnimaPosedPart] = []
        posed.reserveCapacity(figure.parts.count)
        for part in figure.parts {
            let transform = world(of: part, at: time, depth: 0)
            let outline = part.primitive.outline().map { transform.apply(to: $0) }
            posed.append(AnimaPosedPart(name: part.name,
                                        outline: outline,
                                        paint: part.paint,
                                        opacity: min(max(transform.opacity, 0), 1),
                                        depth: part.depth))
        }
        // Stable by depth then by authored order, so two parts at the same
        // depth draw in the order they were written rather than in whatever
        // order the sort happened to land on.
        posed = posed.enumerated()
            .sorted { a, b in
                if a.element.depth != b.element.depth { return a.element.depth < b.element.depth }
                return a.offset < b.offset
            }
            .map(\.element)
        return AnimaPose(parts: posed)
    }

    /// A clip that does nothing, for a figure that is only ever drawn at rest.
    static func still(_ name: String = "still") -> AnimaClip {
        AnimaClip(name, duration: 1, loops: true, tracks: [])
    }
}

// MARK: - Sampling for export

extension AnimaClip {
    /// The clip sampled evenly into `frames` poses.
    ///
    /// Used by `AnimaStudio` and by the golden-master tests. It exists here
    /// rather than in the exporter so that what the previewer shows and what
    /// the tests pin are produced by the same three lines.
    func filmstrip(of figure: AnimaFigure, frames: Int) -> [AnimaPose] {
        let n = max(1, frames)
        return (0..<n).map { i in
            // `n` divisions rather than `n - 1` for a looping clip, so the
            // last frame is one step BEFORE the loop point and playback does
            // not stutter on a duplicated frame. A one-shot wants to end on
            // its final pose instead.
            let denominator = loops ? Double(n) : Double(max(1, n - 1))
            return pose(of: figure, at: duration * Double(i) / denominator)
        }
    }
}
