import CoreGraphics
import Foundation

// THE AIR, WITH A BODY.
//
// `Weather` on its own is a set of per-orb multipliers, and the owner's note
// — "the weather isn't interactive enough… the weather needs to dominate the
// scene" — is precisely the thing a multiplier cannot answer. A multiplier has
// nothing to look at and nothing to meet. So the air gets a field of its own:
// crests that sweep across the glass and carry the pops with them, eddies that
// turn, gusts that gather and ebb, flakes that settle, shafts of low light,
// banks of fog that thin where her finger is.
//
// WHAT KIND OF FORCE THIS IS, AND WHY IT IS SAFE.
//
// Nothing here pushes. Every element describes the VELOCITY OF THE AIR at a
// point, and `apply(to:)` carries the orb along at that velocity — it moves
// the orb's POSITION and never touches the orb's own velocity at all:
//
//     pos += min(air, ceiling − |v|) * f
//
// Two things follow, and both of them matter more than they look.
//
// FIRST, THE TOTAL IS BOUNDED BY THE CEILING THAT WAS ALREADY THERE. What the
// air is allowed to add is exactly what is left under `orbMaxSpeed ×
// speedScale × 1.6` once the orb's own motion is counted, so the fastest
// anything crosses the glass in any air is the same number it has always
// been. Weather cannot add to that, and — because it is a position and not a
// velocity — it cannot accumulate into it either. There is nothing to
// integrate: the moment the water passes, the carrying is over.
//
// SECOND, THE FIELD KEEPS ITS SHAPE. The first version of this blended the
// orb's velocity toward the air's, which is the obvious way to write it and
// is quietly wrong: rain loses no momentum (`glide` is 1), so every wave left
// the whole field moving at the same velocity, the orbs' own drift was
// overwritten again and again, and after a minute the field had gathered into
// a single travelling clump — a 4,000-frame spread of 47 points where still
// air keeps 200. Carrying the position leaves every orb's own motion intact,
// so the field spreads exactly as it always did (247 points, measured) and
// the water still moves it twice as visibly as the blend ever did.
//
// AND WHY IT CANNOT STRAND THE FIELD. Every flow in here integrates to
// approximately zero along any path an orb can take:
//   • a crest carries forward at its core and barely moves at its shoulders,
//     and successive crests STRICTLY ALTERNATE DIRECTION, so whatever one
//     wave carried to the right the next one carries back;
//   • an eddy is purely tangential — it turns things, it does not move them;
//   • a gust's heading rotates continuously, so its mean over time is zero;
//   • a thermal rises on one edge of a shaft and sinks on the other.
// `WeatherTests` holds all of that to the same 4,000-frame standard the older
// weather had to pass.
//
// Pure, deterministic, and UI-free, like everything else in `Game/`: time
// arrives as the clamped frame factor `f`, randomness comes from a SplitMix64
// seeded off the field's own generator, and drawing happens somewhere else.
struct WeatherField {

    // MARK: - What is in the air

    /// A travelling wave. `x` is the crest LINE; the band reaches `halfWidth`
    /// either side of it, and `tilt` leans that line so the water arrives at
    /// an angle rather than as a wipe.
    struct Crest {
        var x: CGFloat
        var previousX: CGFloat
        var dir: CGFloat            // +1 travelling right, −1 travelling left
        var speed: CGFloat
        var halfWidth: CGFloat
        var tilt: CGFloat
        var life: CGFloat
        var ripple: CGFloat         // phase of the drawn edge
        var cell: CGFloat           // phase of the cells the front breaks in
        var strength: CGFloat = 0   // eases in and out; nothing snaps on
        var age: CGFloat = 0
    }

    /// A vortex. Turns what it holds and never carries it anywhere.
    struct Eddy {
        var pos: CGPoint
        var vel: CGVector
        var radius: CGFloat
        var spin: CGFloat           // +1 / −1
        var life: CGFloat
        var phase: CGFloat
        var strength: CGFloat = 0
        var age: CGFloat = 0
    }

