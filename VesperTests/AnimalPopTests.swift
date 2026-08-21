import XCTest
@testable import Vesper

// BALLOON ANIMALS — and what these tests are actually for.
//
// The decorations are not asserted here. Which creature the RNG picked, how
// many particles the last tap throws, which way it faces: none of that is a
// promise to anyone, and a test that pins it down only makes the next tuning
// pass expensive.
//
// What IS asserted is the set of things that would turn a shy creature into
// the one thing this game may not contain — something that can be missed, or
// failed. In order: it surrenders to a close finger, exactly and always; it
// cannot outrun a thumb; it settles in a corner instead of vibrating there;
// its shyness genuinely decays, so it comes out and waits; a touch that does
// not finish it still lands; and — the one that matters more than the rest of
// them together — every field that contains one still finishes, at every
// stage, for many seeds.
//
// Everything is driven by `step(dt:)` with fixed seeds and
// `pinnedWeather = .clear`, never by a wall clock.
final class AnimalPopTests: XCTestCase {

    private let size = CGSize(width: 390, height: 800)
    private let frame: CGFloat = 1   // one 60 fps frame's worth of motion

    // MARK: - Helpers

    private func sim(seed: UInt64 = 42, stage: Int = 4, generation: Int = 0) -> GameSimulation {
        let s = GameSimulation(seed: seed)
        s.pinnedWeather = .clear
        s.layout(size: size)
        s.stage = stage
        s.generation = generation
        s.seedField()
        return s
    }

    private func animalOrb(at p: CGPoint,
                           shape: AnimalPop.Shape = .cat,
                           health: Int = 3,
                           shyness: CGFloat = 1,
                           r: CGFloat = 30) -> Orb {
        var o = Orb(pos: p, vel: .zero, r: r, baseR: r,
                    popNumber: PopCatalog.classic.number, variantIndex: 0, phase: 0)
        o.spawn = 1
        o.kind = .animal(AnimalPop(shape: shape, health: health, shyness: shyness))
        return o
    }

    private func plainOrb(at p: CGPoint, r: CGFloat = 30) -> Orb {
        var o = Orb(pos: p, vel: .zero, r: r, baseR: r,
                    popNumber: PopCatalog.classic.number, variantIndex: 0, phase: 0)
        o.spawn = 1
        return o
    }

    private func animal(in s: GameSimulation) -> AnimalPop? {
        for o in s.orbs where o.alive {
            if case .animal(let a) = o.kind { return a }
        }
        return nil
    }

    private func animalIndex(in s: GameSimulation) -> Int? {
        s.orbs.indices.first { i in
            guard s.orbs[i].alive else { return false }
            if case .animal = s.orbs[i].kind { return true }
            return false
        }
    }

    private func speed(_ v: CGVector) -> CGFloat { sqrt(v.dx * v.dx + v.dy * v.dy) }

    /// The generations at this stage that actually carry an animal.
    private func animalGenerations(stage: Int, count: Int) -> [Int] {
        (0..<24).filter { FieldPlan.hasAnimal(stage: stage, generation: $0) }.prefix(count).map { $0 }
    }

    // MARK: - It surrenders up close. Always, and exactly.

    // THE VETO THIS DEFENDS: "hides" and "hard to pop" must never become "can
    // be missed". Inside the drifter's own surrender radius the animal's step
    // must be arithmetically identical to being left alone — not "weaker",
    // not "damped", identical — so moving at it always catches it.
    func testInsideTheSurrenderRadiusThereIsNoEvasionAtAll() {
        let pos = CGPoint(x: 200, y: 400)
        let creature = AnimalPop(shape: .fox, health: 3, shyness: 1)

        for distance in stride(from: CGFloat(0), through: GameConfig.evadeSurrenderRadius, by: 2) {
            for angle in stride(from: CGFloat(0), to: CGFloat.pi * 2, by: .pi / 6) {
                let finger = CGPoint(x: pos.x + cos(angle) * distance,
                                     y: pos.y + sin(angle) * distance)
                let touched = AnimalMotion.step(creature, pos: pos, vel: .zero,
                                                pointer: finger, bounds: size,
                                                topInset: GameConfig.fieldTopInset,
                                                bottomInset: 0,
                                                reduceMotion: false, f: frame)
                let alone = AnimalMotion.step(creature, pos: pos, vel: .zero,
                                              pointer: nil, bounds: size,
                                              topInset: GameConfig.fieldTopInset,
                                              bottomInset: 0,
                                              reduceMotion: false, f: frame)
                XCTAssertEqual(touched.1.dx, alone.1.dx, accuracy: 1e-9,
                               "it evaded a finger \(distance) away, inside the surrender radius")
                XCTAssertEqual(touched.1.dy, alone.1.dy, accuracy: 1e-9,
                               "it evaded a finger \(distance) away, inside the surrender radius")
            }
        }
    }

