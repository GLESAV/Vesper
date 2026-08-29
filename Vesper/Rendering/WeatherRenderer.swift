import SwiftUI

// THE AIR, DRAWN.
//
// `WeatherField` moves the weather; this draws it, and it draws it in TWO
// passes on purpose. The owner asked for water that "interleaves with pops
// like splashing", and a single layer cannot do that: a band behind the orbs
// is a backdrop and a band in front of them is a filter, while a band behind
// with its foam and its splash in front puts the pops IN the water. Snow,
// light and wind are split the same way, and fog is the one air that is drawn
// entirely in front — that is what makes it fog, and why it is also the one
// air she can push out of the way with a finger.
//
// Read-only, like the rest of the rendering: it takes the field by value and
// changes nothing.
//
// HOW DARK ALL OF THIS IS. Every band, shaft, bank and streak is drawn at the
// opacities in `GameConfig` — 0.06 for a water band, 0.14 for fog — over a
// background that is itself around 6% luminance. Nothing in here approaches
// white except the splash droplets and the specular pin-lights, which are one
// or two points across. The air is meant to be unmistakable and still quiet
// enough to fall asleep to.
enum WeatherRenderer {

    // MARK: - Palette
    //
    // Muted and desaturated, in the same register as the orb paints. No pure
    // white anywhere: the brightest thing here is the foam, at 232 blue.

    private static let water = Color(red: 118/255, green: 152/255, blue: 186/255)
    private static let foam = Color(red: 196/255, green: 214/255, blue: 226/255)
    private static let snow = Color(red: 206/255, green: 214/255, blue: 232/255)
    private static let wind = Color(red: 162/255, green: 172/255, blue: 198/255)
    private static let sun = Color(red: 228/255, green: 204/255, blue: 162/255)
    private static let fog = Color(red: 30/255, green: 29/255, blue: 42/255)

    // MARK: - Behind the field

    /// Bands, shafts, flakes and eddies — everything the pops float *in*.
    static func drawBehind(_ field: WeatherField, glow: inout GraphicsContext,
                           size: CGSize) {
        guard size.width > 0, size.height > 0, field.presence > 0.001 else { return }
        // The whole layer fades with the field's completion — see
        // `WeatherField.presence`. Saved and restored around the layer: the
        // context is `inout` and everything drawn after the weather must not
        // inherit its fade.
        let restored = glow.opacity
        glow.opacity = restored * Double(field.presence)
        defer { glow.opacity = restored }
        drawShafts(field, into: &glow, size: size)
        drawWaterBands(field, into: &glow, size: size)
        drawEddies(field, into: &glow, size: size)
        drawGust(field, into: &glow, size: size)
        drawFlakes(field, into: &glow, size: size)
    }

    // MARK: - In front of the field

    /// Foam, splash, shine, fog. The half of the weather that the pops are
    /// underneath.
    static func drawFront(_ field: WeatherField, orbs: [Orb], pointer: CGPoint?,
                          into context: inout GraphicsContext,
                          glow: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0, field.presence > 0.001 else { return }
        let restoredGlow = glow.opacity
        let restoredContext = context.opacity
        glow.opacity = restoredGlow * Double(field.presence)
        context.opacity = restoredContext * Double(field.presence)
        defer {
            glow.opacity = restoredGlow
            context.opacity = restoredContext
        }
        drawFoam(field, into: &glow, size: size)
        drawSplashes(field, into: &glow)
        drawShine(field, orbs: orbs, into: &glow)
        drawFog(field, pointer: pointer, into: &context, size: size)
    }

    // MARK: - Water

    /// A crest as a leaning band: a wide soft body, then a narrower core that
    /// carries the shape of the cells the water actually pulls in. Two fills
    /// each and two crests — four gradient fills in the heaviest frame of the
    /// wettest air.
    private static func drawWaterBands(_ field: WeatherField,
                                       into glow: inout GraphicsContext, size: CGSize) {
        for c in field.crests where c.strength > 0 {
            let a = Double(c.strength)
            band(crest: c, spread: 1.0, celled: false, size: size,
                 opacity: GameConfig.weatherBandOpacity * a, tint: water, into: &glow)
            band(crest: c, spread: 0.42, celled: true, size: size,
                 opacity: GameConfig.weatherBandOpacity * a * 0.9, tint: water, into: &glow)
        }
    }

