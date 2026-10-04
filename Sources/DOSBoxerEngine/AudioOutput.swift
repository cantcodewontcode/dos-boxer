import AVFAudio
import CDOSBoxerHost

/// Plays the emulator's mixer output through AVAudioEngine (in the engine
/// process, so sound never has to cross over to the app).
///
/// A source node pulls audio straight from the core on the real-time audio
/// thread, so there's no extra buffering or locking on the Swift side.
final class AudioOutput {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    /// Interleaved scratch space for the core; allocated once, used only on
    /// the audio thread.
    private static let maxFramesPerPull = 4096
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: maxFramesPerPull * 2)

    init() {
        scratch.initialize(repeating: 0, count: Self.maxFramesPerPull * 2)
    }

    deinit {
        scratch.deallocate()
    }

    func start() {
        if sourceNode == nil {
            let sampleRate = Double(dbx_audio_sample_rate())
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                              channels: 2) else { return }
            let scratch = self.scratch
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
                Self.render(into: bufferList, frameCount: Int(frameCount), scratch: scratch)
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            sourceNode = node
        }
        do {
            try engine.start()
        } catch {
            print("DOS Boxer: couldn't start audio: \(error)")
        }
    }

    /// 0 (silent) to 1 (full).
    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    func stop() {
        engine.pause()
    }

    /// Pulls interleaved frames from the core and splits them into the
    /// engine's separate left/right buffers. Real-time safe.
    private static func render(into bufferList: UnsafeMutablePointer<AudioBufferList>,
                               frameCount: Int,
                               scratch: UnsafeMutablePointer<Float>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard buffers.count == 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        var done = 0
        while done < frameCount {
            let chunk = min(frameCount - done, maxFramesPerPull)
            dbx_pull_audio(scratch, Int32(chunk))
            for i in 0..<chunk {
                left[done + i] = scratch[2 * i]
                right[done + i] = scratch[2 * i + 1]
            }
            done += chunk
        }
    }
}
