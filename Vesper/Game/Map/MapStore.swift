import Foundation
import Combine

// The living state of The Path: which stones exist, which one you stand on,
// and the quiet erosion of the road behind. Stones are created only when a
// cleared stone opens its roads, every stone that exists is playable, and
// nothing here can fail — the map only ever moves forward and lets go.
// UserDefaults only — nothing leaves the device. Design: docs/pop_map.md.
final class MapStore: ObservableObject {
    static let shared = MapStore()

    // How long a stone stays lit after you've moved past it. AFTER THIS IT
    // SETTLES; IT IS NEVER REMOVED (W08). Read by `SkyLayout.isSettled`, which
    // derives the state from the stone's own dates rather than writing
    // anything back — which is why this needed no migration and no schema.
    static let fadeAfter: TimeInterval = 3 * 24 * 60 * 60

    @Published private(set) var stones: [MapStone] = []
    @Published private(set) var activeStoneID: UUID?

    /// How many times each stone has been cleared. Absent means never.
    @Published private(set) var plays: [UUID: Int] = [:]

    private let defaults: UserDefaults
    var nowProvider: () -> Date   // injectable for tests

    private enum Keys {
        static let stones = "vesper.map.stones"
        static let active = "vesper.map.active"
        // Kept in its OWN key rather than as a field on `MapStone`. Adding a
        // property to a Codable struct makes every previously-saved map fail
        // to decode — `JSONDecoder` throws on a missing key even when the
        // property has a default — and `load()` swallows that failure, so the
        // whole Path would silently vanish. W08's contract is that nothing is
        // ever lost; a separate key that simply reads as empty on first launch
        // keeps it true.
        static let plays = "vesper.map.plays"
        // Where an undecodable blob is PRESERVED instead of lost. If a stored
        // map ever fails to decode — corruption, or a future release changing
        // `MapStone`'s stored shape — `load()` used to leave `stones` empty,
        // `ensureGenesis` would lay a fresh stone, and the very first `save()`
        // would overwrite the only copy of her whole Path. W08's contract is
        // that nothing is ever lost, and that includes being lost to a bug:
        // the raw bytes are moved here before anything can write over the
        // live key, so a future release that understands them can bring the
        // Path back.
        static let stonesKeepsake = "vesper.map.stones.keepsake"
        static let playsKeepsake = "vesper.map.plays.keepsake"
    }

