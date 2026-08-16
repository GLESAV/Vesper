import SwiftUI

// THE SKY — the Path, drawn as a constellation over the field.
//
// This is the feature that answers "which level am I on" by looking up. The
// stones of `MapStore` are the same stones the game already walks; nothing
// here generates, migrates, prunes or persists anything. It reads the store
// and draws it truthfully, and the only write it can cause is the one that
// playing a stone has always caused (`GameViewModel.playStone`).
//
// ─────────────────────────────────────────────────────────────────────────
// WHAT THIS PLACE IS, IN ONE LINE EACH (04 §2/§4, 05 §8, docs/pop_map.md):
//
//   · Stones are STARS: a circle at 60% of a field orb's scale, carrying the
//     stone's pops as tiny gems in their family paints.
//   · Roads are faint dashed constellation lines. The roads ahead of where
//     she stands are lit; everything older is dimmer — and NEVER absent. The
//     trace is permanent by design: history only accrues, so a road that is
//     drawn at zero opacity is a lie about the whole map.
//   · NEWEST NEAREST THE FIELD. The bottom of the sky is the edge she just
//     came up from, so her latest stone sits there and the walked path hangs
//     above it. The sky reads as the path continuing upward.
//   · Choosing a star plays it and takes her straight back down. Leaving
//     without choosing is always possible — the `the field` whisper at the
//     foot, the swipe down, and the VoiceOver escape all do it, and nothing
//     in here is modal, timed, or confirmable.
// ─────────────────────────────────────────────────────────────────────────
//
// INTEGRATION NOTE FOR WHOEVER COMPOSES THE WORLD (W05/W10). This view is
// interactive: its stars and its whisper are buttons. In the composition as
// written for W04 the moving body carries `.allowsHitTesting(false)` and the
// input layer sits above it, so a sky nested there receives no touches at
// all. The sky's interactive layer must be reachable — either by lifting the
// hit-test veto for the place that is at rest on screen, or by hosting this
// view above the input layer. If that is not done the stars still render and
// still read correctly under VoiceOver, but no tap will land on one.
//
// SCOPE. W08 (the settle-instead-of-prune trace) is deferred, so `MapStore`
// still lets old stones go. This view therefore renders *today's* stones —
// it does not pretend to a history the store no longer holds, and it adds no
// persistence of its own to invent one.

// MARK: - Placement (pure)

/// One star, already placed. Pure geometry plus the three facts the drawing
/// and the VoiceOver label both need, so neither re-derives them.
struct SkyStar: Identifiable {
    let stone: MapStone
    let center: CGPoint
    /// The stone she is standing on. Only this one says `you are here`.
    let isActive: Bool
    /// The stone the map leads with — the active one, or her most recent.
    /// Always bright (docs/pop_map.md §2), even when it is also cleared.
    let isAnchor: Bool
    /// Untouched for longer than `MapStore.fadeAfter`: settled, not spent.
    let isSettled: Bool

    var id: UUID { stone.id }
}

/// One constellation line, parent (above) to child (below).
struct SkyRoad {
    /// How lit a road is. Three tiers, and the dimmest is still visible —
    /// `settled` is the map's memory, not its absence.
    enum Tier {
        case onward   // directly ahead of where she stands
        case open     // walked or reachable, recently touched
        case settled  // the trace: quieter, permanent
    }

    let from: CGPoint
    let to: CGPoint
    let tier: Tier
}

/// Where every star and road goes, for a given screenful of sky.
///
/// Pure: it takes stones, an anchor, a clock reading and a size, and returns
/// points. No SwiftUI, no store, no wall clock of its own — which is what
/// makes it checkable in a test without a running world.
struct SkyLayout {

    // MARK: Committed geometry

    /// 60% of a field orb's scale (05 §8), sourced from the orb range itself
    /// so the two cannot drift apart.
    static let starRadius: CGFloat =
        (GameConfig.orbRadiusRange.lowerBound + GameConfig.orbRadiusRange.upperBound) / 2 * 0.6

    /// The floor on the gap between two stars, in either axis. It is the
    /// standard touch target, and it is a *layout* rule rather than a drawing
    /// one: a star that cannot be separated from its neighbour cannot be
    /// tapped, however prettily it is drawn.
    static let minimumSeparation: CGFloat = WhisperPresentation.minimumHitEdge

    /// The widest a generation gap is allowed to be drawn, so a two-stone map
    /// does not stretch one road across the whole screen.
    static let maximumSeparation: CGFloat = 118