    /// One flake, falling or resting. A settled flake melts and falls again —
    /// nothing in this game is ever taken away for good.
    struct Flake {
        var pos: CGPoint
        var vel: CGVector
        var size: CGFloat
        var phase: CGFloat
        var sway: CGFloat
        var rest: CGFloat = 0       // > 0 while settled
    }

    /// A shaft of low light, leaning across the field.
    struct Shaft {
        var x: CGFloat
        var halfWidth: CGFloat
        var tilt: CGFloat
        var drift: CGFloat
        var phase: CGFloat
    }

    /// A bank of fog. Drawn in FRONT of the field and thinned near her finger.
    struct Bank {
        var pos: CGPoint
        var vel: CGVector
        var r: CGFloat
        var alpha: CGFloat
        var phase: CGFloat
    }

    /// Water thrown where a crest met a pop.
    struct Splash {
        var pos: CGPoint
        var vel: CGVector
        var life: CGFloat
        var decay: CGFloat
        var size: CGFloat
    }

    // MARK: - State
    //
    // Every one of these arrays is bounded by the air's own counts: at most
    // 3 crests, 4 eddies, 3 shafts, 7 banks, 72 flakes and 72 splashes — under
    // 160 moving things in the busiest air, and most airs hold one kind only.

    private(set) var crests: [Crest] = []
    private(set) var eddies: [Eddy] = []
    private(set) var flakes: [Flake] = []
    private(set) var shafts: [Shaft] = []
    private(set) var banks: [Bank] = []
    private(set) var splashes: [Splash] = []

    /// The gust envelope: how hard it is blowing right now, and from where.
    /// The level ebbs toward nothing between gusts — wind that blew steadily
    /// would be a fan, not weather.
    private(set) var gustLevel: CGFloat = 0
    private(set) var gustAngle: CGFloat = 0

    private(set) var weather: Weather = .clear
    private(set) var bounds: CGSize = .zero
    private(set) var reduceMotion = false

    /// The speed of the air itself, in points per frame. Zero in still air,
    /// and zero under Reduce Motion — nothing travels toward her there.
    private(set) var carry: CGFloat = 0

    /// The ceiling this air is held to, which is the ceiling
    /// `GameSimulation.applyWeather` has always used. An orb's own speed plus
    /// whatever the air carries it at may not exceed this.
    private(set) var ceiling: CGFloat = 0

    private var gustTarget: CGFloat = 0
    private var gustTimer: CGFloat = 0
    private var gustSpin: CGFloat = 0
    private var crestTimer: CGFloat = 0
    private var lastCrestDir: CGFloat = -1
    private var rng = SplitMix64(seed: 0)
    private var configured = false

    // MARK: - Stepping

    /// One frame of weather. `seed` is read only when the air changes, so the
    /// same field always gets the same sky, and drawing from it never
    /// disturbs the field's own sequence.
    mutating func step(_ f: CGFloat, weather: Weather, bounds: CGSize,
                       reduceMotion: Bool, orbs: [Orb], seed: UInt64) {
        if !configured || weather != self.weather || bounds != self.bounds
            || reduceMotion != self.reduceMotion {
            reset(weather: weather, bounds: bounds, reduceMotion: reduceMotion, seed: seed)
        }
        guard bounds.width > 0, bounds.height > 0, weather.hasField else { return }

        // UNDER REDUCE MOTION EVERYTHING STILL EXISTS AND ALMOST NOTHING
        // MOVES: the air becomes something to look at rather than something
        // travelling toward her, and `carry` is zero, so it does not move the
        // orbs at all.
        let advance = f * (reduceMotion ? GameConfig.weatherStillnessScale : 1)
        guard advance > 0 else { return }

        stepCrests(advance, orbs: orbs)
        stepEddies(advance)
        stepGusts(advance)
        stepFlakes(advance)
        stepShafts(advance)
        stepBanks(advance)
        stepSplashes(advance)
    }

