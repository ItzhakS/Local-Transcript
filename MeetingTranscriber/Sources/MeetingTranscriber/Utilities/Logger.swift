import OSLog

/// Centralized logging for the MeetingTranscriber app
enum Log {
    /// Audio processing and buffer operations
    static let audio = Logger(subsystem: "com.meetingtranscriber", category: "Audio")
    
    /// ScreenCaptureKit and AVAudioEngine capture events
    static let capture = Logger(subsystem: "com.meetingtranscriber", category: "Capture")
    
    /// UI interactions and menu bar events
    static let ui = Logger(subsystem: "com.meetingtranscriber", category: "UI")
    
    /// Meeting detection and microphone monitoring
    static let detection = Logger(subsystem: "com.meetingtranscriber", category: "Detection")
    
    /// Permission requests and status
    static let permissions = Logger(subsystem: "com.meetingtranscriber", category: "Permissions")
    
    /// Transcription engine and results
    static let transcription = Logger(subsystem: "com.meetingtranscriber", category: "Transcription")
}

