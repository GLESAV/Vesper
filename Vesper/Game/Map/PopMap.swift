import Foundation

// The infinite pop map — "The Path" — modeled as stepping stones.
//
// Each stone is one playable level: a field seeded from that stone's 1–3
// pops. Clearing a stone opens 1–3 roads ahead; the road behind SETTLES after
// a few days (MapStore.fadeAfter) into a thin permanent constellation line —
// the map's memory. It used to be deleted at that point; W08 replaced the
// removal with a settle-state transition, so nothing on the map is ever lost
// and what keeps the sky small is the screenful `SkyLayout` draws, not the
// destruction of the past. Design: docs/pop_map.md.

extension MapStone {
    /// The family this stone leans toward: whichever has the most pops on it,
    /// tie broken by the lowest pop number so it is stable forever.
    ///
    /// DERIVED, NEVER STORED. A stone's pops already say what it is, and
    /// adding a field to this Codable struct would make every previously
    /// saved map fail to decode — the same trap the play counts avoided.
    var leaning: PopFamily? {
        var counts: [PopFamily: Int] = [:]
        for number in popNumbers {
            counts[PopCatalog.definition(for: number).family, default: 0] += 1
        }
        let best = counts.values.max()
        return counts.filter { $0.value == best }
            .map(\.key)
            .min { $0.rawValue < $1.rawValue }
    }
}

struct MapStone: Identifiable, Codable, Equatable {
    let id: UUID
    let parentID: UUID?
    let generation: Int
    let lane: Double          // 0…1 horizontal placement on the map
    let popNumbers: [Int]     // 1–3 pops this stone's field seeds from
    let seed: UInt64          // makes this stone's roads ahead deterministic
    let createdAt: Date
    var cleared = false
    var lastPlayedAt: Date? = nil
}

// Pure, seeded generation rules — deterministic and unit-tested.
enum PopMapGen {

    // one road 45%, a fork 45%, a rare three-way 10%
    static func branchCount(using rng: inout SplitMix64) -> Int {
        let roll = Double.random(in: 0..<1, using: &rng)
        if roll < 0.45 { return 1 }
        if roll < 0.90 { return 2 }
        return 3
    }

    // 1–2 pops per stone, rarely 3
    static func popCount(using rng: inout SplitMix64) -> Int {
        let roll = Double.random(in: 0..<1, using: &rng)
        if roll < 0.50 { return 1 }
        if roll < 0.90 { return 2 }
        return 3
    }

    // chance a stone hosts one "visitor": a pop not yet unlocked, playable
    // on that stone only (the permanent unlock still comes via the journey)
    static let visitorChance = 0.35

    // A stone's pop set: distinct pops, avoiding `avoiding` (the parent's
    // and siblings' pops) whenever the collection is large enough to allow it.
    static func popSet(unlocked: [Int], locked: [Int], avoiding: Set<Int>,
                       using rng: inout SplitMix64) -> [Int] {
        let count = popCount(using: &rng)
        var set: [Int] = []

        let freshLocked = locked.filter { !avoiding.contains($0) }
        if !freshLocked.isEmpty, Double.random(in: 0..<1, using: &rng) < visitorChance {
            let idx = Int.random(in: 0..<freshLocked.count, using: &rng)
            set.append(freshLocked[idx])
        }

        var pool = unlocked.filter { !avoiding.contains($0) && !set.contains($0) }
        if pool.isEmpty {
            pool = unlocked.filter { !set.contains($0) }
        }
        while set.count < count, !pool.isEmpty {
            let idx = Int.random(in: 0..<pool.count, using: &rng)
            set.append(pool.remove(at: idx))
        }
        if set.isEmpty {
            set = [unlocked.first ?? PopCatalog.classic.number]
        }
        return set
    }

