# FluidAudio Migration Guide

## Overview

This document summarizes what FluidAudio can and cannot replace in the MeetingTranscriber project, based on FluidAudio's capabilities as described in the [official documentation](https://deepwiki.com/FluidInference/FluidAudio).

## ✅ What FluidAudio CAN Replace

### 1. WhisperKit (ASR/Transcription)

**Status:** ✅ **FULLY REPLACEABLE**

**FluidAudio Alternative:**
- **Batch transcription**: `AsrManager` - For processing complete audio files
- **Streaming transcription**: `StreamingEouAsrManager` - For real-time transcription with end-of-utterance detection

**Benefits:**
- **Apple Neural Engine (ANE) optimized** - All inference runs on ANE, not CPU/GPU
- **Higher performance** - ~190x real-time factor (RTFx) on M4 Pro (1 hour of audio in ~19 seconds)
- **Multilingual support** - Parakeet TDT v3 supports 25 European languages
- **English optimization** - Parakeet TDT v2 offers higher recall for English-only use cases
- **Unified SDK** - Single package for all audio AI tasks

**Migration Steps:**
1. Replace `WhisperEngine.swift` with `FluidAudioEngine.swift`
2. Use `AsrManager` for batch transcription or `StreamingEouAsrManager` for real-time
3. Update `Package.swift` to use FluidAudio instead of WhisperKit
4. Models download automatically from HuggingFace on first use

**Code Example:**
```swift
import FluidAudio

// Batch transcription
let asrManager = try await AsrManager()
let result = try await asrManager.transcribe(audioArray: samples)

// Streaming transcription
let streamingAsr = try await StreamingEouAsrManager(eouLatency: .ms160)
streamingAsr.processAudioChunk(samples) { result in
    // Real-time results as utterances complete
}
```

### 2. SpeakerKit (Speaker Diarization)

**Status:** ✅ **FULLY REPLACEABLE**

**FluidAudio Alternative:**
- **Online/Streaming**: `DiarizerManager` - Real-time speaker identification with agglomerative clustering
- **Offline/Batch**: `OfflineDiarizerManager` - Highest accuracy with VBx clustering

**Benefits:**
- **ANE-optimized** - Inference runs on Apple Neural Engine
- **Better accuracy** - ~17.7% DER (online) or ~13.89% DER (offline) on AMI corpus
- **Streaming support** - Real-time diarization for live transcription
- **Pyannote architecture** - Uses community-1 architecture (powerset segmentation + WeSpeaker embeddings + VBx clustering)

**Migration Steps:**
1. Replace `SpeakerKitManager.swift` with `FluidAudioDiarizer.swift`
2. Use `DiarizerManager` for online/streaming or `OfflineDiarizerManager` for batch
3. Update `Package.swift` to use FluidAudio
4. Models download automatically from HuggingFace

**Code Example:**
```swift
import FluidAudio

// Online/streaming diarization
let diarizer = try await DiarizerManager()
let segments = try await diarizer.diarize(audioArray: samples)
// Returns: [(start: Double, end: Double, speaker: Int)]

// Offline/batch diarization (higher accuracy)
let offlineDiarizer = try await OfflineDiarizerManager()
let segments = try await offlineDiarizer.diarize(audioArray: samples)
```

### 3. Energy-based VAD (Voice Activity Detection)

**Status:** ✅ **FULLY REPLACEABLE**

**FluidAudio Alternative:**
- `VadManager` - Uses Silero VAD models

**Benefits:**
- **ANE-optimized** - ~1230x RTFx on M4 Pro
- **Accurate detection** - Uses Silero VAD models instead of simple energy thresholds
- **Streaming support** - Maintains LSTM state across chunks for real-time detection
- **Better segmentation** - High-level API (`segmentSpeech()`) merges chunk-level probabilities into time ranges

**Migration Steps:**
1. Replace energy-based thresholding in `TranscriptionManager.swift`
2. Use `VadManager` for voice activity detection
3. Models download automatically from HuggingFace

**Code Example:**
```swift
import FluidAudio

let vadManager = VadManager()
let segments = try await vadManager.segmentSpeech(audioArray: samples)
// Returns: [(start: Double, end: Double)] - speech time ranges
```

## ❌ What FluidAudio CANNOT Replace

### 1. ScreenCaptureKit (System Audio Capture)

**Status:** ❌ **STILL REQUIRED**

**Reason:**
- FluidAudio **processes** audio but does **NOT capture** it
- ScreenCaptureKit is needed to capture system audio from the display/applications
- This is a fundamental difference: FluidAudio is an audio processing SDK, not an audio capture framework

