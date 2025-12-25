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
- **Transcription**: MLX Whisper (Apple Silicon native) or faster-whisper via Python bridge
- **Speaker Diarization**: pyannote-audio (Python, called via subprocess or embedded)
- **Summaries**: Ollama (local LLM) or MLX-LM
- **Storage**: SQLite via GRDB.swift or SwiftData
- **Minimum macOS**: 13.0

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
│   │   ├── WhisperEngine.swift          # MLX Whisper interface
│   │   ├── TranscriptionManager.swift   # Orchestrates transcription
│   │   └── PythonBridge.swift           # For faster-whisper fallback
│   ├── Diarization/
│   │   ├── SpeakerIdentifier.swift      # Speaker tracking
│   │   └── PyAnnoteBridge.swift         # Python diarization bridge
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

### MLX Whisper Integration
Either:
1. Use mlx-swift bindings directly (if available)
2. Bundle Python with mlx-whisper, call via Process()
3. Use whisper.cpp with CoreML backend as fallback

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
- [Buzz](https://github.com/chidiwilliams/buzz) - Open-source Whisper desktop app
- [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) - Commercial reference
- [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper) - Apple Silicon Whisper

## Getting Started
See INITIAL_PROMPT.md for the first implementation prompt to give Cursor.
