import CoreGraphics
import Foundation

// The whole game, as a pure deterministic system. No SwiftUI, no UIKit, no
// wall-clock: time arrives as `dt`, randomness comes from the injected seed,
// and every side effect (sound, haptics, UI) is expressed as a returned
// GameEvent for the view model to act on. This is what makes the game
// unit-testable and frame-rate independent.
//
// Content is data: each orb carries a pop number into PopCatalog, and the
// sim reads that pop's behavior/chain values (see PopStandard.swift).
final class GameSimulation {

    private(set) var orbs: [Orb] = []
    private(set) var particles: [Particle] = []
    private(set) var rings: [Ring] = []
    private(set) var motes: [Mote] = []
    private(set) var notes: [FloatNote] = []

    private(set) var popCount = 0
    private(set) var completed = false
    private(set) var started = false
    private(set) var bounds: CGSize = .zero

    var reduceMotion = false

    // The pops a new field may seed from (unlock logic lives in the view
    // model / ProgressionStore; the sim just samples what it's given).
    var availablePops: [Int] = [PopCatalog.classic.number]

    /// Her stage, which decides what a field is made of. Set by the view model
    /// from lifetime fields cleared before `seedField`; 0 is the v1.0 field.
    var stage: Int = 0

    /// The plan the current field was seeded from, kept for tests and points.
    private(set) var plan: FieldPlan = .forStage(0)

    /// WHERE THE FINGER IS, or nil when nothing is touching. Purely
    /// observational — it is reported alongside the input arbiter and never
    /// through it, so nothing about drifters can affect pop-vs-pan
    /// arbitration (the one thing R-SPIKE exists to protect).
    var pointer: CGPoint?

    /// THE BANDS THE FIELD MAY NOT ENTER, driven by `FieldLayout`.
    ///
    /// These were a single hardcoded `GameConfig.fieldTopInset` measured from
    /// the screen edge, which is how orbs came to drift under the sky
    /// whisper — and an orb under a whisper has its tap taken by the whisper,
    /// so she aims at an orb and the world travels instead. Insets are the
    /// simulation's half of that fix; the view's half is placing the signage
    /// where it says it does.
    var topInset: CGFloat = GameConfig.fieldTopInset
    var bottomInset: CGFloat = 0

    private var rng: SplitMix64

