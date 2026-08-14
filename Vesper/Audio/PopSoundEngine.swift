import AVFoundation

// Synthesizes every sound in the game — no audio assets. Pop buffers are
// pre-rendered at init (8 pitch buckets × 3 detuned variants) so playback is
// just scheduling: no per-tap synthesis on the main thread, ~zero latency.
// A pool of player nodes lets chain reactions overlap instead of cutting
// each other off. Sound is a nice-to-have throughout: every failure path
// degrades to silence, never to a crash.
final class PopSoundEngine {
    static let shared = PopSoundEngine()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sampleRate = 44100.0
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0

    private let pitchBuckets = 8
    private let variantsPerBucket = 3
    private var popBuffers: [[AVAudioPCMBuffer]] = []
    private var chimeBuffer: AVAudioPCMBuffer?

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        for _ in 0..<10 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        renderBuffers()
        configureSession()
        observeInterruptions()
        ensureRunning()
    }

    // Touching .shared from onAppear does the real work; this just gives the
    // call site a name.
    func warmUp() {}

    // MARK: - Playback

    // pitch: 0 = large/deep orb, 1 = small/bright orb
    func playPop(pitch: Double) {
        guard SettingsStore.shared.soundEnabled else { return }
        ensureRunning()
        guard engine.isRunning, !popBuffers.isEmpty else { return }
        let clamped = min(1, max(0, pitch))
        let bucket = Int((clamped * Double(pitchBuckets - 1)).rounded())
        guard let buffer = popBuffers[bucket].randomElement() else { return }
        play(buffer)
    }

    func playCompletionChime() {
        guard SettingsStore.shared.soundEnabled else { return }
        ensureRunning()
        guard engine.isRunning, let chimeBuffer else { return }
        play(chimeBuffer)
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        let node = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }

    // MARK: - Lifecycle

    func setActive(_ active: Bool) {
        if active {
            try? AVAudioSession.sharedInstance().setActive(true)
            ensureRunning()
        } else {
            engine.pause()
        }
    }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended {
                try? AVAudioSession.sharedInstance().setActive(true)
                self.ensureRunning()
            }
        }
    }

    private func ensureRunning() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    // MARK: - Synthesis

    private func renderBuffers() {
        popBuffers = (0..<pitchBuckets).map { bucket in
            let pitch = Double(bucket) / Double(pitchBuckets - 1)
            return (0..<variantsPerBucket).compactMap { _ in
                makePopBuffer(pitch: pitch, detune: Double.random(in: -12...12))
            }
        }
        chimeBuffer = makeChimeBuffer()
    }

    private func makePopBuffer(pitch: Double, detune: Double) -> AVAudioPCMBuffer? {
        let duration = 0.14
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let startFreq = 460.0 + pitch * 420.0 + detune
        let endFreq = startFreq * 0.55
        let channel = buffer.floatChannelData![0]

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let progress = t / duration
            let freq = startFreq + (endFreq - startFreq) * progress
            let phase = 2.0 * .pi * freq * t
            let attack = sin(min(1, progress * 40) * .pi / 2)
            let decay = exp(-progress * 7.5)
            channel[frame] = Float(sin(phase) * attack * decay * 0.5)
        }
        return buffer
    }

    // A soft C5–E5–G5 arpeggio for clearing the field: quiet, round, brief.
    private func makeChimeBuffer() -> AVAudioPCMBuffer? {
        let duration = 1.8
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]

        let notes: [(freq: Double, start: Double)] = [
            (523.25, 0.0), (659.25, 0.28), (783.99, 0.56)
        ]
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            var sample = 0.0
            for note in notes where t >= note.start {
                let nt = t - note.start
                let attack = min(1, nt * 30)
                let decay = exp(-nt * 2.6)
                sample += sin(2.0 * .pi * note.freq * nt) * attack * decay * 0.12
            }
            channel[frame] = Float(sample)
        }
        return buffer
    }
}
