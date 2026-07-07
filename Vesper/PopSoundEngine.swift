import AVFoundation

// Synthesizes a soft, stress-relieving "pop" on the fly — no audio asset
// needed. A small pool of player nodes lets overlapping pops (chain
// reactions) play concurrently instead of cutting each other off.
final class PopSoundEngine {
    static let shared = PopSoundEngine()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sampleRate = 44100.0
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        for _ in 0..<10 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            // sound is a nice-to-have; a failure here shouldn't affect gameplay
        }
    }

    // pitch: 0 = large/deep orb, 1 = small/bright orb
    func playPop(pitch: Double) {
        guard engine.isRunning else { return }

        let duration = 0.14
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let clampedPitch = min(1, max(0, pitch))
        let startFreq = 460.0 + clampedPitch * 420.0 + Double.random(in: -12...12)
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

        let node = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }
}