    /// The cells a wave front breaks in — the same shape the water actually
    /// carries with (`WeatherField.airVelocity`), so what she sees gathering is
    /// where the pull is. Without this the core is a straight bar, which is
    /// the one thing water never looks like.
    private static func cell(_ c: WeatherField.Crest, atY y: CGFloat) -> CGFloat {
        0.55 + 0.45 * sin(y * (2 * .pi / GameConfig.weatherCrestCellHeight) + c.cell)
    }

    private static func band(crest c: WeatherField.Crest,
                             spread: CGFloat, celled: Bool, size: CGSize, opacity: Double,
                             tint: Color, into glow: inout GraphicsContext) {
        let base = c.halfWidth * spread
        let mid = size.height / 2
        let steps = 18
        var path = Path()

        // Down the leading edge…
        for k in 0...steps {
            let y = size.height * CGFloat(k) / CGFloat(steps)
            let line = c.x + c.tilt * (y - mid)
            let half = celled ? base * cell(c, atY: y) : base
            let wobble = sin(y * 0.012 + c.ripple) * 7
            let p = CGPoint(x: line - half + wobble, y: y)
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        // …and back up the trailing one.
        for k in stride(from: steps, through: 0, by: -1) {
            let y = size.height * CGFloat(k) / CGFloat(steps)
            let line = c.x + c.tilt * (y - mid)
            let half = celled ? base * cell(c, atY: y) : base
            let wobble = sin(y * 0.014 - c.ripple) * 7
            path.addLine(to: CGPoint(x: line + half + wobble, y: y))
        }
        path.closeSubpath()

        let centre = c.x
        let stops = Gradient(stops: [
            .init(color: tint.opacity(0), location: 0),
            .init(color: tint.opacity(opacity), location: 0.5),
            .init(color: tint.opacity(0), location: 1)
        ])
        glow.fill(path, with: .linearGradient(
            stops,
            startPoint: CGPoint(x: centre - base, y: mid),
            endPoint: CGPoint(x: centre + base, y: mid)))
    }

    /// The foam line — the crest itself, drawn over the pops so the water
    /// closes above them.
    private static func drawFoam(_ field: WeatherField,
                                 into glow: inout GraphicsContext, size: CGSize) {
        let mid = size.height / 2
        for c in field.crests where c.strength > 0 {
            var path = Path()
            let steps = 20
            for k in 0...steps {
                let y = size.height * CGFloat(k) / CGFloat(steps)
                // The foam runs ahead of the line where the water is pulling
                // hardest, so the crest reads as breaking unevenly — the same
                // cells the water is actually carrying with.
                let lead = c.dir * (cell(c, atY: y) - 0.55) * c.halfWidth * 0.5
                let line = c.x + c.tilt * (y - mid) + lead + sin(y * 0.03 + c.ripple) * 5
                let p = CGPoint(x: line, y: y)
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            glow.stroke(path,
                        with: .color(foam.opacity(GameConfig.weatherFoamOpacity
                                                  * Double(c.strength))),
                        lineWidth: 1.2)
        }
    }

    /// Droplets. Small, and the one bright thing the water is allowed.
    private static func drawSplashes(_ field: WeatherField, into glow: inout GraphicsContext) {
        for d in field.splashes {
            let a = Double(max(0, min(1, d.life)))
            let s = d.size * CGFloat(0.6 + a * 0.4)
            let rect = CGRect(x: d.pos.x - s, y: d.pos.y - s, width: s * 2, height: s * 2)
            glow.fill(Path(ellipseIn: rect), with: .color(foam.opacity(a * 0.4)))
        }
    }

    // MARK: - Wind

    /// An eddy: three thin arcs turning on the vortex's own phase. Wind you
    /// can see the shape of, rather than a direction you infer from the orbs.
    private static func drawEddies(_ field: WeatherField,
                                   into glow: inout GraphicsContext, size: CGSize) {
        for e in field.eddies where e.strength > 0.01 {
            for k in 1...3 {
                let r = e.radius * (0.34 + 0.26 * CGFloat(k))
                let start = e.phase * e.spin * 8 + CGFloat(k) * 2.1
                let sweep: CGFloat = 1.5 + CGFloat(k) * 0.28
                var path = Path()
                path.addArc(center: e.pos, radius: r,
                            startAngle: .radians(Double(start)),
                            endAngle: .radians(Double(start + sweep)),
                            clockwise: e.spin < 0)
                glow.stroke(path,
                            with: .color(wind.opacity(0.055 * Double(e.strength))),
                            lineWidth: 1)
            }
        }
    }

    /// The gust: long, faint streaks along the way the air is going, which
    /// appear as it gathers and are gone in the ebb.
    private static func drawGust(_ field: WeatherField,
                                 into glow: inout GraphicsContext, size: CGSize) {
        let level = Double(field.gustLevel)
        guard level > 0.02 else { return }
        let angle = field.gustAngle
        let dx = cos(angle), dy = sin(angle)
        let span = max(size.width, size.height)
        // Ten streaks, spread down the field and slid along by the same angle
        // that is already turning — no per-frame randomness, so the drawing
        // stays stateless.
        for k in 0..<10 {
            let t = CGFloat(k) / 10
            let slide = (angle * 300 + CGFloat(k) * 137).truncatingRemainder(dividingBy: span)
            let cx = size.width * t + dx * slide - dx * span / 2
            let cy = size.height * ((t * 7).truncatingRemainder(dividingBy: 1)) + dy * slide * 0.4
            let length = span * 0.22
            var path = Path()
            path.move(to: CGPoint(x: cx - dx * length / 2, y: cy - dy * length / 2))
            path.addLine(to: CGPoint(x: cx + dx * length / 2, y: cy + dy * length / 2))
            glow.stroke(path, with: .color(wind.opacity(0.05 * level)), lineWidth: 1)
        }
    }

    // MARK: - Snow

    private static func drawFlakes(_ field: WeatherField,
                                   into glow: inout GraphicsContext, size: CGSize) {
        guard !field.flakes.isEmpty else { return }
        var settled = 0
        for flake in field.flakes {
            let resting = flake.rest > 0
            if resting { settled += 1 }
            // A resting flake fades as it melts, so nothing ever blinks out.
            let fade = resting
                ? Double(min(1, flake.rest / 120))
                : 1
            let s = flake.size
            let rect = CGRect(x: flake.pos.x - s, y: flake.pos.y - s,
                              width: s * 2, height: s * 2)
            glow.fill(Path(ellipseIn: rect), with: .color(snow.opacity(0.34 * fade)))
        }

        // What has come to rest, as a soft line along the floor. It deepens
        // as flakes settle and thins as they melt — and it is never in her
        // way, because it is four points tall.
        guard settled > 0 else { return }
        let depth = min(1, CGFloat(settled) / CGFloat(max(1, field.flakes.count)))
        let h = 3 + depth * 5
        let rect = CGRect(x: 0, y: size.height - h, width: size.width, height: h)
        glow.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: snow.opacity(0), location: 0),
                .init(color: snow.opacity(0.06 * Double(depth)), location: 1)
            ]),
            startPoint: CGPoint(x: 0, y: size.height - h),
            endPoint: CGPoint(x: 0, y: size.height)))
    }

    // MARK: - Sun

    /// Shafts of low light, leaning across the field.
    private static func drawShafts(_ field: WeatherField,
                                   into glow: inout GraphicsContext, size: CGSize) {
        let mid = size.height / 2
        for s in field.shafts {
            let breathe = 0.75 + 0.25 * Double(sin(s.phase))
            var path = Path()
            let steps = 8
            for k in 0...steps {
                let y = size.height * CGFloat(k) / CGFloat(steps)
                let line = s.x + s.tilt * (y - mid)
                let p = CGPoint(x: line - s.halfWidth, y: y)
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            for k in stride(from: steps, through: 0, by: -1) {
                let y = size.height * CGFloat(k) / CGFloat(steps)
                let line = s.x + s.tilt * (y - mid)
                path.addLine(to: CGPoint(x: line + s.halfWidth, y: y))
            }
            path.closeSubpath()
            glow.fill(path, with: .linearGradient(
                Gradient(stops: [
                    .init(color: sun.opacity(0), location: 0),
                    .init(color: sun.opacity(0.05 * breathe), location: 0.5),
                    .init(color: sun.opacity(0), location: 1)
                ]),
                startPoint: CGPoint(x: s.x - s.halfWidth, y: mid),
                endPoint: CGPoint(x: s.x + s.halfWidth, y: mid)))
        }
    }

    /// THE POPS PICK UP THE LIGHT. A specular pin-light on the side the light
    /// comes from, brightest where an orb stands in a shaft. Two small fills
    /// per orb and only in the airs that have light to give.
    private static func drawShine(_ field: WeatherField, orbs: [Orb],
                                  into glow: inout GraphicsContext) {
        let shine = field.weather.shine
        guard shine > 0 else { return }
        let tint = field.weather == .summer ? sun : foam
        let mid = field.bounds.height / 2

        for o in orbs where o.alive {
            // Standing in a shaft is what makes an orb bright; in the warm
            // air without shafts, or in the rain, it keeps a base gleam.
            var lit: CGFloat = 0.45
            for s in field.shafts {
                let line = s.x + s.tilt * (o.pos.y - mid)
                let u = (o.pos.x - line) / s.halfWidth
                guard abs(u) < 1 else { continue }
                lit = max(lit, 0.5 + 0.5 * cos(u * .pi / 2))
            }
            let a = Double(shine * lit) * GameConfig.weatherShineOpacity
            let R = o.r * min(1, max(0, o.spawn))
            guard R > 1 else { continue }

            let hr = R * 0.15
            let centre = CGPoint(x: o.pos.x - R * 0.40, y: o.pos.y - R * 0.44)
            glow.fill(Path(ellipseIn: CGRect(x: centre.x - hr, y: centre.y - hr,
                                             width: hr * 2, height: hr * 2)),
                      with: .color(tint.opacity(a)))

            // The bloom around it, which is what actually reads as "shining".
            let br = R * 0.62
            glow.fill(Path(ellipseIn: CGRect(x: centre.x - br, y: centre.y - br,
                                             width: br * 2, height: br * 2)),
                      with: .radialGradient(
                        Gradient(stops: [
                            .init(color: tint.opacity(a * 0.45), location: 0),
                            .init(color: tint.opacity(0), location: 1)
                        ]),
                        center: centre, startRadius: 0, endRadius: br))
        }
    }

    // MARK: - Fog

    /// Banks drawn over the field, with a clearing where her finger is.
    ///
    /// The hole is punched with `destinationOut` inside a transparency layer
    /// rather than drawn as a lighter patch, so the fog genuinely thins there
    /// instead of gaining a bright spot — the one air in the game that gets
    /// out of her way when she touches it.
    private static func drawFog(_ field: WeatherField, pointer: CGPoint?,
                                into context: inout GraphicsContext, size: CGSize) {
        guard !field.banks.isEmpty else { return }
        context.drawLayer { layer in
            for b in field.banks {
                let a = GameConfig.weatherFogOpacity * Double(b.alpha)
                    * (0.75 + 0.25 * Double(sin(b.phase)))
                let rect = CGRect(x: b.pos.x - b.r, y: b.pos.y - b.r,
                                  width: b.r * 2, height: b.r * 2)
                layer.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(stops: [
                        .init(color: fog.opacity(a), location: 0),
                        .init(color: fog.opacity(a * 0.55), location: 0.55),
                        .init(color: fog.opacity(0), location: 1)
                    ]),
                    center: b.pos, startRadius: 0, endRadius: b.r))
            }

            guard let p = pointer else { return }
            var clearing = layer
            clearing.blendMode = .destinationOut
            let r: CGFloat = 130
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            clearing.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color.black.opacity(0.85), location: 0),
                    .init(color: Color.black.opacity(0.5), location: 0.45),
                    .init(color: Color.black.opacity(0), location: 1)
                ]),
                center: p, startRadius: 0, endRadius: r))
        }
    }
}
