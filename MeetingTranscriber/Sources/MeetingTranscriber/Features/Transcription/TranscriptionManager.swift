import Foundation

/// Orchestrates transcription of audio streams with buffering and VAD
@MainActor
class TranscriptionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current transcript entries
    @Published private(set) var transcriptEntries: [TranscriptEntry] = []
    
    /// Whether transcription is currently active
    @Published private(set) var isTranscribing = false
    
    // MARK: - Private Properties
    
    private let whisperEngine: WhisperEngine
    private var pendingTasks: Set<Task<Void, Never>> = []
    
    // Audio buffering (separate buffers for each speaker to avoid flickering flushes)
    private var accumulators: [String: [Float]] = [:]
    private var lastChunkTimes: [String: Date] = [:]
    private var lastSpeechTimes: [String: Date] = [:] // Track last time we actually heard speech
    private var speechDetectedInCurrentBuffer: [String: Bool] = [:] // Track if speech was heard since last flush
    private let bufferDuration: TimeInterval = 5.0  // Increased to 5s for better context
    private let silenceTimeout: TimeInterval = 1.5  // Flush buffer after 1.5s of silence
    private let overlapDuration: TimeInterval = 0.5 // Keep 500ms of overlap between continuous flushes
    private let sampleRate: Int = 16000
    
    // VAD (Voice Activity Detection) parameters
    private let energyThreshold: Float = 1e-6  // Minimum energy to consider as speech
    
    // MARK: - Initialization
    
    init(modelName: String = "base") {
        self.whisperEngine = WhisperEngine(modelName: modelName)
        Log.transcription.info("TranscriptionManager initialized with model: \(modelName, privacy: .public)")
    }
    
    // MARK: - Lifecycle
    
    /// Start transcription system
    func start() async throws {
        guard !isTranscribing else {
            Log.transcription.warning("Transcription already started")
            return
        }
        
        Log.transcription.info("Starting transcription system...")
        
        // Load the Whisper model
        try await whisperEngine.loadModel()
        
        // Reset state
        accumulators = [:]
        lastChunkTimes = [:]
        lastSpeechTimes = [:]
        transcriptEntries = []
        
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
        
        isTranscribing = false
        Log.transcription.info("Transcription system stopped")
    }
    
    // MARK: - Audio Processing
    
    /// Process incoming labeled audio chunk
    func processAudioChunk(_ chunk: LabeledAudioChunk) async {
        guard isTranscribing else {
            Log.transcription.debug("Skipping audio chunk - transcription not active")
            return
        }
        
        let speaker = chunk.speakerLabel
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
        
        // Detect if THIS chunk contains speech
        let hasSpeech = detectSpeech(in: chunk.buffer.samples)
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
            // End of sentence/speech segment - flush everything
            Log.transcription.debug("Flushing buffer for \(speaker, privacy: .public) due to silence")
            await flushBuffer(for: speaker, keepOverlap: false)
            lastSpeechTimes[speaker] = now // Reset silence timer after flush
        } else if accumulatedDuration >= bufferDuration {
            // Buffer full during continuous speech - flush with overlap to prevent word clipping
            Log.transcription.debug("Buffer duration threshold reached for \(speaker, privacy: .public), flushing with overlap")
            await flushBuffer(for: speaker, keepOverlap: true)
        }
    }
    
    /// Detect if audio contains speech using simple energy-based VAD
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
        
        let hasSpeech = speechDetectedInCurrentBuffer[speaker] ?? false
        
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
        speechDetectedInCurrentBuffer[speaker] = false
        
        let duration = Double(samples.count) / Double(sampleRate)
        
        // Minimum duration for Whisper to be effective is ~0.5s
        guard duration >= 0.5 else {
            // If we're not keeping overlap, clear it anyway
            if !keepOverlap {
                accumulators[speaker] = []
            }
            return
        }
        
        Log.transcription.info("Flushing buffer: \(samples.count) samples (\(String(format: "%.2f", duration), privacy: .public)s) from \(speaker, privacy: .public)")
        
        // Create audio buffer for transcription
        let audioBuffer = AudioBuffer(
            samples: samples,
            sampleRate: sampleRate,
            timestamp: Date(),
            source: speaker == "Me" ? .microphone : .system
        )
        
        // Handle overlap/cleanup
        if keepOverlap {
            // Keep the tail of the audio to prepend to the next chunk
            let overlapSamplesCount = Int(overlapDuration * Double(sampleRate))
            if samples.count > overlapSamplesCount {
                accumulators[speaker] = Array(samples.suffix(overlapSamplesCount))
                Log.transcription.debug("Kept \(overlapSamplesCount) samples for overlap")
            } else {
                accumulators[speaker] = samples // Keep all if shorter than overlap
            }
        } else {
            // Clean break
            accumulators[speaker] = []
        }
        
        // Transcribe in background
        let task = Task {
            await transcribeBuffer(audioBuffer, speaker: speaker)
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
            let result = try await whisperEngine.transcribe(buffer)
            
            // Only add non-empty transcriptions
            guard !result.isEmpty else {
                Log.transcription.debug("Skipping empty transcription result")
                return
            }
            
            // Filter out common Whisper meta-tags and noise
            let forbiddenTokens = ["[blank_audio]", "[skip]", "[noise]", "[laughter]", "[vocalized-noise]", "[unintelligible]"]
            let lowerText = result.text.lowercased()
            if forbiddenTokens.contains(where: { lowerText.contains($0) }) || result.text.trimmingCharacters(in: .punctuationCharacters).isEmpty {
                Log.transcription.debug("Filtering Whisper meta-tag or empty punctuation from \(speaker, privacy: .public): \"\(result.text, privacy: .public)\"")
                return
            }
            
            // Reconcile text overlap to prevent duplication in the UI
            var finalResultText = result.text
            
            // Find the last entry from the SAME speaker to check for overlap
            // We only do this on the MainActor since transcriptEntries is @Published
            await MainActor.run {
                if let lastEntry = transcriptEntries.last(where: { $0.speaker == speaker }) {
                    // If the segments are close in time, reconcile them
                    let timeGap = result.timestamp.timeIntervalSince(lastEntry.timestamp)
                    if timeGap < (bufferDuration + 2.0) { 
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

