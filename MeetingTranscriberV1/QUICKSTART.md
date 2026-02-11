# Quick Start Guide

## 🚀 Get Started in 3 Steps

### Step 1: Build & Bundle
```bash
cd "/Users/itzhak/Local Transcript/MeetingTranscriber"
./Scripts/bundle.sh
```

This will:
- Build the app in release mode
- Create `MeetingTranscriber.app` bundle
- Display installation instructions

### Step 2: Install
```bash
# Option A: Copy to Applications
cp -r MeetingTranscriber.app /Applications/

# Option B: Just open from current directory
open MeetingTranscriber.app
```

### Step 3: Grant Permissions

On first launch, you'll be prompted for:

1. **Microphone** - Click "OK" on the dialog
2. **Notifications** - Click "Allow" on the dialog  
3. **Screen Recording** - Follow these steps:
   - Click "Start Recording" in the menu bar
   - macOS will prompt you to open System Settings
   - Enable "MeetingTranscriber" in Screen Recording
   - Restart the app

## 🎯 Usage

### See It in Action

Look for this icon in your menu bar: **○~**

### Manual Recording

1. Click the menu bar icon
2. Select **"Start Recording"**
3. Icon changes to **●~** (filled = recording)
4. Speak and/or play audio
5. Click again and select **"Stop Recording"**

### Auto-Detect Recording

1. Join a meeting (Zoom, Meet, Teams, etc.)
2. You'll see a notification: **"Meeting detected - Start recording?"**
3. Click the notification to start automatically

### First Recording Note

- The first time you start recording, FluidAudio will download the ASR model (Parakeet TDT v3)
- Models download automatically from HuggingFace in the background
- Subsequent recordings will be instant

## 🔍 Verify It's Working

### Check the Logs
```bash
# Open Console.app
open -a Console

# Filter for: com.meetingtranscriber
# You should see logs from categories: Audio, Capture, UI, Detection, Permissions
```

### What You Should See
- Starting recording: "Starting display audio capture", "Starting microphone capture"
- While recording: "Received chunk from Me: XXX samples", "Received chunk from Others: XXX samples"
- Stopping: "Display audio capture stopped", "Microphone capture stopped"

## 📊 What's Happening

Right now, the app is:
- ✅ Capturing system audio (everything playing on your Mac) via ScreenCaptureKit
- ✅ Capturing microphone input (your voice) via AVAudioEngine
- ✅ Mixing them together with labels ("Me" vs "Others")
- ✅ Processing audio with FluidAudio:
  - Voice Activity Detection (VAD) using FluidAudio VadManager
  - Automatic Speech Recognition (ASR) using FluidAudio AsrManager
  - Real-time transcription displayed in transcript window

**Note:** Advanced speaker diarization is planned for Phase 3. Current version labels audio sources ("Me" vs "Others").

## 🧪 Test Without a Meeting

### Test System Audio
```bash
# Open Music or any video
open -a Music
# Or open YouTube in browser
# Start recording in MeetingTranscriber
# Play audio - you should see "Others" chunks in logs
```

### Test Microphone
```bash
# Start recording
# Speak into your microphone
# You should see "Me" chunks in logs
```

### Test Auto-Detection
```bash
# Open Voice Memos
open -a "Voice Memos"
# Start recording in Voice Memos
# MeetingTranscriber should show a notification
```

## 🔧 Troubleshooting

### App doesn't appear in menu bar
- Check if already running: `ps aux | grep MeetingTranscriber`
- Try quitting and reopening: `killall MeetingTranscriber && open MeetingTranscriber.app`

### "Screen Recording permission not granted"
```bash
# Open System Settings
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
# Enable MeetingTranscriber
# Restart the app
```

### No audio captured
- Check Console.app logs for errors
- Ensure audio is actually playing (test with Music app)
- Verify Screen Recording permission is granted

### Build fails
```bash
# Clean and rebuild
swift package clean
swift build -c release
./Scripts/bundle.sh
```

## ⚙️ Optional: Add to Login Items

To start automatically on login:
1. Open System Settings
2. General → Login Items
3. Click "+" and add MeetingTranscriber.app
4. Done!

## 📁 Project Location

Everything is in:
```
/Users/itzhak/Local Transcript/MeetingTranscriber/
```

Key files:
- `README.md` - Full documentation
- `IMPLEMENTATION_SUMMARY.md` - Technical details
- `Scripts/bundle.sh` - Build script
- `MeetingTranscriber.app` - The app bundle (after running bundle.sh)

## 🎉 You're All Set!

The audio capture and transcription infrastructure is now ready. Next phases will add:
- Phase 3: Advanced speaker diarization (FluidAudio DiarizerManager)
- Phase 4: Storage & history
- Phase 5: AI summaries

---

**Need Help?** Check the logs in Console.app with filter: `com.meetingtranscriber`

