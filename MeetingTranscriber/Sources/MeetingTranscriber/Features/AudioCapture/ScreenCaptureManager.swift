import Foundation
import ScreenCaptureKit
import CoreMedia
import AVFoundation

/// Manages system audio capture from the display using ScreenCaptureKit
actor ScreenCaptureManager: NSObject {
    
    private var stream: SCStream?
    private var audioBufferContinuation: AsyncStream<AudioBuffer>.Continuation?
    private(set) var isCapturing = false
    
    // MARK: - Public API
    
    /// Start capturing all system audio from the main display
    /// - Returns: An async stream of audio buffers
    /// - Throws: AppError if capture cannot be started
    func startCapture() async throws -> AsyncStream<AudioBuffer> {
        Log.capture.info("Starting display audio capture")
        
        // Check permission first
        guard Permissions.checkScreenRecordingPermission() else {
            Log.capture.error("Screen recording permission not granted")
            throw AppError.permissionDenied(.screenRecording)
        }
        
        // Stop any existing capture
        if isCapturing {
            Log.capture.warning("Already capturing, stopping existing stream")
            await stopCapture()
        }
        
        // Get available content
        let content = try await SCShareableContent.current
        
        // Get the main display
        guard let display = content.displays.first else {
            Log.capture.error("No display found")
            throw AppError.noDisplayFound
        }
        
        Log.capture.info("Found display: \(display.displayID)")
        
        // Create filter for display-wide capture (excluding no windows means capturing all)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Configure stream for audio-only capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000  // Whisper requirement
        config.channelCount = 1    // Mono
        
        // Minimal video configuration (some APIs may require it)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        
        // Create the stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        // Create the async stream for audio buffers
        let audioStream = AsyncStream<AudioBuffer> { continuation in
            self.audioBufferContinuation = continuation
        }
        
        // Add audio output
        do {
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
            try await stream?.startCapture()
            isCapturing = true
            Log.capture.info("Display audio capture started successfully")
        } catch {
            Log.capture.error("Failed to start capture: \(error.localizedDescription)")
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
        
        Log.capture.info("Stopping display audio capture")
        
        do {
            try await stream?.stopCapture()
            audioBufferContinuation?.finish()
            audioBufferContinuation = nil
            stream = nil
            isCapturing = false
            Log.capture.info("Display audio capture stopped")
        } catch {
            Log.capture.error("Error stopping capture: \(error.localizedDescription)")
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.capture.error("Stream stopped with error: \(error.localizedDescription)")
        
        Task {
            await self.handleStreamError(error)
        }
    }
    
    private func handleStreamError(_ error: Error) {
        audioBufferContinuation?.finish()
        audioBufferContinuation = nil
        isCapturing = false
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureManager: SCStreamOutput {
    
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio samples
        guard type == .audio else { return }
        
        Task {
            await self.processSampleBuffer(sampleBuffer)
        }
    }
    
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Extract audio buffer from sample buffer
        guard let audioBuffer = convertToAudioBuffer(sampleBuffer) else {
            Log.audio.warning("Failed to convert sample buffer to audio buffer")
            return
        }
        
        Log.audio.debug("ScreenCapture: Produced buffer with \(audioBuffer.samples.count) samples")
        
        // Send to continuation
        audioBufferContinuation?.yield(audioBuffer)
    }
    
    /// Convert CMSampleBuffer to AudioBuffer
    private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AudioBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            Log.audio.error("Failed to get data buffer from sample buffer")
            return nil
        }
        
        // Get format description
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            Log.audio.error("Failed to get format description")
            return nil
        }
        
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        guard let streamDescription = asbd else {
            Log.audio.error("Failed to get stream description")
            return nil
        }
        
        // Get audio data
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == kCMBlockBufferNoErr, let pointer = dataPointer else {
            Log.audio.error("Failed to get data pointer from block buffer")
            return nil
        }
        
        // Convert to Float samples
        let samples = convertToFloatSamples(pointer: pointer, length: length, format: streamDescription)
        
        return AudioBuffer(
            samples: samples,
            sampleRate: Int(streamDescription.mSampleRate),
            timestamp: Date(),
            source: .system
        )
    }
    
    /// Convert raw audio data to Float samples
    private func convertToFloatSamples(pointer: UnsafeMutablePointer<Int8>, length: Int, format: AudioStreamBasicDescription) -> [Float] {
        let sampleCount = length / MemoryLayout<Float>.size
        let floatPointer = pointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { $0 }
        let buffer = UnsafeBufferPointer(start: floatPointer, count: sampleCount)
        return Array(buffer)
    }
}