    /// Room at the top for the status bar and the sky's own darkness, and at
    /// the foot for the `the field` whisper's 44 pt target inside the bottom
    /// dead zone (04 §4).
    static let topInset: CGFloat = 96
    static let bottomInset: CGFloat = 132

    /// The banks. A star centred here still has its whole 44 pt target on
    /// screen.
    static let laneInset: CGFloat = 44

    // MARK: The placement

    /// Oldest first, so the newest star is drawn last and hit-tested first.
    let stars: [SkyStar]
    let roads: [SkyRoad]
    /// The vertical gap actually used between two generations.
    let rowSpacing: CGFloat

    init(stones: [MapStone],
         activeID: UUID?,
         anchorID: UUID?,
         now: Date,
         size: CGSize) {

        guard !stones.isEmpty, size.width > 0, size.height > 0 else {
            stars = []
            roads = []
            rowSpacing = Self.maximumSeparation
            return
        }

        let generations = stones.map(\.generation)
        let newest = generations.max() ?? 0
        let oldest = generations.min() ?? 0
        let rows = newest - oldest + 1

        // The sky does not scroll: vertical is the world's own axis and means
        // nothing else inside a place (04 §4). So the generations are fitted
        // into one screenful, compressed no further than the touch target.
        let usable = max(0, size.height - Self.topInset - Self.bottomInset)
        if rows > 1 {
            let even = usable / CGFloat(rows - 1)
            rowSpacing = min(Self.maximumSeparation, max(Self.minimumSeparation, even))
        } else {
            rowSpacing = Self.maximumSeparation
        }

        // The baseline is the edge she came up from: her newest stones sit
        // there, and the walked path climbs away from it.
        let baseline = size.height - Self.bottomInset

        var centers: [UUID: CGPoint] = [:]
        let byGeneration = Dictionary(grouping: stones, by: \.generation)
        for (generation, row) in byGeneration {
            let y = baseline - CGFloat(newest - generation) * rowSpacing
            for (id, x) in Self.rowPositions(row, width: size.width) {
                centers[id] = CGPoint(x: x, y: y)
            }
        }

        // Anything whose centre has climbed off the top of this screenful is
        // simply not on this screenful. It is not removed from the map and
        // nothing about it changes — reaching it is the sky's own upward
        // drift, which is not built yet.
        let ceiling = Self.starRadius
        let visible = stones
            .filter { stone in (centers[stone.id]?.y ?? -1) >= ceiling }
            .sorted { left, right in
                if left.generation != right.generation { return left.generation < right.generation }
                return left.createdAt < right.createdAt
            }

        var placed: [SkyStar] = []
        placed.reserveCapacity(visible.count)
        for stone in visible {
            guard let center = centers[stone.id] else { continue }
            placed.append(SkyStar(stone: stone,
                                  center: center,
                                  isActive: stone.id == activeID,
                                  isAnchor: stone.id == anchorID,
                                  isSettled: Self.isSettled(stone, now: now)))
        }
        stars = placed

        var lines: [SkyRoad] = []
        for star in placed {
            guard let parentID = star.stone.parentID,
                  let from = centers[parentID] else { continue }
            let tier: SkyRoad.Tier
            if parentID == anchorID {
                tier = .onward
            } else if star.isSettled {
                tier = .settled
            } else {
                tier = .open
            }
            lines.append(SkyRoad(from: from, to: star.center, tier: tier))
        }
        roads = lines
    }

    /// Settling is read from the stone's own dates, never written back: this
    /// view has no business changing the map (W08 owns that transition).
    static func isSettled(_ stone: MapStone, now: Date) -> Bool {
        let touched = stone.lastPlayedAt ?? stone.createdAt
        return now.timeIntervalSince(touched) > MapStore.fadeAfter
    }

