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
        }
        
        // ALWAYS accumulate audio. Whisper needs silence for context, 
        // and we were previously "chopping" the audio by skipping non-speech chunks.
        accumulators[speaker, default: []].append(contentsOf: chunk.buffer.samples)
        lastChunkTimes[speaker] = now
        
        // Detect if THIS chunk contains speech
        let hasSpeech = detectSpeech(in: chunk.buffer.samples)
        if hasSpeech {
            lastSpeechTimes[speaker] = now
        }
        
        // Check for silence timeout (no speech for X seconds)
        let silenceDuration = now.timeIntervalSince(lastSpeechTimes[speaker] ?? now)
        let silenceDetected = silenceDuration > silenceTimeout
        
        let accumulatedDuration = Double(accumulators[speaker]?.count ?? 0) / Double(sampleRate)
        
        // Flush logic
        if silenceDetected && accumulatedDuration >= 1.0 {
            // End of sentence/speech segment - flush everything
            Log.transcription.debug("Flushing buffer for \(speaker, privacy: .public) due to silence (\(String(format: "%.1f", silenceDuration), privacy: .public)s)")
            await flushBuffer(for: speaker, keepOverlap: false)
            lastSpeechTimes[speaker] = now // Reset silence timer after flush
        } else if accumulatedDuration >= bufferDuration {
            // Buffer full during continuous speech - flush with overlap to prevent word clipping
            Log.transcription.info("Buffer duration threshold reached for \(speaker, privacy: .public), flushing with overlap")
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
        let newWords = newText.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let prevWords = previousText.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        // We look for a match in the last 10 words of the previous segment
        // and the first 10 words of the new segment (increased from 5 for better matching)
        let lookbackCount = min(10, prevWords.count)
        let lookaheadCount = min(10, newWords.count)
        
        guard lookbackCount > 0 && lookaheadCount > 0 else { return newText }
        
        // Try to find the longest matching sequence of words
        for length in (1...min(lookbackCount, lookaheadCount)).reversed() {
            let suffix = prevWords.suffix(length)
            let prefix = newWords.prefix(length)
            
            if Array(suffix) == Array(prefix) {
                // Found a match! Reconstruct the new text without the overlap
                // We use the original newText to preserve case/punctuation, but split into words
                let originalNewWords = newText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                if originalNewWords.count > length {
                    let reconciledWords = originalNewWords.dropFirst(length)
                    return reconciledWords.joined(separator: " ")
                } else {
                    // The entire new segment was a duplicate
                    return ""
                }
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

