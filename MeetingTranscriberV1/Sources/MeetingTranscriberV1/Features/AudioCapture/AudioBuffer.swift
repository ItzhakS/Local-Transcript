import Foundation

/// Represents a buffer of audio samples with metadata
struct AudioBuffer: Sendable {
    /// PCM audio samples as Float values (typically -1.0 to 1.0)
    let samples: [Float]
    
    /// Sample rate in Hz (should be 16000 for Whisper compatibility)
    let sampleRate: Int
    
    /// Timestamp when this buffer was captured
    let timestamp: Date
    
    /// Source of the audio (system or microphone)
    let source: AudioSource
    
    /// Audio source type
    enum AudioSource: Sendable {
        /// System audio from ScreenCaptureKit (others' audio)
        case system
        
        /// Microphone audio from AVAudioEngine (user's audio)
        case microphone
    }
    
    /// Duration of the audio buffer in seconds
    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / Double(sampleRate)
    }
    
    /// Create an audio buffer
    init(samples: [Float], sampleRate: Int, timestamp: Date = Date(), source: AudioSource) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestamp = timestamp
        self.source = source
    }
}

/// Represents an audio chunk with speaker labeling
struct LabeledAudioChunk: Sendable {
    /// The underlying audio buffer
    let buffer: AudioBuffer
    
    /// Speaker label (e.g., "Me" for microphone, "Others" for system audio)
    let speakerLabel: String
    
    /// Create a labeled audio chunk
    init(buffer: AudioBuffer, speakerLabel: String) {
        self.buffer = buffer
        self.speakerLabel = speakerLabel
    }
    
    /// Convenience initializer from buffer with automatic labeling
    init(buffer: AudioBuffer) {
        self.buffer = buffer
        self.speakerLabel = buffer.source == .microphone ? "Me" : "Others"
    }
}