**Continue Using:**
- `ScreenCaptureManager.swift` - Wrapper around ScreenCaptureKit for system audio capture
- No changes needed to audio capture infrastructure

### 2. AVAudioEngine (Microphone Capture)

**Status:** ❌ **STILL REQUIRED**

**Reason:**
- FluidAudio processes audio but does not capture it
- AVAudioEngine is needed to capture microphone input
- Same reason as ScreenCaptureKit - different responsibilities

**Continue Using:**
- `MicrophoneManager.swift` - Wrapper around AVAudioEngine for microphone capture
- No changes needed to audio capture infrastructure

## Architecture Flow

### Current Architecture (with FluidAudio)

```
┌─────────────────────────┐
│  ScreenCaptureKit       │  ← Still required (capture)
│  (System Audio)         │
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│  AVAudioEngine          │  ← Still required (capture)
│  (Microphone)           │
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│  AudioMixer             │  ← No change needed
│  (Combine streams)      │
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│  FluidAudio VadManager  │  ← ✅ Replaced energy-based VAD
│  (Voice Activity)       │
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│  FluidAudio AsrManager  │  ← ✅ Replaced WhisperKit
│  (Transcription)        │
│  OR                     │
│  StreamingEouAsrManager │  ← ✅ Streaming option
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│  FluidAudio Diarizer    │  ← ✅ Replaced SpeakerKit (Phase 3)
│  (Speaker IDs)          │
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│  TranscriptView         │
│  (Display results)      │
└─────────────────────────┘
```

## Platform Requirements

### Minimum Requirements

- **macOS**: 14.0+ (Sonoma) - Required for FluidAudio
- **Hardware**: Apple Silicon only (M1/M2/M3/M4) - Required for Apple Neural Engine access
- **Swift**: 5.9+

### Previous Requirements (Before FluidAudio)

- **macOS**: 13.0+ (Ventura) - For ScreenCaptureKit
- **Hardware**: Apple Silicon recommended (M1/M2/M3)
- **Swift**: 5.9+

**Change:** macOS requirement increased from 13.0 to 14.0

## Performance Comparison

| Component | Previous (WhisperKit) | FluidAudio | Improvement |
|-----------|----------------------|------------|-------------|
| ASR | ~15-30% CPU usage | Minimal CPU (ANE) | ✅ ANE-optimized |
| ASR Speed | Variable | ~190x RTFx (M4 Pro) | ✅ Much faster |
| VAD | Energy-based (simple) | Silero VAD (ANE) | ✅ More accurate |
| VAD Speed | CPU-based | ~1230x RTFx (M4 Pro) | ✅ Much faster |
| Diarization | Not implemented | ~17.7% DER (online) | ✅ High accuracy |
| Memory | ~1.5-2GB | ~1.5-2GB | Similar |

## Migration Checklist

- [x] Update `PROMPT.md` with FluidAudio information
- [x] Update `README.md` with FluidAudio references
- [x] Update `PHASE2_SUMMARY.md` with FluidAudio details
- [x] Update `DEPENDENCIES.md` with FluidAudio package info
- [x] Update `QUICKSTART.md` and `PHASE2_QUICKSTART.md`
- [ ] Replace `WhisperEngine.swift` with `FluidAudioEngine.swift` (code implementation)
- [ ] Update `Package.swift` to use FluidAudio
- [ ] Replace energy-based VAD with `VadManager` in `TranscriptionManager.swift`
- [ ] Test ASR transcription with FluidAudio
- [ ] Test VAD with FluidAudio
- [ ] Implement `DiarizerManager` for Phase 3 speaker diarization

## Summary

**Complete Replacement Strategy:**
1. ✅ Replace WhisperKit → FluidAudio ASR (`AsrManager` or `StreamingEouAsrManager`)
2. ✅ Replace SpeakerKit → FluidAudio Diarization (`DiarizerManager` or `OfflineDiarizerManager`)
3. ✅ Replace energy-based VAD → FluidAudio VAD (`VadManager`)
4. ❌ Keep ScreenCaptureKit for system audio capture (cannot be replaced)
5. ❌ Keep AVAudioEngine for microphone capture (cannot be replaced)

**Result:** A complete on-device audio AI pipeline optimized for Apple Neural Engine, with all inference running on ANE rather than CPU/GPU, providing better performance and lower power consumption.

## References

- [FluidAudio Documentation](https://deepwiki.com/FluidInference/FluidAudio)
- [FluidAudio GitHub](https://github.com/FluidInference/FluidAudio)
