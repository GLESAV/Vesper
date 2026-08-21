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
    /// The air this field is played in. Chosen at seed time from the field's
    /// own RNG, so a seed is still a field.
    private(set) var weather: Weather = .clear

    /// THE AIR AS A THING WITH A BODY: crests that sweep across the field and
    /// carry the pops with them, eddies, gusts, flakes, shafts of light, banks
    /// of fog. Stepped once per frame from `step(dt:)`, read by
    /// `applyWeather` to move the orbs, and drawn by `WeatherRenderer` — see
    /// `WeatherField`, which owns all of it and none of the drawing.
    private(set) var weatherField = WeatherField()

    /// Forces a particular air, for tests whose subject is something else.
    ///
    /// The W20 storm regression and the tap baselines measure input
    /// arbitration and pop reliability; if the air under them changes between
    /// runs, they are measuring two things at once and the number they report
    /// stops meaning what it says. Nil in the app, always.
    var pinnedWeather: Weather?

    /// Where this field sits on the Path, and how many times she has cleared
    /// this stone before. Both grow the field's DEPTH, never its crowding.
    var generation: Int = 0
    var plays: Int = 0

    /// The orbs waiting below the surface.
    ///
    /// A field is an aerial view of something with depth: only
    /// `GameConfig.surfaceCapacity` orbs are on the glass at once, and as she
    /// makes room the ones underneath crowd up into it. This is what lets a
    /// field grow along the Path without ever looking busier — what grows is
    /// how deep it goes.
    private(set) var reserve: [Orb] = []

    /// Shells on the field, and the haze they leave. Neither is an orb and
    /// neither gates completion — see `Firework`.
    private(set) var fireworks: [Firework] = []
    private(set) var smoke: [Smoke] = []

    /// How many orbs this field may hold on the surface at once.
    ///
    /// `GameConfig.surfaceCapacity` plus this field's generators: a generator
    /// always starts on the surface — a generator underneath would be the
    /// field making more of itself where she cannot see it happen — so it
    /// occupies a place that is not one of the capacity's. Without this the
    /// surface was over budget from the first frame and NOTHING EVER ROSE.
    private var surfaceBudget = GameConfig.surfaceCapacity

    /// Phase of the lateral swell, advanced per frame. Not published and not
    /// read during a draw.
    private var swellPhase: CGFloat = 0

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
            && smoke.isEmpty && !fireworks.contains { $0.phase != .spent }
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
        weather = pinnedWeather ?? Weather.choose(using: &rng)
        swellPhase = 0
        let pool = availablePops.isEmpty ? [PopCatalog.classic.number] : availablePops

        // The kinds are dealt into the field rather than rolled per orb, so a
        // stage's plan is exactly what she gets: two splitters means two, not
        // "two on average". A field that sometimes forgets to contain the
        // thing it just taught her is a field that reads as broken.
        // How big this field actually is, once its place on the Path and her
        // history with this stone are counted.
        // Shells sit ALONGSIDE the orbs rather than instead of them (owner's
        // correction), and a break sows pops — see `burst`.
        plan.fireworks = FieldPlan.fireworkCount(stage: stage, generation: generation)
        plan.animals = FieldPlan.animalCount(stage: stage, generation: generation)
        let total = FieldPlan.totalOrbs(base: plan.orbCount,
                                        generation: generation,
                                        plays: plays)
        let surface = FieldPlan.surfaceCount(total: total)
        surfaceBudget = surface + plan.generators

        var kinds: [OrbKind] = []
        for _ in 0..<plan.splitters { kinds.append(.splitter(remaining: plan.splitDepth)) }
        for _ in 0..<plan.drifters { kinds.append(.drifter) }
        while kinds.count < total { kinds.append(.plain) }
        if kinds.count > total { kinds.removeLast(kinds.count - total) }
        kinds.shuffle(using: &rng)

        // THE ANIMAL, IF THIS FIELD HAS ONE, AND ALWAYS ON THE SURFACE. It
        // takes an ordinary orb's place rather than adding one, so the plan
        // she was promised is still exactly the field she gets. It has to
        // start on the glass because its shyness begins running down the
        // moment the field opens: an animal that waited in the reserve would
        // arrive late and still shy, which is the one ordering that could
        // leave it awkward at the END of a field instead of the beginning.
        if plan.animals > 0 {
            let surfaceSlots = Array(kinds.indices.prefix(min(surface, kinds.count)))
            let plainSlots = surfaceSlots.filter { kinds[$0] == .plain }
            if let slot = plainSlots.randomElement(using: &rng) {
                kinds[slot] = .animal(makeAnimal())
            } else {
                plan.animals = 0
            }
        }

        // The surface, and then the depth beneath it. Generators always start
        // on the surface: a generator underneath would be a field making more
        // of itself where she cannot see it happen.
        for kind in kinds.prefix(surface) {
            orbs.append(makeOrb(kind: kind, pool: pool))
        }
        for _ in 0..<plan.generators {
            orbs.append(makeOrb(kind: .generator(makeGenerator()), pool: pool))
        }
        reserve = kinds.dropFirst(surface).map { makeOrb(kind: $0, pool: pool) }

        fireworks.removeAll()
        smoke.removeAll()
        for _ in 0..<plan.fireworks {
            fireworks.append(makeFirework(pool: pool))
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
            // Weather scales the field's pace from the moment it is seeded,
            // so the air is something she walks into rather than something
            // that arrives a few seconds later.
            vel: CGVector(dx: rnd(-GameConfig.orbMaxSpeed ... GameConfig.orbMaxSpeed) * weather.speedScale,
                          dy: rnd(-GameConfig.orbMaxSpeed ... GameConfig.orbMaxSpeed) * weather.speedScale),
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

    /// One balloon animal: a creature and how many touches it takes.
    ///
    /// Both come from the field's own RNG, so a stone is the same creature
    /// every time she walks back to it — the eight shapes are what stop the
    /// hundred pops reading as one sphere in a hundred paints, and a shape
    /// that changed between visits would be a costume rather than a resident.
    private func makeAnimal() -> AnimalPop {
        let shape = AnimalPop.Shape.allCases.randomElement(using: &rng) ?? .cat
        return AnimalPop(shape: shape,
                         health: Int.random(in: GameConfig.animalHealthRange, using: &rng),
                         shyness: 1,
                         startle: 0)
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
        reserve.removeAll()
        fireworks.removeAll()
        smoke.removeAll()
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
        reserve.removeAll()
        fireworks.removeAll()
        smoke.removeAll()
        surfaceBudget = max(GameConfig.surfaceCapacity, newOrbs.count)
        // Weather is part of the randomness this hook exists to remove: a
        // test that installs an exact field and then watches it move must not
        // have the air chosen for it. `layout(size:)` seeds a field on first
        // call, so by the time a test reaches here an air has already been
        // picked — pin it back to still.
        weather = .clear
        swellPhase = 0
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

        // SHELLS FIRST, and only while they are on the ground. A shell in
        // flight is not a target — chasing one would turn a thing you watch
        // into a thing you must keep up with — and a spent one is smoke.
        //
        // THE SHELL AND ITS FUSE ARE ONE TARGET (owner): touching the shell
        // does exactly what touching the cord does. There is no wrong place
        // to tap a firework.
        // LIGHTING BEATS HURRYING, and that ordering is not a detail.
        //
        // Ropes overlap. A single pass in index order let an already-burning
        // shell whose cord happened to lie under her finger swallow a tap
        // meant for the unlit shell right beside it — so she would touch a
        // firework, watch a different one speed up, and touch it again to the
        // same effect. Unlit shells are therefore offered the touch first,
        // and only if none wants it does a burning fuse take it.
        for i in fireworks.indices {
            guard case .waiting = fireworks[i].phase else { continue }
            guard touchesFirework(fireworks[i], at: p) else { continue }
            fireworks[i].phase = .fuse(burned: 0)
            started = true
            events.append(.fuseLit(fireworks[i]))
            return events
        }
        // Tapping a burning fuse hurries it along. The pacing is hers: light
        // it and let it take its time, or chase it down the cord.
        for i in fireworks.indices {
            guard case .fuse(let burned) = fireworks[i].phase else { continue }
            guard touchesFirework(fireworks[i], at: p) else { continue }
            fireworks[i].phase = .fuse(burned: min(0.995, burned + GameConfig.fuseTapBoost))
            events.append(.fuseHurried(fireworks[i]))
            return events
        }
        for i in stride(from: orbs.count - 1, through: 0, by: -1) where orbs[i].alive {
            let dx = p.x - orbs[i].pos.x
            let dy = p.y - orbs[i].pos.y
            // a touch of extra tolerance so small orbs are easy to hit — and
            // a little more for an animal, whose ears and tail reach past the
            // body circle this radius is measured from.
            var rr = orbs[i].r + GameConfig.tapTolerance
            if case .animal = orbs[i].kind { rr += GameConfig.animalTapBonus }
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
                detonate(index: i, chained: false, from: p, into: &events)
                break
            }
        }
        return events
    }

    /// `from` is where the touch landed, when there was one. A chain has no
    /// finger behind it and passes nil; only the animal reads it, to know
    /// which way to bolt.
    private func detonate(index: Int, chained: Bool, from: CGPoint? = nil,
                          into events: inout [GameEvent]) {
        guard orbs[index].alive else { return }

        // A CREATURE TAKES A FEW TOUCHES, AND THE ONES THAT DO NOT FINISH IT
        // STILL LAND. Handled here rather than in `tap` on purpose: a
        // shockwave that reaches the animal counts exactly as a finger does,
        // so there is no route by which it can be popped in one and no route
        // by which it becomes unreachable. Nothing is lost either way — the
        // health it has left is the only thing that changes.
        if case .animal(let animal) = orbs[index].kind, animal.health > 1 {
            // A SHOCKWAVE IS ONE EVENT, EVEN THOUGH IT ARRIVES OVER SEVERAL
            // FRAMES. A ring's shell overlaps the animal for as long as it
            // takes to sweep past, and `stepRings` calls this on every one of
            // those frames — without a refractory a single chain would spend
            // the whole creature in a fifth of a second. `startle` is the
            // refractory, and it applies to chains only: a finger cannot tap
            // faster than a creature can flinch, so a direct touch is never
            // swallowed by it.
            if chained && animal.startle > 0 { return }

            let (next, vel) = AnimalMotion.startled(animal,
                                                    at: orbs[index].pos,
                                                    from: from,
                                                    angle: rnd(0 ... .pi * 2),
                                                    reduceMotion: reduceMotion)
            orbs[index].kind = .animal(next)
            orbs[index].vel = vel
            started = true
            events.append(.startled(orb: orbs[index]))
            return
        }

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
        // An animal's going is a larger event than an orb's: a wider ring, and
        // more of it. It only ever helps — a bigger shockwave clears more of
        // the field, never less.
        var kindScale: CGFloat = 1
        if case .animal = orb.kind { kindScale = GameConfig.animalRingScale }

        for k in 0..<max(1, def.chain.ringCount) {
            let scale = (1 - 0.28 * CGFloat(k)) * kindScale
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

        // WHAT WAS UNDERNEATH CROWDS IN. Surfaced at the popped orb's own
        // position, because that is where the room just appeared — a field
        // that refills from the edges reads as things arriving, and a field
        // that refills where you just made space reads as depth.
        if let risen = surfaceFromReserve(near: orb.pos) {
            events.append(.rose(orb: risen))
        }

        checkCleared(into: &events)
    }

    /// Brings one orb up from the reserve, if there is room on the surface.
    ///
    /// It arrives at `spawn = 0` and grows over `GameConfig.riseFrames`, which
    /// is about a second — four times slower than the old spawn curve, and
    /// that difference is the whole of it. Fast growth reads as something
    /// TELEPORTING IN; slow growth from small and faint reads as something
    /// that was always there, coming up.
    @discardableResult
    private func surfaceFromReserve(near p: CGPoint) -> Orb? {
        guard !reserve.isEmpty else { return nil }
        guard aliveCount < surfaceBudget else { return nil }
        var orb = reserve.removeLast()
        orb.spawn = 0
        orb.pos = clampIntoBounds(
            CGPoint(x: p.x + rnd(-18 ... 18), y: p.y + rnd(-18 ... 18)),
            radius: orb.baseR)
        orbs.append(orb)
        return orb
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
        // The reserve counts: a field with orbs still underneath is not
        // finished, it is only momentarily empty on top.
        if !completed && reserve.isEmpty && orbs.allSatisfy({ !$0.alive }) {
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
        // The last touch on an animal is the reward the mechanic is built
        // around, so it opens wider than an ordinary pop.
        if case .animal = orb.kind { n = Int(CGFloat(n) * GameConfig.animalBurstScale) }
        if reduceMotion { n /= 2 }
        let overflow = particles.count + n - GameConfig.particleCap
        if overflow > 0 {
            particles.removeFirst(min(overflow, particles.count))
        }
        let speed = def.behavior.particleSpeedRange
        let size = def.style.particleSizeRange
        for k in 0..<n {
            let a = rnd(0 ... .pi * 2)
            let base = rnd(CGFloat(speed.lowerBound) ... CGFloat(speed.upperBound)) * (0.7 + strength)

            // THE GESTURE OF THE BURST. Every pop in the catalog used to throw
            // its particles the same way — a full-circle scatter with a slight
            // upward bias, falling under gravity — so the thing the eye
            // actually remembers about a pop was identical across all 100.
            // Shape and speed varied; the MOTION did not.
            //
            // Each case below is one gesture. They are deliberately extreme
            // relative to one another: a difference the eye has to look for is
            // not a difference.
            var vel: CGVector
            var life: CGFloat = 1
            var decay = rnd(0.01 ... 0.024)

            switch def.behavior.burst {
            case .radial:
                vel = CGVector(dx: cos(a) * base, dy: sin(a) * base - rnd(0 ... 0.8))

            case .bloom:
                // Slow, even, and held: petals opening rather than debris.
                let sp = base * 0.45
                vel = CGVector(dx: cos(a) * sp, dy: sin(a) * sp - rnd(0 ... 0.3))
                decay *= 0.55

            case .implode:
                // Inward first. The particle starts outside and falls in, so
                // the burst reads as a breath taken before it goes.
                let sp = base * 0.8
                vel = CGVector(dx: -cos(a) * sp, dy: -sin(a) * sp)

            case .spiral:
                // Tangential rather than radial: the burst turns as it leaves.
                let sp = base * 0.9
                vel = CGVector(dx: cos(a + .pi / 2) * sp + cos(a) * sp * 0.35,
                               dy: sin(a + .pi / 2) * sp + sin(a) * sp * 0.35)

            case .drip:
                // Heavy and downward, a few thrown wide.
                let sp = base * (k % 5 == 0 ? 0.9 : 0.35)
                vel = CGVector(dx: cos(a) * sp * 0.5, dy: abs(sin(a)) * sp + 0.6)

            case .ascend:
                // Upward and slowing — sparks leaving a fire.
                let sp = base * 0.7
                vel = CGVector(dx: cos(a) * sp * 0.6, dy: -abs(sin(a)) * sp - 0.5)
                decay *= 0.7

            case .scatter:
                // Flat and fast: a horizontal sweep more than a circle.
                let sp = base * 1.35
                vel = CGVector(dx: cos(a) * sp, dy: sin(a) * sp * 0.28)

            case .shiver:
                // Barely travels. It trembles apart in place.
                let sp = base * 0.22
                vel = CGVector(dx: cos(a) * sp, dy: sin(a) * sp)
                decay *= 1.5

            case .ring:
                // One speed for everything: a thin expanding band.
                let sp = base * 0.85 + 1.2
                vel = CGVector(dx: cos(a) * sp, dy: sin(a) * sp)
                life = 0.9

            case .veil:
                // Hangs and fades. Almost no speed, almost no fall.
                let sp = base * 0.18
                vel = CGVector(dx: cos(a) * sp, dy: sin(a) * sp * 0.5 - 0.12)
                decay *= 0.5
            }

            particles.append(Particle(
                pos: orb.pos,
                vel: vel,
                life: life, decay: decay,
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

        swellPhase += weather.swellRate * f

        // THE AIR MOVES BEFORE THE FIELD DOES. Its seed is drawn from a COPY
        // of the generator, so the sky is deterministic from the field's seed
        // while taking nothing out of the sequence the field itself is dealt
        // from — a weather layer that consumed randomness every frame would
        // quietly change every field that already exists.
        var sky = rng
        weatherField.step(f, weather: weather, bounds: bounds,
                          reduceMotion: reduceMotion, orbs: orbs, seed: sky.next())

        stepOrbs(f)
        stepFireworks(f, into: &events)
        stepSmoke(f)
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
                orbs[i].spawn = min(1, orbs[i].spawn + (1 / GameConfig.riseFrames) * f)
            }
            if case .drifter = orbs[i].kind { evade(i, f) }
            applyWeather(i, f)
            // AFTER THE AIR, not before it, and that ordering is the whole of
            // why the startle survives. `applyWeather` ends on a speed ceiling
            // built from `orbMaxSpeed`, which is a seventh of the dart — an
            // animal stepped before it would have its reaction to being
            // touched quietly deleted by the weather on every field that is
            // not still. It keeps its own ceiling, which it applies last.
            if case .animal(let animal) = orbs[i].kind {
                let (next, vel) = AnimalMotion.step(animal,
                                                    pos: orbs[i].pos,
                                                    vel: orbs[i].vel,
                                                    pointer: pointer,
                                                    bounds: bounds,
                                                    topInset: topInset,
                                                    bottomInset: bottomInset,
                                                    reduceMotion: reduceMotion,
                                                    f: f)
                orbs[i].kind = .animal(next)
                orbs[i].vel = vel
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

    /// The air, applied to one orb.
    ///
    /// Everything here is a small force or a multiplier — weather never
    /// teleports an orb, never changes its size, and never touches whether it
    /// can be hit. The speed ceiling below is the guardrail that makes that
    /// true in fact rather than in intention: whatever the air does, an orb
    /// may not end up travelling faster than the weather's own scale allows.
    private func applyWeather(_ i: Int, _ f: CGFloat) {
        guard weather != .clear else { return }

        // Glide: how much momentum survives. Rain keeps all of it and slides.
        if weather.glide != 1 {
            let k = pow(weather.glide, f)
            orbs[i].vel.dx *= k
            orbs[i].vel.dy *= k
        }

        // Swell: the whole field breathing sideways together. Phase is shared,
        // so it is a tide rather than a hundred independent wobbles — that
        // togetherness is the entire feeling of `summer`.
        if weather.swellAmount > 0 {
            orbs[i].vel.dx += sin(swellPhase) * weather.swellAmount * f * 0.06
        }

        // Wander: the heading turns, the speed does not rise. This is the
        // whole of storm, and the reason storm cannot make the field harder.
        if weather.wander > 0 {
            let amount: CGFloat
            if weather.wanderIsStepped {
                // Crunch: nothing, then a step. Snow moves in little jerks.
                amount = (rnd(0 ... 1) < 0.06) ? weather.wander * 8 : 0
            } else {
                amount = weather.wander * (rnd(-1 ... 1))
            }
            if amount != 0 {
                let a = amount * f
                let dx = orbs[i].vel.dx, dy = orbs[i].vel.dy
                orbs[i].vel.dx = dx * cos(a) - dy * sin(a)
                orbs[i].vel.dy = dx * sin(a) + dy * cos(a)
            }
        }

        // THE FIELD OF THE AIR: crests, eddies, gusts, thermals. It CARRIES
        // this orb — moving where it is, never how fast it is going — and it
        // may only use what is left under the same ceiling once the orb's own
        // speed is counted. So the air cannot accumulate into the velocity
        // below it, and cannot make anything cross the glass faster than it
        // always could. The wall clamp in `stepOrbs` still runs after this.
        weatherField.apply(to: &orbs[i], f)

        // THE CEILING. Weather may change the character of the motion and may
        // not make the field faster than its own scale permits — a field that
        // outruns her is a field she has to keep up with, and this game does
        // not ask that of anyone.
        let cap = GameConfig.orbMaxSpeed * weather.speedScale * 1.6
        let speed = sqrt(orbs[i].vel.dx * orbs[i].vel.dx + orbs[i].vel.dy * orbs[i].vel.dy)
        if speed > cap {
            let k = cap / speed
            orbs[i].vel.dx *= k
            orbs[i].vel.dy *= k
        }
    }

    // MARK: - Fireworks

    /// One shell, placed and aimed.
    ///
    /// The heading is chosen with a strong upward bias but is free to point
    /// anywhere: fourteen shells that all climb vertically read as a
    /// mechanism, while the same fourteen fanning across the field read as a
    /// display.
    private func makeFirework(pool: [Int]) -> Firework {
        // Drawn from the shells that suit this field's road, so a display on
        // the ember road looks like the ember road.
        let family = pool.first.map { PopCatalog.definition(for: $0).family }
        let choices = FireworkCatalog.forFamily(family)
        let definition = choices.randomElement(using: &rng) ?? FireworkCatalog.all[0]
        let kind = definition.kind
        let flight = kind.flight

        // Shells wait low, where a rising thing has somewhere to go.
        let inset = GameConfig.edgeInset + GameConfig.fireworkTouchRadius
        let origin = CGPoint(
            x: rnd(inset ... max(inset, bounds.width - inset)),
            y: rnd(max(topInset, bounds.height - bottomInset - bounds.height * 0.34)
                   ... max(topInset, bounds.height - bottomInset - 20)))

        // Straight up, then rotated away from it by an amount the kind
        // allows. `upwardBias` of 1 never leaves vertical; 0 goes anywhere.
        let spread = (1 - flight.upwardBias) * .pi
        let heading = -CGFloat.pi / 2 + rnd(-spread ... spread)
        let distance = bounds.height * flight.rise
        let apex = clampIntoBounds(
            CGPoint(x: origin.x + cos(heading) * distance,
                    y: origin.y + sin(heading) * distance),
            radius: GameConfig.fireworkTouchRadius)

        return Firework(pos: origin, origin: origin, apex: apex, kind: kind,
                        definitionID: definition.id,
                        variantIndex: Int.random(in: 0..<max(1, definition.paints.count),
                                                 using: &rng),
                        angle: rnd(0 ... .pi * 2),
                        drift: CGVector(dx: rnd(-0.04 ... 0.04), dy: rnd(-0.03 ... 0.01)),
                        fuseFrames: definition.fuse)
    }

    private func stepFireworks(_ f: CGFloat, into events: inout [GameEvent]) {
        for i in fireworks.indices {
            if fireworks[i].spawn < 1 {
                fireworks[i].spawn = min(1, fireworks[i].spawn + (1 / GameConfig.riseFrames) * f)
            }
            let flight = fireworks[i].kind.flight
            fireworks[i].angle += flight.spin * f
            stepFuseRope(i, f)

            switch fireworks[i].phase {
            case .fuse(let burned):
                let next = burned + (1 / max(1, fireworks[i].fuseFrames)) * f
                if next >= 1 {
                    fireworks[i].phase = .rising(progress: 0)
                    events.append(.fireworkLaunched(fireworks[i]))
                } else {
                    fireworks[i].phase = .fuse(burned: next)
                    // The cord sheds sparks where it is burning.
                    if rnd(0 ... 1) < 0.5 {
                        addTrailSpark(at: fuseSpark(fireworks[i]), for: fireworks[i])
                    }
                }

            case .waiting:
                // Alive on the field, but barely: a shell that wandered would
                // be a moving target, and it is meant to be an easy one.
                fireworks[i].pos.x += fireworks[i].drift.dx * f
                fireworks[i].pos.y += fireworks[i].drift.dy * f
                fireworks[i].pos = clampIntoBounds(fireworks[i].pos,
                                                   radius: GameConfig.fireworkTouchRadius)

            case .rising(let progress):
                // INTERPOLATED, NOT INTEGRATED. A shell that accumulates
                // velocity drifts off its own apex, and the break has to land
                // where the arc says it will.
                let next = min(1, progress + (1 / GameConfig.fireworkRiseFrames) * flight.speed * f)
                let eased = 1 - pow(1 - next, 1.7)   // fast away, slowing at the top
                let from = fireworks[i].origin, to = fireworks[i].apex
                let wobble = sin(next * .pi * 5 + fireworks[i].angle)
                    * flight.wobble * GameConfig.fireworkWobbleWidth * (1 - next)
                fireworks[i].pos = CGPoint(
                    x: from.x + (to.x - from.x) * eased + wobble,
                    y: from.y + (to.y - from.y) * eased)

                // The trail: sparks shed on the way, which is most of what
                // makes a rise read as a fuse rather than as a moving dot.
                if rnd(0 ... 1) < 0.75 {
                    addTrailSpark(at: fireworks[i].pos, for: fireworks[i])
                }

                if next >= 1 {
                    fireworks[i].phase = .spent
                    burst(fireworks[i])
                    events.append(.fireworkBurst(fireworks[i]))
                } else {
                    fireworks[i].phase = .rising(progress: next)
                }

            case .spent:
                break
            }
        }
    }

    // MARK: The fuse

    /// Whether a touch lands on a shell or anywhere along its cord.
    ///
    /// The whole rope is a target, not just the shell. A fuse she can see
    /// burning and cannot touch would be the one thing on this field that
    /// looks interactive and is not.
    private func touchesFirework(_ shell: Firework, at p: CGPoint) -> Bool {
        let head = GameConfig.fireworkTouchRadius
        let dx = p.x - shell.pos.x, dy = p.y - shell.pos.y
        if dx * dx + dy * dy <= head * head { return true }

        let cord = GameConfig.fuseTouchRadius
        guard shell.fuseNodes.count > 1 else { return false }
        for k in 0..<(shell.fuseNodes.count - 1) {
            if distance(from: p, toSegment: shell.fuseNodes[k], shell.fuseNodes[k + 1]) <= cord {
                return true
            }
        }
        return false
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let vx = b.x - a.x, vy = b.y - a.y
        let wx = p.x - a.x, wy = p.y - a.y
        let len2 = vx * vx + vy * vy
        guard len2 > 0.0001 else { return sqrt(wx * wx + wy * wy) }
        let t = min(1, max(0, (wx * vx + wy * vy) / len2))
        let cx = a.x + vx * t, cy = a.y + vy * t
        return sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy))
    }

    /// Where the fuse is currently burning, in screen space.
    ///
    /// `burned` runs 0 at the trailing end to 1 at the shell, so the spark
    /// travels UP the cord toward the shell — which is the direction a real
    /// fuse burns and the direction that makes the wait legible.
    func fuseSpark(_ shell: Firework) -> CGPoint {
        guard shell.fuseNodes.count > 1 else { return shell.pos }
        guard case .fuse(let burned) = shell.phase else { return shell.pos }
        let last = shell.fuseNodes.count - 1
        // Node 0 is the shell, so travel from the tail toward it.
        let along = (1 - min(1, max(0, burned))) * CGFloat(last)
        let k = min(last - 1, Int(along))
        let t = along - CGFloat(k)
        let a = shell.fuseNodes[k], b = shell.fuseNodes[k + 1]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// The rope, one frame.
    ///
    /// Verlet: each node moves by where it went last frame, damped, plus a
    /// little gravity; then a couple of passes pull neighbours back to their
    /// rest length. Node 0 is pinned to the shell, so when the shell drifts —
    /// or a break shoves the field — the cord whips and keeps swinging after
    /// the shell has stopped. That lag is the difference between a drawn line
    /// and a thing made of string.
    private func stepFuseRope(_ i: Int, _ f: CGFloat) {
        guard fireworks[i].phase != .spent else { return }
        if fireworks[i].fuseNodes.isEmpty { seedFuseRope(i) }

        let count = fireworks[i].fuseNodes.count
        guard count > 1 else { return }
        let rest = GameConfig.fuseSegmentLength
        let damping = GameConfig.fuseDamping

        for k in 1..<count {
            let current = fireworks[i].fuseNodes[k]
            let previous = fireworks[i].fusePrev[k]
            var vx = (current.x - previous.x) * damping
            var vy = (current.y - previous.y) * damping
            // A rising shell drags its cord behind it.
            if case .rising = fireworks[i].phase { vy += GameConfig.fuseGravity * 0.4 * f }
            else { vy += GameConfig.fuseGravity * f }
            // Weather moves the cord too — a string in wind is the clearest
            // reading of wind there is.
            vx += sin(swellPhase + CGFloat(k)) * weather.swellAmount * 0.5 * f
            fireworks[i].fusePrev[k] = current
            fireworks[i].fuseNodes[k] = CGPoint(x: current.x + vx * f, y: current.y + vy * f)
        }

        for _ in 0..<GameConfig.fuseRelaxPasses {
            fireworks[i].fuseNodes[0] = fireworks[i].pos
            for k in 0..<(count - 1) {
                let a = fireworks[i].fuseNodes[k]
                let b = fireworks[i].fuseNodes[k + 1]
                let dx = b.x - a.x, dy = b.y - a.y
                let d = max(0.0001, sqrt(dx * dx + dy * dy))
                let correction = (d - rest) / d * 0.5
                let ox = dx * correction, oy = dy * correction
                if k > 0 {
                    fireworks[i].fuseNodes[k] = CGPoint(x: a.x + ox, y: a.y + oy)
                }
                fireworks[i].fuseNodes[k + 1] = CGPoint(x: b.x - ox, y: b.y - oy)
            }
        }
        fireworks[i].fuseNodes[0] = fireworks[i].pos
    }

    private func seedFuseRope(_ i: Int) {
        let count = GameConfig.fuseNodeCount
        let rest = GameConfig.fuseSegmentLength
        // Hangs down and away, so it is visible against the field rather than
        // tucked under the shell.
        let lean = rnd(-0.5 ... 0.5)
        var nodes: [CGPoint] = []
        for k in 0..<count {
            nodes.append(CGPoint(x: fireworks[i].pos.x + lean * CGFloat(k) * rest,
                                 y: fireworks[i].pos.y + CGFloat(k) * rest))
        }
        fireworks[i].fuseNodes = nodes
        fireworks[i].fusePrev = nodes
    }

    private func addTrailSpark(at p: CGPoint, for shell: Firework) {
        guard particles.count < GameConfig.particleCap else { return }
        particles.append(Particle(
            pos: CGPoint(x: p.x + rnd(-1.5 ... 1.5), y: p.y + rnd(-1.5 ... 1.5)),
            vel: CGVector(dx: rnd(-0.25 ... 0.25), dy: rnd(0.1 ... 0.5)),
            life: 0.7, decay: rnd(0.03 ... 0.06),
            size: rnd(0.8 ... 1.6),
            popNumber: PopCatalog.classic.number, variantIndex: shell.variantIndex,
            fireworkID: shell.definitionID))
    }

    /// The break: stars, smoke, and a shove to whatever is nearby.
    private func burst(_ shell: Firework) {
        let spec = FireworkCatalog.definition(for: shell.definitionID).burst
        var n = spec.stars
        if reduceMotion { n /= 2 }
        let overflow = particles.count + n - GameConfig.particleCap
        if overflow > 0 { particles.removeFirst(min(overflow, particles.count)) }

        for k in 0..<n {
            let a: CGFloat
            var speed = rnd(spec.speed)
            var vel: CGVector

            switch spec.pattern {
            case .sphere:
                a = rnd(0 ... .pi * 2)
                vel = CGVector(dx: cos(a) * speed, dy: sin(a) * speed)
            case .ring:
                // Evenly spaced and one speed: a band, not a cloud.
                a = (CGFloat(k) / CGFloat(max(1, n))) * .pi * 2
                vel = CGVector(dx: cos(a) * speed, dy: sin(a) * speed * 0.42)
            case .droop:
                a = rnd(0 ... .pi * 2)
                speed *= 0.85
                vel = CGVector(dx: cos(a) * speed, dy: sin(a) * speed - 0.6)
            case .spray:
                a = rnd(-.pi * 0.85 ... -.pi * 0.15)
                vel = CGVector(dx: cos(a) * speed, dy: sin(a) * speed)
            case .spiral:
                a = (CGFloat(k) / CGFloat(max(1, n))) * .pi * 6
                vel = CGVector(dx: cos(a + .pi / 2) * speed, dy: sin(a + .pi / 2) * speed)
            }

            particles.append(Particle(
                pos: shell.pos,
                vel: vel,
                life: spec.life,
                decay: rnd(0.008 ... 0.02) / max(0.4, spec.life),
                size: rnd(1.0 ... 2.2) + spec.trail * 1.4,
                popNumber: PopCatalog.classic.number, variantIndex: shell.variantIndex,
                fireworkID: shell.definitionID))
        }

        // SMOKE, AND IT STACKS. Puffs are additive and overlapping, they grow
        // as they age, and they thin slowly — so a field where several shells
        // have gone builds a haze the way a real display does. One puff is an
        // effect; a gathering haze is a fireworks show.
        let puffs = max(1, Int(CGFloat(GameConfig.smokePuffsPerBurst) * spec.smoke))
        for _ in 0..<puffs {
            guard smoke.count < GameConfig.smokeCap else { break }
            smoke.append(Smoke(
                pos: CGPoint(x: shell.pos.x + rnd(-14 ... 14),
                             y: shell.pos.y + rnd(-14 ... 14)),
                vel: CGVector(dx: rnd(-0.06 ... 0.06), dy: rnd(-0.09 ... -0.02)),
                radius: rnd(16 ... 30) * spec.smoke,
                life: 1,
                decay: rnd(GameConfig.smokeDecayRange),
                fireworkID: shell.definitionID, variantIndex: shell.variantIndex))
        }

        // A BREAK SOWS POPS. The stars scatter and some of them stay — orbs
        // brought up from the field's own reserve at the point of the break.
        //
        // Taken FROM THE RESERVE rather than created, which is the whole
        // reason this is safe. A shell that manufactured orbs would make a
        // field longer every time she touched one, so the more she enjoyed
        // the fireworks the further away the quiet would get — the exact
        // shape of a treadmill. Drawing from the reserve means a display
        // rearranges when the field arrives, never how much of it there is,
        // and a field with every shell fired holds precisely as many pops as
        // one where she ignored them all.
        for _ in 0..<GameConfig.orbsSownPerBurst {
            guard surfaceFromReserve(near: shell.pos) != nil else { break }
        }

        // THE SHOVE. It moves the field; it may not make it harder to play,
        // so the push is clamped to the same ceiling everything else obeys.
        for i in orbs.indices where orbs[i].alive {
            let dx = orbs[i].pos.x - shell.pos.x
            let dy = orbs[i].pos.y - shell.pos.y
            let d2 = dx * dx + dy * dy
            let reach = GameConfig.fireworkShoveRadius
            guard d2 < reach * reach, d2 > 0.01 else { continue }
            let d = sqrt(d2)
            let falloff = 1 - d / reach
            let push = GameConfig.fireworkShove * falloff * falloff
            orbs[i].vel.dx += dx / d * push
            orbs[i].vel.dy += dy / d * push
            clampOrbSpeed(i)
        }
    }

    private func clampOrbSpeed(_ i: Int) {
        let cap = GameConfig.orbMaxSpeed * weather.speedScale * 1.6
        let speed = sqrt(orbs[i].vel.dx * orbs[i].vel.dx + orbs[i].vel.dy * orbs[i].vel.dy)
        if speed > cap {
            let k = cap / speed
            orbs[i].vel.dx *= k
            orbs[i].vel.dy *= k
        }
    }

    private func stepSmoke(_ f: CGFloat) {
        for i in smoke.indices {
            smoke[i].pos.x += smoke[i].vel.dx * f
            smoke[i].pos.y += smoke[i].vel.dy * f
            // It spreads as it thins, the way smoke does.
            smoke[i].radius += GameConfig.smokeSpread * f
            smoke[i].life -= smoke[i].decay * f
        }
        smoke.removeAll { $0.life <= 0 }
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
