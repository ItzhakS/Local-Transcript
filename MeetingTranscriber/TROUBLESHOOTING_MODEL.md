# Troubleshooting: Model Download Issues

## Problem: "Failed to load Whisper model: Model not found"

This error occurs when WhisperKit's model download is interrupted or incomplete.

### Symptoms
- Error message: "Model not found. Please check the model or repo name"
- File system error about `.incomplete` files
- App fails to start transcription

### Root Cause
WhisperKit downloads CoreML models from HuggingFace on first use. If the download is interrupted (network issue, app crash, etc.), incomplete files remain in the cache, preventing future downloads.

### Solution

#### Option 1: Clean Cache (Recommended)
```bash
# Remove incomplete model cache
rm -rf ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/

# Or remove just the specific model
rm -rf ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-base
```

Then restart the app and try recording again. The model will download fresh.

#### Option 2: Manual Model Download (Advanced)
If automatic download keeps failing, you can manually download:

1. Download from: https://huggingface.co/argmaxinc/whisperkit-coreml
2. Place in: `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-base/`
3. Ensure these files exist:
   - `config.json`
   - `generation_config.json`
   - `AudioEncoder.mlmodelc/` (directory)
   - `MelSpectrogram.mlmodelc/` (directory)
   - `TextDecoder.mlmodelc/` (directory)

### Prevention

**Ensure stable internet connection before first recording:**
- Model download is ~150MB
- Takes 30-60 seconds
- Progress shown in Console.app logs

**Check logs during download:**
```bash
# Open Console.app
# Filter: com.meetingtranscriber
# Look for: [Transcription] Loading Whisper model...
```

### Model Download Requirements

| Model | Size | Download Time | Quality |
|-------|------|---------------|---------|
| tiny  | ~40MB | 10-15s | Low |
| base  | ~150MB | 30-60s | Good ⭐ |
| small | ~500MB | 2-3min | Better |
| medium | ~1.5GB | 5-10min | High |

**Note:** Default is `base` model (good balance of speed/accuracy).

### Still Having Issues?

1. **Check internet connection**
   ```bash
   curl -I https://huggingface.co
   # Should return: HTTP/2 200
   ```

2. **Check disk space**
   ```bash
   df -h ~/Documents
   # Need at least 500MB free for base model
   ```

3. **Check permissions**
   ```bash
   ls -la ~/Documents/huggingface/
   # Should be readable/writable by your user
   ```

4. **Try different model**
   Edit `TranscriptionManager.swift`:
   ```swift
   init(modelName: String = "tiny")  // Smaller, faster download
   ```

5. **Check Console.app for detailed errors**
   - Open Console.app
   - Filter: `com.meetingtranscriber`
   - Category: `Transcription`
   - Look for detailed error messages

### Known Issues

**Issue**: "couldn't be moved" error
- **Cause**: Previous download interrupted
- **Fix**: Clean cache (Option 1 above)

**Issue**: Download times out
- **Cause**: Slow connection or HuggingFace server issues
- **Fix**: Wait and retry, or use manual download

**Issue**: "No such file or directory"
- **Cause**: Incomplete directory structure
- **Fix**: Remove entire cache, let app recreate

### Getting Help

If none of the above works:

1. **Collect logs**:
   ```bash
   log show --predicate 'subsystem == "com.meetingtranscriber"' --last 5m > ~/Desktop/meetingtranscriber.log
   ```

2. **Check model cache**:
   ```bash
   ls -laR ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/
   ```

3. **Report issue** with logs and directory listing

### Success Indicators

You'll know it worked when you see:
```
[Transcription] Loading Whisper model: base...
[Transcription] This may take 30-60 seconds on first launch...
[Transcription] Whisper model loaded successfully: base
```

And the transcript window opens with live transcription! 🎉