    // And the same thing said through the whole simulation: a finger that
    // arrives and stays on it pops it, however shy it is.
    func testAFingerThatSimplyArrivesAlwaysCatchesIt() {
        for seed in UInt64(0)..<8 {
            let s = GameSimulation(seed: seed)
            s.pinnedWeather = .clear
            s.layout(size: size)
            s.replaceOrbs([animalOrb(at: CGPoint(x: 200, y: 400), health: 3)])

            var taps = 0
            for _ in 0..<400 {
                guard let i = animalIndex(in: s) else { break }
                let here = s.orbs[i].pos
                s.pointer = here                  // her hand is on it
                s.step(dt: 1.0 / 60)
                s.tap(at: here)
                taps += 1
            }
            XCTAssertTrue(s.completed, "seed \(seed): a finger on it did not finish it")
            XCTAssertLessThanOrEqual(taps, GameConfig.animalHealthRange.upperBound + 1,
                                     "seed \(seed): it took more taps than it has health")
        }
    }

    // MARK: - It cannot outrun a thumb

    func testItsCeilingIsFarBelowAMovingThumb() {
        // A slow drag is on the order of 300 points a second; these are the
        // two ceilings the animal has, in the same units.
        let slowThumb: CGFloat = 300
        XCTAssertLessThan(GameConfig.animalMaxSpeed * 60, slowThumb / 4,
                          "the animal's cruise is not far enough below a finger")
        XCTAssertLessThan(GameConfig.animalStartleSpeed * 60, slowThumb / 2,
                          "the startle dart is fast enough to be a chase")
    }

    func testNoAmountOfChasingEverRaisesItAboveItsCeiling() {
        var creature = AnimalPop(shape: .rabbit, health: 3, shyness: 1)
        var pos = CGPoint(x: 200, y: 400)
        var vel = CGVector.zero

        // A finger held just outside the surrender line, in the worst place
        // for it — always directly behind, always pushing.
        for _ in 0..<4000 {
            let d = GameConfig.evadeSurrenderRadius + 1
            let back = speed(vel) > 0.0001
                ? CGPoint(x: pos.x - vel.dx / speed(vel) * d, y: pos.y - vel.dy / speed(vel) * d)
                : CGPoint(x: pos.x - d, y: pos.y)
            let out = AnimalMotion.step(creature, pos: pos, vel: vel, pointer: back,
                                        bounds: size, topInset: GameConfig.fieldTopInset,
                                        bottomInset: 0, reduceMotion: false, f: frame)
            creature = out.0
            vel = out.1
            pos = CGPoint(x: pos.x + vel.dx, y: pos.y + vel.dy)
            XCTAssertLessThanOrEqual(speed(vel), GameConfig.animalMaxSpeed + 1e-6,
                                     "it accelerated past its own ceiling")
        }
    }

    // MARK: - A corner is a place to settle, not to vibrate

    func testACorneredAnimalSettlesInsteadOfVibrating() {
        let s = GameSimulation(seed: 5)
        s.pinnedWeather = .clear
        s.layout(size: size)
        let corner = CGPoint(x: 34, y: GameConfig.fieldTopInset + 34)
        s.replaceOrbs([animalOrb(at: corner)])
        // A finger held just outside the surrender line, pressing it in.
        s.pointer = CGPoint(x: corner.x + 50, y: corner.y + 50)

        var reversals = 0
        var previous = CGVector.zero
        let frames = 900
        for _ in 0..<frames {
            s.step(dt: 1.0 / 60)
            guard let i = animalIndex(in: s) else { break }
            let v = s.orbs[i].vel
            if v.dx * previous.dx < 0 { reversals += 1 }
            if v.dy * previous.dy < 0 { reversals += 1 }
            previous = v
        }

        XCTAssertLessThan(reversals, frames / 10,
                          "it chattered against the corner instead of settling")

        guard let i = animalIndex(in: s) else { return XCTFail("it left the field") }
        let p = s.orbs[i].pos
        let room = min(min(p.x, size.width - p.x),
                       min(p.y - s.topInset, size.height - p.y))
        XCTAssertGreaterThan(room, 15,
                             "it stayed jammed in the corner rather than easing back out")
        XCTAssertLessThanOrEqual(speed(s.orbs[i].vel), GameConfig.animalMaxSpeed + 1e-6)
    }