    /// Lays one generation across the banks, keeping neighbours far enough
    /// apart to be separately tappable.
    ///
    /// Lanes come from the map's own generation and are honoured wherever
    /// they fit. Where a generation is too crowded for `minimumSeparation`,
    /// the row is spread evenly instead of clamped into a pile: centres stay
    /// distinct, so every star keeps a patch of its own that the star above
    /// it does not cover, and nothing becomes unreachable.
    static func rowPositions(_ row: [MapStone], width: CGFloat) -> [UUID: CGFloat] {
        let left = laneInset
        let right = max(left, width - laneInset)
        let span = right - left
        let sorted = row.sorted { a, b in
            if a.lane != b.lane { return a.lane < b.lane }
            return a.createdAt < b.createdAt
        }
        var positions: [UUID: CGFloat] = [:]
        guard !sorted.isEmpty else { return positions }
        guard sorted.count > 1 else {
            positions[sorted[0].id] = left + CGFloat(sorted[0].lane) * span
            return positions
        }

        // Too crowded for the touch target: spread the row evenly rather than
        // pile it up. Centres stay distinct and evenly spaced, so each star
        // keeps a patch the star drawn over it does not cover.
        let needed = CGFloat(sorted.count - 1) * minimumSeparation
        if needed > span {
            let step = span / CGFloat(sorted.count - 1)
            for (index, stone) in sorted.enumerated() {
                positions[stone.id] = left + step * CGFloat(index)
            }
            return positions
        }

        // Otherwise: the map's own lanes, opened out to the minimum gap. A
        // forward pass gives every star its neighbour's room, and a backward
        // pass folds the row back inside the right bank. Because the row is
        // known to fit, the backward pass cannot push the first star past the
        // left bank, and neither pass can shrink a gap below the minimum.
        var xs: [CGFloat] = sorted.map { left + CGFloat($0.lane) * span }
        for index in xs.indices {
            var x = max(left, xs[index])
            if index > 0 { x = max(x, xs[index - 1] + minimumSeparation) }
            xs[index] = x
        }
        for index in xs.indices.reversed() {
            var x = min(right, xs[index])
            if index < xs.count - 1 { x = min(x, xs[index + 1] - minimumSeparation) }
            xs[index] = x
        }
        for (index, stone) in sorted.enumerated() {
            positions[stone.id] = xs[index]
        }
        return positions
    }
}

// MARK: - The voice

/// What VoiceOver says about a star. Its own type because it is copy, and
/// copy is reviewed: every word it can say comes from `Strings`, and the only
/// thing assembled here is the order.
enum StarVoice {

    /// Reads as one calm clause: the pops, then where she stands relative to
    /// it. Pop names are the catalog's proper nouns, lowercased into the
    /// world's voice (07 §2).
    static func label(for stone: MapStone, isActive: Bool) -> String {
        var parts = stone.popNumbers.map { PopCatalog.definition(for: $0).name.lowercased() }
        if isActive {
            parts.append(Strings.starHere)
        } else if stone.cleared {
            parts.append(Strings.starWalked)
        } else {
            parts.append(Strings.starUnwalked)
        }
        return parts.joined(separator: separator)
    }

    /// Punctuation, not copy: it is what makes a list read as a list.
    private static let separator = ", "
}

// MARK: - Drawing

/// The constellation itself. Read-only, like every renderer in this app.
struct SkyRenderer {

    // 05 §2.1 tokens. `road.line` is #D9D6E8 at 20–25%; the settled tier sits
    // below that band on purpose and is floored well clear of zero.
    private static let roadInk = Color(red: 217/255, green: 214/255, blue: 232/255)
    private static let accent = Color(red: 195/255, green: 175/255, blue: 220/255)
    private static let rim = Color(red: 214/255, green: 204/255, blue: 230/255)
    private static let stoneBody = Color(red: 24/255, green: 22/255, blue: 34/255)

