# Meeting Transcription App for macOS

## Overview
Native macOS menu bar app that captures and transcribes online meetings in real-time, with speaker diarization and AI-powered summaries. Similar to Cluely/Highlight but runs entirely locally.

## Core Requirements
- macOS 14+ (Sonoma) - required for FluidAudio and ScreenCaptureKit audio capture
- Apple Silicon only (M1/M2/M3/M4) - required for Apple Neural Engine (ANE) access
- Runs 100% locally - no cloud APIs
- Menu bar app with floating transcript window

## Technical Stack
- **Language**: Swift 5.9+, SwiftUI for UI
- **Audio Capture**: ScreenCaptureKit (system audio + mic)
- **ASR (Transcription)**: FluidAudio (AsrManager for batch, StreamingEouAsrManager for streaming)
- **Voice Activity Detection**: FluidAudio (VadManager)
- **Speaker Diarization**: FluidAudio (DiarizerManager for online/streaming, OfflineDiarizerManager for batch)
- **Summaries**: Ollama (local LLM)
- **Storage**: SQLite via GRDB.swift or SwiftData
- **Minimum macOS**: 14.0 (required for FluidAudio)

> **Note**: FluidAudio provides a complete on-device audio AI stack:
> - 100% native Swift - fully local processing
> - Apple Neural Engine optimized - all inference on ANE (not CPU/GPU)
> - Unified SDK - ASR, VAD, and Diarization in one package
> - Low latency streaming - real-time processing with end-of-utterance detection
> - High performance - ~190x real-time factor on M4 Pro for ASR, ~1230x RTFx for VAD
> - ScreenCaptureKit still required for audio capture - FluidAudio processes audio, it doesn't capture it

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
│   │   ├── ScreenCaptureManager.swift   # ScreenCaptureKit wrapper (still needed for capture)
│   │   ├── MicrophoneManager.swift      # AVAudioEngine mic capture
│   │   └── AudioMixer.swift             # Combine streams
│   ├── Transcription/
│   │   ├── FluidAudioEngine.swift       # FluidAudio ASR wrapper
│   │   └── TranscriptionManager.swift   # Orchestrates transcription + VAD
│   ├── Diarization/
│   │   ├── FluidAudioDiarizer.swift     # FluidAudio DiarizerManager interface
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
    ├── models/                          # FluidAudio models (auto-downloaded from HuggingFace)
    └── Assets.xcassets
```

## Key Implementation Notes

### ScreenCaptureKit Audio Capture
```swift
// Must use SCStreamConfiguration with audio enabled
let config = SCStreamConfiguration()
config.capturesAudio = true
config.excludesCurrentProcessAudio = true  // Don't capture our own app
config.sampleRate = 16000  // FluidAudio ASR expects 16kHz

// Can filter to specific app
let filter = SCContentFilter(desktopIndependentWindow: zoomWindow)
```

### Permissions Required
- Screen Recording (for ScreenCaptureKit audio)
- Microphone access
- Add to Info.plist:
  - NSScreenCaptureUsageDescription
  - NSMicrophoneUsageDescription

### FluidAudio Integration

**ASR (Automatic Speech Recognition):**
```swift
import FluidAudio

// Batch transcription with AsrManager
let asrManager = try await AsrManager()
let result = try await asrManager.transcribe(audioArray: samples)
// Returns: TranscriptionResult with text, segments, timestamps

// Streaming transcription with StreamingEouAsrManager
let streamingAsr = try await StreamingEouAsrManager(eouLatency: .ms160)
streamingAsr.processAudioChunk(samples) { result in
    // Real-time results as utterances complete
}
```

**Voice Activity Detection:**
```swift
import FluidAudio

let vadManager = VadManager()
let segments = try await vadManager.segmentSpeech(audioArray: samples)
// Returns: [(start: Double, end: Double)] - speech time ranges
```

**Speaker Diarization:**
```swift
import FluidAudio

// Online/streaming diarization
let diarizer = try await DiarizerManager()
let segments = try await diarizer.diarize(audioArray: samples)
// Returns: [(start: Double, end: Double, speaker: Int)]

