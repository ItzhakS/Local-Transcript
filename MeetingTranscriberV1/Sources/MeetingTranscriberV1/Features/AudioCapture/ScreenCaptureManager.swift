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
        
        // Configure stream for audio-only capture at 16kHz (Whisper requirement)
        // Note: The "tin can" audio effect was caused by AVAudioEngine voice processing,
        // not by ScreenCaptureKit sample rate. We've disabled voice processing in MicrophoneManager.
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000  // Whisper requirement
        config.channelCount = 1    // Mono
        
        // Minimal video configuration (some APIs may require it)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        
        Log.capture.info("ScreenCaptureKit configured for 16kHz mono capture")
        
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
        // Convert CMSampleBuffer to AudioBuffer
        guard let audioBuffer = convertToAudioBuffer(sampleBuffer) else {
            return
        }
        
        // Send to continuation
        audioBufferContinuation?.yield(audioBuffer)
    }
    
    /// Convert CMSampleBuffer to AudioBuffer
    private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AudioBuffer? {
        // Extract format description
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }
        
        // ScreenCaptureKit provides audio in various formats.
        // We need to handle both Float32 and Int16 formats robustly.
        
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr else { return nil }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        if frameCount == 0 { return nil }
        
        let channels = Int(streamDescription.mChannelsPerFrame)
        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let wordSize = Int(streamDescription.mBitsPerChannel / 8)
        
        var samples = [Float]()
        samples.reserveCapacity(Int(frameCount))
        
        let bufferListPtr = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        
        // Simple mono extraction
        if isFloat {
            // Float32
            if let mData = bufferListPtr[0].mData {
                let floatPtr = mData.assumingMemoryBound(to: Float.self)
                samples = Array(UnsafeBufferPointer(start: floatPtr, count: Int(frameCount) * channels))
            }
        } else {
            // Int16 (pcmFormatInt16)
            if let mData = bufferListPtr[0].mData {
                let int16Ptr = mData.assumingMemoryBound(to: Int16.self)
                let int16Samples = UnsafeBufferPointer(start: int16Ptr, count: Int(frameCount) * channels)
                samples = int16Samples.map { Float($0) / 32768.0 }
            }
        }
        
        if samples.isEmpty { return nil }
        
        // Convert to mono if needed
        var finalSamples = samples
        if channels > 1 {
            let monoCount = samples.count / channels
            var monoSamples = [Float](repeating: 0, count: monoCount)
            for i in 0..<monoCount {
                var sum: Float = 0
                for j in 0..<channels {
                    sum += samples[i * channels + j]
                }
                monoSamples[i] = sum / Float(channels)
            }
            finalSamples = monoSamples
        }
        
        return AudioBuffer(
            samples: finalSamples,
            sampleRate: Int(streamDescription.mSampleRate),
            timestamp: Date(),
            source: .system
        )
    }
    
    // Remove the old conversion methods
}

