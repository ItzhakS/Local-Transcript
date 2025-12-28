import Foundation

/// Combines audio streams from system and microphone into labeled chunks
actor AudioMixer {
    
    private var systemTask: Task<Void, Never>?
    private var microphoneTask: Task<Void, Never>?
    private var mixedContinuation: AsyncStream<LabeledAudioChunk>.Continuation?
    private(set) var isMixing = false
    
    // MARK: - Public API
    
    /// Start mixing audio from both system and microphone sources
    /// - Parameters:
    ///   - system: Async stream of system audio buffers
    ///   - microphone: Async stream of microphone audio buffers
    /// - Returns: An async stream of labeled audio chunks
    func startMixing(
        system: AsyncStream<AudioBuffer>,
        microphone: AsyncStream<AudioBuffer>
    ) -> AsyncStream<LabeledAudioChunk> {
        Log.audio.info("Starting audio mixing")
        
        // Stop any existing mixing
        if isMixing {
            Log.audio.warning("Already mixing, stopping existing streams")
            stopMixing()
        }
        
        // Create the mixed output stream
        let mixedStream = AsyncStream<LabeledAudioChunk> { continuation in
            self.mixedContinuation = continuation
        }
        
        isMixing = true
        
        // Process system audio stream
        systemTask = Task {
            for await buffer in system {
                await processBuffer(buffer)
            }
            Log.audio.debug("System audio stream ended")
        }
        
        // Process microphone audio stream
        microphoneTask = Task {
            for await buffer in microphone {
                await processBuffer(buffer)
            }
            Log.audio.debug("Microphone audio stream ended")
        }
        
        return mixedStream
    }
    
    /// Stop mixing and clean up resources
    func stopMixing() {
        guard isMixing else {
            Log.audio.debug("Stop mixing called but not currently mixing")
            return
        }
        
        Log.audio.info("Stopping audio mixing")
        
        systemTask?.cancel()
        microphoneTask?.cancel()
        systemTask = nil
        microphoneTask = nil
        
        mixedContinuation?.finish()
        mixedContinuation = nil
        
        isMixing = false
        Log.audio.info("Audio mixing stopped")
    }
    
    // MARK: - Private Methods
    
    private func processBuffer(_ buffer: AudioBuffer) {
        // Create labeled chunk with automatic labeling based on source
        let chunk = LabeledAudioChunk(buffer: buffer)
        
        // Calculate energy to detect if it's silence (only log non-silence to reduce spam)
        let energy = buffer.samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, buffer.samples.count))
        
        if energy > 1e-6 {
            Log.audio.info("Mixed audio chunk - Source: \(chunk.speakerLabel, privacy: .public), Samples: \(buffer.samples.count), Duration: \(String(format: "%.2f", buffer.duration), privacy: .public)s, Energy: \(energy, privacy: .public) (Signal)")
        }
        
        // Send to mixed stream
        mixedContinuation?.yield(chunk)
    }
}