    static func drawRoads(_ layout: SkyLayout, in context: GraphicsContext) {
        var glow = context
        glow.blendMode = .plusLighter

        for road in layout.roads {
            // The parent is above its child, so the curve leans out of the
            // parent's foot and into the child's head.
            let lean = (road.to.y - road.from.y) * 0.42
            var path = Path()
            path.move(to: road.from)
            path.addCurve(to: road.to,
                          control1: CGPoint(x: road.from.x, y: road.from.y + lean),
                          control2: CGPoint(x: road.to.x, y: road.to.y - lean))

            let ink: Color
            let alpha: Double
            switch road.tier {
            case .onward:  ink = accent;  alpha = 0.30
            case .open:    ink = roadInk; alpha = 0.22
            case .settled: ink = roadInk; alpha = 0.14
            }

            glow.stroke(path,
                        with: .color(ink.opacity(alpha)),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [2.5, 7]))
        }
    }

    static func drawStars(_ layout: SkyLayout, in context: GraphicsContext) {
        // The star's dark ground is printed, not lit; everything else in
        // the sky is light (05 §3), so the two contexts are separated once
        // here rather than switched per draw call.
        var flat = context
        flat.blendMode = .normal
        var glow = context
        glow.blendMode = .plusLighter

        for star in layout.stars {
            let definitions = star.stone.popNumbers.map { PopCatalog.definition(for: $0) }
            // Cleared stars sink slightly and dim — settled, not spent (05
            // §8). The anchor is exempt: the map always leads with it.
            let quiet = (star.stone.cleared || star.isSettled) && !star.isAnchor
            let center = CGPoint(x: star.center.x, y: star.center.y + (quiet ? 2 : 0))
            let r = SkyLayout.starRadius

            if let paint = definitions.first?.style.paints.first {
                let haloR = r * 2.1
                let halo = CGRect(x: center.x - haloR, y: center.y - haloR,
                                  width: haloR * 2, height: haloR * 2)
                let glowColor = color(paint.glow)
                let gradient = Gradient(stops: [
                    .init(color: glowColor.opacity(quiet ? 0.10 : (star.isAnchor ? 0.26 : 0.18)),
                          location: 0),
                    .init(color: glowColor.opacity(0), location: 1)
                ])
                glow.fill(Path(ellipseIn: halo),
                          with: .radialGradient(gradient, center: center,
                                                startRadius: r * 0.4, endRadius: haloR))
            }

            // A dark ground so the gems read against a road passing behind.
            let body = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            flat.fill(Path(ellipseIn: body), with: .color(stoneBody.opacity(quiet ? 0.5 : 0.75)))

            glow.stroke(Path(ellipseIn: body),
                        with: .color(star.isAnchor ? accent.opacity(0.85)
                                                   : rim.opacity(quiet ? 0.22 : 0.34)),
                        lineWidth: star.isAnchor ? 1.6 : 1)

            drawGems(definitions, at: center, quiet: quiet, in: glow)
        }
    }

    private static func drawGems(_ definitions: [PopDefinition],
                                 at center: CGPoint,
                                 quiet: Bool,
                                 in glow: GraphicsContext) {
        guard !definitions.isEmpty else { return }
        var context = glow
        context.blendMode = .plusLighter
        let gemRadius: CGFloat = definitions.count > 2 ? 3.4 : 4.2
        let step = gemRadius * 2.4
        let start = center.x - step * CGFloat(definitions.count - 1) / 2

        for (index, definition) in definitions.enumerated() {
            guard let paint = definition.style.paints.first else { continue }
            let gemCenter = CGPoint(x: start + step * CGFloat(index), y: center.y)
            // `star.gem` at 80% (05 §2.1), quieter on a settled star.
            context.fill(gemPath(family: definition.family,
                                 center: gemCenter,
                                 radius: gemRadius),
                         with: .color(color(paint.fill).opacity(quiet ? 0.55 : 0.80)))
        }
    }

    /// The family's shape signature (05 §8): facet count and rotation, so the
    /// sky still sorts itself in grayscale for anyone who does not read the
    /// paints as colour.
    static func gemPath(family: PopFamily, center: CGPoint, radius: CGFloat) -> Path {
        let facets = signature(for: family)
        guard facets.sides >= 3 else {
            return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
        }
        var path = Path()
        for corner in 0..<facets.sides {
            let angle = facets.rotation
                + (Double(corner) / Double(facets.sides)) * 2 * Double.pi
                - Double.pi / 2
            let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                                y: center.y + radius * CGFloat(sin(angle)))
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Ten families, ten silhouettes. `sides == 0` means a plain disc, which
    /// belongs to `vesper` — the original pop keeps the original shape.
    private static func signature(for family: PopFamily) -> (sides: Int, rotation: Double) {
        switch family {
        case .vesper:  return (0, 0)
        case .ember:   return (3, 0)
        case .tide:    return (4, Double.pi / 4)
        case .bloom:   return (5, 0)
        case .frost:   return (6, 0)
        case .chime:   return (3, Double.pi)
        case .lantern: return (4, 0)
        case .current: return (5, Double.pi)
        case .prism:   return (8, 0)
        case .aurora:  return (6, Double.pi / 6)
        }
    }

    private static func color(_ c: PopColor) -> Color {
        Color(red: c.r, green: c.g, blue: c.b)
    }
}

// MARK: - The place

struct SkyView: View {

    let model: WorldModel

    init(model: WorldModel) {
        self.model = model
    }

    // The map is read, never written: nothing in this view calls
    // `ensureGenesis`, `recordClear` or `prune`. `GameViewModel` already
    // guarantees the first stone exists before any of this is on screen.
    @ObservedObject private var map = MapStore.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Breathing means touchable (05 §6.1), and every star is. One shared
    /// opacity for the whole star layer says that once, rather than 30 times.
    @State private var breathing = false

