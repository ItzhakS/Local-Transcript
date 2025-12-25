#!/bin/bash

# bundle.sh - Create a macOS .app bundle for MeetingTranscriber
# Usage: ./Scripts/bundle.sh

set -e

echo "🔨 Building MeetingTranscriber..."

# Build in release mode
swift build -c release

# Get the built executable path
EXECUTABLE_PATH=".build/release/MeetingTranscriber"

if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "❌ Error: Executable not found at $EXECUTABLE_PATH"
    echo "   Make sure 'swift build -c release' succeeded"
    exit 1
fi

echo "✅ Build complete"

# Create app bundle structure
APP_NAME="MeetingTranscriber.app"
APP_BUNDLE="$APP_NAME"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Creating app bundle structure..."

# Remove existing bundle if it exists
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
fi

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
echo "📋 Copying executable..."
cp "$EXECUTABLE_PATH" "$MACOS_DIR/MeetingTranscriber"
chmod +x "$MACOS_DIR/MeetingTranscriber"

# Create Info.plist in Contents directory
echo "📝 Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MeetingTranscriber</string>
    
    <key>CFBundleIdentifier</key>
    <string>com.meetingtranscriber.app</string>
    
    <key>CFBundleName</key>
    <string>MeetingTranscriber</string>
    
    <key>CFBundleDisplayName</key>
    <string>Meeting Transcriber</string>
    
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    
    <key>CFBundleVersion</key>
    <string>1</string>
    
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    
    <key>CFBundleSignature</key>
    <string>????</string>
    
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    
    <key>LSUIElement</key>
    <true/>
    
    <key>NSScreenCaptureUsageDescription</key>
    <string>MeetingTranscriber needs screen recording permission to capture audio from your meeting apps like Zoom, Google Meet, and Teams.</string>
    
    <key>NSMicrophoneUsageDescription</key>
    <string>MeetingTranscriber needs microphone access to transcribe what you say in meetings.</string>
    
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Create a simple icon (optional - can be replaced with a proper .icns file)
echo "🎨 Creating placeholder icon..."
# For now, we'll skip creating an actual .icns file
# You can add a proper icon by placing AppIcon.icns in Resources/

echo "✅ App bundle created successfully!"
echo ""
echo "📍 Location: $(pwd)/$APP_BUNDLE"
echo ""
echo "🚀 Next steps:"
echo "   1. Drag $APP_BUNDLE to /Applications"
echo "   2. Double-click to launch"
echo "   3. Grant permissions when prompted"
echo "   4. Look for the app in your menu bar"
echo ""
echo "💡 To add to Login Items:"
echo "   System Settings > General > Login Items > Add $APP_BUNDLE"

