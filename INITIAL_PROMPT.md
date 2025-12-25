# Initial Implementation Prompt

Use this prompt to start the Cursor agent on the first implementation phase.

---

Create a new macOS app called "MeetingTranscriber" as a Swift Package with an executable target. Set up the foundational audio capture infrastructure without transcription yet.

## Project Setup

1. Create a Swift Package with:
   - Executable target: `MeetingTranscriber`
   - Minimum macOS deployment: 13.0
   - Swift tools version: 5.9

2. Create the folder structure as outlined in PROMPT.md architecture section

## Phase 1 Implementation: Audio Capture Infrastructure

### 1. App Entry Point (`App/MeetingTranscriberApp.swift`)
- SwiftUI App with @main
- Set up as menu bar app (no dock icon)
- Initialize AppDelegate for NSStatusItem management

### 2. AppDelegate (`App/AppDelegate.swift`)
- Create NSStatusItem with SF Symbol icon (waveform.circle)
- Menu with:
  - "Start Recording" / "Stop Recording" (toggles)
  - Separator
  - "Select App to Record..." (opens window picker)
  - "Settings..."
  - Separator  
  - "Quit"
- Track recording state

### 3. Permissions Utility (`Utilities/Permissions.swift`)
- `checkScreenRecordingPermission() -> Bool` - Check current status
- `requestScreenRecordingPermission()` - Open System Settings to grant
- `checkMicrophonePermission() async -> Bool` - Check mic access
- `requestMicrophonePermission() async -> Bool` - Request mic via AVCaptureDevice
- Use CGPreflightScreenCaptureAccess() and CGRequestScreenCaptureAccess() for screen recording

### 4. ScreenCaptureManager (`Features/AudioCapture/ScreenCaptureManager.swift`)
Create an actor that handles all ScreenCaptureKit operations:

```swift
actor ScreenCaptureManager {
    // List available windows, filtered by app name
    func availableWindows(forApps appNames: [String]?) async throws -> [SCWindow]
    
    // Start capturing audio from a specific window
    func startCapture(window: SCWindow) async throws -> AsyncStream<AudioBuffer>
    
    // Stop current capture
    func stopCapture() async
    
    // Current capture state
    var isCapturing: Bool { get }
}
```

Configuration requirements:
- Sample rate: 16000 Hz (Whisper requirement)
- Channels: 1 (mono)
- Exclude current process audio
- Use SCStreamConfiguration properly

Handle SCStreamDelegate to receive CMSampleBuffers and convert to AudioBuffer.

### 5. MicrophoneManager (`Features/AudioCapture/MicrophoneManager.swift`)
Create an actor for microphone capture:

```swift
actor MicrophoneManager {
    // Start capturing from default microphone
    func startCapture() async throws -> AsyncStream<AudioBuffer>
    
    // Stop capture
    func stopCapture() async
    
    // Current state
    var isCapturing: Bool { get }
}
```

Use AVAudioEngine with:
- Input node tap at 16000 Hz, mono, Float32
- Convert to matching AudioBuffer format

### 6. AudioBuffer Model (`Features/AudioCapture/AudioBuffer.swift`)
```swift
struct AudioBuffer: Sendable {
    let samples: [Float]      // PCM samples
    let sampleRate: Int       // Should be 16000
    let timestamp: Date
    let source: AudioSource
    
    enum AudioSource: Sendable {
        case system    // From ScreenCaptureKit (others' audio)
        case microphone // From AVAudioEngine (my audio)
    }
}
```

### 7. AudioMixer (`Features/AudioCapture/AudioMixer.swift`)
Combines streams from both sources:

```swift
actor AudioMixer {
    // Start mixing from both sources
    func startMixing(
        system: AsyncStream<AudioBuffer>,
        microphone: AsyncStream<AudioBuffer>
    ) -> AsyncStream<LabeledAudioChunk>
    
    func stopMixing() async
}

struct LabeledAudioChunk: Sendable {
    let buffer: AudioBuffer
    let speakerLabel: String  // "Me" or "Others" for now
}
```

### 8. Logger Setup (`Utilities/Logger.swift`)
```swift
import OSLog

enum Log {
    static let audio = Logger(subsystem: "com.meetingtranscriber", category: "Audio")
    static let capture = Logger(subsystem: "com.meetingtranscriber", category: "Capture")
    static let ui = Logger(subsystem: "com.meetingtranscriber", category: "UI")
}
```

### 9. Basic UI (`UI/MenuBar/MenuBarView.swift`)
- Window picker view showing available meeting apps
- Use List with app icons and names
- Filter to common meeting apps: Zoom, Google Meet, Microsoft Teams, Slack, Discord, Webex

## Error Handling

Create `AppError.swift`:
```swift
enum AppError: LocalizedError {
    case permissionDenied(PermissionType)
    case captureFailure(String)
    case noWindowSelected
    case audioFormatError
    
    enum PermissionType {
        case screenRecording
        case microphone
    }
    
    var errorDescription: String? { ... }
}
```

## Testing Notes

For testing without real meetings:
1. Open QuickTime and play a video with audio
2. Select QuickTime as the capture target
3. Speak into mic while video plays
4. Both streams should produce AudioBuffers

## What NOT to Implement Yet
- Transcription (Phase 2)
- Diarization (Phase 3)
- Storage/persistence (Phase 4)
- Summaries (Phase 5)

Focus purely on reliable audio capture from both sources with proper error handling, permissions, and clean async stream interfaces.

---

## Verification Checklist

After implementation, verify:
- [ ] App appears in menu bar only (no dock icon)
- [ ] Menu shows all items correctly
- [ ] Permission requests work (screen recording opens System Settings, mic shows dialog)
- [ ] Window picker shows running apps with windows
- [ ] Selecting a window and starting capture produces AudioBuffers from system
- [ ] Microphone capture produces AudioBuffers
- [ ] Both streams can run simultaneously
- [ ] Stopping capture cleans up properly
- [ ] No memory leaks (check in Instruments)
- [ ] Logs appear in Console.app with correct categories
