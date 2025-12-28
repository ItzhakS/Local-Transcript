# Meeting Transcription App for macOS

## Overview
Native macOS menu bar app that captures and transcribes online meetings in real-time, with speaker diarization and AI-powered summaries. Similar to Cluely/Highlight but runs entirely locally.

## Core Requirements
- macOS 13+ (Ventura) - required for ScreenCaptureKit audio capture
- Apple Silicon optimized (M1/M2/M3)
- Runs 100% locally - no cloud APIs
- Menu bar app with floating transcript window

## Technical Stack
- **Language**: Swift 5.9+, SwiftUI for UI
- **Audio Capture**: ScreenCaptureKit (system audio + mic)
- **Transcription**: WhisperKit (native Swift, Apple Silicon optimized via CoreML)
- **Speaker Diarization**: SpeakerKit (native Swift, from Argmax - same creators as WhisperKit)
- **Summaries**: Ollama (local LLM)
- **Storage**: SQLite via GRDB.swift or SwiftData
- **Minimum macOS**: 13.0

> **Note**: We chose WhisperKit + SpeakerKit over MLX Whisper + pyannote-audio because:
> - 100% native Swift - no Python bridge or subprocess required
> - Simpler distribution - single app bundle without bundled Python runtime
> - Lower latency - no IPC overhead between Swift and Python
> - SpeakerKit: ~10MB, matches pyannote accuracy, ~1 second for 4 min audio

## Features (Priority Order)

### P0 - Core
1. Menu bar icon with start/stop recording
2. Capture system audio from specific app (Zoom, Meet, Teams, etc.)
3. Capture microphone input simultaneously
4. Real-time transcription display in floating window
5. Basic speaker separation (me vs others based on audio source)

### P1 - Enhanced
6. Speaker diarization (distinguish multiple remote speakers)
7. Auto-detect meeting app and prompt to record
8. Keyboard shortcuts (global hotkey to start/stop)
9. Export transcript as markdown/txt
10. Meeting metadata (date, duration, app used)

### P2 - Intelligence
11. Post-meeting AI summary (action items, key points, decisions)
12. Searchable transcript history
13. Tag and organize meetings
14. Custom vocabulary/name correction

### P3 - Polish
15. Calendar integration (auto-name meetings)
16. Notion/Obsidian export
17. Custom LLM prompt templates for summaries

## Architecture

```
MeetingTranscriber/
├── App/
│   ├── MeetingTranscriberApp.swift      # App entry point
│   ├── AppDelegate.swift                 # Menu bar setup
│   └── ContentView.swift                 # Main UI
├── Features/
│   ├── AudioCapture/
│   │   ├── ScreenCaptureManager.swift   # ScreenCaptureKit wrapper
│   │   ├── MicrophoneManager.swift      # AVAudioEngine mic capture
│   │   └── AudioMixer.swift             # Combine streams
│   ├── Transcription/
│   │   ├── WhisperEngine.swift          # WhisperKit interface
│   │   └── TranscriptionManager.swift   # Orchestrates transcription
│   ├── Diarization/
│   │   ├── SpeakerKitManager.swift      # SpeakerKit interface
│   │   └── SpeakerIdentifier.swift      # Speaker tracking & labeling
│   ├── Summary/
│   │   ├── OllamaClient.swift           # Local LLM interface
│   │   └── SummaryGenerator.swift       # Summary prompts/logic
│   └── Storage/
│       ├── MeetingStore.swift           # SQLite/SwiftData
│       └── Models/
│           ├── Meeting.swift
│           ├── Transcript.swift
│           └── Speaker.swift
├── UI/
│   ├── MenuBar/
│   │   ├── MenuBarView.swift
│   │   └── StatusItemManager.swift
│   ├── TranscriptWindow/
│   │   ├── TranscriptView.swift
│   │   └── TranscriptRow.swift
│   ├── History/
│   │   └── MeetingHistoryView.swift
│   └── Settings/
│       └── SettingsView.swift
├── Utilities/
│   ├── Permissions.swift                # Request screen recording, mic
│   ├── AudioFormatConverter.swift
│   └── Logger.swift
└── Resources/
    ├── whisper-model/                   # Bundled or downloaded model
    └── Assets.xcassets
```

## Key Implementation Notes

### ScreenCaptureKit Audio Capture
```swift
// Must use SCStreamConfiguration with audio enabled
let config = SCStreamConfiguration()
config.capturesAudio = true
config.excludesCurrentProcessAudio = true  // Don't capture our own app
config.sampleRate = 16000  // Whisper expects 16kHz

// Can filter to specific app
let filter = SCContentFilter(desktopIndependentWindow: zoomWindow)
```

### Permissions Required
- Screen Recording (for ScreenCaptureKit audio)
- Microphone access
- Add to Info.plist:
  - NSScreenCaptureUsageDescription
  - NSMicrophoneUsageDescription

### WhisperKit Integration
WhisperKit is a native Swift package from Argmax that uses CoreML for Apple Silicon optimization:
```swift
import WhisperKit

let whisperKit = try await WhisperKit(model: "base")
let result = try await whisperKit.transcribe(audioArray: samples)
```

### SpeakerKit Integration (Diarization)
SpeakerKit is the companion package for speaker diarization:
```swift
import SpeakerKit

let diarizer = try await SpeakerDiarizer()
let segments = try await diarizer.diarize(audioArray: samples)
// Returns: [(start: Double, end: Double, speaker: Int)]
```

### Real-time Streaming Approach
- Buffer audio in 3-5 second chunks
- Run VAD (Voice Activity Detection) to detect speech boundaries
- Transcribe complete utterances, not arbitrary chunks
- Display interim results, replace with final

## Non-Functional Requirements
- CPU usage < 30% during active transcription
- Memory < 2GB (including model)
- Transcription latency < 3 seconds from speech end
- App size < 500MB (model can be downloaded separately)

## Reference Projects
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Native Swift Whisper for Apple Silicon
- [SpeakerKit](https://github.com/argmaxinc/SpeakerKit) - Native Swift speaker diarization
- [Buzz](https://github.com/chidiwilliams/buzz) - Open-source Whisper desktop app
- [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) - Commercial reference

## Getting Started
See INITIAL_PROMPT.md for the first implementation prompt to give Cursor.
