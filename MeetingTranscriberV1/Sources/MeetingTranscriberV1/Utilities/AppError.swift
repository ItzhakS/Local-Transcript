import Foundation

/// Application-wide errors with localized descriptions
enum AppError: LocalizedError {
    case permissionDenied(PermissionType)
    case captureFailure(String)
    case noWindowSelected
    case noDisplayFound
    case audioFormatError
    case microphoneInUse
    case streamConfigurationFailed
    case transcriptionError(String)
    case diarizationError(String)
    
    enum PermissionType {
        case screenRecording
        case microphone
        case notifications
    }
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied(let type):
            switch type {
            case .screenRecording:
                return "Screen recording permission is required to capture system audio. Please grant permission in System Settings > Privacy & Security > Screen Recording."
            case .microphone:
                return "Microphone permission is required to capture your audio. Please grant permission in System Settings > Privacy & Security > Microphone."
            case .notifications:
                return "Notification permission is required to alert you when meetings are detected."
            }
        case .captureFailure(let reason):
            return "Audio capture failed: \(reason)"
        case .noWindowSelected:
            return "No window was selected for recording."
        case .noDisplayFound:
            return "No display found for audio capture."
        case .audioFormatError:
            return "Failed to configure audio format. The app requires 16kHz mono audio."
        case .microphoneInUse:
            return "Microphone is already in use by another application."
        case .streamConfigurationFailed:
            return "Failed to configure audio stream. Please try again."
        case .transcriptionError(let reason):
            return "Transcription failed: \(reason)"
        case .diarizationError(let reason):
            return "Speaker diarization failed: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied(let type):
            switch type {
            case .screenRecording, .microphone:
                return "Open System Settings and grant the required permission, then restart the app."
            case .notifications:
                return "Open System Settings > Notifications to enable notifications for MeetingTranscriber."
            }
        case .captureFailure:
            return "Check that your audio devices are properly connected and try starting the recording again."
        case .noDisplayFound:
            return "Ensure your display is properly connected and recognized by macOS."
        case .audioFormatError:
            return "Check your system audio settings and ensure a valid audio device is selected."
        case .microphoneInUse:
            return "Close other applications using the microphone or wait for them to finish."
        case .streamConfigurationFailed:
            return "Restart the application and try again. If the problem persists, check your audio device settings."
        case .transcriptionError:
            return "Restart the application and try again. If the problem persists, check Console.app for detailed logs."
        case .diarizationError:
            return "Speaker identification will fall back to 'Others' label. Check Console.app for detailed logs."
        default:
            return nil
        }
    }
}