    /// A new sky. Called whenever the air, the screen or Reduce Motion change.
    private mutating func reset(weather: Weather, bounds: CGSize,
                                reduceMotion: Bool, seed: UInt64) {
        self.weather = weather
        self.bounds = bounds
        self.reduceMotion = reduceMotion
        configured = true
        rng = SplitMix64(seed: seed)
        crests.removeAll()
        eddies.removeAll()
        flakes.removeAll()
        shafts.removeAll()
        banks.removeAll()
        splashes.removeAll()
        gustLevel = 0
        gustTarget = 0
        gustTimer = 0
        crestTimer = 0
        carry = reduceMotion ? 0 : weather.flowCarry * GameConfig.orbMaxSpeed
        ceiling = GameConfig.orbMaxSpeed * weather.speedScale * 1.6
        guard bounds.width > 0, bounds.height > 0, weather.hasField else { return }

        gustAngle = weatherRandom(0 ... .pi * 2, &rng)
        gustSpin = weatherRandom(0.0012 ... 0.0028, &rng) * weatherSign(&rng)
        lastCrestDir = weatherSign(&rng)

        for _ in 0..<min(weather.eddyCount, 4) {
            let e = makeEddy(in: bounds, &rng)
            eddies.append(e)
        }
        for _ in 0..<min(weather.flakeCount, 72) {
            let flake = makeFlake(in: bounds, fresh: false, &rng)
            flakes.append(flake)
        }
        for _ in 0..<min(weather.shaftCount, 3) {
            let s = makeShaft(in: bounds, &rng)
            shafts.append(s)
        }
        for _ in 0..<min(weather.bankCount, 7) {
            let b = makeBank(in: bounds, &rng)
            banks.append(b)
        }
    }

    // MARK: - Water

    private mutating func stepCrests(_ f: CGFloat, orbs: [Orb]) {
        guard weather.crestCount > 0 else { return }

        crestTimer -= f
        if crestTimer <= 0 && crests.count < min(weather.crestCount, 3) {
            // STRICTLY ALTERNATING. This is why water cannot pile the field
            // against a wall: whatever one crest carries to the right, the
            // next one carries back.
            let dir: CGFloat = lastCrestDir > 0 ? -1 : 1
            lastCrestDir = dir
            let c = makeCrest(dir: dir, in: bounds, &rng)
            crests.append(c)
            crestTimer = weatherRandom(GameConfig.weatherCrestGapRange, &rng)
        }

        let mid = bounds.height / 2
        for i in crests.indices {
            crests[i].previousX = crests[i].x
            crests[i].x += crests[i].dir * crests[i].speed * f
            crests[i].age += f
            crests[i].ripple += 0.035 * f
            // In over half a second and out over half a second: a wave that
            // arrived at full strength would read as a cut.
            let ease: CGFloat = 34
            let age = crests[i].age
            let life = crests[i].life
            crests[i].strength = max(0, min(1, min(age / ease, (life - age) / ease)))
        }

        if !reduceMotion {
            let existing = crests
            for c in existing where c.strength > 0.35 {
                let drops = makeSplashes(crest: c, orbs: orbs, mid: mid,
                                         room: GameConfig.weatherSplashCap - splashes.count,
                                         &rng)
                if !drops.isEmpty { splashes.append(contentsOf: drops) }
            }
        }

        crests.removeAll { $0.age >= $0.life }
    }

    /// Where the crest LINE sits at a given height, once its lean is counted.
    func crestLine(_ c: Crest, atY y: CGFloat) -> CGFloat {
        c.x + c.tilt * (y - bounds.height / 2)
    }

