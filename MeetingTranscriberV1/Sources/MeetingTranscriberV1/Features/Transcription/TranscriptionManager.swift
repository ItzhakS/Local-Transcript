import Foundation
import FluidAudio

/// Orchestrates transcription of audio streams with buffering, VAD, and speaker diarization
@MainActor
class TranscriptionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current transcript entries
    @Published private(set) var transcriptEntries: [TranscriptEntry] = []
    
    /// Whether transcription is currently active
    @Published private(set) var isTranscribing = false
    
    /// Active speakers (from diarization)
    @Published private(set) var activeSpeakers: [Int: String] = [:]
    
    // MARK: - Private Properties
    
    private let fluidAudioEngine: FluidAudioEngine
    private var pendingTasks: Set<Task<Void, Never>> = []
    
    // Diarization components
    private var diarizer: FluidAudioDiarizer?
    private let speakerIdentifier = SpeakerIdentifier()
    private var isDiarizationEnabled = true
    
    // Audio buffering (separate buffers for each speaker to avoid flickering flushes)
    private var accumulators: [String: [Float]] = [:]
    private var lastChunkTimes: [String: Date] = [:]
    private var lastSpeechTimes: [String: Date] = [:] // Track last time we actually heard speech
    private var speechDetectedInCurrentBuffer: [String: Bool] = [:] // Track if speech was heard since last flush
    /// Soft upper bound for how long we let a single continuous segment grow before forcing a flush.
    /// We keep this relatively high so that, in normal conversations, segments end on real pauses,
    /// not arbitrary time limits.
    private let maxSegmentDuration: TimeInterval = 15.0
    /// How long of silence we wait before deciding a sentence/segment has ended.
    private let silenceTimeout: TimeInterval = 1.5  // Flush buffer after 1.5s of silence
    private let overlapDuration: TimeInterval = 0.5 // Keep 500ms of overlap between continuous flushes
    private let sampleRate: Int = 16000
    
    // VAD (Voice Activity Detection) parameters
    private let energyThreshold: Float = 1e-6  // Minimum energy to consider as speech (fallback when FluidAudio VAD unavailable)
    
    // FluidAudio VAD (Silero) - optional; falls back to energy-based if load fails
    private var vadManager: VadManager?
    private var vadBuffers: [String: [Float]] = [:]
    private let vadChunkSize = 4096  // VadManager.chunkSize (256ms at 16kHz)
    
    // MARK: - Initialization
    
    init(modelVersion: AsrModelVersion = .v3, diarizer: FluidAudioDiarizer? = nil) {
        self.fluidAudioEngine = FluidAudioEngine(modelVersion: modelVersion)
        self.diarizer = diarizer
        Log.transcription.info("TranscriptionManager initialized with FluidAudio model version: \(modelVersion == .v3 ? "v3" : "v2", privacy: .public), diarization: \(diarizer != nil)")
    }
    
    /// Set the diarizer after initialization
    func setDiarizer(_ diarizer: FluidAudioDiarizer?) {
        self.diarizer = diarizer
        Log.transcription.info("Diarizer \(diarizer != nil ? "enabled" : "disabled")")
    }
    
    /// Enable or disable diarization
    func setDiarizationEnabled(_ enabled: Bool) {
        isDiarizationEnabled = enabled
        Log.transcription.info("Diarization \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Lifecycle
    
    /// Start transcription system
    func start() async throws {
        guard !isTranscribing else {
            Log.transcription.warning("Transcription already started")
            return
        }
        
        Log.transcription.info("Starting transcription system...")
        
        // Load the FluidAudio ASR model
        try await fluidAudioEngine.loadModel()
        
        // Load FluidAudio VAD (Silero); fall back to energy-based if load fails
        do {
            vadManager = try await VadManager()
            Log.transcription.info("FluidAudio VAD loaded successfully")
        } catch {
            Log.transcription.warning("Failed to load FluidAudio VAD, using energy-based detection: \(error.localizedDescription, privacy: .public)")
            vadManager = nil
        }
        
        // Start diarization if available
        if let diarizer = diarizer, isDiarizationEnabled {
            do {
                try await diarizer.start()
                Log.transcription.info("Diarization started successfully")
            } catch {
                Log.transcription.error("Failed to start diarization, falling back to 'Others' label: \(error.localizedDescription, privacy: .public)")
                Log.transcription.error("Diarization error details: \(String(describing: error), privacy: .public)")
                // Continue without diarization - will fall back to "Others" label
                // Disable diarization for this session to avoid repeated errors
                isDiarizationEnabled = false
            }
        } else {
            if diarizer == nil {
                Log.transcription.warning("No diarizer available - all speakers will be labeled 'Others'")
            } else if !isDiarizationEnabled {
                Log.transcription.info("Diarization is disabled - all speakers will be labeled 'Others'")
            }
        }
        
        // Reset speaker identifier for new recording
        await speakerIdentifier.reset()
        
        // Reset state
        accumulators = [:]
        lastChunkTimes = [:]
        lastSpeechTimes = [:]
        speechDetectedInCurrentBuffer = [:]
        vadBuffers = [:]
        transcriptEntries = []
        activeSpeakers = [:]
        
        isTranscribing = true
        Log.transcription.info("Transcription system started")
    }
    
    /// Stop transcription system
    func stop() async {
        guard isTranscribing else {
            Log.transcription.warning("Transcription not active")
            return
        }
        
        Log.transcription.info("Stopping transcription system...")
        
        // Flush all remaining audio first (without overlap)
        for speaker in accumulators.keys {
            await flushBuffer(for: speaker, keepOverlap: false)
        }
        
        // Wait for all pending transcription tasks to complete
        Log.transcription.debug("Waiting for \(self.pendingTasks.count) pending transcription tasks...")
        while !pendingTasks.isEmpty {
            let tasksToWait = Array(pendingTasks)
            for task in tasksToWait {
                _ = await task.result
            }
        }
        Log.transcription.debug("All pending tasks completed")
        
        // Stop diarization
        if let diarizer = diarizer {
            await diarizer.stop()
            Log.transcription.info("Diarization stopped")
        }
        
        vadBuffers = [:]
        isTranscribing = false
        Log.transcription.info("Transcription system stopped")
    }
    
    /// Perform offline refinement of speaker labels (optional, call after recording stops)
    func refineOfflineDiarization() async {
        guard let diarizer = diarizer else {
            Log.transcription.warning("No diarizer available for offline refinement")
            return
        }
        
        Log.transcription.info("Starting offline diarization refinement...")
        
        do {
            let refinedSegments = try await diarizer.refineOffline()
            
            // Update speaker labels based on refined segments
            await speakerIdentifier.updateFromSegments(refinedSegments)
            
            // Update active speakers
            activeSpeakers = await speakerIdentifier.getActiveSpeakers()
            
            Log.transcription.info("Offline refinement complete with \(refinedSegments.count) segments")
            
            // Note: To fully update transcript entries with refined labels,
            // you would need to re-process the segments and match them with existing entries.
            // This is a more complex operation that could be added in a future enhancement.
            
        } catch {
            Log.transcription.error("Offline refinement failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Audio Processing
    
    /// Process incoming labeled audio chunk
    func processAudioChunk(_ chunk: LabeledAudioChunk) async {
        guard isTranscribing else {
            Log.transcription.debug("Skipping audio chunk - transcription not active")
            return
        }
        
        var speaker = chunk.speakerLabel
        let now = Date()
        
        // Initialize state for speaker if needed
        if accumulators[speaker] == nil {
            accumulators[speaker] = []
            lastSpeechTimes[speaker] = now
            speechDetectedInCurrentBuffer[speaker] = false
        }
        
        // ALWAYS accumulate audio. Whisper needs silence for context, 
        // and we were previously "chopping" the audio by skipping non-speech chunks.
        accumulators[speaker, default: []].append(contentsOf: chunk.buffer.samples)
        lastChunkTimes[speaker] = now
        
        // Note: Diarization will be run on accumulated buffers when flushing (see flushBuffer method)
        // This ensures we have enough audio (1-5 seconds) for diarization to work effectively
        
        // Detect if THIS chunk contains speech (FluidAudio VAD when available, else energy-based)
        let hasSpeech = await detectSpeechWithVad(samples: chunk.buffer.samples, speaker: speaker)
        if hasSpeech {
            lastSpeechTimes[speaker] = now
            speechDetectedInCurrentBuffer[speaker] = true
        }
        
        // Check for silence timeout (no speech for X seconds)
        let silenceDuration = now.timeIntervalSince(lastSpeechTimes[speaker] ?? now)
        let silenceDetected = silenceDuration > silenceTimeout
        
        let accumulatedDuration = Double(accumulators[speaker]?.count ?? 0) / Double(sampleRate)
        
        // Flush logic
        if silenceDetected && accumulatedDuration >= 1.0 {
            // End of sentence/speech segment - flush everything at a natural pause
            Log.transcription.debug("Flushing buffer for \(speaker, privacy: .public) due to silence")
            await flushBuffer(for: speaker, keepOverlap: false)
            lastSpeechTimes[speaker] = now // Reset silence timer after flush
        } else if accumulatedDuration >= maxSegmentDuration {
            // Extremely long continuous speech with no pause - force a flush with overlap
            // This is a safety valve; in normal scenarios we prefer the silence-based path above.
            Log.transcription.debug("Max segment duration reached for \(speaker, privacy: .public), flushing with overlap")
            await flushBuffer(for: speaker, keepOverlap: true)
        }
    }
    
    /// Detect if audio contains speech using FluidAudio VAD when available, else energy-based fallback.
    /// Buffers samples per speaker until we have 4096 (256ms), then runs VadManager.process().
    private func detectSpeechWithVad(samples: [Float], speaker: String) async -> Bool {
        // Append to per-speaker VAD buffer
        vadBuffers[speaker, default: []].append(contentsOf: samples)
        
        guard let vad = vadManager else {
            return detectSpeech(in: samples)
        }
        
        // Process when we have at least one full chunk
        guard (vadBuffers[speaker]?.count ?? 0) >= vadChunkSize else {
            return detectSpeech(in: samples)
        }
        
        let buffer = vadBuffers[speaker]!
        let toProcess = Array(buffer.prefix(vadChunkSize))
        let remainder = Array(buffer.dropFirst(vadChunkSize))
        vadBuffers[speaker] = remainder.isEmpty ? nil : remainder
        
        do {
            let results = try await vad.process(toProcess)
            let hasSpeech = results.contains { $0.isVoiceActive }
            return hasSpeech
        } catch {
            Log.transcription.warning("VAD process failed, using energy-based fallback: \(error.localizedDescription, privacy: .public)")
            return detectSpeech(in: samples)
        }
    }
    
    /// Energy-based VAD fallback when FluidAudio VAD is unavailable or fails
    private func detectSpeech(in samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        
        // Calculate RMS energy
        let energy = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        
        return energy > energyThreshold
    }
    
    /// Flush accumulated audio buffer for a specific speaker to transcription
    private func flushBuffer(for speaker: String, keepOverlap: Bool) async {
        guard let samples = accumulators[speaker], !samples.isEmpty else {
            return
        }
        
        // For "Others" buffers, run diarization on the accumulated audio before flushing
        // This gives us enough audio (1-5 seconds) for diarization to work
        var finalSpeaker = speaker
        if speaker == "Others" && isDiarizationEnabled, let diarizer = diarizer {
            let accumulatedDuration = Double(samples.count) / Double(sampleRate)
            
            // Only run diarization if we have at least 1 second of audio
            if accumulatedDuration >= 1.0 {
                do {
                    // Create a buffer from accumulated audio for diarization
                    let accumulatedBuffer = AudioBuffer(
                        samples: samples,
                        sampleRate: sampleRate,
                        timestamp: Date(),
                        source: .system
                    )
                    
                    let segments = try await diarizer.diarizeSystemAudio(accumulatedBuffer)
                    
                    if segments.isEmpty {
                        Log.diarization.debug("No speaker segments found in accumulated buffer (samples: \(samples.count), duration: \(String(format: "%.2f", accumulatedDuration))s)")
                    } else {
                        Log.diarization.info("Found \(segments.count) speaker segments in accumulated buffer (\(String(format: "%.2f", accumulatedDuration))s)")
                        
                        // Find the speaker with the most speaking time in this accumulated segment
                        var speakerDurations: [Int: Double] = [:]
                        for segment in segments {
                            let numericId = segment.numericSpeakerId
                            speakerDurations[numericId, default: 0] += segment.duration
                        }
                        
                        // Get the dominant speaker
                        if let (speakerId, duration) = speakerDurations.max(by: { $0.value < $1.value }) {
                            // Get speaker label from identifier
                            finalSpeaker = await speakerIdentifier.getLabel(for: speakerId)
                            
                            // Update speaker activity from all segments
                            await speakerIdentifier.updateFromSegments(segments)
                            
                            // Update active speakers list
                            activeSpeakers = await speakerIdentifier.getActiveSpeakers()
                            
                            Log.diarization.info("Identified speaker \(speakerId) -> '\(finalSpeaker, privacy: .public)' (duration: \(String(format: "%.2f", duration))s) from \(String(format: "%.2f", accumulatedDuration))s buffer")
                            
                            // If we identified a specific speaker, transfer the accumulator
                            if finalSpeaker != "Others" {
                                accumulators[finalSpeaker] = samples
                                accumulators.removeValue(forKey: "Others")
                                
                                // Transfer state
                                if let lastSpeech = lastSpeechTimes["Others"] {
                                    lastSpeechTimes[finalSpeaker] = lastSpeech
                                    lastSpeechTimes.removeValue(forKey: "Others")
                                }
                                if let speechDetected = speechDetectedInCurrentBuffer["Others"] {
                                    speechDetectedInCurrentBuffer[finalSpeaker] = speechDetected
                                    speechDetectedInCurrentBuffer.removeValue(forKey: "Others")
                                }
                            }
                        }
                    }
                } catch {
                    Log.diarization.error("Diarization failed on accumulated buffer, using 'Others' label: \(error.localizedDescription, privacy: .public)")
                    // Fall back to "Others" on error
                }
            }
        }
        
        // Use the final speaker (may have been updated by diarization)
        let finalSamples = accumulators[finalSpeaker] ?? samples
        let hasSpeech = speechDetectedInCurrentBuffer[finalSpeaker] ?? speechDetectedInCurrentBuffer[speaker] ?? false
        
        // If no speech was detected in this entire window, just clear/overlap and exit
        guard hasSpeech else {
            if keepOverlap {
                // Keep the tail for continuity even if it was silent
                let overlapSamplesCount = Int(overlapDuration * Double(sampleRate))
                if samples.count > overlapSamplesCount {
                    accumulators[speaker] = Array(samples.suffix(overlapSamplesCount))
                }
            } else {
                accumulators[speaker] = []
            }
            return
        }
        
        // Reset speech flag for the next segment
        speechDetectedInCurrentBuffer[finalSpeaker] = false
        
        let duration = Double(finalSamples.count) / Double(sampleRate)
        
        // Minimum duration for FluidAudio AsrManager is 1.0 second (16,000 samples)
        guard duration >= 1.0 else {
            // If we're not keeping overlap, clear it anyway
            if !keepOverlap {
                accumulators[finalSpeaker] = []
            }
            return
        }
        
        Log.transcription.info("Flushing buffer: \(finalSamples.count) samples (\(String(format: "%.2f", duration), privacy: .public)s) from \(finalSpeaker, privacy: .public)")
        
        // Determine audio source - "Me" is microphone, everything else is system
        let audioSource: AudioBuffer.AudioSource = finalSpeaker == "Me" ? .microphone : .system
        
        // Create audio buffer for transcription
        let audioBuffer = AudioBuffer(
            samples: finalSamples,
            sampleRate: sampleRate,
            timestamp: Date(),
            source: audioSource
        )
        
        // Handle overlap/cleanup
        if keepOverlap {
            // Keep the tail of the audio to prepend to the next chunk
            let overlapSamplesCount = Int(overlapDuration * Double(sampleRate))
            if finalSamples.count > overlapSamplesCount {
                accumulators[finalSpeaker] = Array(finalSamples.suffix(overlapSamplesCount))
                Log.transcription.debug("Kept \(overlapSamplesCount) samples for overlap")
            } else {
                accumulators[finalSpeaker] = finalSamples // Keep all if shorter than overlap
            }
        } else {
            // Clean break
            accumulators[finalSpeaker] = []
        }
        
        // Transcribe in background
        let task = Task {
            await transcribeBuffer(audioBuffer, speaker: finalSpeaker)
        }
        
        pendingTasks.insert(task)
        
        Task {
            _ = await task.result
            pendingTasks.remove(task)
        }
    }
    
    /// Transcribe an audio buffer and add to transcript
    private func transcribeBuffer(_ buffer: AudioBuffer, speaker: String) async {
        do {
            let result = try await fluidAudioEngine.transcribe(buffer)
            
            // Only add non-empty transcriptions
            guard !result.isEmpty else {
                Log.transcription.debug("Skipping empty transcription result")
                return
            }
            
            // Filter out empty or punctuation-only text (Parakeet TDT may produce these)
            if result.text.trimmingCharacters(in: .punctuationCharacters).isEmpty {
                Log.transcription.debug("Filtering empty/punctuation-only text from \(speaker, privacy: .public): \"\(result.text, privacy: .public)\"")
                return
            }
            
            // Reconcile text overlap to prevent duplication in the UI
            var finalResultText = result.text
            
            // Find the last entry from the SAME speaker to check for overlap
            // We only do this on the MainActor since transcriptEntries is @Published
            await MainActor.run {
                if let lastEntry = transcriptEntries.last(where: { $0.speaker == speaker }) {
                    // If the segments are close in time, reconcile them.
                    // Use maxSegmentDuration as an upper bound for how far apart two chunks
                    // can be while still being considered part of the same logical segment.
                    let timeGap = result.timestamp.timeIntervalSince(lastEntry.timestamp)
                    if timeGap < (maxSegmentDuration + 2.0) {
                        finalResultText = reconcile(newText: result.text, with: lastEntry.text)
                    }
                }
                
                // Only add if we still have text after reconciliation
                guard !finalResultText.isEmpty else {
                    Log.transcription.debug("Skipping duplicate/overlapping text from \(speaker, privacy: .public)")
                    return
                }
                
                // Create transcript entry
                let entry = TranscriptEntry(
                    text: finalResultText,
                    speaker: speaker,
                    timestamp: result.timestamp,
                    confidence: result.confidence
                )
                
                // Add to transcript
                transcriptEntries.append(entry)
                Log.transcription.info("Added transcript entry: \(speaker, privacy: .public): \"\(finalResultText, privacy: .public)\"")
            }
            
        } catch {
            Log.transcription.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Reconciles text overlap between segments to prevent duplication.
    /// This looks for shared words at the boundary of two segments.
    private func reconcile(newText: String, with previousText: String) -> String {
        // Clean words for comparison (remove punctuation, lowercase)
        func cleanWords(_ text: String) -> [String] {
            text.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
        }
        
        let newWordsClean = cleanWords(newText)
        let prevWordsClean = cleanWords(previousText)
        
        // We look for a match in the last 12 words of the previous segment
        // and the first 12 words of the new segment
        let lookbackCount = min(12, prevWordsClean.count)
        let lookaheadCount = min(12, newWordsClean.count)
        
        guard lookbackCount > 0 && lookaheadCount > 0 else { return newText }
        
        // Try to find the longest matching sequence of words at the boundary
        for length in (1...min(lookbackCount, lookaheadCount)).reversed() {
            let suffix = prevWordsClean.suffix(length)
            let prefix = newWordsClean.prefix(length)
            
            if Array(suffix) == Array(prefix) {
                // Found a match! Reconstruct the new text without the overlap
                let originalNewWords = newText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                
                // If it's a perfect match of the whole segment, it's a duplicate
                if originalNewWords.count <= length {
                    return ""
                }
                
                let reconciledWords = originalNewWords.dropFirst(length)
                return reconciledWords.joined(separator: " ")
            }
        }
        
        return newText
    }
    
    /// Clear all transcript entries
    func clearTranscript() {
        transcriptEntries.removeAll()
        Log.transcription.info("Transcript cleared")
    }
    
    /// Get the full transcript as a single string
    func getFullTranscript() -> String {
        transcriptEntries.map { "[\($0.speaker)] \($0.text)" }.joined(separator: "\n")
    }
}

// MARK: - TranscriptEntry

/// Represents a single entry in the transcript
struct TranscriptEntry: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let speaker: String
    let timestamp: Date
    let confidence: Double
    
    /// Formatted timestamp string
    var timestampString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: timestamp)
    }
}