    // MARK: - Shyness is a phase, and it ends

    func testShynessOnlyEverFallsAndReachesZero() {
        var creature = AnimalPop(shape: .deer, health: 2, shyness: 1)
        var last = creature.shyness
        var frames = 0
        while creature.shyness > 0 && frames < 10_000 {
            creature = AnimalMotion.step(creature, pos: CGPoint(x: 200, y: 400), vel: .zero,
                                         pointer: CGPoint(x: 260, y: 400), bounds: size,
                                         topInset: GameConfig.fieldTopInset, bottomInset: 0,
                                         reduceMotion: false, f: frame).0
            XCTAssertLessThanOrEqual(creature.shyness, last, "shyness went back up")
            last = creature.shyness
            frames += 1
        }
        XCTAssertEqual(creature.shyness, 0, "it never came out")
        XCTAssertLessThanOrEqual(frames, Int(GameConfig.animalShyFrames) + 2)
        // And it happens inside a field, not eventually: about half a minute.
        XCTAssertLessThan(Double(frames) / 60, 40,
                          "it stayed shy for longer than a field lasts")
    }

    func testOnceItHasComeOutTheStepIsIndistinguishableFromAnOrdinaryOrb() {
        let creature = AnimalPop(shape: .frog, health: 2, shyness: 0)
        let pos = CGPoint(x: 200, y: 400)
        let vel = CGVector(dx: 0.1, dy: -0.05)

        // A finger at the exact mid-band, where evasion would be strongest.
        let mid = (GameConfig.animalEvadeRadius + GameConfig.evadeSurrenderRadius) / 2
        let out = AnimalMotion.step(creature, pos: pos, vel: vel,
                                    pointer: CGPoint(x: pos.x - mid, y: pos.y),
                                    bounds: size, topInset: GameConfig.fieldTopInset,
                                    bottomInset: 0, reduceMotion: false, f: frame)

        XCTAssertEqual(out.1.dx, vel.dx, accuracy: 1e-9, "a settled animal still ran")
        XCTAssertEqual(out.1.dy, vel.dy, accuracy: 1e-9, "a settled animal still ran")
    }

    // MARK: - Health: it reacts, and the last touch is the reward

    func testATapThatDoesNotFinishItStartlesItInstead() {
        let s = GameSimulation(seed: 7)
        s.pinnedWeather = .clear
        s.layout(size: size)
        let here = CGPoint(x: 200, y: 400)
        s.replaceOrbs([animalOrb(at: here, health: 3), plainOrb(at: CGPoint(x: 60, y: 600))])

        let events = s.tap(at: here)

        XCTAssertTrue(events.contains { if case .startled = $0 { return true } else { return false } },
                      "a touch that lands must be answered")
        XCTAssertFalse(events.contains { if case .popped = $0 { return true } else { return false } })
        XCTAssertEqual(s.popCount, 0, "nothing popped")
        guard let creature = animal(in: s) else { return XCTFail("it vanished") }
        XCTAssertEqual(creature.health, 2, "the touch did not count")
        XCTAssertEqual(creature.startle, 1, "it did not flinch")
        XCTAssertGreaterThan(speed(s.orbs[0].vel), GameConfig.animalMaxSpeed,
                             "the flinch did not move it")
    }

    func testTheLastTapPopsItAndClearsTheField() {
        let s = GameSimulation(seed: 8)
        s.pinnedWeather = .clear
        s.layout(size: size)
        let here = CGPoint(x: 200, y: 400)
        s.replaceOrbs([animalOrb(at: here, health: 2)])

        s.tap(at: here)
        XCTAssertFalse(s.completed)
        let events = s.tap(at: s.orbs[0].pos)

        XCTAssertTrue(events.contains { if case .popped = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .cleared = $0 { return true } else { return false } })
        XCTAssertTrue(s.completed)
        XCTAssertGreaterThan(s.particles.count, 0, "the last touch threw nothing")
    }