    // The keys this store owns. See ProgressionStore.ownedDefaultsKeys for why
    // this is declared, and why it is not `#if DEBUG`.
    static let ownedDefaultsKeys: [String] = [
        Keys.stones,
        Keys.active,
        Keys.plays,
        Keys.stonesKeepsake,
        Keys.playsKeepsake,
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

    // Make sure the map exists: if this is a fresh journey, lay the first
    // stone. Nothing is removed here any more — see the note on `fadeAfter`.
    func ensureGenesis(unlocked: Set<Int>) {
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

    /// The roads opening ahead of a stone — its children, oldest first.
    func roads(from id: UUID) -> [MapStone] {
        stones.filter { $0.parentID == id }.sorted { $0.createdAt < $1.createdAt }
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
        plays[id, default: 0] += 1
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
        // Each child keeps one of the parent's pops and branches with new
        // ones. `heritable` is shuffled and dealt round-robin so siblings
        // inherit DIFFERENT things — two roads out of one stone have to
        // genuinely diverge, or a fork is a coin toss.
        //
        // `avoiding` now carries only what earlier SIBLINGS took, never the
        // parent's own set: the parent's pops are the thing being passed
        // down, so excluding them was excluding the inheritance.
        var heritable = parent.popNumbers.shuffled(using: &rng)
        if heritable.isEmpty { heritable = [PopCatalog.classic.number] }
        var avoiding = Set<Int>()
        var children: [MapStone] = []

        // EACH ROAD GETS ITS OWN FAMILY, and no two roads out of one stone
        // share it. That is what makes a fork a choice she can read: one road
        // is the ember road and the other is the tide road, and the sky says
        // so in the gem silhouettes before she takes either.
        //
        // The parent's own family is offered first, so continuing straight on
        // is always available — a fork should never force a change of
        // direction, only offer one.
        var families = PopFamily.allCases.shuffled(using: &rng)
        if let parentFamily = parent.leaning {
            families.removeAll { $0 == parentFamily }
            families.insert(parentFamily, at: 0)
        }

        for k in 0..<count {
            let childSeed = rng.next()
            var childRng = SplitMix64(seed: childSeed)
            let pops = PopMapGen.branchedSet(inheriting: heritable[k % heritable.count],
                                             leaning: families[k % families.count],
                                             unlocked: Array(unlocked).sorted(),
                                             locked: locked, avoiding: avoiding,
                                             using: &childRng)
            // Only the NEW pops are withheld from later siblings; the
            // inherited one may legitimately repeat when a parent has fewer
            // pops than it has roads.
            avoiding.formUnion(pops.dropFirst())
            children.append(MapStone(id: UUID(), parentID: parent.id,
                                     generation: parent.generation + 1,
                                     lane: lanes[k], popNumbers: pops,
                                     seed: childSeed, createdAt: nowProvider()))
        }
        return children
    }

    // W08 — THE REMOVAL PASS IS GONE, AND NOTHING REPLACES IT.
    //
    // What stood here deleted every stone untouched for `fadeAfter`, except
    // the anchor and the roads directly ahead of it, and it ran on every
    // foreground. It was the code behind "the road disappears behind" — and
    // it implemented that by destroying the map, which is a different thing
    // from the map leading with where you are.
    //
    // `docs/pop_map.md` has specified the replacement all along: the road
    // "transmutes, never disappears — it becomes a thin, permanent
    // constellation line, quieter and dimmer, the map's memory", and "no
    // stone or road is ever removed". `SkyView` was built to that spec and
    // has been ready the whole time: `SkyLayout.isSettled`, the `.settled`
    // road tier, the quieted star. None of it could ever fire, because the
    // stones it describes were deleted before the sky was asked to draw them.
    //
    // THE MIGRATION THIS WAS DEFERRED FOR TURNED OUT NOT TO EXIST. W08 was
    // held back as a one-way persisted-schema change the view flag could not
    // protect. It is not one: settledness is a pure function of the stone's
    // own dates and the current time (`SkyLayout.isSettled`), so there is no
    // new field, no migration, and nothing to roll back. Deleting the pass is
    // the whole change.
    //
    // What she sees is unchanged in the way she asked for and different in
    // the way that matters: the map still leads with the latest stone and its
    // open roads, and everything walked before is still there, hanging above
    // as trace. The map's memory stops being a promise the code was breaking
    // every three days.

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: Keys.stones) {
            if let decoded = try? JSONDecoder().decode([MapStone].self, from: data) {
                stones = decoded
            } else {
                // The blob exists and cannot be read. It is her whole Path,
                // and the next `save()` would overwrite it with a fresh
                // genesis — so it is moved aside FIRST, whole, where a future
                // release that understands it can find it. Never overwritten
                // once set: the first failure is the copy worth keeping.
                if defaults.data(forKey: Keys.stonesKeepsake) == nil {
                    defaults.set(data, forKey: Keys.stonesKeepsake)
                }
            }
        }
        if let raw = defaults.string(forKey: Keys.active), let id = UUID(uuidString: raw),
           stones.contains(where: { $0.id == id }) {
            activeStoneID = id
        }
        if let data = defaults.data(forKey: Keys.plays) {
            if let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
                plays = Dictionary(uniqueKeysWithValues:
                    decoded.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
            } else if defaults.data(forKey: Keys.playsKeepsake) == nil {
                defaults.set(data, forKey: Keys.playsKeepsake)
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stones) {
            defaults.set(data, forKey: Keys.stones)
        }
        defaults.set(activeStoneID?.uuidString ?? "", forKey: Keys.active)
        let encodable = Dictionary(uniqueKeysWithValues: plays.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Keys.plays)
        }
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
        plays = [:]
        for key in Self.ownedDefaultsKeys { defaults.removeObject(forKey: key) }
    }
    #endif

}
