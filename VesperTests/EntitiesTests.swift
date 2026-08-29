import XCTest
import CoreGraphics
@testable import Vesper

// The things the field is made of.
//
// `Entities.swift` holds no behaviour — it is five plain structs and the event
// enum — so there is nothing here to test about what they *do*. What there is
// to test is what the simulation ASSUMES about them, and those assumptions are
// load-bearing in two specific ways:
//
//   * They are VALUES. `split` makes a child with `var child = parent` and then
//     overrides eight fields; `emit` makes an orb out of its generator the same
//     way; `pop` snapshots `let orb = orbs[index]` into a `.popped` event that
//     `GameViewModel` handles a frame later, off `DispatchQueue.main.async`.
//     Every one of those is a bug the day one of these structs becomes a class.
//   * Their DEFAULTS are the shape every construction site depends on. Nothing
//     in the game passes `alive`, `spawn`, `isFortune`, `kind` or `fireworkID`
//     at the point of construction; they are set afterward, if at all.
//
// Those are the invariants below. Anything else here would be a test of the
// Swift language, not of Vesper.
final class EntitiesTests: XCTestCase {

    private func makeOrb(pos: CGPoint = CGPoint(x: 100, y: 200),
                         r: CGFloat = 18,
                         popNumber: Int = PopCatalog.classic.number,
                         variantIndex: Int = 0) -> Orb {
        Orb(pos: pos,
            vel: CGVector(dx: 0.4, dy: -0.3),
            r: r, baseR: r,
            popNumber: popNumber,
            variantIndex: variantIndex,
            phase: 1.25)
    }

    // MARK: - Defaults

    // Every orb in the game is built from these seven fields and nothing else;
    // the rest arrive by default. If `alive` ever defaulted to false a field
    // would seed dead, and if `spawn` defaulted to 1 orbs would appear at full
    // size instead of rising into view — neither would fail to compile
    // anywhere, which is exactly why it is pinned here.
    func testANewOrbArrivesAliveMidRiseOrdinaryAndPlain() {
        let orb = makeOrb()
        XCTAssertTrue(orb.alive, "a new orb must arrive alive")
        XCTAssertEqual(orb.spawn, 0, "a new orb must arrive at the start of its rise")
        XCTAssertFalse(orb.isFortune, "a fortune is chosen, never a default")
        XCTAssertEqual(orb.kind, OrbKind.plain, "the v1.0 orb is what an orb is")
    }

    // `fireworkID == nil` is what tells `SceneRenderer` to take a particle's
    // colour from `PopCatalog` rather than `FireworkCatalog`. Pop bursts never
    // set it, so the default IS the pop-coloured case — a default of anything
    // else would repaint every pop in the game with a shell's hotter palette.
    func testANewParticleIsAPopStarUntilAShellClaimsIt() {
        let star = Particle(pos: .zero, vel: .zero, life: 1, decay: 0.05, size: 2,
                            popNumber: PopCatalog.classic.number, variantIndex: 0)
        XCTAssertNil(star.fireworkID, "a pop's star must not be painted as a shell's")

        let spark = Particle(pos: .zero, vel: .zero, life: 1, decay: 0.05, size: 2,
                             popNumber: PopCatalog.classic.number, variantIndex: 0,
                             fireworkID: 3)
        XCTAssertEqual(spark.fireworkID ?? -1, 3, "a shell has to be able to claim its own stars")
    }

    // MARK: - Orbs are values

    // `split` writes `var child = parent` and then overrides only what a child
    // differs in. Everything it does NOT name has to come across by itself —
    // above all the paint, because a splitter's children being the parent's
    // colour is the whole reason nested dolls read as one thing coming apart
    // rather than as five new arrivals.
    func testCopyingAnOrbCarriesEveryFieldIncludingItsPaint() {
        var parent = makeOrb(pos: CGPoint(x: 140, y: 260), r: 30,
                             popNumber: 11, variantIndex: 2)
        parent.spawn = 1
        parent.isFortune = true
        parent.kind = .splitter(remaining: 2)

        let copy = parent

        // Against the values the parent was BUILT with, never against `parent`
        // itself: a field read back off the thing it was copied from is the
        // same expression twice and would agree under any semantics at all.
        XCTAssertEqual(copy.pos, CGPoint(x: 140, y: 260))
        XCTAssertEqual(copy.vel.dx, 0.4)
        XCTAssertEqual(copy.vel.dy, -0.3)
        XCTAssertEqual(copy.r, 30)
        XCTAssertEqual(copy.baseR, 30)
        XCTAssertEqual(copy.popNumber, 11)
        XCTAssertEqual(copy.variantIndex, 2)
        XCTAssertEqual(copy.phase, 1.25)
        XCTAssertTrue(copy.alive)
        XCTAssertEqual(copy.spawn, 1)
        XCTAssertTrue(copy.isFortune, "the paint and the state set after construction come across too")
        XCTAssertEqual(copy.kind, OrbKind.splitter(remaining: 2))
    }

