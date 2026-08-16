import Foundation
import Combine

// The living state of The Path: which stones exist, which one you stand on,
// and the quiet erosion of the road behind. Stones are created only when a
// cleared stone opens its roads, every stone that exists is playable, and
// nothing here can fail — the map only ever moves forward and lets go.
// UserDefaults only — nothing leaves the device. Design: docs/pop_map.md.
final class MapStore: ObservableObject {
    static let shared = MapStore()

    // how long a stone lingers after you've moved past it
    static let fadeAfter: TimeInterval = 3 * 24 * 60 * 60

    @Published private(set) var stones: [MapStone] = []
    @Published private(set) var activeStoneID: UUID?

    private let defaults: UserDefaults
    var nowProvider: () -> Date   // injectable for tests

    private enum Keys {
        static let stones = "vesper.map.stones"
        static let active = "vesper.map.active"
    }

    // The keys this store owns. See ProgressionStore.ownedDefaultsKeys for why
    // this is declared, and why it is not `#if DEBUG`.
    static let ownedDefaultsKeys: [String] = [
        Keys.stones,
        Keys.active,
    ]

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.nowProvider = now
        load()
    }

    // MARK: - Reading

    var activeStone: MapStone? {
        stones.first { $0.id == activeStoneID }
    }

    // where the map "twiddles down" to: the stone you stand on, else the
    // one you touched most recently
    var anchorStone: MapStone? {
        if let active = activeStone { return active }
        return stones.max { lastActivity($0) < lastActivity($1) }
    }

    private func lastActivity(_ stone: MapStone) -> Date {
        stone.lastPlayedAt ?? stone.createdAt
    }

    // MARK: - Lifecycle

    // Make sure the map exists: prune the faded past, and if nothing is
    // left (or this is a fresh journey), lay the first stone.
    func ensureGenesis(unlocked: Set<Int>) {
        prune()
        guard stones.isEmpty else { return }
        let seed = UInt64.random(in: .min ... .max)
        var rng = SplitMix64(seed: seed)
        let locked = PopCatalog.all.map(\.number).filter { !unlocked.contains($0) }
        let pops = PopMapGen.popSet(unlocked: Array(unlocked).sorted(),
                                    locked: locked, avoiding: [], using: &rng)
        stones = [MapStone(id: UUID(), parentID: nil, generation: 0, lane: 0.5,
                           popNumbers: pops, seed: seed, createdAt: nowProvider())]
        activeStoneID = nil
        save()
    }

    func setActive(_ id: UUID?) {
        activeStoneID = id
        if let id, let i = stones.firstIndex(where: { $0.id == id }) {
            stones[i].lastPlayedAt = nowProvider()
        }
        save()
    }

    // Called when the field of the active stone is cleared. The first clear
    // opens this stone's roads ahead; replays open nothing new.
    @discardableResult
    func recordClear(unlocked: Set<Int>) -> [MapStone] {
        guard let id = activeStoneID,
              let i = stones.firstIndex(where: { $0.id == id }) else { return [] }
        stones[i].cleared = true
        stones[i].lastPlayedAt = nowProvider()
        var created: [MapStone] = []
        if !stones.contains(where: { $0.parentID == id }) {
            created = makeChildren(of: stones[i], unlocked: unlocked)
            stones.append(contentsOf: created)
        }
        save()
        return created
    }

    private func makeChildren(of parent: MapStone, unlocked: Set<Int>) -> [MapStone] {
        var rng = SplitMix64(seed: parent.seed)
        let count = PopMapGen.branchCount(using: &rng)
        let lanes = PopMapGen.lanes(from: parent.lane, count: count, using: &rng)
        let locked = PopCatalog.all.map(\.number).filter { !unlocked.contains($0) }
        var avoiding = Set(parent.popNumbers)
        var children: [MapStone] = []
        for k in 0..<count {
            let childSeed = rng.next()
            var childRng = SplitMix64(seed: childSeed)
            let pops = PopMapGen.popSet(unlocked: Array(unlocked).sorted(),
                                        locked: locked, avoiding: avoiding,
                                        using: &childRng)
            avoiding.formUnion(pops)
            children.append(MapStone(id: UUID(), parentID: parent.id,
                                     generation: parent.generation + 1,
                                     lane: lanes[k], popNumbers: pops,
                                     seed: childSeed, createdAt: nowProvider()))
        }
        return children
    }

    // The road behind fades: any stone untouched for fadeAfter disappears —
    // except the anchor and the roads directly ahead of it, which always stay.
    func prune() {
        guard let anchor = anchorStone else { return }
        let cutoff = nowProvider().addingTimeInterval(-Self.fadeAfter)
        var keep = Set([anchor.id])
        keep.formUnion(stones.filter { $0.parentID == anchor.id }.map(\.id))

        let before = stones.count
        stones.removeAll { stone in
            !keep.contains(stone.id) && lastActivity(stone) < cutoff
        }
        if let id = activeStoneID, !stones.contains(where: { $0.id == id }) {
            activeStoneID = nil
        }
        if stones.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: Keys.stones),
           let decoded = try? JSONDecoder().decode([MapStone].self, from: data) {
            stones = decoded
        }
        if let raw = defaults.string(forKey: Keys.active), let id = UUID(uuidString: raw),
           stones.contains(where: { $0.id == id }) {
            activeStoneID = id
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stones) {
            defaults.set(data, forKey: Keys.stones)
        }
        defaults.set(activeStoneID?.uuidString ?? "", forKey: Keys.active)
    }

    // MARK: - W24: fresh install (DEBUG only)

    #if DEBUG
    // Erases The Path entirely — no stones, nobody standing anywhere — in
    // memory and on disk. The caller is responsible for laying the genesis
    // stone again (`ensureGenesis`), because that is what a first launch does
    // and doing it here would leave the sweep unable to say "nothing owned by
    // the game is left in defaults".
    func resetToFreshInstall() {
        stones = []
        activeStoneID = nil
        for key in Self.ownedDefaultsKeys { defaults.removeObject(forKey: key) }
    }
    #endif

}
