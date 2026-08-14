import Foundation
import Combine

// Everything the journey remembers — and it only ever counts up. Pop points,
// lifetime counters, per-pop tallies, and which pop is featured. Numbers
// affirm; nothing here can be lost, spent, or compared to anyone.
// UserDefaults only — nothing leaves the device (see PRIVACY.md).
// Design: docs/pop_progression.md and docs/pop_points.md.
final class ProgressionStore: ObservableObject {
    static let shared = ProgressionStore()

    @Published private(set) var popPoints: Int
    @Published private(set) var lifetimePops: Int
    @Published private(set) var fieldsCleared: Int
    @Published private(set) var fortunesFound: Int
    @Published private(set) var bestChain: Int
    @Published private(set) var popCounts: [Int: Int]

    // nil = "Drift": every new field mixes all unlocked pops
    @Published var featuredPop: Int? {
        didSet { defaults.set(featuredPop ?? 0, forKey: Keys.featured) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let points = "vesper.progress.points"
        static let lifetimePops = "vesper.stats.lifetimePops"   // pre-1.1 key, carried over
        static let fieldsCleared = "vesper.stats.fieldsCleared" // pre-1.1 key, carried over
        static let fortunes = "vesper.progress.fortunes"
        static let bestChain = "vesper.progress.bestChain"
        static let popCounts = "vesper.progress.popCounts"
        static let featured = "vesper.progress.featured"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        popPoints = defaults.integer(forKey: Keys.points)
        lifetimePops = defaults.integer(forKey: Keys.lifetimePops)
        fieldsCleared = defaults.integer(forKey: Keys.fieldsCleared)
        fortunesFound = defaults.integer(forKey: Keys.fortunes)
        bestChain = defaults.integer(forKey: Keys.bestChain)
        let stored = defaults.dictionary(forKey: Keys.popCounts) as? [String: Int] ?? [:]
        popCounts = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        let featured = defaults.integer(forKey: Keys.featured)
        self.featuredPop = featured == 0 ? nil : featured
    }

    // MARK: - Recording

    func recordPop(popNumber: Int, points: Int, chainLength: Int) {
        lifetimePops += 1
        popPoints += max(0, points)
        popCounts[popNumber, default: 0] += 1
        if chainLength > bestChain { bestChain = chainLength }
        persist()
    }

    func recordClear(bonus: Int) {
        fieldsCleared += 1
        popPoints += max(0, bonus)
        persist()
    }

    func recordFortune() {
        fortunesFound += 1
        persist()
    }

    private func persist() {
        defaults.set(popPoints, forKey: Keys.points)
        defaults.set(lifetimePops, forKey: Keys.lifetimePops)
        defaults.set(fieldsCleared, forKey: Keys.fieldsCleared)
        defaults.set(fortunesFound, forKey: Keys.fortunes)
        defaults.set(bestChain, forKey: Keys.bestChain)
        defaults.set(Dictionary(uniqueKeysWithValues: popCounts.map { (String($0.key), $0.value) }),
                     forKey: Keys.popCounts)
    }

    // MARK: - Unlocks

    func isUnlocked(_ def: PopDefinition) -> Bool {
        switch def.unlock {
        case .start: return true
        case .points(let n): return popPoints >= n
        case .totalPops(let n): return lifetimePops >= n
        case .fieldsCleared(let n): return fieldsCleared >= n
        case .fortunesFound(let n): return fortunesFound >= n
        case .bestChain(let n): return bestChain >= n
        }
    }

    func unlockedNumbers() -> Set<Int> {
        Set(PopCatalog.all.filter { isUnlocked($0) }.map(\.number))
    }

    // The pops a new field should seed from: the featured pop alone, or the
    // whole unlocked collection when drifting.
    func fieldPops() -> [Int] {
        if let featured = featuredPop, isUnlocked(PopCatalog.definition(for: featured)) {
            return [featured]
        }
        let unlocked = unlockedNumbers()
        return unlocked.isEmpty ? [PopCatalog.classic.number] : Array(unlocked).sorted()
    }
}
