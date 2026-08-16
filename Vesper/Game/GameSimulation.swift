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
        let pool = availablePops.isEmpty ? [PopCatalog.classic.number] : availablePops
        let count = Int.random(in: GameConfig.orbCountRange, using: &rng)
        for _ in 0..<count {
            let popNumber = pool.randomElement(using: &rng) ?? PopCatalog.classic.number
            let paintCount = PopCatalog.definition(for: popNumber).style.paints.count
            let r = rnd(GameConfig.orbRadiusRange)
            let inset = GameConfig.edgeInset
            var orb = Orb(
                pos: CGPoint(x: rnd(r + inset ... bounds.width - r - inset),
                             y: rnd(r + GameConfig.spawnTopInset ... bounds.height - r - inset)),
                vel: CGVector(dx: rnd(-GameConfig.orbMaxSpeed ... GameConfig.orbMaxSpeed),
                              dy: rnd(-GameConfig.orbMaxSpeed ... GameConfig.orbMaxSpeed)),
                r: r, baseR: r,
                popNumber: popNumber,
                variantIndex: Int.random(in: 0..<max(1, paintCount), using: &rng),
                phase: rnd(0 ... .pi * 2))
            orb.spawn = 1
            orbs.append(orb)
        }
        if let idx = orbs.indices.randomElement(using: &rng) {
            orbs[idx].isFortune = true
        }
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
            events.append(.fortuneRevealed)
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

        if !completed && orbs.allSatisfy({ !$0.alive }) {
            completed = true
            events.append(.cleared(total: popCount))
        }
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
            if orbs[i].pos.y < r + GameConfig.fieldTopInset {
                orbs[i].pos.y = r + GameConfig.fieldTopInset
                orbs[i].vel.dy = abs(orbs[i].vel.dy)
            } else if orbs[i].pos.y > bounds.height - r {
                orbs[i].pos.y = bounds.height - r
                orbs[i].vel.dy = -abs(orbs[i].vel.dy)
            }

            orbs[i].r = orbs[i].baseR * (1 + sin(orbs[i].phase) * GameConfig.wobbleAmount) * orbs[i].spawn
        }
    }

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
