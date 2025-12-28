# Phase 2 Quick Start Guide

## 🎯 Goal
Get Phase 2 (Real-time Transcription) working in 5 minutes.

## Prerequisites
- ✅ Phase 1 completed and working
- ✅ macOS 13.0+ (Ventura)
- ✅ Apple Silicon Mac (M1/M2/M3)
- ✅ ~200MB free disk space (for model)

## Step 1: Build & Install

```bash
cd "/Users/itzhak/Local Transcript/MeetingTranscriber"
./Scripts/bundle.sh
open MeetingTranscriber.app
```

## Step 2: Grant Permissions (if first time)

When prompted, grant:
- ✅ Screen Recording (System Settings)
- ✅ Microphone (Dialog)
- ✅ Notifications (Dialog)

## Step 3: Start Recording

Click menu bar icon (○~) → **"Start Recording"**

### What Happens:
1. **First time only**: WhisperKit downloads model (~150MB, 30-60 seconds)
   - Check Console.app: `[Transcription] Loading Whisper model: base...`
2. **Transcript window opens** automatically
3. Menu bar icon changes to (●~)

## Step 4: Test Transcription

### Test 1: System Audio (YouTube)
1. Open YouTube: https://www.youtube.com/watch?v=dQw4w9WgXcQ (or any video with speech)
2. Play the video
3. **Watch transcript window** - text should appear labeled "Others"
4. ✅ Success: You see transcribed text from the video

### Test 2: Microphone
1. Speak into your microphone clearly
2. Say something like: "This is a test of the microphone transcription"
3. **Watch transcript window** - text should appear labeled "Me"
4. ✅ Success: You see your own words transcribed

### Test 3: Both Streams
1. Play YouTube video (Others)
2. Speak into mic (Me)
3. **Watch transcript window** - both should appear with correct labels
4. ✅ Success: Both streams transcribed correctly

## Step 5: Verify Features

### Auto-scroll
- Toggle button in transcript window
- When ON: automatically scrolls to latest entry
- When OFF: stays at current position

### Clear Transcript
- Click "Clear" button
- Removes all entries (recording continues)
- Start fresh

### Confidence Indicators
- 🟢 Green checkmark: >80% confidence (excellent)
- 🟠 Orange checkmark: 50-80% confidence (good)
- 🔴 Red question mark: <50% confidence (verify accuracy)

### Window Management
- Resize window - size persists
- Move window - position persists
- Close window - recording continues (window hidden)

## Step 6: Stop Recording

Click menu bar icon (●~) → **"Stop Recording"**

- Transcript window stays open (view completed transcript)
- Can close window manually
- Recording and transcription stopped

## ✅ Success Checklist

- [ ] Model downloaded successfully
- [ ] Transcript window appears when recording starts
- [ ] YouTube audio transcribed correctly (labeled "Others")
- [ ] Microphone transcribed correctly (labeled "Me")
- [ ] Timestamps appear on entries
- [ ] Confidence indicators visible
- [ ] Auto-scroll works
- [ ] Clear button works
- [ ] Window position persists

## 🐛 Troubleshooting

### "No transcript window appears"
- Check Console.app for errors
- Look for: `[UI] Transcript window created and shown`

### "Model download stuck"
- Check internet connection
- Check Console.app: `[Transcription] Loading Whisper model...`
- Wait 60 seconds
- If still stuck: Quit app, delete cache, restart
  ```bash
  rm -rf ~/Library/Caches/whisperkit/
  ```

### "No text appearing in transcript"
- Ensure audio is playing/speaking
- Speak continuously for 3+ seconds (VAD threshold)
- Check Console.app for transcription logs
- Look for: `[Transcription] Transcription complete: "..."`

### "Text is inaccurate"
- Ensure clear audio (minimal background noise)
- Speak clearly and at normal volume
- Base model prioritizes speed over accuracy
- Check confidence indicators - red means low confidence

### "App is slow/laggy"
- Normal during first transcription (model loading)
- Should be smooth after first transcription
- Check Activity Monitor - CPU should be <30% when transcribing
- Check Console.app for errors

## 📊 Performance Expectations

**Apple Silicon (M1 Pro, base model):**
- Model download: 30-60 seconds (first time only)
- Transcription latency: 1-3 seconds
- CPU usage: 15-30% during active transcription
- Memory: ~1.5-2GB (includes model)

**Intel Macs:**
- Not optimized (WhisperKit is CoreML-based)
- Will be slower
- Consider waiting for Phase 3 (alternative engines)

## 🎓 Tips & Tricks

### Better Accuracy
- Speak clearly and at normal pace
- Use headphones to reduce echo
- Close door/minimize background noise
- Position mic closer to mouth

### Model Selection
Currently hardcoded to `base` model. To change:

Edit `TranscriptionManager.swift`:
```swift
init(modelName: String = "small")  // Change "base" to "small", "medium", etc.
```

Models (speed vs accuracy):
- `tiny` - Fastest, lowest accuracy
- `base` - ⭐ Default, good balance
- `small` - Slower, better accuracy
- `medium` - Slow, high accuracy
- `large-v3` - Slowest, best accuracy

### Performance Tuning
Edit `TranscriptionManager.swift`:
```swift
private let bufferDuration: TimeInterval = 5.0  // Default: 3.0 (longer = more context, higher latency)
private let silenceTimeout: TimeInterval = 2.0  // Default: 1.5 (longer = fewer interruptions)
private let energyThreshold: Float = 2e-5       // Default: 1e-5 (higher = ignore quieter speech)
```

## 🚀 Next Steps

Phase 2 complete! Ready for:

1. **Phase 3**: Advanced speaker diarization (multiple speakers in "Others")
2. **Phase 4**: Storage & history (save transcripts, search)
3. **Phase 5**: AI summaries (action items, key points)

See `PHASE2_SUMMARY.md` for detailed implementation notes.

---

**Need help?** Check Console.app logs (filter: `com.meetingtranscriber`)