    /// The hit target scales with Dynamic Type and is floored at 44 pt, the
    /// same floor and the same reasoning as `WhisperLabel`'s.
    @ScaledMetric(relativeTo: .footnote)
    private var scaledHitEdge: CGFloat = WhisperPresentation.minimumHitEdge

    private var hitEdge: CGFloat {
        max(scaledHitEdge, WhisperPresentation.minimumHitEdge)
    }

    var body: some View {
        GeometryReader { geo in
            // The layout is built OUTSIDE the view builder, in a plain
            // function, so nothing here depends on what a result builder does
            // with a local declaration.
            constellation(layout: SkyLayout(stones: map.stones,
                                            activeID: map.activeStoneID,
                                            anchorID: map.anchorStone?.id,
                                            now: map.nowProvider(),
                                            size: geo.size),
                          size: geo.size)
        }
        // Two-finger Z from anywhere in the sky (04 §10). She is never held
        // here by having chosen nothing.
        .accessibilityAction(.escape) { returnToField() }
        // The breath is started and stopped the same way `WhisperLabel`
        // starts and stops its own: by moving the state to the end the
        // current setting calls for, so Reduce Motion turning on mid-evening
        // stops an in-flight cycle instead of leaving it running forever.
        .onAppear { breathing = !reduceMotion }
        .onChange(of: reduceMotion) { _, value in breathing = !value }
    }

    // MARK: The constellation

    private func constellation(layout: SkyLayout, size: CGSize) -> some View {
        ZStack {
            Canvas { context, _ in
                SkyRenderer.drawRoads(layout, in: context)
            }
            .allowsHitTesting(false)

            Canvas { context, _ in
                SkyRenderer.drawStars(layout, in: context)
            }
            .opacity(starLayerOpacity)
            .animation(breathAnimation, value: breathing)
            .allowsHitTesting(false)

            // The targets, and the whole of the sky's accessibility. They are
            // added in the same order as the stars are drawn, so the newest
            // star — the one nearest the field, and the one most likely to be
            // reached for — is last, and therefore resolves any overlap.
            ForEach(layout.stars) { star in
                starTarget(star)
            }

            // The way home, for anyone who does not swipe. It is not the only
            // way out and it is not a dismissal: the swipe down and the
            // VoiceOver escape do the same thing, and choosing nothing is a
            // complete visit.
            VStack {
                Spacer(minLength: 0)
                WhisperLabel(text: Strings.fieldWhisper,
                             accessibilityLabel: Strings.fieldA11y,
                             hint: Strings.fieldWhisperHint,
                             isPlaying: false,
                             onTap: returnToField)
                    // Read last: she came up here to look at stars, and the
                    // way home is the thing she already knows how to find.
                    .accessibilitySortPriority(-1)
                    // Clear of the home indicator: the world ignores the safe
                    // area, so the whisper keeps its own distance.
                    .padding(.bottom, 34)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Stars

    private func starTarget(_ star: SkyStar) -> some View {
        Button {
            play(star.stone)
        } label: {
            // Invisible, and deliberately larger than the star it covers:
            // the visual is ~31 pt across and the target is at least 44.
            Color.clear
                .frame(width: hitEdge, height: hitEdge)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(star.center)
        .accessibilityLabel(Text(StarVoice.label(for: star.stone, isActive: star.isActive)))
        .accessibilityHint(Text(Strings.starHint))
        .accessibilityAddTraits(.isButton)
        // Newest first in the rotor: the sky is read from the field outward,
        // the same direction it is drawn.
        .accessibilitySortPriority(Double(star.stone.generation))
    }

    // MARK: Acts

    /// Choosing a star: the field re-seeds from that stone, and the world
    /// carries her back down to it. Two lines, in this order — the field is
    /// already the stone's field by the time the camera arrives.
    private func play(_ stone: MapStone) {
        model.game.playStone(stone)
        model.handle([.commit(.down, velocity: 0)])
    }

    /// Leaving with nothing chosen. Identical to the swipe, and it changes
    /// nothing about the map.
    private func returnToField() {
        model.handle([.commit(.down, velocity: 0)])
    }

    // MARK: Lighting

    /// Reduce Motion leaves the stars fully lit and still: the breath is an
    /// affordance, never information, so removing it may not also dim them.
    private var starLayerOpacity: Double {
        if reduceMotion { return 1 }
        return breathing ? 1 : 0.88
    }

    /// `nil` under Reduce Motion, where the stars are simply lit and still
    /// (04 §11: every motion has a defined reduced variant, and none of them
    /// carries information).
    private var breathAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: 3.4).repeatForever(autoreverses: true)
    }
}
