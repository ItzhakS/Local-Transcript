import Foundation
import FluidAudio

/// Manages FluidAudio ASR model loading and transcription
actor FluidAudioEngine {
    
    // MARK: - Properties
    
    private var asrManager: AsrManager?
    private(set) var isLoaded = false
    private let modelVersion: AsrModelVersion
    
    // MARK: - Initialization
    
    /// Initialize the FluidAudio engine with a specific model version
    /// - Parameter modelVersion: The ASR model version to use (default: .v3 for multilingual)
    init(modelVersion: AsrModelVersion = .v3) {
        self.modelVersion = modelVersion
        Log.transcription.info("FluidAudioEngine initialized with model version: \(modelVersion == .v3 ? "v3" : "v2", privacy: .public)")
    }
    
    // MARK: - Model Management
    
    /// Load the FluidAudio ASR models
    func loadModel() async throws {
        guard !isLoaded else {
            Log.transcription.debug("FluidAudio model already loaded")
            return
        }
        
        Log.transcription.info("Loading FluidAudio ASR models (version: \(self.modelVersion == .v3 ? "v3" : "v2", privacy: .public))...")
        
        do {
            // Download and load models from HuggingFace (auto-cached)
            let models = try await AsrModels.downloadAndLoad(
                to: nil,
                configuration: nil,
                version: self.modelVersion
            )
            
            // Create and initialize AsrManager
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            
            self.asrManager = manager
            self.isLoaded = true
            
            Log.transcription.info("FluidAudio ASR models loaded successfully (version: \(self.modelVersion == .v3 ? "v3" : "v2", privacy: .public))")
            
        } catch {
            Log.transcription.error("Failed to load FluidAudio ASR models: \(error.localizedDescription, privacy: .public)")
            
            // Map FluidAudio errors to user-friendly messages
            let errorMsg: String
            if let asrError = error as? ASRError {
                switch asrError {
                case .unsupportedPlatform(let reason):
                    errorMsg = "Parakeet models require Apple Silicon. This app runs on M1/M2/M3/M4 only. \(reason)"
                case .invalidAudioData:
                    errorMsg = "Audio segment too short for transcription. Minimum duration is 1 second."
                case .notInitialized:
                    errorMsg = "Transcription model not loaded. Please try again."
                case .processingFailed(let reason):
                    errorMsg = "Transcription processing failed: \(reason)"
                case .modelLoadFailed:
                    errorMsg = "Failed to load transcription model. Try deleting ~/Library/Application Support/FluidAudio and restarting."
                case .modelCompilationFailed:
                    errorMsg = "Model compilation failed. Try deleting ~/Library/Application Support/FluidAudio and restarting."
                @unknown default:
                    errorMsg = "Failed to load FluidAudio ASR models: \(error.localizedDescription)"
                }
            } else if let modelsError = error as? AsrModelsError {
                switch modelsError {
                case .downloadFailed(let reason):
                    errorMsg = "Model download failed. Check your internet connection and try again. \(reason)"
                case .loadingFailed(let reason):
                    errorMsg = "Failed to load transcription model. Try deleting ~/Library/Application Support/FluidAudio and restarting. \(reason)"
                case .modelNotFound(let name, let path):
                    errorMsg = "Model file '\(name)' not found at: \(path.path). Try deleting the cache and re-downloading."
                case .modelCompilationFailed(let reason):
                    errorMsg = "Model compilation failed. Try deleting ~/Library/Application Support/FluidAudio and restarting. \(reason)"
                @unknown default:
                    errorMsg = "Failed to load FluidAudio ASR models: \(error.localizedDescription)"
                }
            } else {
                errorMsg = "Failed to load FluidAudio ASR models: \(error.localizedDescription)"
            }
            
            throw AppError.transcriptionError(errorMsg)
        }
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio samples
    /// - Parameter audioBuffer: Audio buffer containing 16kHz mono PCM samples
    /// - Returns: Transcription result with text and metadata
    func transcribe(_ audioBuffer: AudioBuffer) async throws -> TranscriptionResult {
        guard isLoaded, let manager = asrManager else {
            throw AppError.transcriptionError("FluidAudio ASR model not loaded")
        }
        
        // Validate audio format
        guard audioBuffer.sampleRate == 16000 else {
            throw AppError.transcriptionError("Audio must be 16kHz (got \(audioBuffer.sampleRate)Hz)")
        }
        
        guard !audioBuffer.samples.isEmpty else {
            Log.transcription.debug("Empty audio buffer, skipping transcription")
            return TranscriptionResult(text: "", confidence: 0.0, duration: 0.0, timestamp: audioBuffer.timestamp)
        }
        
        // AsrManager requires minimum 16,000 samples (1 second)
        guard audioBuffer.samples.count >= 16_000 else {
            Log.transcription.debug("Audio buffer too short (\(audioBuffer.samples.count) samples, need 16,000), skipping transcription")
            throw AppError.transcriptionError("Audio segment too short for transcription. Minimum duration is 1 second.")
        }
        
        let startTime = Date()
        Log.transcription.debug("Starting transcription of \(audioBuffer.samples.count) samples (\(String(format: "%.2f", audioBuffer.duration), privacy: .public)s)")
        
        do {
            // Map AudioBuffer.AudioSource to FluidAudio AudioSource (top-level enum)
            let fluidSource: AudioSource = audioBuffer.source == .microphone ? .microphone : .system
            
            // Transcribe using FluidAudio AsrManager
            let result = try await manager.transcribe(
                audioBuffer.samples,
                source: fluidSource
            )
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            // Extract transcribed text
            let trimmedText = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            // Convert Float confidence to Double
            let confidence = Double(result.confidence)
            
            Log.transcription.info("Transcription complete: \"\(trimmedText, privacy: .public)\" (confidence: \(String(format: "%.2f", confidence), privacy: .public), processing time: \(String(format: "%.2f", processingTime), privacy: .public)s)")
            
            // Map ASRResult to TranscriptionResult
            // Note: ASRResult does not include timestamp, so we use AudioBuffer.timestamp
            return TranscriptionResult(
                text: trimmedText,
                confidence: confidence,
                duration: result.duration,
                timestamp: audioBuffer.timestamp
            )
            
        } catch {
            Log.transcription.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            
            // Map FluidAudio errors to user-friendly messages
            let errorMsg: String
            if let asrError = error as? ASRError {
                switch asrError {
                case .unsupportedPlatform(let reason):
                    errorMsg = "Parakeet models require Apple Silicon. This app runs on M1/M2/M3/M4 only. \(reason)"
                case .invalidAudioData:
                    errorMsg = "Audio segment too short for transcription."
                case .notInitialized:
                    errorMsg = "Transcription model not loaded. Please try again."
                case .processingFailed(let reason):
                    errorMsg = "Transcription processing failed: \(reason)"
                case .modelLoadFailed:
                    errorMsg = "Failed to load transcription model. Try deleting ~/Library/Application Support/FluidAudio and restarting."
                case .modelCompilationFailed:
                    errorMsg = "Model compilation failed. Try deleting ~/Library/Application Support/FluidAudio and restarting."
                @unknown default:
                    errorMsg = "Transcription failed: \(error.localizedDescription)"
                }
            } else {
                errorMsg = "Transcription failed: \(error.localizedDescription)"
            }
            
            throw AppError.transcriptionError(errorMsg)
        }
    }
}

// MARK: - TranscriptionResult

/// Result from a transcription operation
/// This struct is shared between WhisperEngine and FluidAudioEngine
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
