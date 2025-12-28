import Foundation
import WhisperKit
import AVFoundation

/// Manages Whisper model loading and transcription
actor WhisperEngine {
    
    // MARK: - Properties
    
    private var whisperKit: WhisperKit?
    private(set) var isLoaded = false
    private let modelName: String
    
    // MARK: - Initialization
    
    /// Initialize the Whisper engine with a specific model
    /// - Parameter modelName: The Whisper model to use (default: "base")
    init(modelName: String = "base") {
        self.modelName = modelName
        Log.transcription.info("WhisperEngine initialized with model: \(modelName, privacy: .public)")
    }
    
    // MARK: - Model Management
    
    /// Load the Whisper model
    func loadModel() async throws {
        guard !isLoaded else {
            Log.transcription.debug("Model already loaded")
            return
        }
        
        Log.transcription.info("Preparing Whisper model: \(self.modelName, privacy: .public)...")
        
        do {
            // Initialize WhisperKit with the specified model
            // Use the full repo path for more reliable downloads
            let modelVariant = "openai_whisper-\(modelName)"
            
            whisperKit = try await WhisperKit(
                model: modelVariant,
                verbose: true,  // Enable verbose for better debugging
                logLevel: .info,
                prewarm: false,
                load: true,
                download: true // This will only download if files are missing
            )
            
            isLoaded = true
            Log.transcription.info("Whisper model ready: \(self.modelName, privacy: .public)")
            
        } catch {
            Log.transcription.error("Failed to load Whisper model: \(error.localizedDescription, privacy: .public)")
            
            // Provide helpful error message
            let errorMsg: String
            if error.localizedDescription.contains("Model not found") || error.localizedDescription.contains("couldn't be moved") {
                errorMsg = "Model download was interrupted. Please ensure you have a stable internet connection and try again. The app will download ~150MB on first use."
            } else {
                errorMsg = "Failed to load Whisper model: \(error.localizedDescription)"
            }
            
            throw AppError.transcriptionError(errorMsg)
        }
    }
    
    /// Unload the model and free resources
    func unloadModel() async {
        guard isLoaded else {
            Log.transcription.debug("Model not loaded, nothing to unload")
            return
        }
        
        Log.transcription.info("Unloading Whisper model")
        whisperKit = nil
        isLoaded = false
        Log.transcription.info("Whisper model unloaded")
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio samples
    /// - Parameter audioBuffer: Audio buffer containing 16kHz mono PCM samples
    /// - Returns: Transcription result with text and metadata
    func transcribe(_ audioBuffer: AudioBuffer) async throws -> TranscriptionResult {
        guard isLoaded, let whisperKit = whisperKit else {
            throw AppError.transcriptionError("Whisper model not loaded")
        }
        
        // Validate audio format
        guard audioBuffer.sampleRate == 16000 else {
            throw AppError.transcriptionError("Audio must be 16kHz (got \(audioBuffer.sampleRate)Hz)")
        }
        
        guard !audioBuffer.samples.isEmpty else {
            Log.transcription.debug("Empty audio buffer, skipping transcription")
            return TranscriptionResult(text: "", confidence: 0.0, duration: 0.0, timestamp: audioBuffer.timestamp)
        }
        
        let startTime = Date()
        Log.transcription.debug("Starting transcription of \(audioBuffer.samples.count) samples (\(String(format: "%.2f", audioBuffer.duration), privacy: .public)s)")
        
        do {
            // WhisperKit expects audio as [Float] at 16kHz
            let results = try await whisperKit.transcribe(
                audioArray: audioBuffer.samples,
                decodeOptions: DecodingOptions()
            )
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            // WhisperKit returns an array of TranscriptionResult
            // Each result has text and segments. We'll combine all text
            guard let firstResult = results.first else {
                Log.transcription.debug("No transcription results returned")
                return TranscriptionResult(text: "", confidence: 0.0, duration: audioBuffer.duration, timestamp: audioBuffer.timestamp)
            }
            
            // Extract the transcribed text
            let trimmedText = firstResult.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            // Calculate average confidence from segments
            let segments = firstResult.segments
            let avgLogprob: Double
            if segments.isEmpty {
                avgLogprob = 0.0
            } else {
                let sum = segments.compactMap { $0.avgLogprob }.reduce(0.0, +)
                avgLogprob = Double(sum) / Double(segments.count)
            }
            let confidence = exp(avgLogprob) // Convert log probability to probability
            
            Log.transcription.info("Transcription complete: \"\(trimmedText, privacy: .public)\" (confidence: \(String(format: "%.2f", confidence), privacy: .public), processing time: \(String(format: "%.2f", processingTime), privacy: .public)s)")
            
            return TranscriptionResult(
                text: trimmedText,
                confidence: confidence,
                duration: audioBuffer.duration,
                timestamp: audioBuffer.timestamp
            )
            
        } catch {
            Log.transcription.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.transcriptionError("Transcription failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - TranscriptionResult

/// Result from a transcription operation
struct TranscriptionResult: Sendable {
    /// The transcribed text
    let text: String
    
    /// Confidence score (0.0 to 1.0)
    let confidence: Double
    
    /// Duration of the audio segment in seconds
    let duration: TimeInterval
    
    /// Timestamp when the audio was captured
    let timestamp: Date
    
    /// Whether the transcription is empty
    var isEmpty: Bool {
        text.isEmpty
    }
}

