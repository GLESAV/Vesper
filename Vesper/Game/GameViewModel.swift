import SwiftUI

// Bridges the pure simulation to everything worldly: published UI state,
// sound, haptics, pop points and unlocks, and the timing of cards and
// whispers. Scoring rules: docs/pop_points.md · unlocks: docs/pop_progression.md.
final class GameViewModel: ObservableObject {

    @Published private(set) var count = 0
    @Published private(set) var started = false
    @Published var showDone = false
    @Published var showFortune = false
    @Published private(set) var fortuneText = ""
    @Published private(set) var chainNote: String?
    @Published private(set) var unlockNote: String?
    @Published private(set) var pathNote: String?
    @Published private(set) var sessionPoints = 0
    @Published private(set) var renderingPaused = false

    let sim = GameSimulation()
    let settings = SettingsStore.shared
    let progression = ProgressionStore.shared
    let map = MapStore.shared

    private var lastFrameDate: Date?
    private var fortuneDismissWork: DispatchWorkItem?
    private var chainFadeWork: DispatchWorkItem?
    private var unlockFadeWork: DispatchWorkItem?
    private var pathFadeWork: DispatchWorkItem?
    private var doneRevealWork: DispatchWorkItem?
    private var lastPopAt: Date?
    private var chainStreak = 0
    private var knownUnlocked: Set<Int>

    init() {
        knownUnlocked = progression.unlockedNumbers()
        map.ensureGenesis(unlocked: knownUnlocked)
        applyFieldPops()
    }

    // A field seeds from the stone you stand on; free play (featured/Drift)
    // when you're not on the path.
    private func applyFieldPops() {
        let pops = map.activeStone?.popNumbers ?? progression.fieldPops()
        sim.availablePops = pops
        PopSoundEngine.shared.prepare(pops.map {
            PopCatalog.definition(for: $0).behavior.sound
        })
    }

    // MARK: - The Path

    func playStone(_ stone: MapStone) {
        map.setActive(stone.id)
        restart()
    }

    // Featured/Drift selections step off the path into free play.
    func leavePath() {
        map.setActive(nil)
        restart()
    }

    // MARK: - Frame

