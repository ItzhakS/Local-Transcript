import Foundation
import FluidAudio

/// Represents a speaker segment with timing and speaker ID
struct SpeakerSegment: Sendable {
    let start: Double
    let end: Double
    let speakerId: String  // FluidAudio uses String IDs
    
    var duration: Double {
        end - start
    }
    
    /// Numeric speaker ID extracted from the string ID
    var numericSpeakerId: Int {
        // FluidAudio returns IDs like "SPEAKER_0", "SPEAKER_1", etc.
        // Extract the numeric part
        if let lastPart = speakerId.split(separator: "_").last,
           let num = Int(lastPart) {
            return num
        }
        // Fallback: hash the string to get a consistent number
        return abs(speakerId.hashValue) % 100
    }
}

/// Actor-based wrapper around FluidAudio DiarizerManager for speaker identification
actor FluidAudioDiarizer {
    
    // MARK: - Properties
    
    /// Online diarizer for real-time processing
    private var onlineDiarizer: DiarizerManager?
    
    /// Offline diarizer for higher accuracy refinement
    private var offlineDiarizer: OfflineDiarizerManager?
    
    /// Whether the diarizer is currently loaded and ready
    private(set) var isLoaded = false
    
    /// Accumulated audio for offline refinement
    private var accumulatedAudio: [Float] = []
    
    /// Sample rate (FluidAudio expects 16kHz)
    private let sampleRate: Int = 16000
    
    /// Track the cumulative time offset for segment timestamps
    private var cumulativeTimeOffset: Double = 0
    
    // MARK: - Initialization
    
    init() {
        Log.diarization.info("FluidAudioDiarizer initialized")
    }
    
    // MARK: - Lifecycle
    
    /// Start the diarization system and load models
    func start() async throws {
        guard !isLoaded else {
            Log.diarization.warning("Diarizer already started")
            return
        }
        
        Log.diarization.info("Starting diarization system...")
        
        do {
            // Initialize online diarizer for real-time processing
            let diarizer = DiarizerManager()
            
            // Load models (FluidAudio auto-downloads from HuggingFace)
            let models = try await DiarizerModels.load()
            diarizer.initialize(models: models)
            
            onlineDiarizer = diarizer
            Log.diarization.info("Online diarizer loaded successfully")
            
            // Initialize offline diarizer for refinement (lazy load on first use)
            // offlineDiarizer will be created when refinement is requested
            
            accumulatedAudio = []
            cumulativeTimeOffset = 0
            isLoaded = true
            
            Log.diarization.info("Diarization system started")
        } catch {
            Log.diarization.error("Failed to load diarization models: \(error.localizedDescription, privacy: .public)")
            throw AppError.diarizationError("Failed to load diarization models: \(error.localizedDescription)")
        }
    }
    
    /// Stop the diarization system and release resources
    func stop() async {
        Log.diarization.info("Stopping diarization system...")
        
        onlineDiarizer?.cleanup()
        onlineDiarizer = nil
        offlineDiarizer = nil
        accumulatedAudio = []
        cumulativeTimeOffset = 0
        isLoaded = false
        
        Log.diarization.info("Diarization system stopped")
    }
    
    // MARK: - Online Diarization
    
    /// Process an audio buffer and return speaker segments (online/real-time mode)
    /// - Parameter buffer: The audio buffer to process
    /// - Returns: Array of speaker segments with timing and speaker IDs
    func diarizeSystemAudio(_ buffer: AudioBuffer) async throws -> [SpeakerSegment] {
        guard isLoaded, let diarizer = onlineDiarizer else {
            Log.diarization.warning("Diarizer not loaded, returning empty segments")
            return []
        }
        
        let samples = buffer.samples
        guard !samples.isEmpty else {
            return []
        }
        
        let chunkDuration = Double(samples.count) / Double(sampleRate)
        
        Log.diarization.debug("Processing \(samples.count) samples for diarization (\(String(format: "%.2f", chunkDuration))s)")
        
        do {
            // FluidAudio DiarizerManager.performCompleteDiarization returns DiarizationResult
            let result = try diarizer.performCompleteDiarization(
                samples,
                sampleRate: sampleRate,
                atTime: cumulativeTimeOffset
            )
            
            // Convert TimedSpeakerSegment to our SpeakerSegment type
            let segments = result.segments.map { segment in
                SpeakerSegment(
                    start: Double(segment.startTimeSeconds),
                    end: Double(segment.endTimeSeconds),
                    speakerId: segment.speakerId
                )
            }
            
            // Update cumulative time offset for next chunk
            cumulativeTimeOffset += chunkDuration
            
            // Accumulate audio for potential offline refinement
            accumulatedAudio.append(contentsOf: samples)
            
            Log.diarization.debug("Diarization complete: \(segments.count) segments found")
            
            return segments
        } catch {
            Log.diarization.error("Diarization failed: \(error.localizedDescription, privacy: .public)")
            // Return empty segments on error - fallback to "Others" label
            return []
        }
    }
    
    /// Process an audio chunk and return the dominant speaker for the chunk
    /// This is a convenience method for simpler integration
    /// - Parameter buffer: The audio buffer to process
    /// - Returns: The numeric speaker ID, or nil if no speaker detected
    func getDominantSpeaker(for buffer: AudioBuffer) async throws -> Int? {
        let segments = try await diarizeSystemAudio(buffer)
        
        guard !segments.isEmpty else {
            return nil
        }
        
        // Find the speaker with the most speaking time in this chunk
        var speakerDurations: [String: Double] = [:]
        for segment in segments {
            speakerDurations[segment.speakerId, default: 0] += segment.duration
        }
        
        // Get the dominant speaker string ID and convert to numeric
        if let dominantSpeakerId = speakerDurations.max(by: { $0.value < $1.value })?.key {
            // Return numeric ID for the SpeakerIdentifier
            let segment = segments.first { $0.speakerId == dominantSpeakerId }
            return segment?.numericSpeakerId
        }
        
        return nil
    }
    
    // MARK: - Offline Refinement
    
    /// Perform offline refinement on accumulated audio for higher accuracy
    /// - Returns: Refined speaker segments for the entire recording
    func refineOffline() async throws -> [SpeakerSegment] {
        guard !accumulatedAudio.isEmpty else {
            Log.diarization.warning("No accumulated audio for offline refinement")
            return []
        }
        
        Log.diarization.info("Starting offline refinement on \(self.accumulatedAudio.count) samples...")
        
        do {
            // Lazy-load offline diarizer
            if offlineDiarizer == nil {
                Log.diarization.info("Loading offline diarizer...")
                let diarizer = OfflineDiarizerManager()
                try await diarizer.prepareModels()
                offlineDiarizer = diarizer
                Log.diarization.info("Offline diarizer loaded")
            }
            
            guard let diarizer = offlineDiarizer else {
                throw AppError.diarizationError("Failed to initialize offline diarizer")
            }
            
            // Run offline diarization on the complete audio
            let result = try await diarizer.process(audio: self.accumulatedAudio)
            
            let segments = result.segments.map { segment in
                SpeakerSegment(
                    start: Double(segment.startTimeSeconds),
                    end: Double(segment.endTimeSeconds),
                    speakerId: segment.speakerId
                )
            }
            
            Log.diarization.info("Offline refinement complete: \(segments.count) segments")
            
            return segments
        } catch {
            Log.diarization.error("Offline refinement failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.diarizationError("Offline refinement failed: \(error.localizedDescription)")
        }
    }
    
    /// Get the total accumulated audio duration
    var accumulatedDuration: Double {
        Double(accumulatedAudio.count) / Double(sampleRate)
    }
    
    /// Clear accumulated audio (call after offline refinement if needed)
    func clearAccumulatedAudio() {
        accumulatedAudio = []
        cumulativeTimeOffset = 0
        Log.diarization.debug("Accumulated audio cleared")
    }
}