    init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        rng = SplitMix64(seed: seed)
    }

    // True once the field is cleared and every visual effect has faded —
    // the moment rendering can stop entirely.
    var isQuiescent: Bool {
        completed && particles.isEmpty && rings.isEmpty && notes.isEmpty
    }

    // MARK: - Setup

    func layout(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let changed = size != bounds
        bounds = size
        if motes.isEmpty || changed { seedMotes() }
        if orbs.isEmpty && !completed { seedField() }
    }

    func seedField() {
        orbs.removeAll()
        guard bounds.width > 0 else { return }
        plan = FieldPlan.forStage(stage)
        let pool = availablePops.isEmpty ? [PopCatalog.classic.number] : availablePops

        // The kinds are dealt into the field rather than rolled per orb, so a
        // stage's plan is exactly what she gets: two splitters means two, not
        // "two on average". A field that sometimes forgets to contain the
        // thing it just taught her is a field that reads as broken.
        var kinds: [OrbKind] = []
        for _ in 0..<plan.splitters { kinds.append(.splitter(remaining: plan.splitDepth)) }
        for _ in 0..<plan.drifters { kinds.append(.drifter) }
        while kinds.count < plan.orbCount { kinds.append(.plain) }
        kinds.shuffle(using: &rng)

        for kind in kinds.prefix(plan.orbCount) {
            orbs.append(makeOrb(kind: kind, pool: pool))
        }
        for _ in 0..<plan.generators {
            orbs.append(makeOrb(kind: .generator(makeGenerator()), pool: pool))
        }

        // The fortune never rides a generator or a splitter: it should be a
        // quiet gift on an ordinary orb, not a prize attached to the busiest
        // thing on screen.
        let ordinary = orbs.indices.filter { if case .plain = orbs[$0].kind { return true } else { return false } }
        if let idx = ordinary.randomElement(using: &rng) {
            orbs[idx].isFortune = true
        }
    }

    /// One orb, placed and painted. `radiusScale` lets a generator sit a
    /// little larger than what it makes.
    private func makeOrb(kind: OrbKind, pool: [Int]) -> Orb {
        let popNumber = pool.randomElement(using: &rng) ?? PopCatalog.classic.number
        let paintCount = PopCatalog.definition(for: popNumber).style.paints.count
        var r = rnd(GameConfig.orbRadiusRange)
        if case .generator = kind { r *= GameConfig.generatorRadiusScale }
        let inset = GameConfig.edgeInset
        var orb = Orb(
            pos: CGPoint(x: rnd(r + inset ... max(r + inset, bounds.width - r - inset)),
                         y: rnd(r + topInset + GameConfig.spawnMargin
                                ... max(r + topInset + GameConfig.spawnMargin,
                                        bounds.height - r - bottomInset - inset))),
            vel: CGVector(dx: rnd(-GameConfig.orbMaxSpeed ... GameConfig.orbMaxSpeed),
                          dy: rnd(-GameConfig.orbMaxSpeed ... GameConfig.orbMaxSpeed)),
            r: r, baseR: r,
            popNumber: popNumber,
            variantIndex: Int.random(in: 0..<max(1, paintCount), using: &rng),
            phase: rnd(0 ... .pi * 2))
        orb.spawn = 1
        orb.kind = kind
        return orb
    }

    /// A generator's closing rule, chosen at random from the three. Mixing
    /// them inside one field is the point — each reads differently under the
    /// finger, and a field with two identical generators has one idea in it.
    private func makeGenerator() -> Generator {
        let closing: Generator.Closing
        switch Int.random(in: 0..<3, using: &rng) {
        case 0:
            closing = .taps(remaining: Int.random(in: GameConfig.generatorTapsRange, using: &rng))
        case 1:
            closing = .quota(remaining: Int.random(in: GameConfig.generatorQuotaRange, using: &rng))
        default:
            closing = .settles(remaining: rnd(GameConfig.generatorSettleRange))
        }
        return Generator(closing: closing,
                         interval: rnd(GameConfig.generatorIntervalRange),
                         sinceLast: 0)
    }

    private func seedMotes() {
        motes.removeAll()
        for _ in 0..<GameConfig.moteCount {
            motes.append(Mote(
                pos: CGPoint(x: rnd(0 ... bounds.width), y: rnd(0 ... bounds.height)),
                vel: CGVector(dx: rnd(-0.05 ... 0.05), dy: rnd(-0.08 ... -0.02)),
                size: rnd(0.8 ... 2.2),
                alpha: rnd(0.04 ... 0.12),
                phase: rnd(0 ... .pi * 2)))
        }
    }

    func restart() {
        particles.removeAll()
        rings.removeAll()
        notes.removeAll()
        popCount = 0
        completed = false
        started = false
        seedField()
    }

    // Test hook: install an exact field so behavior tests don't depend on
    // random layout.
    func replaceOrbs(_ newOrbs: [Orb]) {
        orbs = newOrbs
        particles.removeAll()
        rings.removeAll()
        notes.removeAll()
        popCount = 0
        completed = false
        started = false
    }

    // A soft text whisper that drifts up from a point and fades.
    func addNote(at p: CGPoint, text: String) {
        notes.append(FloatNote(pos: p, text: text, life: 1))
        if notes.count > 8 { notes.removeFirst(notes.count - 8) }
    }

    // MARK: - Input

    @discardableResult
    func tap(at p: CGPoint) -> [GameEvent] {
        guard !completed else { return [] }
        var events: [GameEvent] = []
        for i in stride(from: orbs.count - 1, through: 0, by: -1) where orbs[i].alive {
            let dx = p.x - orbs[i].pos.x
            let dy = p.y - orbs[i].pos.y
            // a touch of extra tolerance so small orbs are easy to hit
            let rr = orbs[i].r + GameConfig.tapTolerance
            if dx * dx + dy * dy <= rr * rr {
                // A `.taps` generator does not pop on every press: it GIVES.
                // Each press yields an orb and leaves it open, and the press
                // that closes it is the one that pops. That last press is the
                // reward the whole mechanic is built around, so it has to be
                // the only one that behaves like a pop.
                if case .generator(var gen) = orbs[i].kind,
                   case .taps(let remaining) = gen.closing,
                   remaining > 1 {
                    gen.closing = .taps(remaining: remaining - 1)
                    gen.sinceLast = 0
                    orbs[i].kind = .generator(gen)
                    started = true
                    if let born = emit(from: orbs[i]) {
                        events.append(.emitted(orb: born, byTap: true))
                    }
                    break
                }
                detonate(index: i, chained: false, into: &events)
                break
            }
        }
        return events
    }

    private func detonate(index: Int, chained: Bool, into events: inout [GameEvent]) {
        guard orbs[index].alive else { return }
        orbs[index].alive = false
        started = true
        popCount += 1

        let orb = orbs[index]
        let def = PopCatalog.definition(for: orb.popNumber)
        events.append(.popped(orb: orb, chained: chained))
        if orb.isFortune {
            events.append(.fortuneRevealed(at: orb.pos))
        }

        spawnBurst(for: orb, def: def)

        // Only the first ring of a direct pop arms further chains; echo
        // rings — extras, and any ring from a chained pop — are visual only.
        for k in 0..<max(1, def.chain.ringCount) {
            let scale = 1 - 0.28 * CGFloat(k)
            rings.append(Ring(
                pos: orb.pos,
                r: orb.baseR * 0.5 * scale,
                maxR: (CGFloat(def.chain.maxRadiusBase)
                       + orb.baseR * CGFloat(def.chain.maxRadiusPerOrbRadius)) * scale,
                life: 1,
                popNumber: orb.popNumber,
                variantIndex: orb.variantIndex,
                popped: chained || k > 0))
        }

        // SPLIT BEFORE THE CLEAR CHECK. The children are alive the instant
        // the parent is not, so a field whose last orb was a splitter is not
        // finished — it has just become more of itself. Getting this order
        // wrong ends the field on the pop that should have opened it up.
        if case .splitter(let remaining) = orb.kind, remaining > 0 {
            let born = split(orb, remaining: remaining)
            if born > 0 { events.append(.split(from: orb, into: born)) }
        }

        checkCleared(into: &events)
    }

    /// Opens a splitter into `GameConfig.splitChildCount` smaller orbs.
    ///
    /// Children keep the parent's pop family and paint, so a split reads as
    /// one thing becoming several rather than as new things arriving. They
    /// start at `spawn = 0` and grow in through the existing spawn curve,
    /// which is what makes it bloom instead of blink.
    @discardableResult
    private func split(_ parent: Orb, remaining: Int) -> Int {
        let childR = max(GameConfig.orbRadiusRange.lowerBound * 0.62,
                         parent.baseR * GameConfig.splitChildScale)
        var born = 0
        for k in 0..<GameConfig.splitChildCount {
            let angle = rnd(0 ... .pi * 2) + CGFloat(k) * (.pi * 2 / CGFloat(GameConfig.splitChildCount))
            var child = parent
            child.alive = true
            child.isFortune = false
            child.baseR = childR
            child.r = childR
            child.spawn = 0
            child.phase = rnd(0 ... .pi * 2)
            child.kind = remaining > 1 ? .splitter(remaining: remaining - 1) : .plain
            child.pos = clampIntoBounds(
                CGPoint(x: parent.pos.x + cos(angle) * childR,
                        y: parent.pos.y + sin(angle) * childR),
                radius: childR)
            child.vel = CGVector(dx: cos(angle) * GameConfig.orbMaxSpeed * GameConfig.splitSpread,
                                 dy: sin(angle) * GameConfig.orbMaxSpeed * GameConfig.splitSpread)
            orbs.append(child)
            born += 1
        }
        return born
    }

    /// The field is clear when nothing is left alive — generators included,
    /// since a generator is an orb. Called from every place that can remove
    /// the last one: a pop, a spent quota, a settle.
    private func checkCleared(into events: inout [GameEvent]) {
        if !completed && orbs.allSatisfy({ !$0.alive }) {
            completed = true
            events.append(.cleared(total: popCount))
        }
    }

    private func clampIntoBounds(_ p: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: min(max(p.x, radius), max(radius, bounds.width - radius)),
                y: min(max(p.y, radius + topInset),
                       max(radius + topInset, bounds.height - radius - bottomInset)))
    }

    private func spawnBurst(for orb: Orb, def: PopDefinition) {
        let strength = orb.baseR / GameConfig.orbRadiusRange.upperBound
        var n = def.behavior.particleCountBase + Int(orb.baseR)
        if reduceMotion { n /= 2 }
        let overflow = particles.count + n - GameConfig.particleCap
        if overflow > 0 {
            particles.removeFirst(min(overflow, particles.count))
        }
        let speed = def.behavior.particleSpeedRange
        let size = def.style.particleSizeRange
        for _ in 0..<n {
            let a = rnd(0 ... .pi * 2)
            let sp = rnd(CGFloat(speed.lowerBound) ... CGFloat(speed.upperBound)) * (0.7 + strength)
            particles.append(Particle(
                pos: orb.pos,
                vel: CGVector(dx: cos(a) * sp, dy: sin(a) * sp - rnd(0 ... 0.8)),
                life: 1, decay: rnd(0.01 ... 0.024),
                size: rnd(CGFloat(size.lowerBound) ... CGFloat(size.upperBound)),
                popNumber: orb.popNumber,
                variantIndex: orb.variantIndex))
        }
    }

    // MARK: - Step

    @discardableResult
    func step(dt: TimeInterval) -> [GameEvent] {
        let f = CGFloat(min(max(dt, 0), GameConfig.maxFrameDt) * 60)
        guard f > 0 else { return [] }
        var events: [GameEvent] = []

        stepOrbs(f)
        stepGenerators(f, into: &events)
        stepRings(f, into: &events)
        stepParticles(f)
        stepMotes(f)
        stepNotes(f)

        return events
    }

    private func stepOrbs(_ f: CGFloat) {
        for i in orbs.indices where orbs[i].alive {
            if orbs[i].spawn < 1 {
                orbs[i].spawn = min(1, orbs[i].spawn + GameConfig.spawnGrowth * f)
            }
            if case .drifter = orbs[i].kind { evade(i, f) }

            orbs[i].pos.x += orbs[i].vel.dx * f
            orbs[i].pos.y += orbs[i].vel.dy * f
            orbs[i].phase += GameConfig.wobbleSpeed * f

            let r = orbs[i].r
            if orbs[i].pos.x < r {
                orbs[i].pos.x = r
                orbs[i].vel.dx = abs(orbs[i].vel.dx)
            } else if orbs[i].pos.x > bounds.width - r {
                orbs[i].pos.x = bounds.width - r
                orbs[i].vel.dx = -abs(orbs[i].vel.dx)
            }
            if orbs[i].pos.y < r + topInset {
                orbs[i].pos.y = r + topInset
                orbs[i].vel.dy = abs(orbs[i].vel.dy)
            } else if orbs[i].pos.y > bounds.height - r - bottomInset {
                orbs[i].pos.y = bounds.height - r - bottomInset
                orbs[i].vel.dy = -abs(orbs[i].vel.dy)
            }

            orbs[i].r = orbs[i].baseR * (1 + sin(orbs[i].phase) * GameConfig.wobbleAmount) * orbs[i].spawn
        }
    }

    /// A drifter easing away from the finger.
    ///
    /// THE SHAPE OF THIS IS THE WHOLE ANTI-FRUSTRATION ARGUMENT. Three things
    /// keep it a tease rather than a chase, and all three matter:
    ///
    ///   1. **It surrenders up close.** Inside `evadeSurrenderRadius` there is
    ///      no evasion at all, so moving at a drifter always catches it. It
    ///      cannot be missed by anyone who decides they want it.
    ///   2. **It is slower than a finger.** `evadeMaxSpeed` is a hair above
    ///      the ordinary orb speed and vastly below a moving thumb, so a
    ///      follow always gains.
    ///   3. **It gives up in a corner.** Evasion fades as it nears a wall, so
    ///      a cornered drifter settles rather than vibrating against the edge
    ///      — which is what would actually read as the game fighting her.
    ///
    /// The strength also falls off with distance, so the far edge of the
    /// radius is a drift and not a dart.
    private func evade(_ i: Int, _ f: CGFloat) {
        guard let finger = pointer else { return }
        let dx = orbs[i].pos.x - finger.x
        let dy = orbs[i].pos.y - finger.y
        let d2 = dx * dx + dy * dy
        let radius = GameConfig.evadeRadius
        guard d2 < radius * radius else { return }
        let d = max(sqrt(d2), 0.0001)
        guard d > GameConfig.evadeSurrenderRadius else { return }

        // 0 at the surrender line, 1 at the outer edge — then inverted, so it
        // is strongest in the middle band and gentle at both ends.
        let span = radius - GameConfig.evadeSurrenderRadius
        let t = (d - GameConfig.evadeSurrenderRadius) / max(span, 0.0001)
        let falloff = sin(t * .pi)

        // Wall easing: how much room it still has in the direction it wants.
        let room = min(min(orbs[i].pos.x, bounds.width - orbs[i].pos.x),
                       min(orbs[i].pos.y - GameConfig.fieldTopInset,
                           bounds.height - orbs[i].pos.y))
        let cornered = min(1, max(0, room) / GameConfig.evadeWallEasing)

        let push = GameConfig.evadeStrength * falloff * cornered * f
        orbs[i].vel.dx += dx / d * push
        orbs[i].vel.dy += dy / d * push

        let speed = sqrt(orbs[i].vel.dx * orbs[i].vel.dx + orbs[i].vel.dy * orbs[i].vel.dy)
        if speed > GameConfig.evadeMaxSpeed {
            let k = GameConfig.evadeMaxSpeed / speed
            orbs[i].vel.dx *= k
            orbs[i].vel.dy *= k
        }
    }

    /// Generators, once per frame: emit on the interval, then close if their
    /// own rule says so.
    private func stepGenerators(_ f: CGFloat, into events: inout [GameEvent]) {
        var closedAny = false
        // Snapshot the count: `emit` appends, and an orb born this frame must
        // not be walked as though it were a generator. Existing indices stay
        // valid across an append, so this is the whole of what is needed.
        let existing = orbs.count
        for i in 0..<existing where orbs[i].alive {
            guard case .generator(var gen) = orbs[i].kind else { continue }

            // `.settles` runs down whether or not it is emitting, so an
            // ignored generator still closes quietly on its own.
            if case .settles(let left) = gen.closing {
                let remaining = left - f
                if remaining <= 0 {
                    orbs[i].alive = false
                    orbs[i].kind = .generator(gen)
                    events.append(.generatorClosed(orb: orbs[i]))
                    closedAny = true
                    continue
                }
                gen.closing = .settles(remaining: remaining)
            }

            gen.sinceLast += f
            if gen.sinceLast >= gen.interval && aliveCount < GameConfig.activeOrbCeiling {
                gen.sinceLast = 0
                if let born = emit(from: orbs[i]) {
                    events.append(.emitted(orb: born, byTap: false))
                    if case .quota(let left) = gen.closing {
                        if left <= 1 {
                            orbs[i].alive = false
                            orbs[i].kind = .generator(gen)
                            events.append(.generatorClosed(orb: orbs[i]))
                            closedAny = true
                            continue
                        }
                        gen.closing = .quota(remaining: left - 1)
                    }
                }
            }
            orbs[i].kind = .generator(gen)
        }
        if closedAny { checkCleared(into: &events) }
    }

    /// One orb from a generator, born beside it and growing in.
    ///
    /// Returns nil when the field is already at its ceiling — the calm-guard.
    /// A generator that would crowd the screen simply holds what it has;
    /// nothing is queued, nothing is owed, and it will try again next
    /// interval.
    @discardableResult
    private func emit(from generator: Orb) -> Orb? {
        guard aliveCount < GameConfig.activeOrbCeiling else { return nil }
        let r = rnd(GameConfig.orbRadiusRange) * 0.86
        let angle = rnd(0 ... .pi * 2)
        var orb = generator
        orb.alive = true
        orb.isFortune = false
        orb.kind = .plain
        orb.baseR = r
        orb.r = r
        orb.spawn = 0
        orb.phase = rnd(0 ... .pi * 2)
        orb.pos = clampIntoBounds(
            CGPoint(x: generator.pos.x + cos(angle) * (generator.baseR + r),
                    y: generator.pos.y + sin(angle) * (generator.baseR + r)),
            radius: r)
        orb.vel = CGVector(dx: cos(angle) * GameConfig.orbMaxSpeed * 0.6,
                           dy: sin(angle) * GameConfig.orbMaxSpeed * 0.6)
        orbs.append(orb)
        return orb
    }

    /// Orbs currently on the field, generators included.
    var aliveCount: Int { orbs.reduce(0) { $1.alive ? $0 + 1 : $0 } }

    private func stepRings(_ f: CGFloat, into events: inout [GameEvent]) {
        let rc = rings.count
        for i in 0..<rc {
            let cb = PopCatalog.definition(for: rings[i].popNumber).chain
            rings[i].r += (rings[i].maxR - rings[i].r) * CGFloat(cb.growthFactor) * f
                + CGFloat(cb.growthLinear) * f
            rings[i].life -= CGFloat(cb.lifeDecay) * f

            if !rings[i].popped && rings[i].r > GameConfig.ringArmRadius {
                let rr = rings[i].r
                for j in orbs.indices where orbs[j].alive {
                    let d = hypot(orbs[j].pos.x - rings[i].pos.x,
                                  orbs[j].pos.y - rings[i].pos.y)
                    if d < rr + orbs[j].r && d > rr - CGFloat(cb.shellThickness) {
                        detonate(index: j, chained: true, into: &events)
                    }
                }
                if rings[i].r > rings[i].maxR * CGFloat(cb.disarmFraction) {
                    rings[i].popped = true
                }
            }
        }
        rings.removeAll { $0.life <= 0 }
    }

    private func stepParticles(_ f: CGFloat) {
        let damp = pow(GameConfig.particleDamping, f)
        for i in particles.indices {
            let gravity = CGFloat(PopCatalog.definition(for: particles[i].popNumber).behavior.particleGravity)
            particles[i].vel.dy += gravity * f
            particles[i].vel.dx *= damp
            particles[i].vel.dy *= damp
            particles[i].pos.x += particles[i].vel.dx * f
            particles[i].pos.y += particles[i].vel.dy * f
            particles[i].life -= particles[i].decay * f
        }
        particles.removeAll { $0.life <= 0 }
    }

    private func stepMotes(_ f: CGFloat) {
        guard !reduceMotion else { return }
        for i in motes.indices {
            motes[i].pos.x += motes[i].vel.dx * f
            motes[i].pos.y += motes[i].vel.dy * f
            motes[i].phase += 0.008 * f
            if motes[i].pos.y < -4 { motes[i].pos.y = bounds.height + 4 }
            if motes[i].pos.y > bounds.height + 4 { motes[i].pos.y = -4 }
            if motes[i].pos.x < -4 { motes[i].pos.x = bounds.width + 4 }
            if motes[i].pos.x > bounds.width + 4 { motes[i].pos.x = -4 }
        }
    }

    private func stepNotes(_ f: CGFloat) {
        for i in notes.indices {
            notes[i].pos.y -= 0.35 * f
            notes[i].life -= 0.016 * f
        }
        notes.removeAll { $0.life <= 0 }
    }

    // MARK: - Helpers

    private func rnd(_ range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &rng)
    }
}