    private mutating func stepSplashes(_ f: CGFloat) {
        guard !splashes.isEmpty else { return }
        let drag = pow(0.985, f)
        for i in splashes.indices {
            splashes[i].pos.x += splashes[i].vel.dx * f
            splashes[i].pos.y += splashes[i].vel.dy * f
            splashes[i].vel.dy += 0.055 * f      // droplets fall back
            splashes[i].vel.dx *= drag
            splashes[i].life -= splashes[i].decay * f
        }
        splashes.removeAll { $0.life <= 0 }
        if splashes.count > GameConfig.weatherSplashCap {
            splashes.removeFirst(splashes.count - GameConfig.weatherSplashCap)
        }
    }

    // MARK: - Wind

    private mutating func stepEddies(_ f: CGFloat) {
        guard weather.eddyCount > 0 else { return }
        for i in eddies.indices {
            eddies[i].age += f
            eddies[i].phase += 0.01 * f
            eddies[i].pos.x += eddies[i].vel.dx * f
            eddies[i].pos.y += eddies[i].vel.dy * f
            let ease: CGFloat = 90
            let age = eddies[i].age
            let life = eddies[i].life
            eddies[i].strength = max(0, min(1, min(age / ease, (life - age) / ease)))
        }
        // One turns away and another forms elsewhere. The count never changes,
        // so the array is bounded by the air's own `eddyCount`.
        for i in eddies.indices where eddies[i].age >= eddies[i].life {
            let fresh = makeEddy(in: bounds, &rng)
            eddies[i] = fresh
        }
    }

    /// Gusts arrive, and then ebb. The heading turns the whole time, which is
    /// what keeps a gust from being a direction the field slowly loses to.
    private mutating func stepGusts(_ f: CGFloat) {
        guard weather.hasGusts else { return }
        gustAngle += gustSpin * f
        gustTimer -= f
        if gustTimer <= 0 {
            gustTarget = weatherRandom(0.4 ... 1, &rng)
            gustTimer = weatherRandom(GameConfig.weatherGustGapRange, &rng)
        }
        gustTarget *= pow(GameConfig.weatherGustEbb, f)
        gustLevel += (gustTarget - gustLevel) * min(1, GameConfig.weatherGustRise * f)
        gustLevel = max(0, min(1, gustLevel))
    }

    // MARK: - Snow

    private mutating func stepFlakes(_ f: CGFloat) {
        guard weather.flakeCount > 0 else { return }
        let floorY = bounds.height - 4
        let width = bounds.width
        for i in flakes.indices {
            if flakes[i].rest > 0 {
                flakes[i].rest -= f
                if flakes[i].rest <= 0 {
                    let fresh = makeFlake(in: bounds, fresh: true, &rng)
                    flakes[i] = fresh
                }
                continue
            }
            flakes[i].phase += 0.02 * f
            let lateral = flakes[i].vel.dx + sin(flakes[i].phase) * flakes[i].sway
            flakes[i].pos.x += lateral * f
            flakes[i].pos.y += flakes[i].vel.dy * f
            if flakes[i].pos.x < -6 { flakes[i].pos.x += width + 12 }
            if flakes[i].pos.x > width + 6 { flakes[i].pos.x -= width + 12 }
            if flakes[i].pos.y >= floorY {
                let rest = weatherRandom(GameConfig.weatherFlakeRestRange, &rng)
                flakes[i].pos.y = floorY
                flakes[i].rest = rest
            }
        }
    }

    // MARK: - Sun

    private mutating func stepShafts(_ f: CGFloat) {
        guard weather.shaftCount > 0 else { return }
        let span = bounds.width + 260
        for i in shafts.indices {
            shafts[i].x += shafts[i].drift * f
            shafts[i].phase += 0.004 * f
            if shafts[i].x < -130 { shafts[i].x += span }
            if shafts[i].x > span - 130 { shafts[i].x -= span }
        }
    }

    // MARK: - Fog

