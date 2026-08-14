import SwiftUI

// Bridges the pure simulation to everything worldly: published UI state,
// sound, haptics, persisted stats, and the timing of cards and whispers.
final class GameViewModel: ObservableObject {

    @Published private(set) var count = 0
    @Published private(set) var started = false
    @Published var showDone = false
    @Published var showFortune = false
    @Published private(set) var fortuneText = ""
    @Published private(set) var chainNote: String?
    @Published private(set) var renderingPaused = false

    let sim = GameSimulation()
    let settings = SettingsStore.shared

    private var lastFrameDate: Date?
    private var fortuneDismissWork: DispatchWorkItem?
    private var chainFadeWork: DispatchWorkItem?
    private var doneRevealWork: DispatchWorkItem?
    private var lastPopAt: Date?
    private var chainStreak = 0

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
        chainStreak = 0
        lastPopAt = nil
        lastFrameDate = nil
        count = 0
        started = false
        renderingPaused = false
        withAnimation(.easeInOut(duration: 0.35)) { showDone = false }
        sim.restart()
    }

    // MARK: - Events

    private func apply(_ events: [GameEvent]) {
        for event in events {
            switch event {
            case .popped(let orb, let chained):
                handlePop(orb: orb, chained: chained)
            case .fortuneRevealed:
                triggerFortune()
            case .cleared:
                handleCleared()
            }
        }
    }

    private func handlePop(orb: Orb, chained: Bool) {
        count = sim.popCount
        started = true
        settings.recordPop()

        let range = GameConfig.orbRadiusRange
        let sizeNorm = Double((orb.baseR - range.lowerBound) / (range.upperBound - range.lowerBound))
        PopSoundEngine.shared.playPop(pitch: 1 - sizeNorm)
        HapticsEngine.shared.pop(intensity: 0.35 + sizeNorm * 0.5, chained: chained)

        noteChainProgress()
    }

    private func handleCleared() {
        settings.recordClear()
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