    /// A child's pops: some of what its parent held, plus something new.
    ///
    /// **This inverts what the map used to do.** Children were generated with
    /// their parent's pops in `avoiding`, so every step along the Path
    /// replaced the whole set and nothing carried. A lineage that shares
    /// nothing with its parent is not a lineage, it is a shuffle — and it
    /// meant a stone told you nothing about the stone it came from.
    ///
    /// Now each child KEEPS one of its parent's pops and BRANCHES with new
    /// ones. Two things follow from that, and both are the point:
    ///
    ///   * A field always has something she recognises in it and something
    ///     she does not. That is the shape of a good introduction, repeated
    ///     every step, forever.
    ///   * Siblings keep DIFFERENT pops from the parent and take different
    ///     new ones, so two roads out of the same stone genuinely diverge —
    ///     and a fork becomes a choice about which lineage to follow rather
    ///     than a coin toss between two random sets.
    ///
    /// `inherited` is chosen by the caller so siblings can be given different
    /// ones; `avoiding` carries what earlier siblings already took.
    /// `leaning` is the family this road belongs to. New pops are drawn from
    /// it where they can be, which is what makes a fork a CHOICE — one road is
    /// the ember road and the other is the tide road, and she can see that in
    /// the sky before she takes either.
    ///
    /// Nothing is foreclosed by choosing. The road not taken stays on the map
    /// forever and stays walkable (W08), so a fork asks "what am I exploring
    /// tonight", never "what am I giving up". That is the difference between
    /// a branching path and a skill tree, and this game may only have the
    /// first.
    static func branchedSet(inheriting inherited: Int?,
                            leaning: PopFamily?,
                            unlocked: [Int], locked: [Int], avoiding: Set<Int>,
                            using rng: inout SplitMix64) -> [Int] {
        var set: [Int] = []
        if let inherited { set.append(inherited) }

        // One new pop from the locked book now and then — the same visitor
        // chance the map has always had, kept because meeting a pop you have
        // not unlocked is how the collection advertises itself.
        let freshLocked = locked.filter { !avoiding.contains($0) && !set.contains($0) }
        if !freshLocked.isEmpty, Double.random(in: 0..<1, using: &rng) < visitorChance {
            let idx = Int.random(in: 0..<freshLocked.count, using: &rng)
            set.append(freshLocked[idx])
        }

        let target = max(popCount(using: &rng), set.count + 1)
        var pool = unlocked.filter { !avoiding.contains($0) && !set.contains($0) }
        if pool.isEmpty { pool = unlocked.filter { !set.contains($0) } }

        // The road's own family first. Preference, not a rule: a family she
        // has barely unlocked would otherwise produce a road with one pop on
        // it, and a thin road is worse than a mixed one.
        if let leaning {
            var kin = pool.filter { PopCatalog.definition(for: $0).family == leaning }
            while set.count < target, !kin.isEmpty {
                let idx = Int.random(in: 0..<kin.count, using: &rng)
                let pick = kin.remove(at: idx)
                set.append(pick)
                pool.removeAll { $0 == pick }
            }
        }

        while set.count < target, !pool.isEmpty {
            let idx = Int.random(in: 0..<pool.count, using: &rng)
            set.append(pool.remove(at: idx))
        }

        if set.isEmpty { set = [unlocked.first ?? PopCatalog.classic.number] }
        return set
    }

    // roads spread from the parent's lane, clamped to the map's banks
    static func lanes(from parentLane: Double, count: Int,
                      using rng: inout SplitMix64) -> [Double] {
        let spreads: [Double]
        switch count {
        case 1: spreads = [Double.random(in: -0.16...0.16, using: &rng)]
        case 2: spreads = [-0.22, 0.22].map { $0 + Double.random(in: -0.06...0.06, using: &rng) }
        default: spreads = [-0.30, 0, 0.30].map { $0 + Double.random(in: -0.05...0.05, using: &rng) }
        }
        return spreads.map { min(0.92, max(0.08, parentLane + $0)) }
    }
}