    private mutating func stepBanks(_ f: CGFloat) {
        guard weather.bankCount > 0 else { return }
        let w = bounds.width, h = bounds.height
        for i in banks.indices {
            banks[i].pos.x += banks[i].vel.dx * f
            banks[i].pos.y += banks[i].vel.dy * f
            banks[i].phase += 0.003 * f
            let r = banks[i].r
            if banks[i].pos.x < -r { banks[i].pos.x = w + r }
            if banks[i].pos.x > w + r { banks[i].pos.x = -r }
            if banks[i].pos.y < -r { banks[i].pos.y = h + r }
            if banks[i].pos.y > h + r { banks[i].pos.y = -r }
        }
    }

    // MARK: - The force

    /// The velocity of the air at a point, in points per frame. Pure — it
    /// changes nothing, so anything may ask.
    ///
    /// Each element contributes its own velocity weighted by its own envelope,
    /// which is 1 where the element is strongest and eases to 0 at its edge;
    /// the sum is then held to `carry`, the speed of this air. There is no
    /// separate coupling constant to tune, and nothing here can be anywhere
    /// near as strong as the sum of everything overlapping — that is what the
    /// clamp is for.
    func airVelocity(at p: CGPoint) -> CGVector {
        guard carry > 0 else { return .zero }
        var vx: CGFloat = 0, vy: CGFloat = 0

        // CRESTS. The core runs forward at the full speed of the water and the
        // shoulders barely move (`backwash`), and the front is cut into cells
        // so a wave does not break evenly along its whole length. The cells
        // are the reason the water can carry the field without gathering it:
        // the field is sheared rather than moved as one block.
        for c in crests where c.strength > 0 {
            let u = (p.x - crestLine(c, atY: p.y)) / c.halfWidth
            guard abs(u) < 1 else { continue }
            let env = cos(u * .pi / 2)
            let w = env * env * c.strength
            guard w > 0 else { continue }
            let back = GameConfig.weatherCrestBackwash
            let along = (1 - back) + back * cos(u * .pi)
            let cell = 0.55 + 0.45 * sin(p.y * (2 * .pi / GameConfig.weatherCrestCellHeight)
                                         + c.cell)
            vx += c.dir * carry * along * cell * w
            vy += c.dir * carry * GameConfig.weatherCrestLift * (-sin(u * .pi)) * w
        }

        // EDDIES: purely tangential. They turn what they hold, and a thing
        // that only ever moves along a circle is not going anywhere.
        for e in eddies where e.strength > 0 {
            let dx = p.x - e.pos.x, dy = p.y - e.pos.y
            let r = sqrt(dx * dx + dy * dy)
            guard r > 0.5, r < e.radius else { continue }
            let w = sin(r / e.radius * .pi) * e.strength * GameConfig.weatherEddyPull
            guard w > 0 else { continue }
            vx += (-dy / r) * carry * e.spin * w
            vy += (dx / r) * carry * e.spin * w
        }

        // THE GUST: everywhere at once, and turning the whole time, so what it
        // carries one way it carries back a minute later.
        if gustLevel > 0.002 {
            let w = gustLevel * GameConfig.weatherGustPull
            vx += cos(gustAngle) * carry * w
            vy += sin(gustAngle) * carry * w * 0.6
        }

        // THERMALS: a shaft lifts along one edge and settles along the other,
        // so warm shimmers and never climbs.
        for s in shafts {
            let line = s.x + s.tilt * (p.y - bounds.height / 2)
            let u = (p.x - line) / s.halfWidth
            guard abs(u) < 1 else { continue }
            let env = cos(u * .pi / 2)
            vy += (-sin(u * .pi)) * carry * GameConfig.weatherThermalPull * env * env
        }

        var air = CGVector(dx: vx, dy: vy)
        let speed = sqrt(air.dx * air.dx + air.dy * air.dy)
        if speed > carry {                                  // the air's own ceiling
            let k = carry / speed
            air.dx *= k
            air.dy *= k
        }
        return air
    }

