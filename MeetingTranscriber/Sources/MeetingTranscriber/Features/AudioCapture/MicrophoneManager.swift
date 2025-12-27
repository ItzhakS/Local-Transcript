import Foundation
import AVFoundation

/// Manages microphone audio capture using AVAudioEngine
actor MicrophoneManager {
    
    private var audioEngine: AVAudioEngine?
    private var audioBufferContinuation: AsyncStream<AudioBuffer>.Continuation?
    private(set) var isCapturing = false
    
    // Target audio format: 16kHz, mono, Float32
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1
    
    // MARK: - Public API
    
    /// Start capturing audio from the default microphone
    /// - Returns: An async stream of audio buffers
    /// - Throws: AppError if capture cannot be started
    func startCapture() async throws -> AsyncStream<AudioBuffer> {
        Log.capture.info("Starting microphone capture")
        
        // Check permission first
        guard await Permissions.checkMicrophonePermission() else {
            Log.capture.error("Microphone permission not granted")
            throw AppError.permissionDenied(.microphone)
        }
        
        // Stop any existing capture
        if isCapturing {
            Log.capture.warning("Already capturing, stopping existing engine")
            await stopCapture()
        }
        
        // Create audio engine
        let engine = AVAudioEngine()
        audioEngine = engine
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        Log.capture.info("Microphone input format - Sample Rate: \(inputFormat.sampleRate)Hz, Channels: \(inputFormat.channelCount)")
        
        // Create target format (16kHz mono Float32)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        ) else {
            Log.capture.error("Failed to create target audio format")
            throw AppError.audioFormatError
        }
        
        // Create format converter if needed
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        
        // Create the async stream for audio buffers
        let audioStream = AsyncStream<AudioBuffer> { continuation in
            self.audioBufferContinuation = continuation
        }
        
        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer, time) in
            Task {
                await self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }
        }
        
        // Start the engine
        do {
            try engine.start()
            isCapturing = true
            Log.capture.info("Microphone capture started successfully")
        } catch {
            Log.capture.error("Failed to start audio engine: \(error.localizedDescription)")
            throw AppError.captureFailure(error.localizedDescription)
        }
        
        return audioStream
    }
    
    /// Stop the current capture
    func stopCapture() async {
        guard isCapturing else {
            Log.capture.debug("Stop capture called but not currently capturing")
            return
        }
        
        Log.capture.info("Stopping microphone capture")
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        
        isCapturing = false
        Log.capture.info("Microphone capture stopped")
    }
    
    // MARK: - Private Methods
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat) {
        // Convert to target format if converter exists
        let finalBuffer: AVAudioPCMBuffer
        
        if let converter = converter {
            // Create output buffer for converted audio
            let frameCapacity = AVAudioFrameCount((Double(buffer.frameLength) * targetSampleRate) / buffer.format.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                Log.audio.error("Failed to create converted buffer")
                return
            }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                Log.audio.error("Audio conversion error: \(error.localizedDescription)")
                return
            }
            
            finalBuffer = convertedBuffer
        } else {
            finalBuffer = buffer
        }
        
        // Extract float samples
        guard let floatChannelData = finalBuffer.floatChannelData else {
            Log.audio.error("Failed to get float channel data")
            return
        }
        
        let frameLength = Int(finalBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: floatChannelData[0], count: frameLength))
        
        Log.audio.debug("Microphone: Produced buffer with \(samples.count) samples")
        
        // Create AudioBuffer
        let audioBuffer = AudioBuffer(
            samples: samples,
            sampleRate: Int(targetSampleRate),
            timestamp: Date(),
            source: .microphone
        )
        
        // Send to continuation
        audioBufferContinuation?.yield(audioBuffer)
    }
}

