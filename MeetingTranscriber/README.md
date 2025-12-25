# MeetingTranscriber - Phase 1: Audio Capture

A native macOS menu bar app that captures system audio and microphone input for meeting transcription.

## Features ✨

### Phase 1 (Current)
- ✅ **Menu bar app** - Runs in menu bar only, no dock icon
- ✅ **System audio capture** - Captures all display audio via ScreenCaptureKit
- ✅ **Microphone capture** - Captures your voice via AVAudioEngine
- ✅ **Auto-detect meetings** - Prompts to record when microphone becomes active
- ✅ **Manual recording control** - Start/stop via menu bar
- ✅ **Permission management** - Handles screen recording, microphone, and notification permissions
- ✅ **Audio mixing** - Combines system and mic audio with speaker labels ("Me" / "Others")

### Coming in Future Phases
- 🔄 Real-time transcription (Phase 2)
- 🔄 Speaker diarization (Phase 3)
- 🔄 Storage and history (Phase 4)
- 🔄 AI summaries (Phase 5)

## Requirements 📋

- **macOS**: 13.0 (Ventura) or later
- **Hardware**: Apple Silicon (M1/M2/M3) recommended
- **Xcode**: 15.0+ (for building)
- **Swift**: 5.9+

## Building & Installation 🔨

### Quick Start

1. **Clone or navigate to the project:**
   ```bash
   cd "/Users/itzhak/Local Transcript/MeetingTranscriber"
   ```

2. **Build the project:**
   ```bash
   swift build -c release
   ```

3. **Create the app bundle:**
   ```bash
   ./Scripts/bundle.sh
   ```

4. **Install:**
   ```bash
   # Drag MeetingTranscriber.app to /Applications
   cp -r MeetingTranscriber.app /Applications/
   ```

5. **Launch:**
   - Open `/Applications/MeetingTranscriber.app`
   - Or run from terminal: `open /Applications/MeetingTranscriber.app`

### Alternative: Run Directly

You can also run without creating a bundle:
```bash
swift run
```

## First Launch 🚀

When you first launch the app, you'll need to grant three permissions:

### 1. Screen Recording Permission
- **When**: Automatically prompted when you start recording
- **Why**: Required to capture system audio from meetings
- **How**: System Settings → Privacy & Security → Screen Recording → Enable MeetingTranscriber

### 2. Microphone Permission
- **When**: Automatically prompted on first launch
- **Why**: Required to capture your voice
- **How**: Dialog appears automatically, or System Settings → Privacy & Security → Microphone

### 3. Notification Permission
- **When**: Automatically prompted on first launch
- **Why**: Required to alert you when meetings are detected
- **How**: Dialog appears automatically

## Usage 📱

### Menu Bar Icon

Look for the waveform icon (○~) in your menu bar.

### Manual Recording

1. **Click** the menu bar icon
2. Select **"Start Recording"**
3. The icon fills (●~) to show recording is active
4. Click again and select **"Stop Recording"** when done

### Auto-Detect Recording

1. Join a meeting (Zoom, Google Meet, Teams, etc.)
2. When the meeting app activates your microphone, you'll see a notification
3. Click the notification to **start recording automatically**

### What's Being Captured

- **System Audio** (labeled "Others"): All audio playing on your Mac (meeting participants)
- **Microphone** (labeled "Me"): Your voice from the default microphone

Audio is captured at 16kHz mono (optimized for speech transcription).

## Testing Without a Meeting 🧪

You can test the app without joining a real meeting:

### Test System Audio Capture:
1. Open **QuickTime Player** or **Music**
2. Play any audio
3. Start recording in MeetingTranscriber
4. Audio buffers from "Others" will be captured

### Test Microphone Capture:
1. Start recording in MeetingTranscriber
2. Speak into your microphone
3. Audio buffers from "Me" will be captured

### Test Auto-Detection:
1. Open any app that uses the microphone (e.g., Voice Memos, FaceTime)
2. Start recording/call in that app
3. MeetingTranscriber should show a notification prompting you to record