    /// How far the air may carry this orb in one 60 fps frame, given how fast
    /// the orb is already travelling under its own steam.
    ///
    /// THIS IS THE GUARDRAIL, AND IT IS ONE SUBTRACTION. The orb's own speed
    /// is counted first, and the air may only use what is left under the
    /// ceiling — so the total distance anything covers in a frame is exactly
    /// what it always was, and an orb already at its own top speed is not
    /// carried at all.
    func drift(at p: CGPoint, ownSpeed: CGFloat) -> CGVector {
        guard carry > 0, !reduceMotion else { return .zero }
        var air = airVelocity(at: p)
        let speed = sqrt(air.dx * air.dx + air.dy * air.dy)
        guard speed > 0 else { return .zero }
        let allowance = max(0, ceiling - min(ceiling, ownSpeed))
        if speed > allowance {
            let k = allowance / speed
            air.dx *= k
            air.dy *= k
        }
        return air
    }

    /// Carry one orb with the air. Its velocity is not touched — see the note
    /// at the top of this file.
    func apply(to orb: inout Orb, _ f: CGFloat) {
        guard carry > 0, !reduceMotion else { return }
        let own = sqrt(orb.vel.dx * orb.vel.dx + orb.vel.dy * orb.vel.dy)
        let d = drift(at: orb.pos, ownSpeed: own)
        guard d.dx != 0 || d.dy != 0 else { return }
        orb.pos.x += d.dx * f
        orb.pos.y += d.dy * f
    }
}

// MARK: - Makers
//
// Free functions rather than methods on purpose. Each takes the generator by
// `inout` and touches nothing else, which keeps every construction site a
// single simple statement — `let c = makeCrest(...); crests.append(c)` — with
// no call that mutates the whole struct while one of its own arrays is being
// written into.

private func weatherRandom(_ range: ClosedRange<CGFloat>, _ rng: inout SplitMix64) -> CGFloat {
    CGFloat.random(in: range, using: &rng)
}

private func weatherSign(_ rng: inout SplitMix64) -> CGFloat {
    Bool.random(using: &rng) ? 1 : -1
}

private func makeCrest(dir: CGFloat, in bounds: CGSize,
                       _ rng: inout SplitMix64) -> WeatherField.Crest {
    let halfWidth = max(40, bounds.width * GameConfig.weatherCrestWidth / 2)
    let speed = weatherRandom(GameConfig.weatherCrestSpeedRange, &rng)
    let startX = dir > 0 ? -halfWidth : bounds.width + halfWidth
    let travel = bounds.width + halfWidth * 2
    return WeatherField.Crest(x: startX, previousX: startX, dir: dir, speed: speed,
                              halfWidth: halfWidth,
                              tilt: weatherRandom(-0.18 ... 0.18, &rng),
                              life: travel / max(0.2, speed),
                              ripple: weatherRandom(0 ... .pi * 2, &rng),
                              cell: weatherRandom(0 ... .pi * 2, &rng))
}