    // Called from inside the Canvas renderer. Publishing during a view update
    // is a SwiftUI hazard, so any events produced here (chain pops) are
    // applied on the next main-queue hop; direct taps apply synchronously.
    func frame(date: Date, size: CGSize) {
        sim.layout(size: size)

        var dt: TimeInterval = 0
        if let last = lastFrameDate {
            dt = date.timeIntervalSince(last)
        }
        lastFrameDate = date

        let events = sim.step(dt: dt)
        let paused = sim.isQuiescent
        if !events.isEmpty || paused != renderingPaused {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.apply(events)
                if self.renderingPaused != paused {
                    self.renderingPaused = paused
                }
            }
        }
    }

    // MARK: - Input

    func tap(at p: CGPoint) {
        apply(sim.tap(at: p))
    }

    func restart() {
        doneRevealWork?.cancel()
        doneRevealWork = nil
        dismissFortune()
        chainFadeWork?.cancel()
        chainNote = nil
        unlockFadeWork?.cancel()
        unlockNote = nil
        pathFadeWork?.cancel()
        pathNote = nil
        chainStreak = 0
        lastPopAt = nil
        lastFrameDate = nil
        count = 0
        sessionPoints = 0
        started = false
        renderingPaused = false
        withAnimation(.easeInOut(duration: 0.35)) { showDone = false }
        applyFieldPops()
        sim.restart()
    }

    // MARK: - Events

    private func apply(_ events: [GameEvent]) {
        for event in events {
            switch event {
            case .popped(let orb, let chained):
                handlePop(orb: orb, chained: chained)
            case .fortuneRevealed:
                progression.recordFortune()
                triggerFortune()
            case .cleared:
                handleCleared()
            }
        }
        if !events.isEmpty { checkUnlocks() }
    }

    private func handlePop(orb: Orb, chained: Bool) {
        count = sim.popCount
        started = true

        let def = PopCatalog.definition(for: orb.popNumber)
        let range = GameConfig.orbRadiusRange
        let sizeNorm = Double((orb.baseR - range.lowerBound) / (range.upperBound - range.lowerBound))

        PopSoundEngine.shared.playPop(profile: def.behavior.sound, pitch: 1 - sizeNorm)
        HapticsEngine.shared.pop(profile: def.behavior.haptic, sizeNorm: sizeNorm, chained: chained)

        noteChainProgress()

        let earned = points(for: def, sizeNorm: sizeNorm, fortune: orb.isFortune)
        sessionPoints += earned
        progression.recordPop(popNumber: orb.popNumber, points: earned,
                              chainLength: chainStreak)
        if settings.pointWhispersEnabled {
            sim.addNote(at: CGPoint(x: orb.pos.x, y: orb.pos.y - orb.baseR - 8),
                        text: "+\(earned)")
        }
    }

    // Scoring per docs/pop_points.md: rarity base × size × chain multiplier,
    // plus the fortune bonus. Points only ever add.
    private func points(for def: PopDefinition, sizeNorm: Double, fortune: Bool) -> Int {
        var value = Double(def.rarity.pointValue) * (1 + 0.5 * sizeNorm)
        let multiplier = min(1 + 0.1 * Double(max(0, chainStreak - 1)), 2.0)
        value *= multiplier
        if fortune { value += 50 }
        return Int(value.rounded())
    }

    private func handleCleared() {
        sessionPoints += 100
        progression.recordClear(bonus: 100)

        if map.activeStoneID != nil {
            let roads = map.recordClear(unlocked: progression.unlockedNumbers())
            if !roads.isEmpty {
                showPathNote(roads.count == 1
                    ? "the path continues"
                    : "the path forks — \(roads.count) roads ahead")
            }
        }

        doneRevealWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sim.completed else { return }
            PopSoundEngine.shared.playCompletionChime()
            HapticsEngine.shared.cleared()
            withAnimation(.easeOut(duration: 0.5)) { self.showDone = true }
        }
        doneRevealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.doneRevealDelay, execute: work)
    }

    // MARK: - Unlocks

    private func checkUnlocks() {
        let unlocked = progression.unlockedNumbers()
        let fresh = unlocked.subtracting(knownUnlocked)
        knownUnlocked = unlocked
        guard !fresh.isEmpty else { return }

        let names = fresh.sorted().map { PopCatalog.definition(for: $0).name }
        let text = names.count == 1
            ? "new pop · \(names[0])"
            : "\(names.count) new pops found"
        withAnimation(.easeOut(duration: 0.4)) { unlockNote = text }
        unlockFadeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.6)) { self?.unlockNote = nil }
        }
        unlockFadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private func showPathNote(_ text: String) {
        withAnimation(.easeOut(duration: 0.4)) { pathNote = text }
        pathFadeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.6)) { self?.pathNote = nil }
        }
        pathFadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    // MARK: - Chain whisper

    private func noteChainProgress() {
        let now = Date()
        if let last = lastPopAt, now.timeIntervalSince(last) < GameConfig.chainWindow {
            chainStreak += 1
        } else {
            chainStreak = 1
        }
        lastPopAt = now
        guard chainStreak >= GameConfig.chainNoteThreshold else { return }

        withAnimation(.easeOut(duration: 0.25)) { chainNote = "chain of \(chainStreak)" }
        chainFadeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.6)) { self?.chainNote = nil }
        }
        chainFadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.chainNoteDuration, execute: work)
    }

    // MARK: - Fortune

    func dismissFortune() {
        fortuneDismissWork?.cancel()
        fortuneDismissWork = nil
        withAnimation(.easeInOut(duration: 0.3)) { showFortune = false }
    }

    private func triggerFortune() {
        fortuneText = Fortunes.messages.randomElement() ?? ""
        withAnimation(.easeOut(duration: 0.4)) { showFortune = true }
        fortuneDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.4)) { self?.showFortune = false }
        }
        fortuneDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.fortuneDisplayDuration, execute: work)
    }
}