    // The other half of the same contract, and the one that would actually
    // bite. `split` overrides nine fields on the copy while the parent is still
    // being read — for the burst, the rings and the `.popped` event. If `Orb`
    // became a class this test would still compile and would fail, which is the
    // point of writing it as an assertion instead of as a comment.
    func testOverridingACopiedOrbNeverReachesTheOriginal() {
        let parent = makeOrb(pos: CGPoint(x: 140, y: 260), r: 30,
                             popNumber: 11, variantIndex: 2)

        var child = parent
        child.alive = false
        child.isFortune = true
        child.baseR = 9
        child.r = 9
        child.spawn = 0.5
        child.phase = 0
        child.kind = .splitter(remaining: 1)
        child.pos = CGPoint(x: 1, y: 1)
        child.vel = CGVector(dx: -2, dy: -2)

        XCTAssertTrue(parent.alive)
        XCTAssertFalse(parent.isFortune)
        XCTAssertEqual(parent.baseR, 30)
        XCTAssertEqual(parent.r, 30)
        XCTAssertEqual(parent.spawn, 0)
        XCTAssertEqual(parent.phase, 1.25)
        XCTAssertEqual(parent.kind, OrbKind.plain)
        XCTAssertEqual(parent.pos, CGPoint(x: 140, y: 260))
        XCTAssertEqual(parent.vel.dx, 0.4)
        XCTAssertEqual(parent.vel.dy, -0.3)

        // ...and the child really did change, so the assertions above are not
        // passing because nothing happened.
        XCTAssertFalse(child.alive)
        XCTAssertEqual(child.baseR, 9)
        XCTAssertEqual(child.kind, OrbKind.splitter(remaining: 1))
    }

    // `pop` does `let orb = orbs[index]` and then keeps stepping the field.
    // Taking an orb out of the array has to take a copy of it, or every local
    // the simulation holds would follow the array's later edits.
    func testTakingAnOrbOutOfTheFieldArrayCopiesIt() {
        var field = [makeOrb(), makeOrb(pos: CGPoint(x: 10, y: 10))]
        let taken = field[0]

        field[0].alive = false
        field[0].pos = CGPoint(x: 999, y: 999)
        field[0].kind = .drifter

        XCTAssertTrue(taken.alive, "the orb the simulation is holding went dead under it")
        XCTAssertEqual(taken.pos, CGPoint(x: 100, y: 200))
        XCTAssertEqual(taken.kind, OrbKind.plain)
    }

    // THE ASYNCHRONOUS ONE. Chain events from `step()` are applied through
    // `DispatchQueue.main.async`, so a `.popped` or `.startled` payload is read
    // one or more frames after the field has moved on. The payload must be a
    // snapshot of the orb as it was when the event was made — a handle would
    // sound the pop at wherever that orb had drifted to by the time the
    // view model got to it, or read a startled animal's health after the next
    // tap had already taken one off.
    func testAnOrbCarriedInAnEventIsASnapshotNotAHandle() {
        var orb = makeOrb(pos: CGPoint(x: 55, y: 66), r: 20)
        orb.kind = .animal(AnimalPop(shape: .fox, health: 3, shyness: 1))

        let popped = GameEvent.popped(orb: orb, chained: false)
        let startled = GameEvent.startled(orb: orb)

        // The field moves on.
        orb.pos = CGPoint(x: 300, y: 400)
        orb.r = 2
        orb.alive = false
        orb.kind = .animal(AnimalPop(shape: .fox, health: 1, shyness: 0))

        guard case .popped(let carried, let chained) = popped else {
            return XCTFail("expected a popped event")
        }
        XCTAssertEqual(carried.pos, CGPoint(x: 55, y: 66), "the pop moved after it was reported")
        XCTAssertEqual(carried.r, 20, "the pop shrank after it was reported")
        XCTAssertTrue(carried.alive)
        XCTAssertFalse(chained)
        XCTAssertEqual(carried.kind, OrbKind.animal(AnimalPop(shape: .fox, health: 3, shyness: 1)))

        guard case .startled(let animal) = startled else {
            return XCTFail("expected a startled event")
        }
        XCTAssertEqual(animal.pos, CGPoint(x: 55, y: 66))
        XCTAssertEqual(animal.kind, OrbKind.animal(AnimalPop(shape: .fox, health: 3, shyness: 1)))
    }

    // MARK: - The rest of the field is values too

