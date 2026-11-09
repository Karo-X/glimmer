import AVFoundation

/// Erzeugt einen auf- und abschwellenden Sirenenton.
final class Siren {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?

    func start(gain: Float) {
        guard source == nil else { return }
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48000
        var phase = 0.0
        var sweep = 0.0
        let node = AVAudioSourceNode { _, _, frameCount, buffers -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            for frame in 0..<Int(frameCount) {
                sweep += 1.4 / sampleRate
                if sweep >= 1 { sweep -= 1 }
                let frequency = 650 + 750 * (0.5 - 0.5 * cos(2 * .pi * sweep))
                phase += 2 * .pi * frequency / sampleRate
                if phase > 2 * .pi { phase -= 2 * .pi }
                let value = Float(sin(phase) > 0 ? 1 : -1) * gain * 0.6 + Float(sin(phase)) * gain * 0.4
                for buffer in list {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
        let monoOrStereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: monoOrStereo)
        source = node
        try? engine.start()
    }

    var isRunning: Bool { engine.isRunning }

    func stop() {
        engine.stop()
        if let source {
            engine.detach(source)
        }
        source = nil
    }
}
