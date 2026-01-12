# MeetingTranscriber - Phases 1 & 2: Audio Capture + Transcription

A native macOS menu bar app that captures system audio and microphone input, transcribing meetings in real-time.

## Features ✨

### Phase 1 (Complete)
- ✅ **Menu bar app** - Runs in menu bar only, no dock icon
- ✅ **System audio capture** - Captures all display audio via ScreenCaptureKit
- ✅ **Microphone capture** - Captures your voice via AVAudioEngine
- ✅ **Auto-detect meetings** - Prompts to record when microphone becomes active
- ✅ **Manual recording control** - Start/stop via menu bar
- ✅ **Permission management** - Handles screen recording, microphone, and notification permissions
- ✅ **Audio mixing** - Combines system and mic audio with speaker labels ("Me" / "Others")

### Phase 2 (Complete)
- ✅ **Real-time transcription** - Uses FluidAudio ASR (AsrManager/StreamingEouAsrManager)
- ✅ **Live transcript window** - Displays transcription as it happens
- ✅ **Speaker labeling** - "Me" for microphone, "Others" for system audio
- ✅ **Confidence scoring** - Visual indicators for transcription quality
- ✅ **Voice Activity Detection** - Uses FluidAudio VadManager for accurate speech detection
- ✅ **Smart buffering** - 3-second segments with speaker change detection

### Coming in Future Phases
- 🔄 Advanced speaker diarization via FluidAudio DiarizerManager (Phase 3) - Native Swift, ANE-optimized
- 🔄 Storage and history (Phase 4)
- 🔄 AI summaries via Ollama (Phase 5)

## Requirements 📋

- **macOS**: 14.0 (Sonoma) or later (required for FluidAudio)
- **Hardware**: Apple Silicon only (M1/M2/M3/M4) - required for Apple Neural Engine access
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
4. **Transcript window** opens automatically showing live transcription
5. Click again and select **"Stop Recording"** when done

### Auto-Detect Recording

1. Join a meeting (Zoom, Google Meet, Teams, etc.)
2. When the meeting app activates your microphone, you'll see a notification
3. Click the notification to **start recording automatically**
4. Transcript window will open with live transcription

### What's Being Captured & Transcribed

- **System Audio** (labeled "Others"): All audio playing on your Mac (meeting participants) - transcribed in real-time
- **Microphone** (labeled "Me"): Your voice from the default microphone - transcribed in real-time

Audio is captured at 16kHz mono (optimized for speech transcription).

## Testing Without a Meeting 🧪

You can test the app without joining a real meeting:

### Test System Audio Capture + Transcription:
1. Open **YouTube** and play a video with clear speech
2. Start recording in MeetingTranscriber
3. Transcript window opens - you should see text appear labeled "Others"
4. Verify transcription accuracy

### Test Microphone Capture + Transcription:
1. Start recording in MeetingTranscriber
2. Speak clearly into your microphone
3. You should see text appear labeled "Me"
4. Verify transcription accuracy

### Test Both Streams:
1. Play YouTube video (Others)
2. Speak into microphone (Me)
3. Both should appear in transcript with correct labels
4. Verify speaker detection works correctly

### First Recording Note:
- The first time you start recording, FluidAudio will download the ASR model (Parakeet TDT v3 ~0.6b parameters)
- Models are automatically downloaded from HuggingFace in the background
- Subsequent recordings will be instant

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

### "No transcription appearing"
**Possible causes:**
- Model still downloading (check Console.app)
- Audio too quiet (VAD threshold)
- Background noise interfering
**Solution:**
- Check Console.app for "Transcription" category logs
- Speak clearly and continuously for 3+ seconds
- Ensure audio levels are adequate

### "Transcription is slow or inaccurate"
**Solutions:**
- First transcription downloads model (~150MB) - be patient
- Base model prioritizes speed over accuracy
- Ensure clear audio with minimal background noise
- Check CPU usage in Activity Monitor

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
│   │   ├── Transcription/                  # ⭐ NEW in Phase 2
│   │   │   ├── FluidAudioEngine.swift      # FluidAudio ASR wrapper
│   │   │   └── TranscriptionManager.swift  # Audio buffering + FluidAudio VAD
│   │   └── MeetingDetection/
│   │       └── MicrophoneActivityMonitor.swift  # Auto-detection
│   ├── UI/
│   │   └── TranscriptWindow/               # ⭐ NEW in Phase 2
│   │       ├── TranscriptView.swift        # Live transcript UI
│   │       └── TranscriptWindowController.swift  # Window management
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
   - `Transcription` - ⭐ Model loading, transcription results, performance

Example logs:
```
[Transcription] Loading Whisper model: base...
[Transcription] Whisper model loaded successfully
[Transcription] Starting transcription of 48000 samples (3.00s)
[Transcription] Transcription complete: "Hello world" (confidence: 0.95, processing time: 0.82s)
```

## What's Next? 🔮

Phase 2 provides real-time transcription with basic speaker labeling. Next phases will add:

- **Phase 3**: Advanced speaker diarization via **FluidAudio DiarizerManager** (native Swift, ANE-optimized) to identify multiple speakers in system audio
- **Phase 4**: Storage, search, and meeting history via GRDB.swift
- **Phase 5**: AI-powered summaries and action items via Ollama

See `PHASE2_SUMMARY.md` for detailed Phase 2 implementation notes.

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
└────────┬───────────────┘
         │
┌────────▼──────────────────────┐
│   TranscriptionManager         │
│  • Audio buffering             │
│  • Voice Activity Detection    │
│  • Speaker change detection    │
└────────┬──────────────────────┘
         │
┌────────▼──────────────────────┐
│      FluidAudioEngine          │
│  • FluidAudio ASR (ANE)        │
│  • Real-time transcription     │
└────────┬──────────────────────┘
         │
┌────────▼──────────────────────┐
│     TranscriptView             │
│  • Live transcript display     │
│  • Speaker labels              │
│  • Confidence indicators       │
└────────────────────────────────┘
```

## License & Credits 📄

Built with:
- Swift 5.9+, SwiftUI
- ScreenCaptureKit (system audio), AVFoundation (microphone)
- [FluidAudio](https://github.com/FluidInference/FluidAudio) - Native Swift on-device audio AI (ASR, VAD, Diarization)
- [FluidAudio Documentation](https://deepwiki.com/FluidInference/FluidAudio) - Comprehensive API reference

> **Note**: ScreenCaptureKit is still required for audio capture. FluidAudio processes audio but does not capture it.

---

**Note**: Phases 1 & 2 are complete. Audio is captured and transcribed in real-time. Transcripts are displayed live but not yet saved to disk. Storage will be added in Phase 4.