// Offline/batch diarization (higher accuracy)
let offlineDiarizer = try await OfflineDiarizerManager()
let segments = try await offlineDiarizer.diarize(audioArray: samples)
// Returns: [(start: Double, end: Double, speaker: Int)]
```

### Real-time Streaming Approach
- Buffer audio in 3-5 second chunks
- Use FluidAudio VadManager for accurate voice activity detection
- Use FluidAudio StreamingEouAsrManager for real-time transcription with end-of-utterance detection
- Use FluidAudio DiarizerManager for online speaker identification
- Display interim results, replace with final

## Non-Functional Requirements
- CPU usage < 30% during active transcription
- Memory < 2GB (including model)
- Transcription latency < 3 seconds from speech end
- App size < 500MB (model can be downloaded separately)

## Reference Projects
- [FluidAudio](https://github.com/FluidInference/FluidAudio) - Native Swift on-device audio AI (ASR, VAD, Diarization)
- [FluidAudio Documentation](https://deepwiki.com/FluidInference/FluidAudio) - Comprehensive API reference
- [Buzz](https://github.com/chidiwilliams/buzz) - Open-source Whisper desktop app
- [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) - Commercial reference

## FluidAudio Integration - What Can Be Replaced?

### ✅ CAN BE REPLACED

**WhisperKit (ASR/Transcription):**
- ✅ **Replaced by**: FluidAudio `AsrManager` (batch) or `StreamingEouAsrManager` (streaming)
- **Benefits**: 
  - Apple Neural Engine (ANE) optimized - all inference on ANE (not CPU/GPU)
  - Higher performance (~190x RTFx on M4 Pro)
  - Supports multilingual (25 European languages) via Parakeet TDT v3
  - Unified SDK for all audio AI tasks
- **Migration**: Replace `WhisperEngine.swift` with `FluidAudioEngine.swift` using FluidAudio ASR APIs

**SpeakerKit (Diarization):**
- ✅ **Replaced by**: FluidAudio `DiarizerManager` (online/streaming) or `OfflineDiarizerManager` (batch)
- **Benefits**:
  - ANE-optimized inference
  - Lower DER (17.7% online, ~13.89% offline on AMI corpus)
  - Streaming support for real-time diarization
- **Migration**: Replace `SpeakerKitManager.swift` with `FluidAudioDiarizer.swift` using FluidAudio Diarization APIs

**Energy-based VAD:**
- ✅ **Replaced by**: FluidAudio `VadManager`
- **Benefits**:
  - Accurate Silero VAD models
  - ANE-optimized (~1230x RTFx on M4 Pro)
  - Better speech boundary detection
- **Migration**: Replace energy-based thresholding with FluidAudio VadManager in `TranscriptionManager.swift`

### ❌ CANNOT BE REPLACED

**ScreenCaptureKit (Audio Capture):**
- ❌ **Still Required**: FluidAudio processes audio but does NOT capture it
- **Reason**: ScreenCaptureKit is needed to capture system audio from the display/applications
- **Usage**: Continue using `ScreenCaptureManager.swift` to capture system audio, then feed to FluidAudio for processing

**AVAudioEngine (Microphone Capture):**
- ❌ **Still Required**: FluidAudio processes audio but does NOT capture it
- **Reason**: AVAudioEngine is needed to capture microphone input
- **Usage**: Continue using `MicrophoneManager.swift` to capture microphone audio, then feed to FluidAudio for processing

### Summary

**Complete Replacement Strategy:**
1. ✅ Replace WhisperKit → FluidAudio ASR (`AsrManager` or `StreamingEouAsrManager`)
2. ✅ Replace SpeakerKit → FluidAudio Diarization (`DiarizerManager` or `OfflineDiarizerManager`)
3. ✅ Replace energy-based VAD → FluidAudio VAD (`VadManager`)
4. ❌ Keep ScreenCaptureKit for system audio capture
5. ❌ Keep AVAudioEngine for microphone capture

**Architecture Flow:**
```
ScreenCaptureKit (capture) → AudioMixer → FluidAudio VAD → FluidAudio ASR → Transcript
AVAudioEngine (capture) ──┘                              ↓
                                                      FluidAudio Diarization → Speaker Labels
```

## Getting Started
See INITIAL_PROMPT.md for the first implementation prompt to give Cursor.
