# Local Transcript (MeetingTranscriberV1)

`Local Transcript` is a native macOS menu bar app that captures meeting audio and transcribes it live on-device.

## What the app does

- Runs as a menu bar app (no main dock window)
- Captures:
  - System audio (other meeting participants)
  - Microphone audio (your voice)
- Mixes both streams and sends them through local speech recognition
- Shows a live transcript window with speaker labels (`Me`, `Others`, and diarized speakers when enabled)
- Lets you copy the current full transcript to the clipboard

## Main tech used

- Swift 5.9+, SwiftUI
- ScreenCaptureKit (system audio capture)
- AVAudioEngine (microphone capture)
- FluidAudio (local ASR, VAD, and diarization)

## Where things are stored ("where it's holding")

- **Live transcript text:** kept in memory while the app is running (not permanently saved yet)
- **Copied transcript:** sent to macOS clipboard when you click `Copy All`
- **FluidAudio models/cache:** `~/Library/Application Support/FluidAudio`
- **Transcript window frame/position:** autosaved in app preferences (window autosave name: `TranscriptWindow`)
- **Logs:** viewable in Console under subsystem `com.meetingtranscriber`

## Current persistence status

- Transcript history/database storage is **not implemented yet** in this version.
- After quitting, live transcript entries are cleared unless you copied them manually.

## Project location in this repo

- App package root: `MeetingTranscriberV1/`
- Swift sources: `MeetingTranscriberV1/Sources/MeetingTranscriberV1/`
- App build config: `MeetingTranscriberV1/Package.swift`

## Quick start

```bash
cd "MeetingTranscriberV1"
swift build -c release
swift run
```
