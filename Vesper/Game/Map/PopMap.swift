import Foundation

// The infinite pop map — "The Path" — modeled as stepping stones.
//
// Each stone is one playable level: a field seeded from that stone's 1–3
// pops. Clearing a stone opens 1–3 roads ahead; the road behind fades after
// a few days (MapStore.fadeAfter), so the map stays small and the past lets
// go of itself. Design: docs/pop_map.md.

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