## Troubleshooting 🔧

### "Screen Recording permission not granted"
**Solution:**
1. Open System Settings → Privacy & Security → Screen Recording
2. Find MeetingTranscriber and toggle it ON
3. Restart the app

### "No audio from system"
**Possible causes:**
- App you're trying to capture isn't playing audio
- Screen recording permission not granted
- Some apps (like Safari) may need specific handling

### "Microphone not working"
**Solution:**
1. System Settings → Privacy & Security → Microphone
2. Ensure MeetingTranscriber is toggled ON
3. Check System Settings → Sound → Input for correct device

### "Notifications not appearing"
**Solution:**
1. System Settings → Notifications
2. Find MeetingTranscriber
3. Enable "Allow Notifications"

### Build fails
**Solution:**
```bash
# Clean build
swift package clean
swift build -c release
```

## Project Structure 📂

```
MeetingTranscriber/
├── Sources/MeetingTranscriber/
│   ├── App/
│   │   ├── MeetingTranscriberApp.swift    # Entry point
│   │   └── AppDelegate.swift               # Menu bar & coordination
│   ├── Features/
│   │   ├── AudioCapture/
│   │   │   ├── AudioBuffer.swift           # Audio data model
│   │   │   ├── ScreenCaptureManager.swift  # System audio capture
│   │   │   ├── MicrophoneManager.swift     # Mic capture
│   │   │   └── AudioMixer.swift            # Combines streams
│   │   └── MeetingDetection/
│   │       └── MicrophoneActivityMonitor.swift  # Auto-detection
│   └── Utilities/
│       ├── Permissions.swift               # Permission handling
│       ├── Logger.swift                    # Structured logging
│       └── AppError.swift                  # Error handling
├── Scripts/
│   └── bundle.sh                           # Creates .app bundle
└── Package.swift                           # Swift Package config
```

## Adding to Login Items ⚙️

To start MeetingTranscriber automatically when you log in:

1. Open **System Settings**
2. Go to **General** → **Login Items**
3. Click the **+** button
4. Select **MeetingTranscriber** from Applications
5. Done! The app will start on login

## Logs & Debugging 🐛

Logs are written using OSLog. To view them:

1. Open **Console.app**
2. Filter by **"com.meetingtranscriber"**
3. Categories:
   - `Audio` - Audio processing and buffers
   - `Capture` - ScreenCaptureKit and AVAudioEngine events
   - `UI` - Menu bar and user interactions
   - `Detection` - Meeting detection and monitoring
   - `Permissions` - Permission requests and status

## What's Next? 🔮

Phase 1 provides the foundation for audio capture. Next phases will add:

- **Phase 2**: Real-time transcription using Whisper
- **Phase 3**: Speaker diarization to identify who said what
- **Phase 4**: Storage, search, and meeting history
- **Phase 5**: AI-powered summaries and action items

## Architecture 🏗️

```
┌─────────────────────────────────────────────┐
│           Menu Bar UI (SwiftUI)             │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│            AppDelegate                       │
│  • Menu management                           │
│  • Recording coordination                    │
│  • Notification handling                     │
└───┬──────────────────────────────────────┬──┘
    │                                       │
┌───▼─────────────────┐         ┌─────────▼─────────────┐
│ ScreenCaptureManager│         │  MicrophoneManager     │
│ (System Audio)      │         │  (User Audio)          │
└───┬─────────────────┘         └─────────┬─────────────┘
    │                                       │
    │         ┌─────────────────────────────┘
    │         │
┌───▼─────────▼─────────┐
│     AudioMixer         │
│  Labels: Me / Others   │
└────────────────────────┘
```

## License & Credits 📄

Built with Swift, ScreenCaptureKit, and AVFoundation.

---

**Note**: This is Phase 1. Audio is captured but not yet transcribed. Transcription will be added in Phase 2.