/// The water thrown where a crest line passes over a pop.
///
/// This is the interleaving the owner asked for: the band is drawn BEHIND the
/// orbs and the splash in FRONT of them, so a pop is in the water rather than
/// on top of a picture of it.
private func makeSplashes(crest c: WeatherField.Crest, orbs: [Orb], mid: CGFloat,
                          room: Int, _ rng: inout SplitMix64) -> [WeatherField.Splash] {
    guard room >= GameConfig.weatherSplashPerHit else { return [] }
    var made: [WeatherField.Splash] = []
    let travelled = c.x - c.previousX
    for orb in orbs where orb.alive {
        guard made.count + GameConfig.weatherSplashPerHit <= room else { break }
        let line = c.x + c.tilt * (orb.pos.y - mid)
        let previous = line - travelled
        let lo = min(previous, line), hi = max(previous, line)
        // The window is the crest line's own travel this frame, and no wider:
        // an orb splashes as the water REACHES it rather than spraying for the
        // whole time the band covers it, which is what keeps the droplets to a
        // handful per orb per wave instead of a hundred.
        guard orb.pos.x >= lo - 0.5, orb.pos.x <= hi + 0.5 else { continue }
        for _ in 0..<GameConfig.weatherSplashPerHit {
            made.append(WeatherField.Splash(
                pos: CGPoint(x: orb.pos.x + weatherRandom(-0.4 ... 0.4, &rng) * orb.r,
                             y: orb.pos.y + weatherRandom(-0.7 ... 0.2, &rng) * orb.r),
                vel: CGVector(dx: c.dir * weatherRandom(0.4 ... 1.6, &rng)
                                  + weatherRandom(-0.3 ... 0.3, &rng),
                              dy: -weatherRandom(0.6 ... 1.8, &rng)),
                life: 1,
                decay: weatherRandom(0.018 ... 0.032, &rng),
                size: weatherRandom(0.9 ... 2.1, &rng)))
        }
    }
    return made
}

private func makeEddy(in bounds: CGSize, _ rng: inout SplitMix64) -> WeatherField.Eddy {
    let short = min(bounds.width, bounds.height)
    let radius = max(60, short * weatherRandom(GameConfig.weatherEddyRadius, &rng))
    return WeatherField.Eddy(
        pos: CGPoint(x: weatherRandom(0 ... max(1, bounds.width), &rng),
                     y: weatherRandom(0 ... max(1, bounds.height), &rng)),
        vel: CGVector(dx: weatherRandom(-0.25 ... 0.25, &rng),
                      dy: weatherRandom(-0.18 ... 0.18, &rng)),
        radius: radius,
        spin: weatherSign(&rng),
        life: weatherRandom(GameConfig.weatherEddyLifeRange, &rng),
        phase: weatherRandom(0 ... .pi * 2, &rng))
}

private func makeFlake(in bounds: CGSize, fresh: Bool,
                       _ rng: inout SplitMix64) -> WeatherField.Flake {
    let y = fresh
        ? weatherRandom(-40 ... -2, &rng)
        : weatherRandom(0 ... max(1, bounds.height), &rng)
    return WeatherField.Flake(
        pos: CGPoint(x: weatherRandom(0 ... max(1, bounds.width), &rng), y: y),
        vel: CGVector(dx: weatherRandom(-0.06 ... 0.06, &rng),
                      dy: weatherRandom(0.18 ... 0.46, &rng)),
        size: weatherRandom(0.8 ... 2.0, &rng),
        phase: weatherRandom(0 ... .pi * 2, &rng),
        sway: weatherRandom(0.04 ... 0.16, &rng))
}

private func makeShaft(in bounds: CGSize, _ rng: inout SplitMix64) -> WeatherField.Shaft {
    WeatherField.Shaft(
        x: weatherRandom(0 ... max(1, bounds.width), &rng),
        halfWidth: weatherRandom(40 ... 90, &rng),
        tilt: weatherRandom(0.22 ... 0.46, &rng) * weatherSign(&rng),
        drift: weatherRandom(0.05 ... 0.16, &rng) * weatherSign(&rng),
        phase: weatherRandom(0 ... .pi * 2, &rng))
}

private func makeBank(in bounds: CGSize, _ rng: inout SplitMix64) -> WeatherField.Bank {
    WeatherField.Bank(
        pos: CGPoint(x: weatherRandom(0 ... max(1, bounds.width), &rng),
                     y: weatherRandom(0 ... max(1, bounds.height), &rng)),
        vel: CGVector(dx: weatherRandom(-0.14 ... 0.14, &rng),
                      dy: weatherRandom(-0.05 ... 0.05, &rng)),
        r: weatherRandom(90 ... 190, &rng),
        alpha: weatherRandom(0.5 ... 1, &rng),
        phase: weatherRandom(0 ... .pi * 2, &rng))
}
