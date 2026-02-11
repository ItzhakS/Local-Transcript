# Phase 2 Fixes - Transcription & Logging

## Issues Fixed

### 1. No Transcription Occurring ✅

**Problem**: Audio was being captured and mixed, but no transcription was happening.

**Root Cause**: The Voice Activity Detection (VAD) threshold in `TranscriptionManager` was too strict (`1e-5`). The system was detecting all audio as "silence" because the energy levels in the logs showed values like `0.000000` or `0.000001`, which were below the threshold.

**Fix**: Lowered the VAD threshold to `1e-6` (10x more sensitive) to better detect speech.

```swift
// Before
private let energyThreshold: Float = 1e-5

// After  
private let energyThreshold: Float = 1e-6  // More sensitive
```

### 2. Excessive Silence Logging ✅

**Problem**: Console logs were flooded with thousands of "Silence" debug messages, making debugging impossible.

**Root Cause**: Every audio chunk (arriving ~50-100 times per second) was logging whether it was silence or signal.

**Fix**: Modified all audio capture and mixing components to only log non-silence audio:

- **AudioMixer.swift**: Only logs when energy > 1e-6
- **ScreenCaptureManager.swift**: Only logs when energy > 1e-6  
- **MicrophoneManager.swift**: Only logs when energy > 1e-6
- **TranscriptionManager.swift**: Removed debug log for silence, changed accumulation logs to `info` level
- **AppDelegate.swift**: Removed per-chunk debug logging

## Files Modified

1. `Sources/MeetingTranscriber/Features/Transcription/TranscriptionManager.swift`
   - Lowered VAD threshold from `1e-5` to `1e-6`
   - Changed debug logs to info logs for speech detection
   - Removed silence logging

2. `Sources/MeetingTranscriber/Features/AudioCapture/AudioMixer.swift`
   - Only logs audio chunks with energy > 1e-6
   - Changed from debug to info level

3. `Sources/MeetingTranscriber/Features/AudioCapture/ScreenCaptureManager.swift`
   - Only logs buffers with energy > 1e-6
   - Changed from debug to info level

4. `Sources/MeetingTranscriber/Features/AudioCapture/MicrophoneManager.swift`
   - Only logs buffers with energy > 1e-6
   - Changed from debug to info level
   - Removed duplicate energy calculation

5. `Sources/MeetingTranscriber/App/AppDelegate.swift`
   - Removed per-chunk debug logging in audio processing loop

## Testing

### Expected Behavior After Fix

1. **Start Recording**: Click "Start Recording" from menu bar
2. **Model Loading**: See "[Transcription] Loading Whisper model..." in Console.app
3. **Audio Detection**: When you speak or play audio, you should see:
   - `[Audio] Mixed audio chunk - Source: Me/Others, Samples: XXX, Energy: X.XXXXXX (Signal)`
   - `[Transcription] Accumulated X.XXs of audio from Me/Others`
4. **Transcription**: After ~3 seconds of speech, you should see:
   - `[Transcription] Flushing buffer: XXXXX samples (3.00s) from Me/Others`
   - `[Transcription] Added transcript entry: Me/Others: "transcribed text here"`
5. **Transcript Window**: The transcript window should populate with entries

### Debug Logging

To see detailed logs in Console.app:
```bash
# Filter by process
com.meetingtranscriber

# Or by subsystem and category
Subsystem: com.meetingtranscriber
Category: Transcription, Audio, UI
```

## Performance Impact

- **Before**: ~50-100 debug logs per second (mostly silence)
- **After**: Only logs when speech is detected (~1-5 logs per second during speech)
- **Benefit**: Much cleaner logs, easier debugging, no performance impact from excessive logging

## Known Limitations

1. **VAD is simple**: Uses basic energy threshold, may miss very quiet speech
2. **No background noise suppression**: Picks up keyboard typing, mouse clicks, etc.
3. **Basic speaker labeling**: "Me" vs "Others" only (Phase 3 will add proper diarization)
4. **Buffer timing**: Fixed 3-second buffer may cut off mid-word for fast speakers

## Next Steps (Future Phases)

- **Phase 3**: Advanced speaker diarization using SpeakerKit
- **Phase 4**: Save transcripts to disk with export options
- **Phase 5**: Local LLM summarization using Ollama

## Build Info

- **Built**: December 28, 2025
- **Whisper Model**: openai_whisper-base (~150MB)
- **Sample Rate**: 16kHz mono
- **Buffer Duration**: 3 seconds
- **Silence Timeout**: 1.5 seconds