    func testTheStartleNeverCarriesItOutOfReachOfTheSameTap() {
        // The dart is short on purpose: a second tap in the SAME PLACE, after
        // the flinch has run its course, must still find it. A startle that
        // moved it out from under her finger would punish her for a hit.
        for shape in AnimalPop.Shape.allCases {
            let s = GameSimulation(seed: 11)
            s.pinnedWeather = .clear
            s.layout(size: size)
            let here = CGPoint(x: 200, y: 400)
            s.replaceOrbs([animalOrb(at: here, shape: shape, health: 3)])

            s.tap(at: here)
            for _ in 0..<Int(GameConfig.animalStartleFrames) { s.step(dt: 1.0 / 60) }
            s.tap(at: here)

            guard let creature = animal(in: s) else {
                return XCTFail("\(shape.name): it popped a tap early")
            }
            XCTAssertEqual(creature.health, 1,
                           "\(shape.name): the second tap in the same place missed it")
        }
    }

    func testAChainCannotSpendTheWholeCreatureInOneSweep() {
        let s = GameSimulation(seed: 12)
        s.pinnedWeather = .clear
        s.layout(size: size)
        // An orb to pop, and the animal close enough to be washed by its ring.
        s.replaceOrbs([plainOrb(at: CGPoint(x: 200, y: 400)),
                       animalOrb(at: CGPoint(x: 250, y: 400), health: 3)])

        s.tap(at: CGPoint(x: 200, y: 400))
        for _ in 0..<120 { s.step(dt: 1.0 / 60) }

        // Whatever the ring did, it cannot have been more than one touch.
        if let creature = animal(in: s) {
            XCTAssertGreaterThanOrEqual(creature.health, 2,
                                        "one shockwave spent more than one health")
        } else {
            XCTFail("one shockwave finished a three-health creature")
        }
    }

    // MARK: - Reduce Motion

    func testReduceMotionDampsTheStartleAndTheEvasion() {
        let creature = AnimalPop(shape: .bear, health: 3, shyness: 1)
        let pos = CGPoint(x: 200, y: 400)

        let loud = AnimalMotion.startled(creature, at: pos, from: CGPoint(x: 180, y: 400),
                                         angle: 0, reduceMotion: false)
        let quiet = AnimalMotion.startled(creature, at: pos, from: CGPoint(x: 180, y: 400),
                                          angle: 0, reduceMotion: true)
        XCTAssertLessThan(speed(quiet.1), speed(loud.1), "the dart was not damped")
        XCTAssertEqual(quiet.0.health, loud.0.health, "damping changed how much a tap counts")

        let mid = (GameConfig.animalEvadeRadius + GameConfig.evadeSurrenderRadius) / 2
        let finger = CGPoint(x: pos.x - mid, y: pos.y)
        let ranHard = AnimalMotion.step(creature, pos: pos, vel: .zero, pointer: finger,
                                        bounds: size, topInset: GameConfig.fieldTopInset,
                                        bottomInset: 0, reduceMotion: false, f: frame).1
        let ranSoft = AnimalMotion.step(creature, pos: pos, vel: .zero, pointer: finger,
                                        bounds: size, topInset: GameConfig.fieldTopInset,
                                        bottomInset: 0, reduceMotion: true, f: frame).1
        XCTAssertGreaterThan(ranHard.dx, ranSoft.dx, "the evasion was not damped")
    }

    // MARK: - Where they appear

    func testAnimalsStartAtStageThreeAndThereIsNeverMoreThanOne() {
        for stage in 0..<GameConfig.animalStartStage {
            for generation in 0..<40 {
                XCTAssertEqual(FieldPlan.animalCount(stage: stage, generation: generation), 0,
                               "an animal arrived at stage \(stage)")
            }
        }
        var seen = 0
        for generation in 0..<40 {
            let n = FieldPlan.animalCount(stage: GameConfig.animalStartStage,
                                          generation: generation)
            XCTAssertLessThanOrEqual(n, 1, "more than one animal on one field")
            seen += n
        }
        XCTAssertGreaterThan(seen, 0, "they never actually appear")
        XCTAssertLessThan(seen, 40, "every single field carries one — it stops being a visit")
    }

    func testAFieldWithAnAnimalIsNeverAlsoADisplay() {
        for stage in 0...FieldPlan.finalStage {
            for generation in 0..<40 {
                let hasAnimal = FieldPlan.hasAnimal(stage: stage, generation: generation)
                let isDisplay = FieldPlan.isDisplay(stage: stage, generation: generation)
                XCTAssertFalse(hasAnimal && isDisplay,
                               "stage \(stage) gen \(generation): a shy creature under fireworks")
            }
        }
    }