    // Particles, rings, motes and notes all live in arrays that the renderer
    // walks while the simulation mutates them in place. Each has to be a value
    // for `SceneRenderer.draw` to be the read-only pass the architecture rules
    // require it to be.
    func testTheFieldsSmallerThingsAreValuesAsWell() {
        var particle = Particle(pos: .zero, vel: .zero, life: 1, decay: 0.05, size: 2,
                                popNumber: PopCatalog.classic.number, variantIndex: 0)
        let particleCopy = particle
        particle.life = 0
        particle.fireworkID = 7
        XCTAssertEqual(particleCopy.life, 1)
        XCTAssertNil(particleCopy.fireworkID)

        var ring = Ring(pos: .zero, r: 5, maxR: 40, life: 1,
                        popNumber: PopCatalog.classic.number, variantIndex: 0, popped: false)
        let ringCopy = ring
        ring.r = 40
        ring.popped = true
        XCTAssertEqual(ringCopy.r, 5)
        XCTAssertFalse(ringCopy.popped, "a copied ring must not learn that the original popped")

        var mote = Mote(pos: .zero, vel: CGVector(dx: 0, dy: -0.05),
                        size: 1.5, alpha: 0.08, phase: 0)
        let moteCopy = mote
        mote.alpha = 0
        mote.pos = CGPoint(x: 5, y: 5)
        XCTAssertEqual(moteCopy.alpha, 0.08)
        XCTAssertEqual(moteCopy.pos, CGPoint.zero)

        var note = FloatNote(pos: .zero, text: "+2", life: 1)
        let noteCopy = note
        note.life = 0
        note.text = "+9"
        XCTAssertEqual(noteCopy.life, 1)
        XCTAssertEqual(noteCopy.text, "+2")
    }

    // MARK: - OrbKind

    // A splitter's depth lives in its case payload — `split` writes
    // `.splitter(remaining: remaining - 1)` on each child and hands `.plain` to
    // the last generation. Equality therefore has to discriminate on the
    // payload, or a hand-written `==` that only compared cases would make every
    // generation of doll look like every other.
    func testASplittersRemainingGenerationsArePartOfItsIdentity() {
        XCTAssertNotEqual(OrbKind.splitter(remaining: 2), OrbKind.splitter(remaining: 1))
        XCTAssertEqual(OrbKind.splitter(remaining: 2), OrbKind.splitter(remaining: 2))
        XCTAssertNotEqual(OrbKind.splitter(remaining: 1), OrbKind.plain)
        XCTAssertNotEqual(OrbKind.plain, OrbKind.drifter)

        // The same for a generator: two generators with different closing rules
        // are different things, and a field is meant to hold more than one.
        XCTAssertNotEqual(OrbKind.generator(Generator(closing: .quota(remaining: 3), interval: 60)),
                          OrbKind.generator(Generator(closing: .taps(remaining: 3), interval: 60)))
        XCTAssertNotEqual(OrbKind.generator(Generator(closing: .quota(remaining: 3), interval: 60)),
                          OrbKind.generator(Generator(closing: .quota(remaining: 2), interval: 60)))
        XCTAssertEqual(OrbKind.generator(Generator(closing: .quota(remaining: 3), interval: 60)),
                       OrbKind.generator(Generator(closing: .quota(remaining: 3), interval: 60)))
    }

    // Every frame the simulation does `if case .animal(let animal) = orbs[i].kind`,
    // steps a NEW animal out of it, and writes `orbs[i].kind = .animal(next)`
    // back. That write-back is mandatory, not stylistic: the animal bound out of
    // the case is a copy, so shyness decaying — which is the entire safety
    // argument for the mechanic, see `AnimalPop` — only reaches the field
    // because the kind is reassigned.
    func testAnAnimalBoundOutOfAKindIsACopyThatMustBeWrittenBack() {
        var orb = makeOrb()
        orb.kind = .animal(AnimalPop(shape: .rabbit, health: 3, shyness: 1))

        guard case .animal(let bound) = orb.kind else {
            return XCTFail("expected an animal kind")
        }
        var next = bound
        next.shyness = 0
        next.health = 1

        guard case .animal(let stillThere) = orb.kind else {
            return XCTFail("expected an animal kind")
        }
        XCTAssertEqual(stillThere.shyness, 1, "the animal changed without being written back")
        XCTAssertEqual(stillThere.health, 3, "the animal changed without being written back")

        orb.kind = .animal(next)
        guard case .animal(let written) = orb.kind else {
            return XCTFail("expected an animal kind")
        }
        XCTAssertEqual(written.shyness, 0, "writing the animal back did not take")
        XCTAssertEqual(written.health, 1, "writing the animal back did not take")
    }
}
