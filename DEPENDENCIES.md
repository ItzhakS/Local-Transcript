# Dependencies & Setup

## Required Software

### 1. Xcode
- **Version**: 15.0+ (for Swift 5.9 and macOS 14 SDK)
- **Install**: Mac App Store or developer.apple.com

### 2. Ollama (for AI summaries)
```bash
# Install via Homebrew
brew install ollama

# Start Ollama service
ollama serve

# Pull a model for summaries (choose one)
ollama pull llama3.2:3b      # Smaller, faster
ollama pull llama3.1:8b      # Better quality
ollama pull mistral:7b       # Good balance
```

### 3. FluidAudio Models (Auto-Downloaded)

FluidAudio models are automatically downloaded on first use from HuggingFace. They are cached in:
```
~/.cache/huggingface/hub/
```

Available ASR models:
- **Parakeet TDT v3** - Multilingual (25 European languages) (~0.6b parameters) **← Default**
- **Parakeet TDT v2** - English-only with higher recall (~0.6b parameters)

Available VAD models:
- **Silero VAD** - Voice activity detection (auto-downloaded)

Available Diarization models:
- **Pyannote Segmentation 3.0** - Speaker segmentation (auto-downloaded)
- **WeSpeaker** - Speaker embeddings (auto-downloaded)

To pre-download models:
```bash
# Models download automatically when FluidAudio initializes
# No manual setup required!
```

> **Note**: Python environment, pyannote-audio, and HuggingFace tokens are **NOT required**. 
> The entire transcription + diarization pipeline is 100% native Swift, optimized for Apple Neural Engine.

---

## Swift Package Dependencies

Add to `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingTranscriber",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MeetingTranscriber", targets: ["MeetingTranscriber"])
    ],
    dependencies: [
        // Audio AI - Native Swift ASR, VAD, Diarization
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.1.0"),
        
        // Database
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        
        // Keychain access for storing tokens
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingTranscriber",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "GRDB", package: "GRDB.swift"),
                "KeychainAccess",
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MeetingTranscriberTests",
            dependencies: ["MeetingTranscriber"]
        ),
    ]
)
```

> **No Python Required!** The entire stack is native Swift.

---

## System Permissions

The app requires these permissions (configured in Info.plist):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Screen Recording Permission (required for ScreenCaptureKit audio) -->
    <key>NSScreenCaptureUsageDescription</key>
    <string>MeetingTranscriber needs screen recording permission to capture audio from your meeting apps like Zoom, Google Meet, and Teams.</string>
    
    <!-- Microphone Permission -->
    <key>NSMicrophoneUsageDescription</key>
    <string>MeetingTranscriber needs microphone access to transcribe what you say in meetings.</string>
    
    <!-- App runs as menu bar only -->
    <key>LSUIElement</key>
    <true/>
    
    <!-- App category -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
```

---

## Testing Without Real Meetings

### Quick Test Setup
1. Open **QuickTime Player**
2. File → New Movie Recording (or open any video file)
3. Play the video with audio
4. In MeetingTranscriber, select "QuickTime Player" as capture target
5. Start recording - you should see transcription of the video audio
6. Speak into your microphone - should appear as "Me:" entries

### Test Audio Files
Create test audio for development:
```bash
# Generate test tone (requires sox)
brew install sox
sox -n test_tone.wav synth 10 sine 440

# Or record yourself
# Use QuickTime → New Audio Recording → Save
```

### Simulating Multiple Speakers (Phase 3)
1. Open two browser tabs with different YouTube videos
2. Play both at low volume
3. Capture browser audio - FluidAudio DiarizerManager will identify distinct speakers
4. Each speaker will be labeled (Speaker 1, Speaker 2, etc.)

---

## Troubleshooting

### "Screen Recording permission not granted"
1. Open System Settings → Privacy & Security → Screen Recording
2. Find MeetingTranscriber in the list
3. Toggle ON (may require app restart)
4. If not in list, the app needs to attempt capture first to appear

### "No audio from ScreenCaptureKit"
- Ensure the target app is actually playing audio
- Check System Settings → Sound → Output (correct device?)
- Some apps (especially Electron-based) may need specific handling

### "Microphone not working"
1. System Settings → Privacy & Security → Microphone
2. Ensure MeetingTranscriber is toggled ON
3. Check Sound settings for correct input device

### "Ollama connection refused"
```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# If not, start it
ollama serve

# Check if model is downloaded
ollama list
```

### High CPU usage during transcription
- Should be minimal - FluidAudio uses Apple Neural Engine (ANE) for inference
- Preprocessing runs on CPU, but main ASR inference is ANE-optimized
- Check Activity Monitor - if CPU is high, check Console.app for errors

---

## Recommended Hardware

For best experience:
- **Minimum**: M1 Mac with 8GB RAM
- **Recommended**: M1 Pro/Max or M2+ with 16GB RAM
- **Storage**: ~5GB free for models

Performance expectations (M4 Pro, Parakeet TDT v3):
- Transcription latency: 1-2 seconds
- Real-time factor: ~190x (1 hour of audio in ~19 seconds)
- CPU usage: Minimal (ANE handles inference)
- Memory: 1.5-2GB total app footprint