    func testTheAnimalStartsOnTheGlassAndNotInTheReserve() {
        for stage in GameConfig.animalStartStage...FieldPlan.finalStage {
            for generation in animalGenerations(stage: stage, count: 2) {
                for seed in UInt64(0)..<6 {
                    let s = sim(seed: seed, stage: stage, generation: generation)
                    XCTAssertEqual(s.plan.animals, 1, "stage \(stage) gen \(generation)")
                    let onGlass = s.orbs.contains { if case .animal = $0.kind { return true } else { return false } }
                    let below = s.reserve.contains { if case .animal = $0.kind { return true } else { return false } }
                    XCTAssertTrue(onGlass, "the animal was not on the surface")
                    XCTAssertFalse(below, "the animal was waiting underneath")
                }
            }
        }
    }

    func testTheSameStoneIsTheSameCreature() {
        let a = sim(seed: 99, stage: 4, generation: 0)
        let b = sim(seed: 99, stage: 4, generation: 0)
        XCTAssertNotNil(a.animalOnField)
        XCTAssertEqual(a.animalOnField, b.animalOnField,
                       "a stone gave a different creature on the second visit")
    }

    // MARK: - The silhouette

    func testEveryShapeIsUnmistakablyNotASphere() {
        for shape in AnimalPop.Shape.allCases {
            XCTAssertGreaterThan(shape.lobes.count, 1, "\(shape.name) is one circle")
            XCTAssertGreaterThan(shape.reach, 1.1,
                                 "\(shape.name) does not reach past a plain orb")
        }
    }

    func testEveryShapeIsOneUnbrokenBalloon() {
        // Nothing in the silhouette may float free: a balloon animal is one
        // tube twisted into segments, and a lobe with a gap around it reads as
        // a speck beside a head rather than as an ear.
        for shape in AnimalPop.Shape.allCases {
            let lobes = shape.joinedLobes
            XCTAssertGreaterThanOrEqual(lobes.count, shape.lobes.count)

            // Grow the connected set out from the body lobe; everything must
            // join it.
            var joined = [0]
            var added = true
            while added {
                added = false
                for k in lobes.indices where !joined.contains(k) {
                    let (b, rb) = lobes[k]
                    for j in joined {
                        let (a, ra) = lobes[j]
                        if hypot(b.x - a.x, b.y - a.y) <= ra + rb + 1e-6 {
                            joined.append(k)
                            added = true
                            break
                        }
                    }
                }
            }
            XCTAssertEqual(joined.count, lobes.count,
                           "\(shape.name) has \(lobes.count - joined.count) lobes floating free")
        }
    }

    // MARK: - THE ONE THAT MATTERS: every field with an animal still finishes

    // If this ever fails, the mechanic is not "hard to catch" — it is a fail
    // state, and it has to come out. A field cannot be finished without its
    // animal, so the animal has to be catchable by everyone, including someone
    // tired and not really trying.
    //
    // The player modelled here is exactly that person: she does not chase, she
    // does not aim ahead, she does not learn the pattern. She puts a finger on
    // whatever is in front of her, where it is, and taps.
    func testEveryFieldWithAnAnimalStillFinishes() {
        for stage in GameConfig.animalStartStage...FieldPlan.finalStage {
            for generation in animalGenerations(stage: stage, count: 2) {
                for seed in UInt64(0)..<6 {
                    let s = sim(seed: seed, stage: stage, generation: generation)
                    let where_ = "stage \(stage), generation \(generation), seed \(seed)"
                    XCTAssertEqual(s.plan.animals, 1, where_)

                    var rounds = 0
                    while !s.completed && rounds < 600 {
                        for _ in 0..<12 { s.step(dt: 1.0 / 60) }
                        for orb in s.orbs where orb.alive {
                            s.pointer = orb.pos
                            s.tap(at: orb.pos)
                        }
                        rounds += 1
                    }

                    XCTAssertTrue(s.completed, "\(where_): the field never finished")
                    XCTAssertTrue(s.reserve.isEmpty, "\(where_): orbs left underneath")
                    XCTAssertNil(s.animalOnField, "\(where_): the animal outlasted the field")
                }
            }
        }
    }
}
