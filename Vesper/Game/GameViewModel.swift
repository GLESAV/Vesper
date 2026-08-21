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

    /// Where the fortune orb was, so the words rise from it.
    @Published private(set) var fortuneAnchor: CGPoint = .zero

    // MARK: - Onward

    // AFTER A FIELD IS CLEAR, THE WORLD GOES UP TO THE SKY BY ITSELF, and if
    // there is exactly one road ahead it takes it (owner's request).
    //
    // THE TWO CONDITIONS THAT KEEP THIS FROM BEING A SHOVE. This game's whole
    // claim is that it never moves her anywhere she did not ask to go, and an
    // auto-advance is the single most likely feature to break that.
    //
    //   1. **A touch cancels it, instantly and permanently for that field.**
    //      If her thumb is anywhere near the glass while this is pending, it
    //      stops and she stays exactly where she is. Sitting in the quiet
    //      after clearing a field is a thing people do, and it must always
    //      win over the animation.
    //   2. **A FORK STOPS IT.** When `recordClear` opens more than one road,
    //      the sequence halts in the sky with the roads lit and tappable.
    //      Choosing for her would be taking the one decision The Path exists
    //      to offer, and doing it while she is watching.
    //
    // Signalled as a counter rather than a Bool so two consecutive fields
    // each fire, and read by `WorldView`, which owns navigation.
    @Published private(set) var skyRequest = 0
    @Published private(set) var fieldRequest = 0
    private var onwardWork: DispatchWorkItem?

    /// Stops any pending travel. Called on the first touch after a clear.
    func cancelOnward() {
        onwardWork?.cancel()
        onwardWork = nil
    }

    /// The verse shown under "the field is quiet now." on the done card.
    /// Drawn once per completed field, without repeats until the set is
    /// exhausted — a repeat inside one evening turns a small gift into a slot
    /// machine.
    @Published private(set) var closingVerse = ""
    private var verses = Verses.Deck()
    @Published private(set) var chainNote: String?
    @Published private(set) var unlockNote: String?
    @Published private(set) var pathNote: String?
    @Published private(set) var sessionPoints = 0
    @Published private(set) var renderingPaused = false

    // W07 / DELIVERY_ROADMAP §6 ruling 9. Whether the simulation may advance
    // this frame, checked at the very top of `frame(date:size:)`.
    //
    // AN EXPLICIT FLAG, NEVER AN INFERENCE FROM SWIFTUI. Pausing by "the
    // Canvas probably will not be drawn while she is at the sky" is undefined
    // rendering behaviour dressed up as a feature; this is one line, it is
    // deterministic, and a unit test can state it. The world writes it from
    // `camera.isAtRest && camera.place == .field`, so the field stops the
    // instant she has decided to leave it and no chain resolves where she
    // cannot see it (04 §5).
    //
    // NOT `@Published`: it is written once per frame from inside the render
    // pass, and publishing there is SwiftUI's publishing-during-view-update
    // hazard. Nothing observes it — `frame(date:size:)` reads it directly.
    //
    // Defaults to `true` so v1.2's ContentView, which never writes it,
    // behaves exactly as it always has.
    var simActive = true

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
        // The stage rides on fields cleared, so what a field is made of grows
        // with her rather than with anything she has to choose. Set before
        // every seed, because `seedField` reads it once and builds to it.
        sim.stage = FieldPlan.stage(forFieldsCleared: progression.fieldsCleared)
        // Where this field sits on the Path, and how often she has been here.
        // Both grow the field's depth: further along is a longer field, and
        // returning to a stone she has cleared gives her more of it.
        sim.generation = map.activeStone?.generation ?? 0
        sim.plays = map.activeStone.map { map.plays[$0.id] ?? 0 } ?? 0
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
        // W07. `lastFrameDate` is advanced even while paused, and that is the
        // whole reason this is not a bare `return`: coming back to the field
        // after a minute in the journal would otherwise hand the sim one
        // enormous dt. It is clamped downstream, so the field would not
        // explode — it would simply lurch a frame forward the moment she
        // arrived, which is worse, because it looks deliberate.
        guard simActive else {
            lastFrameDate = date
            return
        }

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

    // MARK: - Field bands

    /// The bands the field may not enter, from `FieldLayout`.
    ///
    /// Not `@Published` and not read during a draw: these change on layout
    /// (launch, rotation, Split View, a Dynamic Type change that grows the
    /// whisper's target), which is orders of magnitude rarer than a frame.
    func applyFieldBands(top: CGFloat, bottom: CGFloat) {
        sim.topInset = top
        sim.bottomInset = bottom
    }

    // MARK: - Pointer

    /// Where the finger is, or nil when nothing is touching.
    ///
    /// Drifters read this to ease away. It is reported from the input view
    /// ALONGSIDE the arbiter and never through it — nothing here can reach
    /// pop-vs-pan arbitration, which is the one thing R-SPIKE exists to keep
    /// safe. Written every touch move, so it stays off `@Published`: a
    /// published write at digitizer rate would invalidate the view 120 times
    /// a second (ruling 7).
    func pointerMoved(to p: CGPoint?) {
        sim.pointer = p
        // Her hand is on the glass: whatever the world was about to do on its
        // own, it does not. Condition 1 of the onward sequence.
        if p != nil { cancelOnward() }
    }

    // MARK: - Events

    private func apply(_ events: [GameEvent]) {
        for event in events {
            switch event {
            case .popped(let orb, let chained):
                handlePop(orb: orb, chained: chained)
            case .fortuneRevealed(let at):
                progression.recordFortune()
                fortuneAnchor = at
                triggerFortune()
            case .cleared:
                handleCleared()

            // A splitter opening. It gets its own soft answer rather than
            // borrowing the pop's — the pop already sounded a frame ago, and
            // doubling it reads as a glitch rather than as a reward.
            case .split(let parent, _):
                let def = PopCatalog.definition(for: parent.popNumber)
                PopSoundEngine.shared.playPop(profile: def.behavior.sound, pitch: 1.34)

            // A generator giving. Only answered when SHE caused it: an orb
            // arriving on the generator's own interval is ambient and must
            // not tap her on the shoulder. A press she made is different —
            // that is the whole feel of working a generator.
            case .emitted(let orb, let byTap):
                if byTap {
                    let def = PopCatalog.definition(for: orb.popNumber)
                    PopSoundEngine.shared.playPop(profile: def.behavior.sound, pitch: 1.18)
                    HapticsEngine.shared.pop(profile: def.behavior.haptic,
                                             sizeNorm: 0.25, chained: true)
                }

            // A generator closing on its own terms. DELIBERATELY SILENT.
            // Nothing was popped and nothing was lost, so there is nothing to
            // announce — a sound here would turn "it settled" into "you
            // missed it", which is the exact feeling this game does not have.
            case .generatorClosed:
                break

            // Something came up from below. DELIBERATELY SILENT — it makes no
            // sound and no haptic, because nothing happened TO her: the field
            // simply has depth, and she is seeing more of it. A note here
            // would turn "there is more underneath" into "something arrived".
            case .rose:
                break

            // A CREATURE FLINCHING. Sounded, because the alternative is worse
            // than silence: a tap that lands on the animal and answers with
            // nothing is indistinguishable from a tap that missed, and "did I
            // hit it?" is a question this game must never make her ask.
            //
            // Softer and higher than the pop it is not — this is contact, not
            // completion — and it borrows the orb's own voice so the animal
            // still sounds like the field it lives on.
            case .startled(let orb):
                let def = PopCatalog.definition(for: orb.popNumber)
                PopSoundEngine.shared.playPop(profile: def.behavior.sound, pitch: 1.42)
                HapticsEngine.shared.pop(profile: def.behavior.haptic,
                                         sizeNorm: 0.2, chained: true)

            // THE WHIRR. A shell's rise is the part of a firework that is
            // actually pleasant to hear — the report is the part this game
            // cannot have — so the launch is sounded and the break is
            // answered softly, and neither is ever loud.
            // THE SOUND FLOW, IN THE ORDER A REAL FIREWORK MAKES IT (owner):
            // the fuse catches, the cord hisses as it is hurried, the mortar
            // goes THOOMF, the shell whirrs up, and the bloom opens. Five
            // sounds for one firework, and only the thoomf has any weight in
            // it — the report at the top, which is what a real display is
            // actually loud with, is the one this game cannot have.
            case .fuseLit(let shell):
                let definition = FireworkCatalog.definition(for: shell.definitionID)
                PopSoundEngine.shared.playFuseTick(startFreq: definition.whirr * 0.8)
                HapticsEngine.shared.pop(profile: HapticProfile(baseIntensity: 0.18,
                                                                intensityPerSize: 0,
                                                                sharp: true,
                                                                pattern: .single),
                                         sizeNorm: 0, chained: false)

            case .fuseHurried(let shell):
                let definition = FireworkCatalog.definition(for: shell.definitionID)
                PopSoundEngine.shared.playFuseTick(startFreq: definition.whirr)

            case .fireworkLaunched(let shell):
                let definition = FireworkCatalog.definition(for: shell.definitionID)
                PopSoundEngine.shared.playThoomf()
                PopSoundEngine.shared.playWhirr(startFreq: definition.whirr)
                HapticsEngine.shared.pop(profile: HapticProfile(baseIntensity: 0.22,
                                                                intensityPerSize: 0,
                                                                sharp: false,
                                                                pattern: .swell),
                                         sizeNorm: 0, chained: false)

            case .fireworkBurst(let shell):
                let definition = FireworkCatalog.definition(for: shell.definitionID)
                PopSoundEngine.shared.playPop(
                    profile: SoundProfile(voice: definition.bloom,
                                          startFreq: definition.whirr * 1.6,
                                          freqSpread: 0, sweep: 1.04,
                                          duration: 0.26, decay: 5.5, brightness: 0.1),
                    pitch: 0)
                HapticsEngine.shared.pop(profile: HapticProfile(baseIntensity: 0.3,
                                                                intensityPerSize: 0,
                                                                sharp: false,
                                                                pattern: .ripple),
                                         sizeNorm: 0, chained: false)
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

        let earned = points(for: def, sizeNorm: sizeNorm, fortune: orb.isFortune,
                            kind: orb.kind)
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
    private func points(for def: PopDefinition, sizeNorm: Double, fortune: Bool,
                        kind: OrbKind = .plain) -> Int {
        var value = Double(def.rarity.pointValue) * (1 + 0.5 * sizeNorm)
        let multiplier = min(1 + 0.1 * Double(max(0, chainStreak - 1)), 2.0)
        value *= multiplier
        // A creature took longer to meet, so it gives more. Additive only —
        // nothing anywhere subtracts for the taps that did not finish it.
        if case .animal = kind { value *= GameConfig.animalPointsMultiplier }
        if fortune { value += 50 }
        return Int(value.rounded())
    }

    // MARK: - What the field says out loud

    /// The field's VoiceOver label, which names the creature when there is one.
    ///
    /// The field is drawn into a `Canvas`, so there is no accessibility
    /// element per orb and there must not be one — an orb is a moving target
    /// that lives for seconds, and a rotor filling with and emptying of them
    /// would be worse than useless (see `WorldView`'s note on R-A11Y B1). The
    /// field is one direct-interaction region instead, so anything that has to
    /// be SAID about the field has to be said here, in its label.
    ///
    /// The animal is the one thing on the glass that earns a mention: it is
    /// deliberately awkward to reach for a while, and someone who cannot see
    /// it keeping to the edges should be told what is there and that it comes
    /// out — in the same lowercase-calm voice, and never as a warning.
    var fieldAccessibilityLabel: String {
        guard let animal = sim.animalOnField else { return Strings.fieldA11y }
        return "\(Strings.fieldA11y), and \(animal.accessibilityLabel)"
    }

    private func handleCleared() {
        closingVerse = verses.next()
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

        scheduleOnward()
    }

    /// Travels up to the sky a beat after the done card, then — only if the
    /// way ahead is unambiguous — steps onto the next stone and back down.
    private func scheduleOnward() {
        onwardWork?.cancel()
        let rise = DispatchWorkItem { [weak self] in
            guard let self, self.sim.completed else { return }
            self.skyRequest += 1
            self.scheduleStepOnward()
        }
        onwardWork = rise
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.onwardToSkyDelay,
                                      execute: rise)
    }

    private func scheduleStepOnward() {
        guard let here = map.activeStone else { return }
        let ahead = map.roads(from: here.id)
        // A fork is hers. The sequence ends here, in the sky, with the roads
        // lit — which is exactly the moment the map is worth looking at.
        guard ahead.count == 1, let next = ahead.first else { return }

        let step = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.map.setActive(next.id)
            self.restart()
            self.fieldRequest += 1
        }
        onwardWork = step
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.onwardInSkyPause,
                                      execute: step)
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
        // R-A11Y C3. NO TIMED DISAPPEARANCE WHILE AN ASSISTIVE TECHNOLOGY IS
        // RUNNING. This project already states the principle, in `Strings`,
        // about the `begin again` hold: "a timed disarm would exclude Switch
        // Control users exactly the way a timed hold does (04 §6)." A fortune
        // that removes itself after 3.6 s is the same thing — VoiceOver does
        // not finish speaking a full sentence in that time at the default
        // rate, so she loses it mid-word, every time, with no way back.
        //
        // On the world path there is nothing to dismiss any more — the
        // fortune is a `FortuneWhisper` that blocks nothing and leaves on its
        // own — so under an assistive technology it simply stays until the
        // next one, which is the reading time a screen reader needs and costs
        // her nothing, because it was never in her way.
        guard !AssistiveTechMonitor.shared.isRunning else { return }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.4)) { self?.showFortune = false }
        }
        fortuneDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.fortuneDisplayDuration, execute: work)
    }
}
